import { tryNativeToHexString } from "@certusone/wormhole-sdk"

import {
  init,
  loadChains,
  ChainInfo,
  getCoreRelayerAddress,
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
  const coreRelayerAddress = getCoreRelayerAddress(chain)

  await relayProvider.updateCoreRelayer(coreRelayerAddress).then(wait)

  for (let i = 0; i < chains.length; i++) {
    console.log(`Cross registering with chain ${chains[i].chainId}...`)
    console.log(`Cross registering with chain ${chains[i].chainId}...`)
    await relayProvider.updateSupportedChain(chains[i].chainId, true).then(wait)
  }

  console.log("done with registrations on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
