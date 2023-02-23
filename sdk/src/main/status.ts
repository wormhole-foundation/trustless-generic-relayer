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
import { BigNumber, ContractReceipt, ethers, providers } from "ethers"
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
  | "Receiver Failure"
  | "Invalid Redelivery"
  | "Forward Request Success"
  | "Forward Request Failure"
  | "This should never happen. Contact Support."

type DeliveryInfo = {
  status: DeliveryStatus,
  deliveryTxHash: string | null
  vaaHash: string | null
  sourceChain: number | null
  sourceVaaSequence: BigNumber | null
}

export async function getDeliveryInfoBySourceTx(
  environment: Network,
  sourceChainId: ChainId,
  sourceChainProvider: ethers.providers.Provider,
  sourceTransaction: string,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  sourceNonce?: number,
//  guardianRpcHosts?: string[],
  coreRelayerWhMessageIndex?: number
): Promise<DeliveryInfo[]> {
  const receipt = await sourceChainProvider.getTransactionReceipt(sourceTransaction)
  if(!receipt) throw Error("Transaction has not been mined")
  const bridgeAddress = CONTRACTS[environment][CHAIN_ID_TO_NAME[sourceChainId]].core
  const coreRelayerAddress = getCoreRelayerAddressNative(sourceChainId, environment)
  if (!bridgeAddress || !coreRelayerAddress) {
    throw Error("Invalid chain ID or network")
  }

  const deliveryLog = findLog(
    receipt,
    bridgeAddress,
    tryNativeToHexString(coreRelayerAddress, "ethereum"),
    coreRelayerWhMessageIndex ? coreRelayerWhMessageIndex : 0,
    sourceNonce?.toString()
  )

  /* Potentially use 'guardianRPCHosts' to get status of VAA; code in comments at end [1] */

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


async function pullEventsBySourceSequence(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  sourceChain: number,
  sourceVaaSequence: BigNumber
): Promise<DeliveryInfo[]> {
  const coreRelayer = getCoreRelayer(targetChain, environment, targetChainProvider)
  
  //TODO These compile errors on sourceChain look like an ethers bug
  const deliveryEvents = coreRelayer.filters.Delivery(null, sourceChain, sourceVaaSequence)

  // There is a max limit on RPCs sometimes for how many blocks to query
  return await transformDeliveryEvents(
    await coreRelayer.queryFilter(deliveryEvents, -2040, 'latest'), targetChainProvider
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

async function transformDeliveryEvents(events: DeliveryEvent[], targetProvider: ethers.providers.Provider): Promise<DeliveryInfo[]> {
  return Promise.all(events.map(async (x) => {
    return {
      status: deliveryStatus(x.args[4]),
      deliveryTxHash: x.transactionHash,
      vaaHash: x.args[3],
      sourceVaaSequence: x.args[2],
      sourceChain: x.args[1],
    }
  }))
}

export function findLog(
  receipt: ContractReceipt,
  bridgeAddress: string,
  emitterAddress: string,
  index: number,
  nonce?: string,
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
      x.emitterAddress == emitterAddress.toLowerCase() && ((!nonce) || (x.nonce == nonce.toLowerCase()))
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

async function pullEventsByVaaHash(
  environment: Network,
  targetChain: ChainId,
  targetChainProvider: ethers.providers.Provider,
  vaaHash: string
): Promise<DeliveryInfo[]> {
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