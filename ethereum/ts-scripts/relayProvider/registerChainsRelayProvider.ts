import { tryNativeToHexString } from "@certusone/wormhole-sdk"

import {
  init,
  loadChains,
  ChainInfo,
  getWormholeRelayerAddress,
  getRelayProvider,
  getRelayProviderAddress,
} from "../helpers/env"
import { wait } from "../helpers/utils"

const processName = "registerChainsRelayProvider"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  for (let i = 0; i < chains.length; i++) {
    await registerChainsRelayProvider(chains[i])
  }
}

async function registerChainsRelayProvider(chain: ChainInfo) {
  console.log("about to perform registrations for chain " + chain.chainId)

  const relayProvider = getRelayProvider(chain)
  const coreRelayerAddress = getWormholeRelayerAddress(chain)

  await relayProvider.updateWormholeRelayer(coreRelayerAddress).then(wait)

  for (let i = 0; i < chains.length; i++) {
    console.log(`Cross registering with chain ${chains[i].chainId}...`)
    const targetChainProviderAddress = getRelayProviderAddress(chains[i])
    const whAddress = "0x" + tryNativeToHexString(targetChainProviderAddress, "ethereum")
    await relayProvider.updateDeliveryAddress(chains[i].chainId, whAddress).then(wait)
  }

  console.log("done with registrations on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
