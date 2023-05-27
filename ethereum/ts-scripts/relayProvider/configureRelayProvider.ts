import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk"
import type { BigNumberish } from "ethers"
import {
  init,
  loadChains,
  ChainInfo,
  loadScriptConfig,
  getCoreRelayerAddress,
  getRelayProvider,
  getRelayProviderAddress,
} from "../helpers/env"
import { wait } from "../helpers/utils"

import type { RelayProviderStructs } from "../../../sdk/src"

/**
 * Meant for `config.pricingInfo`
 */
interface PricingInfo {
  chainId: ChainId
  deliverGasOverhead: BigNumberish
  updatePriceGas: BigNumberish
  updatePriceNative: BigNumberish
  maximumBudget: BigNumberish
}

/**
 * Must match `RelayProviderStructs.UpdatePrice`
 */
interface UpdatePrice {
  chainId: ChainId
  gasPrice: BigNumberish
  nativeCurrencyPrice: BigNumberish
}

const processName = "configureRelayProvider"
init()
const chains = loadChains()
const config = loadScriptConfig(processName)

async function run() {
  console.log("Start! " + processName)

  for (let i = 0; i < chains.length; i++) {
    await configureChainsRelayProvider(chains[i])
  }
}

async function configureChainsRelayProvider(chain: ChainInfo) {
  console.log("about to perform RelayProvider configurations for chain " + chain.chainId)
  const relayProvider = getRelayProvider(chain)
  const coreRelayer = getCoreRelayerAddress(chain)

  const thisChainsConfigInfo = config.addresses.find(
    (x: any) => x.chainId == chain.chainId
  )

  if (!thisChainsConfigInfo) {
    throw new Error("Failed to find address config info for chain " + chain.chainId)
  }
  if (!thisChainsConfigInfo.rewardAddress) {
    throw new Error("Failed to find reward address info for chain " + chain.chainId)
  }
  if (!thisChainsConfigInfo.approvedSenders) {
    throw new Error("Failed to find approvedSenders info for chain " + chain.chainId)
  }

  const coreConfig: RelayProviderStructs.CoreConfigStruct = {
    updateCoreRelayer: true,
    updateRewardAddress: true,
    coreRelayer,
    rewardAddress: thisChainsConfigInfo.rewardAddress,
  }
  const senderUpdates: RelayProviderStructs.SenderApprovalUpdateStruct[] =
    thisChainsConfigInfo.approvedSenders.map(
      ({ address, approved }: { address: any; approved: any }) => {
        return {
          sender: address,
          approved,
        }
      }
    )
  const updates: RelayProviderStructs.UpdateStruct[] = []

  // Set the rest of the relay provider configuration
  for (const targetChain of chains) {
    const targetChainPriceUpdate = (config.pricingInfo as PricingInfo[]).find(
      (x: any) => x.chainId == targetChain.chainId
    )
    if (!targetChainPriceUpdate) {
      throw new Error("Failed to find pricingInfo for chain " + targetChain.chainId)
    }
    const targetChainProviderAddress = getRelayProviderAddress(targetChain)
    const remoteRelayProvider =
      "0x" + tryNativeToHexString(targetChainProviderAddress, "ethereum")
    const update = {
      chainId: targetChain.chainId,
      updateAssetConversionBuffer: true,
      updateWormholeFee: false,
      updateDeliverGasOverhead: true,
      updatePrice: true,
      updateDeliveryAddress: true,
      updateMaximumBudget: true,
      buffer: 5,
      bufferDenominator: 100,
      newWormholeFee: 0,
      newGasOverhead: targetChainPriceUpdate.deliverGasOverhead,
      gasPrice: targetChainPriceUpdate.updatePriceGas,
      nativeCurrencyPrice: targetChainPriceUpdate.updatePriceNative,
      deliveryAddress: remoteRelayProvider,
      maximumTotalBudget: targetChainPriceUpdate.maximumBudget,
    }
    updates.push(update)
  }
  await relayProvider.updateConfig(updates, senderUpdates, coreConfig).then(wait)

  console.log("done with RelayProvider configuration on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
