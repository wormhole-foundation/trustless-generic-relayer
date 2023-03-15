import {
  ActionExecutor,
  assertBool,
  assertEvmChainId,
  assertInt,
  CommonPluginEnv,
  ContractFilter,
  ParsedVaaWithBytes,
  parseVaaWithBytes,
  Plugin,
  Providers,
  StagingAreaKeyLock,
  Workflow,
} from "@wormhole-foundation/relayer-engine"
import * as wh from "@certusone/wormhole-sdk"
import { SignedVaa } from "@certusone/wormhole-sdk"
import { Logger } from "winston"
import { PluginError } from "./utils"
import {
  DeliveryInstructionsContainer,
  IDelivery,
  parseDeliveryInstructionsContainer,
  parsePayloadType,
  parseRedeliveryByTxHashInstruction,
  RedeliveryByTxHashInstruction,
  RelayerPayloadId,
  RelayProvider__factory,
} from "../../../pkgs/sdk/src"
import * as ethers from "ethers"
import * as vaaFetching from "./vaaFetching"
import * as syntheticBatch from "./syntheticBatch"

let PLUGIN_NAME: string = "GenericRelayerPlugin"

export interface ChainInfo {
  relayProvider: string
  coreContract: string
  relayerAddress: string
  mockIntegrationContractAddress: string
}

export interface GenericRelayerPluginConfig {
  supportedChains: Map<wh.EVMChainId, ChainInfo>
  logWatcherSleepMs: number
  shouldRest: boolean
  shouldSpy: boolean
}

interface WorkflowPayload {
  payloadId: RelayerPayloadId
  deliveryVaaIndex: number
  vaas: string[] // base64
  // only present when payload type is Redelivery
  redeliveryVaa?: string // base64
}

interface WorkflowPayloadParsed {
  payloadId: RelayerPayloadId
  deliveryInstructionsContainer: DeliveryInstructionsContainer
  deliveryVaaIndex: number
  deliveryVaa: ParsedVaaWithBytes
  redelivery?: {
    vaa: ParsedVaaWithBytes
    ix: RedeliveryByTxHashInstruction
  }
  vaas: Buffer[]
}

export class GenericRelayerPlugin implements Plugin<WorkflowPayload> {
  readonly shouldSpy: boolean
  readonly shouldRest: boolean
  static readonly pluginName: string = PLUGIN_NAME
  readonly pluginName = GenericRelayerPlugin.pluginName
  pluginConfig: GenericRelayerPluginConfig

  constructor(
    readonly engineConfig: CommonPluginEnv,
    pluginConfigRaw: Record<string, any>,
    readonly logger: Logger
  ) {
    this.pluginConfig = GenericRelayerPlugin.validateConfig(pluginConfigRaw)
    this.shouldRest = this.pluginConfig.shouldRest
    this.shouldSpy = this.pluginConfig.shouldSpy
  }

  async afterSetup(
    _providers: Providers,
    listenerResources?: {
      eventSource: (event: SignedVaa) => Promise<void>
      db: StagingAreaKeyLock
    }
  ) {
    // connect to the core wh contract for each chain
    for (const [chainId, info] of this.pluginConfig.supportedChains.entries()) {
      const { coreContract } = info
      if (!coreContract || !wh.isEVMChain(chainId)) {
        throw new PluginError("No known core contract for chain", { chainId })
      }
    }

    if (listenerResources) {
      vaaFetching.fetchVaaWorker(
        listenerResources.eventSource,
        listenerResources.db,
        this.logger,
        this.engineConfig
      )
    }
  }

  // listen to core relayer contract on each chain
  getFilters(): ContractFilter[] {
    return Array.from(this.pluginConfig.supportedChains.entries()).map(
      ([chainId, c]) => ({ emitterAddress: c.relayerAddress, chainId })
    )
  }

  async consumeEvent(
    coreRelayerVaa: ParsedVaaWithBytes,
    db: StagingAreaKeyLock,
    providers: Providers
  ): Promise<{ workflowData: WorkflowPayload } | undefined> {
    const hash = coreRelayerVaa.hash.toString("base64")
    this.logger.debug(
      `Consuming event from chain ${
        coreRelayerVaa.emitterChain
      } with seq ${coreRelayerVaa.sequence.toString()} and hash ${hash}`
    )

    // Kick off workflow if entry has already been fetched
    const payloadId = parsePayloadType(coreRelayerVaa.payload)
    const { [hash]: fetched } = await db.getKeys<
      Record<typeof hash, vaaFetching.SyntheticBatchEntry>
    >([hash])
    if (fetched?.allFetched) {
      // if all vaas have been fetched, kick off workflow
      this.logger.info(`All fetched, queueing workflow for ${hash}...`)
      return {
        workflowData: {
          payloadId,
          deliveryVaaIndex: fetched.deliveryVaaIdx,
          vaas: fetched.vaas.map((v) => v.bytes),
          redeliveryVaa: fetched.redeliveryVaa,
        },
      }
    }

    switch (payloadId) {
      case RelayerPayloadId.Delivery:
        return this.consumeDeliveryEvent(coreRelayerVaa, db, hash, providers)
      case RelayerPayloadId.Redelivery:
        return this.consumeRedeliveryEvent(coreRelayerVaa, db, providers)
    }
  }

  async consumeDeliveryEvent(
    coreRelayerVaa: ParsedVaaWithBytes,
    db: StagingAreaKeyLock,
    hash: string,
    providers: Providers
  ): Promise<{ workflowData: WorkflowPayload } | undefined> {
    this.logger.info(
      `Not fetched, fetching receipt and filtering to synthetic batch for ${hash}...`
    )
    const chainId = coreRelayerVaa.emitterChain as wh.EVMChainId
    const rx = await syntheticBatch.fetchReceipt(
      coreRelayerVaa.sequence,
      chainId,
      providers.evm[chainId],
      this.pluginConfig.supportedChains.get(chainId)!,
      this.logger
    )

    const chainConfig = this.pluginConfig.supportedChains.get(chainId)!
    const { vaas, deliveryVaaIdx } = syntheticBatch.filterLogs(
      rx,
      coreRelayerVaa.nonce,
      chainConfig,
      this.logger
    )
    vaas[deliveryVaaIdx].bytes = coreRelayerVaa.bytes.toString("base64")

    // create entry and pending in db
    const newEntry: vaaFetching.SyntheticBatchEntry = {
      vaas,
      chainId,
      deliveryVaaIdx,
      allFetched: false,
    }
    return await this.addWorkflowOrQueueEntryForFetching(db, hash, newEntry)
  }

  async consumeRedeliveryEvent(
    redeliveryVaa: ParsedVaaWithBytes,
    db: StagingAreaKeyLock,
    providers: Providers
  ): Promise<{ workflowData: WorkflowPayload } | undefined> {
    const redeliveryInstruction = parseRedeliveryByTxHashInstruction(
      redeliveryVaa.payload
    )
    const chainId = redeliveryInstruction.sourceChain as wh.EVMChainId
    const provider = providers.evm[chainId]
    const rx = await provider.getTransactionReceipt(
      ethers.utils.hexlify(redeliveryInstruction.sourceTxHash, {
        allowMissingPrefix: true,
      })
    )
    const chainConfig = this.pluginConfig.supportedChains.get(chainId)!
    const { vaas, deliveryVaaIdx } = syntheticBatch.filterLogs(
      rx,
      redeliveryInstruction.sourceNonce.toNumber(),
      chainConfig,
      this.logger
    )

    // create entry and pending in db
    const newEntry: vaaFetching.SyntheticBatchEntry = {
      vaas,
      chainId,
      deliveryVaaIdx,
      redeliveryVaa: redeliveryVaa.bytes.toString("base64"),
      allFetched: false,
    }
    const hash = Buffer.from(redeliveryVaa.hash).toString("base64")
    return this.addWorkflowOrQueueEntryForFetching(db, hash, newEntry)
  }

  async addWorkflowOrQueueEntryForFetching(
    db: StagingAreaKeyLock,
    hash: string,
    entry: vaaFetching.SyntheticBatchEntry
  ): Promise<{ workflowData: WorkflowPayload } | undefined> {
    const resolvedEntry = await vaaFetching.fetchEntry(
      hash,
      entry,
      this.logger,
      this.engineConfig
    )
    if (resolvedEntry.allFetched) {
      this.logger.info("Resolved entry immediately")
      return {
        workflowData: {
          payloadId: entry.redeliveryVaa
            ? RelayerPayloadId.Redelivery
            : RelayerPayloadId.Delivery,
          deliveryVaaIndex: resolvedEntry.deliveryVaaIdx,
          vaas: resolvedEntry.vaas.map((v) => v.bytes),
          redeliveryVaa: resolvedEntry.redeliveryVaa,
        },
      }
    }

    await vaaFetching.addEntryToPendingQueue(hash, entry, db)
    return
  }

  async handleWorkflow(
    workflow: Workflow<WorkflowPayload>,
    _providers: Providers,
    execute: ActionExecutor
  ): Promise<void> {
    this.logger.info("Got workflow")
    this.logger.info(JSON.stringify(workflow, undefined, 2))
    const payload = this.parseWorkflowPayload(workflow)
    switch (payload.payloadId) {
      case RelayerPayloadId.Delivery:
        if (payload.deliveryInstructionsContainer.sufficientlyFunded) {
          return this.handleDeliveryWorkflow(payload, execute)
        }
        this.logger.info("Delivery instruction is not sufficiently funded")
        return
      case RelayerPayloadId.Redelivery:
        return this.handleRedeliveryWorkflow(payload, execute)
    }
  }

  async handleDeliveryWorkflow(
    payload: WorkflowPayloadParsed,
    execute: ActionExecutor
  ): Promise<void> {
    for (let i = 0; i < payload.deliveryInstructionsContainer.instructions.length; i++) {
      const ix = payload.deliveryInstructionsContainer.instructions[i]
      const chainId = assertEvmChainId(ix.targetChain)
      const budget = ix.receiverValueTarget.add(ix.maximumRefundTarget).add(100)

      await execute.onEVM({
        chainId,
        f: async ({ wallet }) => {
          const relayProvider = RelayProvider__factory.connect(
            this.pluginConfig.supportedChains.get(chainId)!.relayProvider,
            wallet
          )

          const input: IDelivery.TargetDeliveryParametersSingleStruct = {
            encodedVMs: payload.vaas,
            deliveryIndex: payload.deliveryVaaIndex,
            multisendIndex: i,
            relayerRefundAddress: wallet.address,
          }

          if (!(await relayProvider.approvedSender(wallet.address))) {
            this.logger.warn(
              `Approved sender not set correctly for chain ${chainId}, should be ${wallet.address}`
            )
            return
          }

          await relayProvider
            .deliverSingle(input, { value: budget, gasLimit: 3000000 })
            .then((x) => x.wait())

          this.logger.info(
            `Relayed instruction ${i + 1} of ${
              payload.deliveryInstructionsContainer.instructions.length
            } to chain ${chainId}`
          )
        },
      })
    }
  }

  async handleRedeliveryWorkflow(
    payload: WorkflowPayloadParsed,
    execute: ActionExecutor
  ): Promise<void> {
    const redelivery = payload.redelivery!
    const chainId = assertEvmChainId(redelivery.ix.targetChain)
    await execute.onEVM({
      chainId,
      f: async ({ wallet }) => {
        const relayProvider = RelayProvider__factory.connect(
          this.pluginConfig.supportedChains.get(chainId)!.relayProvider,
          wallet
        )

        if (!(await relayProvider.approvedSender(wallet.address))) {
          this.logger.warn(
            `Approved sender not set correctly for chain ${chainId}, should be ${wallet.address}`
          )
          return
        }

        const { newReceiverValueTarget, newMaximumRefundTarget } = redelivery.ix
        const budget = newReceiverValueTarget.add(newMaximumRefundTarget).add(100)
        const input: IDelivery.TargetRedeliveryByTxHashParamsSingleStruct = {
          sourceEncodedVMs: payload.vaas,
          redeliveryVM: redelivery.vaa.bytes,
          relayerRefundAddress: wallet.address,
        }

        await relayProvider
          .redeliverSingle(input, { value: budget, gasLimit: 3000000 })
          .then((x) => x.wait())

        this.logger.info(`Redelivered instruction to chain ${chainId}`)
      },
    })
  }

  static validateConfig(
    pluginConfigRaw: Record<string, any>
  ): GenericRelayerPluginConfig {
    const supportedChains =
      pluginConfigRaw.supportedChains instanceof Map
        ? pluginConfigRaw.supportedChains
        : new Map(
            Object.entries(pluginConfigRaw.supportedChains).map(([chainId, info]) => [
              assertEvmChainId(Number(chainId)),
              info,
            ])
          )

    return {
      supportedChains,
      logWatcherSleepMs: assertInt(
        pluginConfigRaw.logWatcherSleepMs,
        "logWatcherSleepMs"
      ),
      shouldRest: assertBool(pluginConfigRaw.shouldRest, "shouldRest"),
      shouldSpy: assertBool(pluginConfigRaw.shouldSpy, "shouldSpy"),
    }
  }

  parseWorkflowPayload(workflow: Workflow<WorkflowPayload>): WorkflowPayloadParsed {
    this.logger.info("Parse workflow")
    const payloadId = workflow.data.payloadId
    const vaas = workflow.data.vaas.map((s) => Buffer.from(s, "base64"))
    const coreRelayerRedeliveryVaa =
      (workflow.data.redeliveryVaa &&
        parseVaaWithBytes(Buffer.from(workflow.data.redeliveryVaa, "base64"))) ||
      undefined
    const coreRelayerRedelivery = coreRelayerRedeliveryVaa
      ? {
          vaa: coreRelayerRedeliveryVaa,
          ix: parseRedeliveryByTxHashInstruction(coreRelayerRedeliveryVaa.payload),
        }
      : undefined
    const coreRelayerVaa = parseVaaWithBytes(vaas[workflow.data.deliveryVaaIndex])
    return {
      payloadId,
      deliveryVaa: coreRelayerVaa,
      deliveryVaaIndex: workflow.data.deliveryVaaIndex,
      redelivery: coreRelayerRedelivery,
      vaas,
      deliveryInstructionsContainer: parseDeliveryInstructionsContainer(
        coreRelayerVaa.payload
      ),
    }
  }
}
