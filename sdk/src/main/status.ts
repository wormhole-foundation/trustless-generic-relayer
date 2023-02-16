import {
  ChainId,
  CHAIN_ID_TO_NAME,
  CONTRACTS,
  getSignedVAAWithRetry,
  Network,
  parseVaa,
  tryNativeToHexString,
} from "@certusone/wormhole-sdk"
import { GetSignedVAAResponse } from "@certusone/wormhole-sdk-proto-web/lib/cjs/publicrpc/v1/publicrpc"
import { Implementation__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts"
import { BigNumber, ContractReceipt, ethers } from "ethers"
import { getCoreRelayer, getCoreRelayerAddressNative } from "../consts"
import {
  CoreRelayer,
  DeliveryEvent,
  DeliveryEventFilter,
} from "../ethers-contracts/CoreRelayer"

type DeliveryStatus =
  | "Waiting for VAA"
  | "Pending Delivery"
  | "Delivery Success"
  | "Delivery Failure"
  | "Invalid Redelivery"
  | "Forward Request Success"
  | "Forward Request Failure"
  | "Delivery Exception"

type DeliveryInfo = {
  status: DeliveryStatus
  deliveryTxHash: string | null
  vaaHash: string | null
  sourceChain: number | null
  sourceVaaSequence: BigNumber | null
}

export async function getDeliveryStatusBySourceTx(
  environment: Network,
  sourceChainId: ChainId,
  sourceChainProvider: ethers.providers.Provider,
  sourceTransaction: string,
  sourceNonce: number,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  guardianRpcHosts?: string[],
  deliveryIndex?: number
): Promise<DeliveryInfo[]> {
  const receipt = await sourceChainProvider.getTransactionReceipt(sourceTransaction)
  const bridgeAddress = CONTRACTS[environment][CHAIN_ID_TO_NAME[sourceChainId]].core
  const coreRelayerAddress = getCoreRelayerAddressNative(sourceChainId, environment)
  if (!bridgeAddress || !coreRelayerAddress) {
    throw Error("Invalid chain ID or network")
  }

  const deliveryLog = findLog(
    receipt,
    bridgeAddress,
    tryNativeToHexString(coreRelayerAddress, "ethereum"),
    sourceNonce.toString(),
    deliveryIndex ? deliveryIndex : 0
  )

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

  const deliveryEvents = await pullEventsBySourceSequence(
    environment,
    targetChain,
    targetChainProvider,
    sourceChainId,
    BigNumber.from(deliveryLog.sequence)
  )
  if (deliveryEvents.length == 0) {
    deliveryEvents.push({
      status: "Pending Delivery",
      deliveryTxHash: null,
      vaaHash: null,
      sourceChain: sourceChainId,
      sourceVaaSequence: BigNumber.from(deliveryLog.sequence),
    })
  }

  return deliveryEvents
}

export async function getDeliveryInfoByVaaHash(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  vaaHash: string
): Promise<DeliveryInfo[]> {
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

async function pullEventsBySourceSequence(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  sourceChain: number,
  sourceVaaSequence: BigNumber
): Promise<DeliveryInfo[]> {
  const coreRelayer = getCoreRelayer(targetChain, environment, targetChainProvider)

  //TODO These compile errors on sourceChain look like an ethers bug
  const deliveryFailures = coreRelayer.filters.DeliveryFailure(
    null,
    null,
    sourceChain as any,
    sourceVaaSequence
  )
  const deliverySuccesses = coreRelayer.filters.DeliverySuccess(
    null,
    null,
    sourceChain as any,
    sourceVaaSequence
  )
  const forwardFailures = coreRelayer.filters.ForwardRequestFailure(
    null,
    null,
    sourceChain as any,
    sourceVaaSequence
  )
  const forwardSuccesses = coreRelayer.filters.ForwardRequestSuccess(
    null,
    null,
    sourceChain as any,
    sourceVaaSequence
  )
  const invalidRedelivery = coreRelayer.filters.InvalidRedelivery(
    null,
    null,
    sourceChain as any,
    sourceVaaSequence
  )

  return combinedQuery(
    coreRelayer,
    deliveryFailures,
    deliverySuccesses,
    forwardFailures,
    forwardSuccesses,
    invalidRedelivery
  )
}

async function pullEventsByVaaHash(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  vaaHash: string
): Promise<DeliveryInfo[]> {
  const coreRelayer = getCoreRelayer(targetChain, environment, targetChainProvider)

  const deliveryFailures = coreRelayer.filters.DeliveryFailure(vaaHash)
  const deliverySuccesses = coreRelayer.filters.DeliverySuccess(vaaHash)
  const forwardFailures = coreRelayer.filters.ForwardRequestFailure(vaaHash)
  const forwardSuccesses = coreRelayer.filters.ForwardRequestSuccess(vaaHash)
  const invalidRedelivery = coreRelayer.filters.InvalidRedelivery(vaaHash)

  return combinedQuery(
    coreRelayer,
    deliveryFailures,
    deliverySuccesses,
    forwardFailures,
    forwardSuccesses,
    invalidRedelivery
  )
}

function transformDeliveryFailureEvents(events: DeliveryFailureEvent[]): DeliveryInfo[] {
  return events.map((x) => {
    return {
      status: "Delivery Failure",
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[0],
      sourceVaaSequence: x.args[3],
      sourceChain: x.args[2],
    }
  })
}

function transformDeliverySuccessEvents(events: DeliverySuccessEvent[]): DeliveryInfo[] {
  return events.map((x) => {
    return {
      status: "Delivery Success",
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[0],
      sourceVaaSequence: x.args[3],
      sourceChain: x.args[2],
    }
  })
}

function transformForwardRequestSuccessEvents(
  events: ForwardRequestSuccessEvent[]
): DeliveryInfo[] {
  return events.map((x) => {
    return {
      status: "Forward Request Success",
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[0],
      sourceVaaSequence: x.args[3],
      sourceChain: x.args[2],
    }
  })
}

function transformForwardRequestFailureEvents(
  events: ForwardRequestFailureEvent[]
): DeliveryInfo[] {
  return events.map((x) => {
    return {
      status: "Forward Request Failure",
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[0],
      sourceVaaSequence: x.args[3],
      sourceChain: x.args[2],
    }
  })
}

function transformInvalidRedeliveryEvents(
  events: InvalidRedeliveryEvent[]
): DeliveryInfo[] {
  return events.map((x) => {
    return {
      status: "Invalid Redelivery",
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[0],
      sourceVaaSequence: x.args[3],
      sourceChain: x.args[2],
    }
  })
}

async function combinedQuery(
  coreRelayer: CoreRelayer,
  deliveryFailureTopics: DeliveryFailureEventFilter,
  deliverySuccessTopics: DeliverySuccessEventFilter,
  forwardFailureTopics: ForwardRequestFailureEventFilter,
  forwardSuccessTopics: ForwardRequestSuccessEventFilter,
  invalidRedeliveryTopics: InvalidRedeliveryEventFilter
) {
  //TODO potentially query for all at once
  // let combinedTopics : (string | string [])[] = []
  // deliveryFailures.topics?.forEach(x => combinedTopics.push(x));
  // deliverySuccesses.topics?.forEach(x => combinedTopics.push(x))
  // forwardFailures.topics?.forEach(x => combinedTopics.push(x))
  // forwardSuccesses.topics?.forEach(x => combinedTopics.push(x))
  // invalidRedelivery.topics?.forEach(x => combinedTopics.push(x))

  // Can't query more than 2048 blocks at a time

  const deliveryFailureEvents = transformDeliveryFailureEvents(
    await coreRelayer.queryFilter(deliveryFailureTopics, -2040, 'latest')
  )
  const deliverySuccessEvents = transformDeliverySuccessEvents(
    await coreRelayer.queryFilter(deliverySuccessTopics, -2040, 'latest')
  )
  const forwardRequestFailureEvents = transformForwardRequestFailureEvents(
    await coreRelayer.queryFilter(forwardFailureTopics, -2040, 'latest')
  )
  const forwardRequestSuccessEvents = transformForwardRequestSuccessEvents(
    await coreRelayer.queryFilter(forwardSuccessTopics, -2040, 'latest')
  )
  const invalidRedeliveryEvents = transformInvalidRedeliveryEvents(
    await coreRelayer.queryFilter(invalidRedeliveryTopics, -2040, 'latest')
  )

  return combineDeliveryInfos([
    deliveryFailureEvents,
    deliverySuccessEvents,
    forwardRequestFailureEvents,
    forwardRequestSuccessEvents,
    invalidRedeliveryEvents,
  ])
}

function combineDeliveryInfos(array: DeliveryInfo[][]): DeliveryInfo[] {
  return array.flatMap((x) => x)
}

export function findLog(
  receipt: ContractReceipt,
  bridgeAddress: string,
  emitterAddress: string,
  nonce: string,
  deliveryIndex: number
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
    };
  })

  const filtered = parsed.filter(
    (x) =>
      x.emitterAddress == emitterAddress.toLowerCase() && x.nonce == nonce.toLowerCase()
  )

  if (filtered.length == 0) {
    throw Error("No CoreRelayer contract interactions found for this transaction.")
  }

  if (deliveryIndex >= filtered.length) {
    throw Error("Specified delivery index is out of range.")
  } else {
    return {
      log: filtered[deliveryIndex].log,
      sequence: filtered[deliveryIndex].sequence,
    }
  }
}

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
