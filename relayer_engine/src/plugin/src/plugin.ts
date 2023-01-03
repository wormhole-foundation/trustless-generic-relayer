import {
  ActionExecutor,
  assertBool,
  assertInt,
  CommonPluginEnv,
  ContractFilter,
  dbg,
  EventSource,
  ParsedVaaWithBytes,
  parseVaaWithBytes,
  Plugin,
  PluginDefinition,
  Providers,
  sleep,
  StagingAreaKeyLock,
  Workflow,
} from "@wormhole-foundation/relayer-engine"
import * as wh from "@certusone/wormhole-sdk"
import { Logger } from "winston"
import { PluginError } from "./utils"
import {
  EVMChainId,
  parseSequenceFromLogEth,
  parseSequencesFromLogEth,
  SignedVaa,
} from "@certusone/wormhole-sdk"
import {
  CoreRelayer__factory,
  IWormhole,
  IWormhole__factory,
  MockRelayerIntegration__factory,
  MockRelayerIntegration,
} from "../../../../sdk/src"
import * as ethers from "ethers"
import { TypedEvent } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts/commons"
import { Implementation__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts"
import { LogMessagePublishedEvent } from "../../../../sdk/src/ethers-contracts/IWormhole"
import { CoreRelayerStructs } from "../../../../sdk/src/ethers-contracts/CoreRelayer"
import * as _ from "lodash"

let PLUGIN_NAME: string = "GenericRelayerPlugin"

export interface ChainInfo {
  chainId: wh.ChainId
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
  coreRelayerVaa: string // base64
  otherVaas: string[] // base64
}

interface WorkflowPayloadParsed {
  deliveryInstructionsContainer: DeliveryInstructionsContainer
  coreRelayerVaa: ParsedVaaWithBytes
  otherVaas: ParsedVaaWithBytes[]
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
    console.log(`Config: ${JSON.stringify(engineConfig, undefined, 2)}`)
    console.log(`Plugin Env: ${JSON.stringify(pluginConfigRaw, undefined, 2)}`)

    this.pluginConfig = GenericRelayerPlugin.validateConfig(pluginConfigRaw)
    this.shouldRest = this.pluginConfig.shouldRest
    this.shouldSpy = this.pluginConfig.shouldSpy
  }

  async afterSetup(
    providers: Providers,
    eventSource?: (event: SignedVaa) => Promise<void>
  ) {
    if (!eventSource) {
      this.logger.info(
        "No eventSource function provided, not subscribing to blockchain rpc"
      )
      return
    }
    this.logger.info("Starting logWatcher event source...")
    for (const [chainId, info] of this.pluginConfig.supportedChains.entries()) {
      const chainName = wh.coalesceChainName(chainId)
      const { core } = wh.CONTRACTS.TESTNET[chainName]
      if (!core || !wh.isEVMChain(chainId)) {
        this.logger.error("No known core contract for chain", chainName)
        throw new Error("No known core contract for chain")
      }
      info.coreContract = IWormhole__factory.connect(
        core,
        providers.evm[chainId as wh.EVMChainId]
      )
    }

    // fire off task
    this.subscribeToEvents(eventSource)
  }

  async subscribeToEvents(eventSource: (event: SignedVaa) => Promise<void>) {
    // need to keep same function object to unsubscribe from events successfully
    const fns: Record<number, any> = {}
    while (true) {
      // resubscribe to contract events every 5 minutes
      for (const [
        chainId,
        { relayerAddress, coreContract },
      ] of this.pluginConfig.supportedChains.entries()) {
        if (!wh.isEVMChain(chainId) || !coreContract) {
          throw new PluginError("Invalid chain not evm", { chainId })
        }
        try {
          if (!fns[chainId]) {
            fns[chainId] = (
              _sender: string,
              sequence: ethers.BigNumber,
              _nonce: number,
              payload: string,
              _consistencyLevel: number,
              typedEvent: TypedEvent<any>
            ) =>
              this.handleRelayerEvent(
                eventSource,
                chainId as wh.EVMChainId,
                payload,
                typedEvent
              )
          }
          coreContract.off(
            coreContract.filters.LogMessagePublished(relayerAddress),
            fns[chainId]
          )
          coreContract.on(
            coreContract.filters.LogMessagePublished(relayerAddress),
            fns[chainId]
          )
          this.logger.info(
            `Subscribed to ${wh.coalesceChainName(chainId)} ${
              coreContract.address
            } ${relayerAddress}`
          )
        } catch (e: any) {
          // todo: improve error handling
          this.logger.error(e)
        }
      }
      await sleep(this.pluginConfig.logWatcherSleepMs)
    }
  }

  async handleRelayerEvent(
    this: GenericRelayerPlugin,
    eventSource: EventSource,
    chainId: wh.EVMChainId,
    payload: string,
    typedEvent: TypedEvent<
      [string, ethers.BigNumber, number, string, number] & {
        sender: string
        sequence: ethers.BigNumber
        nonce: number
        payload: string
        consistencyLevel: number
      }
    >
  ): Promise<void> {
    dbg(payload, "payload")
    dbg(typedEvent.args.payload, "event args payload")
    parsePayloadType(payload)
    const rx = await typedEvent.getTransactionReceipt()
    // todo: will need to tweak retry and backoff params
    const resp = await wh.getSignedVAAWithRetry(
      ["https://wormhole-v2-testnet-api.certus.one"],
      chainId,
      wh.tryNativeToHexString(typedEvent.args.sender, "ethereum"),
      typedEvent.args.sequence.toString(),
      undefined,
      undefined,
      10
    )
    eventSource(resp.vaaBytes, [rx])
  }

  // This plugin listens to batches or blockchain rpc events,
  // so we actually want to bypass the inbuilt filters.
  getFilters(): ContractFilter[] {
    return []
  }

  async consumeEvent(
    coreRelayerVaa: ParsedVaaWithBytes,
    _stagingArea: StagingAreaKeyLock,
    _providers: Providers,
    [rx]: [ethers.ContractReceipt]
  ): Promise<{ workflowData?: WorkflowPayload }> {
    const payloadType = parsePayloadType(coreRelayerVaa.payload)
    if (payloadType !== RelayerPayloadType.Delivery) {
      // todo: support redelivery
      this.logger.warn(
        "Only delivery payloads currently implemented, found type: " + payloadType
      )
      return {}
    }

    const emitterChain = coreRelayerVaa.emitterChain as wh.EVMChainId
    const otherVaas = await this.fetchOtherVaas(
      rx,
      coreRelayerVaa.nonce,
      emitterChain,
      coreRelayerVaa.emitterAddress
    )

    return {
      workflowData: {
        coreRelayerVaa: dbg(
          coreRelayerVaa.bytes.toString("base64"),
          "coreRelayerSerialized"
        ),
        otherVaas: otherVaas.map((vaa) => vaa.bytes.toString("base64")),
      },
    }
  }

  async fetchOtherVaas(
    rx: ethers.ContractReceipt,
    batchId: number, // aka nonce
    chainId: wh.EVMChainId,
    coreRelayerAddress: Buffer
  ): Promise<ParsedVaaWithBytes[]> {
    // parse log and fetch vaa
    const logToVaa = async (bridgeLog: ethers.providers.Log) => {
      this.logger.info("Bridge log: " + JSON.stringify(bridgeLog))
      const log = Implementation__factory.createInterface().parseLog(
        bridgeLog
      ) as unknown as LogMessagePublishedEvent
      const sender = wh.tryNativeToHexString(log.args.sender, "ethereum")
      if (
        dbg(log.args.sender.toLowerCase(), "log sender") ===
        dbg(
          wh.tryUint8ArrayToNative(coreRelayerAddress, "ethereum").toLowerCase(),
          "coreRelayerAddress"
        )
      ) {
        this.logger.info("Hitting undefined")
        return undefined
      }
      // todo: this should handle VAAs that are not ready for hours
      const resp = await wh.getSignedVAAWithRetry(
        ["https://wormhole-v2-testnet-api.certus.one"],
        chainId,
        sender,
        log.args.sequence.toString(),
        undefined,
        undefined,
        10
      )
      return parseVaaWithBytes(resp.vaaBytes)
    }

    // collect all vaas
    // @ts-ignore
    const vaas: ParsedVaaWithBytes[] = (
      await Promise.all(
        rx.logs
          .filter(
            (log) =>
              log.address ===
              this.pluginConfig.supportedChains.get(chainId)?.coreContract?.address
          )
          .map(logToVaa)
      )
    ).filter((x) => x)

    if (vaas.length == 0) {
      // todo: figure out error handling for subscription code
      this.logger.error("Expected generic relay tx to have >0 VAAs")
    }
    return vaas.filter((vaa) => vaa.nonce === batchId)
  }

  async handleWorkflow(
    workflow: Workflow<WorkflowPayload>,
    providers: Providers,
    execute: ActionExecutor
  ): Promise<void> {
    this.logger.info("Got workflow")
    this.logger.info(JSON.stringify(workflow, undefined, 2))
    console.log("sanity console log")

    const payload = this.parseWorkflowPayload(workflow)
    this.logger.info("after parse")
    for (let i = 0; i < payload.deliveryInstructionsContainer.instructions.length; i++) {
      this.logger.info("top of loop")
      const ix = payload.deliveryInstructionsContainer.instructions[i]
      const budget = ix.applicationBudgetTarget.add(ix.maximumRefundTarget).add(100) // todo: add wormhole fee
      const input: CoreRelayerStructs.TargetDeliveryParametersSingleStruct = {
        // todo: get vaas in order they were emitted
        encodedVMs: [
          ...payload.otherVaas.map((v) => v.bytes),
          payload.coreRelayerVaa.bytes,
        ],
        deliveryIndex: 1,
        multisendIndex: i,
      }
      const chainId = ix.targetChain as wh.EVMChainId
      // todo: consider parallelizing this
      await execute.onEVM({
        chainId,
        f: async ({ wallet }) => {
          let message = await MockRelayerIntegration__factory.connect(
            this.pluginConfig.supportedChains.get(chainId)!
              .mockIntegrationContractAddress,
            wallet
          ).getMessage()

          arrayify(message)
          this.logger.info(
            `Message is ${message} ${Buffer.from(message, "hex").toString()}`
          )
          const coreRelayer = CoreRelayer__factory.connect(
            this.pluginConfig.supportedChains.get(chainId)!.relayerAddress,
            wallet
          )
          const rx = await coreRelayer
            .deliverSingle(input, { value: budget, gasLimit: 3000000 })
            .then((x) => x.wait())

          const seqs = parseSequencesFromLogEth(
            rx,
            wh.tryNativeToHexString(
              this.pluginConfig.supportedChains.get(chainId)!.coreContract?.address!,
              "ethereum"
            )
          )

          seqs.forEach(async (seq) => {
            const resp = await wh.getSignedVAAWithRetry(
              ["https://wormhole-v2-testnet-api.certus.one"],
              chainId,
              wh.tryNativeToHexString(coreRelayer.address, "ethereum"),
              seq.toString(),
              undefined,
              undefined,
              10
            )
            console.log(resp)
            console.log("forward vaa: ", wh.parseVaa(resp.vaaBytes))
          })

          this.logger.info(
            `Relayed instruction ${i + 1} of ${
              payload.deliveryInstructionsContainer.instructions.length
            } to chain ${chainId}`
          )

          setTimeout(async () => {
            message = await MockRelayerIntegration__factory.connect(
              this.pluginConfig.supportedChains.get(chainId)!
                .mockIntegrationContractAddress,
              wallet
            ).getMessage()
            this.logger.info(
              `Message is ${message} ${Buffer.from(message, "hex").toString()}`
            )
          }, 2000)
          // delivery receipt will be picked up by listener for bulk redemption later
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
    this.logger.info("parse workflow")
    const coreRelayerVaa = parseVaaWithBytes(
      dbg(Buffer.from(dbg(workflow.data.coreRelayerVaa), "base64"))
    )
    this.logger.info("after parse core relayer")
    return {
      coreRelayerVaa,
      otherVaas: workflow.data.otherVaas.map((s) =>
        parseVaaWithBytes(Buffer.from(s, "base64"))
      ),
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
