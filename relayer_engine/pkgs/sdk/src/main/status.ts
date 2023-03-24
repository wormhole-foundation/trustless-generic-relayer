import {
  ChainId,
  CHAIN_ID_TO_NAME,
  CHAINS,
  isChain,
  CONTRACTS,
  getSignedVAAWithRetry,
  Network,
  parseVaa,
  ParsedVaa,
  tryNativeToHexString,
} from "@certusone/wormhole-sdk"
import { GetSignedVAAResponse } from "@certusone/wormhole-sdk-proto-web/lib/cjs/publicrpc/v1/publicrpc"
import { Implementation__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts"
import { BigNumber, ContractReceipt, ethers, providers } from "ethers"
import {
  getCoreRelayer,
  getCoreRelayerAddressNative,
  RPCS_BY_CHAIN,
  GUARDIAN_RPC_HOSTS,
} from "../consts"
import {
  parsePayloadType,
  RelayerPayloadId,
  parseDeliveryInstructionsContainer,
  parseRedeliveryByTxHashInstruction,
  DeliveryInstruction,
  DeliveryInstructionsContainer,
  RedeliveryByTxHashInstruction,
  ExecutionParameters,
} from "../structs"
import { DeliveryEvent } from "../ethers-contracts/CoreRelayer"

enum DeliveryStatus {
  WaitingForVAA = "Waiting for VAA",
  PendingDelivery = "Pending Delivery",
  DeliverySuccess = "Delivery Success",
  ReceiverFailure = "Receiver Failure",
  InvalidRedelivery = "Invalid Redelivery",
  ForwardRequestSuccess = "Forward Request Success",
  ForwardRequestFailure = "Forward Request Failure",
  ThisShouldNeverHappen = "This should never happen. Contact Support.",
  DeliveryDidntHappenWithinRange = "Delivery didn't happen within given block range",
}

type DeliveryTargetInfo = {
  status: DeliveryStatus | string
  deliveryTxHash: string | null
  vaaHash: string | null
  sourceChain: number | null
  sourceVaaSequence: BigNumber | null
}

type InfoRequest = {
  environment: Network
  sourceChain: ChainId
  sourceTransaction: string
  sourceChainProvider?: ethers.providers.Provider
  targetChainProviders?: Map<number, ethers.providers.Provider>
  targetChainBlockRanges?: Map<number, [ethers.providers.BlockTag, ethers.providers.BlockTag]>
  coreRelayerWhMessageIndex?: number
}

export function parseWormholeLog(log: ethers.providers.Log): {
  type: RelayerPayloadId
  parsed: DeliveryInstructionsContainer | RedeliveryByTxHashInstruction | string
} {
  const abi = [
    "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel);",
  ]
  const iface = new ethers.utils.Interface(abi)
  const parsed = iface.parseLog(log)
  const payload = Buffer.from(parsed.args.payload.substring(2), "hex")
  const type = parsePayloadType(payload)
  if (type == RelayerPayloadId.Delivery) {
    return { type, parsed: parseDeliveryInstructionsContainer(payload) }
  } else if (type == RelayerPayloadId.Redelivery) {
    return { type, parsed: parseRedeliveryByTxHashInstruction(payload) }
  } else {
    throw Error("Invalid wormhole log");
  }
}

export type DeliveryInfo = {
  type: RelayerPayloadId.Delivery
  sourceChainId: ChainId,
  sourceTransactionHash: string
  deliveryInstructionsContainer: DeliveryInstructionsContainer
  targetChainStatuses: {
    chainId: ChainId
    events: { status: DeliveryStatus | string; transactionHash: string | null }[]
  }[]
}

export type RedeliveryInfo = {
  type: RelayerPayloadId.Redelivery
  redeliverySourceChainId: ChainId,
  redeliverySourceTransactionHash: string
  redeliveryInstruction: RedeliveryByTxHashInstruction
}

export function printChain(chainId: number) {
  return `${CHAIN_ID_TO_NAME[chainId as ChainId]} (Chain ${chainId})`
}

export function printInfo(info: DeliveryInfo | RedeliveryInfo) {
  console.log(stringifyInfo(info));
}
export function stringifyInfo(info: DeliveryInfo | RedeliveryInfo): string {
  let stringifiedInfo = "";
  if(info.type==RelayerPayloadId.Redelivery) {
    stringifiedInfo += (`Found Redelivery request in transaction ${info.redeliverySourceTransactionHash} on ${printChain(info.redeliverySourceChainId)}\n`)
    stringifiedInfo += (`Original Delivery Source Chain: ${printChain(info.redeliveryInstruction.sourceChain)}\n`)
    stringifiedInfo += (`Original Delivery Source Transaction Hash: 0x${info.redeliveryInstruction.sourceTxHash.toString("hex")}\n`)
    //stringifiedInfo += (`Original Delivery Source Nonce: ${info.redeliveryInstruction.sourceNonce}\n`)
    stringifiedInfo += (`Target Chain: ${printChain(info.redeliveryInstruction.targetChain)}\n`)
    stringifiedInfo += (`multisendIndex: ${info.redeliveryInstruction.multisendIndex}\n`)
    //stringifiedInfo += (`deliveryIndex: ${info.redeliveryInstruction.deliveryIndex}\n`)
    stringifiedInfo += (`New max amount (in target chain currency) to use for gas: ${info.redeliveryInstruction.newMaximumRefundTarget}\n`)
    stringifiedInfo += (`New amount (in target chain currency) to pass into target address: ${info.redeliveryInstruction.newMaximumRefundTarget}\n`)
    stringifiedInfo += (`New target chain gas limit: ${info.redeliveryInstruction.executionParameters.gasLimit}\n`)
    stringifiedInfo += (`Relay Provider Delivery Address: 0x${info.redeliveryInstruction.executionParameters.providerDeliveryAddress.toString("hex")}\n`)
  } else if(info.type==RelayerPayloadId.Delivery) {
    stringifiedInfo += (`Found delivery request in transaction ${info.sourceTransactionHash} on ${printChain(info.sourceChainId)}\n`)
    stringifiedInfo += ((info.deliveryInstructionsContainer.sufficientlyFunded ? "The delivery was funded\n" : "** NOTE: The delivery was NOT sufficiently funded. You did not have enough leftover funds to perform the forward **\n"))
    const length = info.deliveryInstructionsContainer.instructions.length;
    stringifiedInfo += (`\nMessages were requested to be sent to ${length} destination${length == 1 ? "" : "s"}:\n`)
    stringifiedInfo += (info.deliveryInstructionsContainer.instructions.map((instruction: DeliveryInstruction, i) => {
      let result = "";
      const targetChainName = CHAIN_ID_TO_NAME[instruction.targetChain as ChainId];
      result += `\n(Destination ${i}): Target address is 0x${instruction.targetAddress.toString("hex")} on ${printChain(instruction.targetChain)}\n`
      result += `Max amount to use for gas: ${instruction.maximumRefundTarget} of ${targetChainName} currency\n`
      result += instruction.receiverValueTarget.gt(0) ? `Amount to pass into target address: ${instruction.receiverValueTarget} of ${CHAIN_ID_TO_NAME[instruction.targetChain as ChainId]} currency\n` : ``
      result += `Gas limit: ${instruction.executionParameters.gasLimit} ${targetChainName} gas\n`
      result += `Relay Provider Delivery Address: 0x${instruction.executionParameters.providerDeliveryAddress.toString("hex")}\n`
      result += info.targetChainStatuses[i].events.map((e, i) => (`Delivery attempt ${i+1}: ${e.status}${e.transactionHash ? ` (${targetChainName} transaction hash: ${e.transactionHash})` : ""}`)).join("\n")
      return result;
    }).join("\n")) + "\n"
  }
  return stringifiedInfo
}

function getDefaultProvider(network: Network, chainId: ChainId) {
  return new ethers.providers.StaticJsonRpcProvider(
    RPCS_BY_CHAIN[network][CHAIN_ID_TO_NAME[chainId]]
  )
}

export async function getDeliveryInfoBySourceTx(
  infoRequest: InfoRequest
): Promise<DeliveryInfo | RedeliveryInfo> {
  const sourceChainProvider =
    infoRequest.sourceChainProvider || getDefaultProvider(infoRequest.environment, infoRequest.sourceChain);
  if (!sourceChainProvider)
    throw Error(
      "No default RPC for this chain; pass in your own provider (as sourceChainProvider)"
    )
  const receipt = await sourceChainProvider.getTransactionReceipt(
    infoRequest.sourceTransaction
  )
  if (!receipt) throw Error("Transaction has not been mined")
  const bridgeAddress =
    CONTRACTS[infoRequest.environment][CHAIN_ID_TO_NAME[infoRequest.sourceChain]].core
  const coreRelayerAddress = getCoreRelayerAddressNative(
    infoRequest.sourceChain,
    infoRequest.environment
  )
  if (!bridgeAddress || !coreRelayerAddress) {
    throw Error(`Invalid chain ID or network: Chain ID ${infoRequest.sourceChain}, ${infoRequest.environment}`)
  }

  const deliveryLog = findLog(
    receipt,
    bridgeAddress,
    tryNativeToHexString(coreRelayerAddress, "ethereum"),
    infoRequest.coreRelayerWhMessageIndex ? infoRequest.coreRelayerWhMessageIndex : 0,
  )

  const { type, parsed } = parseWormholeLog(deliveryLog.log)

  if (type == RelayerPayloadId.Redelivery) {
    const redeliveryInstruction = parsed as RedeliveryByTxHashInstruction
    return {
      type,
      redeliverySourceChainId: infoRequest.sourceChain,
      redeliverySourceTransactionHash: infoRequest.sourceTransaction,
      redeliveryInstruction,
    }
  }

  /* Potentially use 'guardianRPCHosts' to get status of VAA; code in comments at end [1] */

  const deliveryInstructionsContainer = parsed as DeliveryInstructionsContainer

  const targetChainStatuses = await Promise.all(deliveryInstructionsContainer.instructions.map(async (instruction: DeliveryInstruction) => {
    const targetChain = instruction.targetChain as ChainId;
    if(!isChain(targetChain)) throw Error(`Invalid Chain: ${targetChain}`)
    const targetChainProvider = 
      infoRequest.targetChainProviders?.get(targetChain) ||
      getDefaultProvider(infoRequest.environment, targetChain)

    if (!targetChainProvider)
      throw Error(
        "No default RPC for this chain; pass in your own provider (as targetChainProvider)"
      )
    
    const sourceChainBlock = await sourceChainProvider.getBlock(receipt.blockNumber);
    const [blockStartNumber, blockEndNumber] =  infoRequest.targetChainBlockRanges?.get(targetChain) || getBlockRange(targetChainProvider, sourceChainBlock.timestamp);

    const deliveryEvents = await pullEventsBySourceSequence(
      infoRequest.environment,
      targetChain,
      targetChainProvider,
      infoRequest.sourceChain,
      BigNumber.from(deliveryLog.sequence),
      blockStartNumber,
      blockEndNumber
    )
    if (deliveryEvents.length == 0) {
      let status = `Delivery didn't happen on ${printChain(targetChain)} within blocks ${blockStartNumber} to ${blockEndNumber}.`;
      try {
        const blockStart = await targetChainProvider.getBlock(blockStartNumber);
        const blockEnd = await targetChainProvider.getBlock(blockEndNumber);
        status = `Delivery didn't happen on ${printChain(targetChain)} within blocks ${blockStart.number} to ${blockEnd.number} (within times ${new Date(blockStart.timestamp * 1000).toString()} to ${new Date(blockEnd.timestamp * 1000).toString()})`
      } catch(e) {

      }
      deliveryEvents.push({
        status,
        deliveryTxHash: null,
        vaaHash: null,
        sourceChain: infoRequest.sourceChain,
        sourceVaaSequence: BigNumber.from(deliveryLog.sequence),
      })
    }
    return {
      chainId: targetChain,
      events: deliveryEvents.map((e)=>({status: e.status, transactionHash: e.deliveryTxHash}))
    }
  }))

  return {
    type,
    sourceChainId: infoRequest.sourceChain,
    sourceTransactionHash: infoRequest.sourceTransaction,
    deliveryInstructionsContainer,
    targetChainStatuses
  }
}

function getBlockRange(provider: ethers.providers.Provider, timestamp?: number): [ethers.providers.BlockTag, ethers.providers.BlockTag] {
  return [-2040, "latest"]
}

async function pullEventsBySourceSequence(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  sourceChain: number,
  sourceVaaSequence: BigNumber,
  blockStartNumber: ethers.providers.BlockTag,
  blockEndNumber: ethers.providers.BlockTag
): Promise<DeliveryTargetInfo[]> {
  const coreRelayer = getCoreRelayer(targetChain, environment, targetChainProvider)

  //TODO These compile errors on sourceChain look like an ethers bug
  const deliveryEvents = coreRelayer.filters.Delivery(
    null,
    sourceChain,
    sourceVaaSequence
  )

  // There is a max limit on RPCs sometimes for how many blocks to query
  return await transformDeliveryEvents(
    await coreRelayer.queryFilter(deliveryEvents, blockStartNumber, blockEndNumber),
    targetChainProvider
  )
}

function deliveryStatus(status: number) {
  switch (status) {
    case 0:
      return DeliveryStatus.DeliverySuccess
    case 1:
      return DeliveryStatus.ReceiverFailure
    case 2:
      return DeliveryStatus.ForwardRequestFailure
    case 3:
      return DeliveryStatus.ForwardRequestSuccess
    case 4:
      return DeliveryStatus.InvalidRedelivery
    default:
      return DeliveryStatus.ThisShouldNeverHappen
  }
}

async function transformDeliveryEvents(
  events: DeliveryEvent[],
  targetProvider: ethers.providers.Provider
): Promise<DeliveryTargetInfo[]> {
  return Promise.all(
    events.map(async (x) => {
      return {
        status: deliveryStatus(x.args[4]),
        deliveryTxHash: x.transactionHash,
        vaaHash: x.args[3],
        sourceVaaSequence: x.args[2],
        sourceChain: x.args[1],
      }
    })
  )
}

export function findLog(
  receipt: ContractReceipt,
  bridgeAddress: string,
  emitterAddress: string,
  index: number,
): { log: ethers.providers.Log; sequence: string } {
  const bridgeLogs = receipt.logs.filter((l) => {
    return l.address === bridgeAddress
  })

  if (bridgeLogs.length == 0) {
    throw Error("No core contract interactions found for this transaction.")
  }

  const parsed = bridgeLogs.map((bridgeLog) => {
    const log = Implementation__factory.createInterface().parseLog(bridgeLog)
    return {
      sequence: log.args[1].toString(),
      nonce: log.args[2].toString(),
      emitterAddress: tryNativeToHexString(log.args[0].toString(), "ethereum"),
      log: bridgeLog,
    }
  })

  const filtered = parsed.filter(
    (x) =>
      x.emitterAddress == emitterAddress.toLowerCase() 
  )

  if (filtered.length == 0) {
    throw Error("No CoreRelayer contract interactions found for this transaction.")
  }

  if (index >= filtered.length) {
    throw Error("Specified delivery index is out of range.")
  } else {
    return {
      log: filtered[index].log,
      sequence: filtered[index].sequence,
    }
  }
}
