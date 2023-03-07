import {
  ChainId,
  CHAIN_ID_TO_NAME,
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

type DeliveryStatus =
  | "Waiting for VAA"
  | "Pending Delivery"
  | "Delivery Success"
  | "Receiver Failure"
  | "Invalid Redelivery"
  | "Forward Request Success"
  | "Forward Request Failure"
  | "This should never happen. Contact Support."
  | "Delivery didn't happen within given block range"

type DeliveryTargetInfo = {
  status: DeliveryStatus
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
  sourceNonce?: number
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
    return { type: -1, parsed: "Invalid wormhole message" }
  }
}

type DeliveryInfo = {
  type: RelayerPayloadId.Delivery
  sourceChainId: ChainId,
  sourceTransactionHash: string
  deliveryInstructionsContainer: DeliveryInstructionsContainer
  targetChainStatuses: {
    chainId: ChainId
    events: { status: DeliveryStatus; transactionHash: string | null }[]
  }[]
}

type RedeliveryInfo = {
  type: RelayerPayloadId.Redelivery
  redeliverySourceChainId: ChainId,
  redeliverySourceTransactionHash: string
  redeliveryInstruction: RedeliveryByTxHashInstruction
}

function printChain(chainId: number) {
  return `${CHAIN_ID_TO_NAME[chainId as ChainId]} (Chain ${chainId})`
}

export function printInfo(info: DeliveryInfo | RedeliveryInfo) {
  if(info.type==RelayerPayloadId.Redelivery) {
    console.log(`Found Redelivery request in transaction ${info.redeliverySourceTransactionHash} on ${printChain(info.redeliverySourceChainId)}`)
    console.log(`Original Delivery Source Chain: ${printChain(info.redeliveryInstruction.sourceChain)}`)
    console.log(`Original Delivery Source Transaction Hash: 0x${info.redeliveryInstruction.sourceTxHash.toString("hex")}`)
    console.log(`Original Delivery Source Nonce: ${info.redeliveryInstruction.sourceNonce}`)
    console.log(`Target Chain: ${printChain(info.redeliveryInstruction.targetChain)}`)
    console.log(`multisendIndex: ${info.redeliveryInstruction.multisendIndex}`)
    console.log(`deliveryIndex: ${info.redeliveryInstruction.deliveryIndex}`)
    console.log(`New max amount (in target chain currency) to use for gas: ${info.redeliveryInstruction.newMaximumRefundTarget}`)
    console.log(`New amount (in target chain currency) to pass into target address: ${info.redeliveryInstruction.newMaximumRefundTarget}`)
    console.log(`New target chain gas limit: ${info.redeliveryInstruction.executionParameters.gasLimit}`)
    console.log(`Relay Provider Delivery Address: 0x${info.redeliveryInstruction.executionParameters.providerDeliveryAddress.toString("hex")}`)
  } else if(info.type==RelayerPayloadId.Delivery) {
    console.log(`Found delivery request in transaction ${info.sourceTransactionHash} on ${printChain(info.sourceChainId)}`)
    console.log((info.deliveryInstructionsContainer.sufficientlyFunded ? "The delivery was funded" : "** NOTE: The delivery was NOT sufficiently funded. You did not have enough leftover funds to perform the forward **"))
    const length = info.deliveryInstructionsContainer.instructions.length;
    console.log(`\nMessages were requested to be sent to ${length} destination${length == 1 ? "" : "s"}:`)
    console.log(info.deliveryInstructionsContainer.instructions.map((instruction: DeliveryInstruction, i) => {
      let result = "";
      const targetChainName = CHAIN_ID_TO_NAME[instruction.targetChain as ChainId];
      result += `\n(Destination ${i}): Target address is 0x${instruction.targetAddress.toString("hex")} on ${printChain(instruction.targetChain)}\n`
      result += `Max amount to use for gas: ${instruction.maximumRefundTarget} of ${targetChainName} currency\n`
      result += instruction.receiverValueTarget.gt(0) ? `Amount to pass into target address: ${instruction.receiverValueTarget} of ${CHAIN_ID_TO_NAME[instruction.targetChain as ChainId]} currency\n` : ``
      result += `Gas limit: ${instruction.executionParameters.gasLimit} ${targetChainName} gas\n`
      result += `Relay Provider Delivery Address: 0x${instruction.executionParameters.providerDeliveryAddress.toString("hex")}\n`
      result += info.targetChainStatuses[i].events.map((e, i) => (`Delivery attempt ${i+1}: ${e.status}${e.transactionHash ? ` (${targetChainName} transaction hash: ${e.transactionHash})` : ""}`)).join("\n")
      return result;
    }).join("\n"))
  }
}

export async function getDeliveryInfoBySourceTx(
  infoRequest: InfoRequest
): Promise<DeliveryInfo | RedeliveryInfo> {
  const sourceChainProvider =
    infoRequest.sourceChainProvider ||
    new ethers.providers.StaticJsonRpcProvider(
      RPCS_BY_CHAIN[infoRequest.environment][CHAIN_ID_TO_NAME[infoRequest.sourceChain]]
    )
  if (!sourceChainProvider)
    throw Error(
      "No default RPC for this chain; pass in your own provider (as sourceChainProvider)"
    )
  console.log(
    "Default RPC: " +
      RPCS_BY_CHAIN[infoRequest.environment][CHAIN_ID_TO_NAME[infoRequest.sourceChain]]
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
    throw Error("Invalid chain ID or network")
  }

  const deliveryLog = findLog(
    receipt,
    bridgeAddress,
    tryNativeToHexString(coreRelayerAddress, "ethereum"),
    infoRequest.coreRelayerWhMessageIndex ? infoRequest.coreRelayerWhMessageIndex : 0,
    infoRequest.sourceNonce?.toString()
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
    if(!isChain(targetChain)) throw Error("Invalid Chain")
    const targetChainProvider = 
      infoRequest.targetChainProviders?.get(targetChain) ||
      new ethers.providers.StaticJsonRpcProvider(
        RPCS_BY_CHAIN[infoRequest.environment][CHAIN_ID_TO_NAME[targetChain]]
      )

    if (!targetChainProvider)
      throw Error(
        "No default RPC for this chain; pass in your own provider (as targetChainProvider)"
      )

    const deliveryEvents = await pullEventsBySourceSequence(
      infoRequest.environment,
      targetChain,
      targetChainProvider,
      infoRequest.sourceChain,
      BigNumber.from(deliveryLog.sequence)
    )
    if (deliveryEvents.length == 0) {
      deliveryEvents.push({
        status: "Delivery didn't happen within given block range",
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

async function pullEventsBySourceSequence(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  sourceChain: number,
  sourceVaaSequence: BigNumber
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
    await coreRelayer.queryFilter(deliveryEvents),
    targetChainProvider
  )
}

function deliveryStatus(status: number) {
  switch (status) {
    case 0:
      return "Delivery Success"
    case 1:
      return "Receiver Failure"
    case 2:
      return "Forward Request Failure"
    case 3:
      return "Forward Request Success"
    case 4:
      return "Invalid Redelivery"
    default:
      return "This should never happen. Contact Support."
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
  nonce?: string
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
      x.emitterAddress == emitterAddress.toLowerCase() &&
      (!nonce || x.nonce == nonce.toLowerCase())
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

/* [1]
  let vaa: GetSignedVAAResponse | null = null
  if (guardianRpcHosts && guardianRpcHosts.length > 0) {
    vaa = await pullVaa(
      guardianRpcHosts,
      sourceTransaction,
      coreRelayerAddress,
      deliveryLog.sequence,
      sourceChainId
    )
    //TODO we should technically return this value if the other VAAs in the batch aren't emitted yet as well
    if (!vaa) {
      return [
        {
          status: "Waiting for VAA",
          deliveryTxHash: null,
          vaaHash: null,
          sourceChain: sourceChainId,
          sourceVaaSequence: BigNumber.from(deliveryLog.sequence),
        },
      ]
    }
  }

  if (vaa != null) {
    return getDeliveryInfoByVaaHash(
      environment,
      targetChain,
      targetChainProvider,
      parseVaa(vaa.vaaBytes).hash.toString("hex")
    )
    
  }
  */

/*
export async function getDeliveryInfoByVaaHash(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  vaaHash: string
): Promise<DeliveryTargetInfo[]> {
  const deliveryEventInfos = await pullEventsByVaaHash(
    environment,
    targetChain,
    targetChainProvider,
    vaaHash
  )
  if (deliveryEventInfos.length == 0) {
    deliveryEventInfos.push({
      //can't actually figure out the sequence number from this because there's no way to pull a VAA by its hash
      status: "Pending Delivery",
      deliveryTxHash: null,
      vaaHash: null,
      sourceChain: null,
      sourceVaaSequence: null,
    })
  }

  return deliveryEventInfos
}

async function pullEventsByVaaHash(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  vaaHash: string
): Promise<DeliveryTargetInfo[]> {
  const coreRelayer = getCoreRelayer(targetChain, environment, targetChainProvider)

  const deliverys = coreRelayer.filters.Delivery(null, null, null, vaaHash)

  return combinedQuery(
    coreRelayer,
    deliverys
  )
}
*/

/*
//TODO be able to find the VAA even if the sequence number rolls back
export async function pullVaa(
  hosts: string[],
  txHash: string,
  emitterAddress: string,
  sequence: string,
  chain: ChainId
) {
  try {
    return await getSignedVAAWithRetry(
      hosts,
      chain,
      emitterAddress,
      sequence,
      {},
      undefined,
      hosts.length * 2
    )
  } catch (e) {}

  return null
}

export async function pullAllVaasForTx(hosts: string[], txHash: string) {
  //TODO This
}
*/
