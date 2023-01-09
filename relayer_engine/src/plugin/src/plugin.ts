import {
  ActionExecutor,
  assertBool,
  assertInt,
  CommonPluginEnv,
  ContractFilter,
  dbg,
  ParsedVaaWithBytes,
  parseVaaWithBytes,
  Plugin,
  PluginDefinition,
  Providers,
  StagingAreaKeyLock,
  Workflow,
} from "@wormhole-foundation/relayer-engine"
import * as wh from "@certusone/wormhole-sdk"
import { Logger } from "winston"
import { PluginError } from "./utils"
import { parseSequencesFromLogEth, SignedVaa } from "@certusone/wormhole-sdk"
import { CoreRelayer__factory, IWormhole, IWormhole__factory } from "../../../../sdk/src"
import * as ethers from "ethers"
import { Implementation__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts"
import { LogMessagePublishedEvent } from "../../../../sdk/src/ethers-contracts/IWormhole"
import { CoreRelayerStructs } from "../../../../sdk/src/ethers-contracts/CoreRelayer"
import * as _ from "lodash"

let PLUGIN_NAME: string = "GenericRelayerPlugin"

export interface ChainInfo {
  coreContract?: IWormhole
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
  coreRelayerVaaIndex: number
  vaas: string[] // base64
}

interface WorkflowPayloadParsed {
  deliveryInstructionsContainer: DeliveryInstructionsContainer
  coreRelayerVaaIndex: number
  coreRelayerVaa: ParsedVaaWithBytes
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
    providers: Providers,
    _eventSource?: (event: SignedVaa) => Promise<void>
  ) {
    // connect to the core wh contract for each chain
    for (const [chainId, info] of this.pluginConfig.supportedChains.entries()) {
      const chainName = wh.coalesceChainName(chainId)
      const { core } = wh.CONTRACTS.TESTNET[chainName]
      if (!core || !wh.isEVMChain(chainId)) {
        this.logger.error("No known core contract for chain", chainName)
        throw new PluginError("No known core contract for chain", { chainName })
      }
      info.coreContract = IWormhole__factory.connect(
        core,
        providers.evm[chainId as wh.EVMChainId]
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
    _stagingArea: StagingAreaKeyLock,
    _providers: Providers
  ): Promise<{ workflowData?: WorkflowPayload }> {
    const payloadType = parsePayloadType(coreRelayerVaa.payload)
    if (payloadType !== RelayerPayloadType.Delivery) {
      // todo: support redelivery
      this.logger.warn(
        "Only delivery payloads currently implemented, found type: " + payloadType
      )
      return {}
    }

    const chainId = coreRelayerVaa.emitterChain as wh.EVMChainId
    const rx = await this.fetchReceipt(coreRelayerVaa.sequence, chainId)
    const allVAAs = await this.fetchOtherVaas(rx, coreRelayerVaa.nonce, chainId)
    const coreRelayerVaaIndex = allVAAs.findIndex((vaa) =>
      vaa.emitterAddress.equals(coreRelayerVaa.emitterAddress)
    )
    if (coreRelayerVaaIndex === -1) {
      throw new PluginError("CoreRelayerVaa not found in fetched vaas", { vaas: allVAAs })
    }

    return {
      workflowData: {
        coreRelayerVaaIndex,
        vaas: allVAAs.map((vaa) => vaa.bytes.toString("base64")),
      },
    }
  }

  // fetch  the contract transaction receipt for the given sequence number emitted by the core relayer contract
  async fetchReceipt(
    sequence: BigInt,
    chainId: wh.EVMChainId
  ): Promise<ethers.ContractReceipt> {
    const config = this.pluginConfig.supportedChains.get(chainId)!
    const coreWHContract = config.coreContract!
    const filter = coreWHContract.filters.LogMessagePublished(config.relayerAddress)

    const blockNumber = await coreWHContract.provider.getBlockNumber()
    for (let i = 0; i < 20; ++i) {
      let paginatedLogs
      if (i === 0) {
        paginatedLogs = await coreWHContract.queryFilter(filter, -20)
      } else {
        paginatedLogs = await coreWHContract.queryFilter(
          filter,
          blockNumber - (i + 1) * 20,
          blockNumber - i * 20
        )
      }
      const log = paginatedLogs.find(
        (log) => log.args.sequence.toString() === sequence.toString()
      )
      if (log) {
        return await log.getTransactionReceipt()
      }
    }
    throw new PluginError("Could not find contract receipt", { sequence, chainId })
  }

  async fetchOtherVaas(
    rx: ethers.ContractReceipt,
    batchId: number, // aka nonce
    chainId: wh.EVMChainId
  ): Promise<ParsedVaaWithBytes[]> {
    // collect all vaas
    // @ts-ignore
    const onlyVAALogs = rx.logs.filter(
      (log) =>
        log.address ===
        this.pluginConfig.supportedChains.get(chainId)?.coreContract?.address
    )
    const vaas: ParsedVaaWithBytes[] = await Promise.all(
      onlyVAALogs.map(async (bridgeLog: ethers.providers.Log) => {
        const iface = Implementation__factory.createInterface()
        const log = iface.parseLog(bridgeLog) as unknown as LogMessagePublishedEvent
        const resp = await wh.getSignedVAAWithRetry(
          ["https://wormhole-v2-testnet-api.certus.one"],
          chainId,
          wh.tryNativeToHexString(log.args.sender, "ethereum"),
          log.args.sequence.toString(),
          undefined,
          undefined,
          10
        )
        return parseVaaWithBytes(resp.vaaBytes)
      })
    )

    if (vaas.length == 0) {
      // todo: figure out error handling for subscription code
      this.logger.error("Expected generic relay tx to have >0 VAAs")
    }
    return vaas.filter((vaa) => vaa.nonce === batchId)
  }

  async handleWorkflow(
    workflow: Workflow<WorkflowPayload>,
    _providers: Providers,
    execute: ActionExecutor
  ): Promise<void> {
    this.logger.info("Got workflow")
    this.logger.info(JSON.stringify(workflow, undefined, 2))
    console.log("sanity console log")

    const payload = this.parseWorkflowPayload(workflow)
    for (let i = 0; i < payload.deliveryInstructionsContainer.instructions.length; i++) {
      const ix = payload.deliveryInstructionsContainer.instructions[i]
      const budget = ix.applicationBudgetTarget.add(ix.maximumRefundTarget).add(100) // todo: add wormhole fee
      const input: CoreRelayerStructs.TargetDeliveryParametersSingleStruct = {
        encodedVMs: payload.vaas,
        deliveryIndex: payload.coreRelayerVaaIndex,
        multisendIndex: i,
      }
      const chainId = ix.targetChain as wh.EVMChainId

      // todo: consider parallelizing this
      await execute.onEVM({
        chainId,
        f: async ({ wallet }) => {
          const coreRelayer = CoreRelayer__factory.connect(
            this.pluginConfig.supportedChains.get(chainId)!.relayerAddress,
            wallet
          )
          const rx = await coreRelayer
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

  static validateConfig(
    pluginConfigRaw: Record<string, any>
  ): GenericRelayerPluginConfig {
    const supportedChains =
      pluginConfigRaw.supportedChains instanceof Map
        ? pluginConfigRaw.supportedChains
        : new Map(
            Object.entries(pluginConfigRaw.supportedChains).map(([chainId, info]) => [
              Number(chainId) as wh.EVMChainId,
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
    const vaas = workflow.data.vaas.map((s) => Buffer.from(s, "base64"))
    const coreRelayerVaa = parseVaaWithBytes(vaas[workflow.data.coreRelayerVaaIndex])
    return {
      coreRelayerVaa,
      coreRelayerVaaIndex: workflow.data.coreRelayerVaaIndex,
      vaas,
      deliveryInstructionsContainer: parseDeliveryInstructionsContainer(
        coreRelayerVaa.payload
      ),
    }
  }
}

class Definition implements PluginDefinition<GenericRelayerPluginConfig, Plugin> {
  pluginName: string = PLUGIN_NAME

  init(pluginConfig: any): {
    fn: (engineConfig: any, logger: Logger) => GenericRelayerPlugin
    pluginName: string
  } {
    const pluginConfigParsed: GenericRelayerPluginConfig =
      GenericRelayerPlugin.validateConfig(pluginConfig)
    return {
      fn: (env, logger) => new GenericRelayerPlugin(env, pluginConfigParsed, logger),
      pluginName: this.pluginName,
    }
  }
}

// todo: move to sdk
export default new Definition()

import { arrayify } from "ethers/lib/utils"

export enum RelayerPayloadType {
  Delivery = 1,
  Redelivery = 2,
  // DeliveryStatus = 3,
}

export interface DeliveryInstructionsContainer {
  payloadId: number
  sufficientlyFunded: boolean
  instructions: DeliveryInstruction[]
}

export interface DeliveryInstruction {
  targetChain: number
  targetAddress: Buffer
  refundAddress: Buffer
  maximumRefundTarget: ethers.BigNumber
  applicationBudgetTarget: ethers.BigNumber
  executionParameters: ExecutionParameters
}

export interface ExecutionParameters {
  version: number
  gasLimit: number
  providerDeliveryAddress: Buffer
}

export function parsePayloadType(
  stringPayload: string | Buffer | Uint8Array
): RelayerPayloadType {
  const payload =
    typeof stringPayload === "string" ? arrayify(stringPayload) : stringPayload
  if (payload[0] == 0 || payload[0] >= 3) {
    throw new Error("Unrecogned payload type " + payload[0])
  }
  return payload[0]
}

export function parseDeliveryInstructionsContainer(
  bytes: Buffer
): DeliveryInstructionsContainer {
  dbg(bytes.length, "payload length")
  let idx = 0
  const payloadId = bytes.readUInt8(idx)
  if (payloadId !== RelayerPayloadType.Delivery) {
    throw new Error(
      `Expected Delivery payload type (${RelayerPayloadType.Delivery}), found: ${payloadId}`
    )
  }
  idx += 1

  const sufficientlyFunded = Boolean(bytes.readUInt8(idx))
  idx += 1
  dbg(sufficientlyFunded)

  const numInstructions = bytes.readUInt8(idx)
  dbg(numInstructions)
  idx += 1
  let instructions = [] as DeliveryInstruction[]
  for (let i = 0; i < numInstructions; ++i) {
    const targetChain = bytes.readUInt16BE(idx)
    dbg(targetChain)
    idx += 2
    const targetAddress = bytes.slice(idx, idx + 32)
    dbg(targetAddress)
    idx += 32
    const refundAddress = bytes.slice(idx, idx + 32)
    dbg(refundAddress)
    idx += 32
    const maximumRefundTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    dbg(maximumRefundTarget)
    idx += 32
    const applicationBudgetTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    dbg(applicationBudgetTarget)
    idx += 32
    const version = bytes.readUInt8(idx)
    dbg(version)
    idx += 1
    const gasLimit = bytes.readUint32BE(idx)
    dbg(gasLimit)
    idx += 4
    const providerDeliveryAddress = bytes.slice(idx, idx + 32)
    dbg(providerDeliveryAddress)
    idx += 32
    const executionParameters = { version, gasLimit, providerDeliveryAddress }
    instructions.push(
      // dumb typechain format
      {
        targetChain,
        targetAddress,
        refundAddress,
        maximumRefundTarget,
        applicationBudgetTarget,
        executionParameters,
      }
    )
  }
  console.log("here")
  return {
    payloadId,
    sufficientlyFunded,
    instructions,
  }
}
