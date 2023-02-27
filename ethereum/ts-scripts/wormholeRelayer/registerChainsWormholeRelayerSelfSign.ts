import { tryNativeToHexString } from "@certusone/wormhole-sdk"
import {
  init,
  loadChains,
  ChainInfo,
  getWormholeRelayer,
  getRelayProviderAddress,
  getWormholeRelayerAddress,
} from "../helpers/env"
import { wait } from "../helpers/utils"
import { createRegisterChainVAA, createDefaultRelayProviderVAA } from "../helpers/vaa"

const processName = "registerChainsWormholeRelayer"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  for (let i = 0; i < chains.length; i++) {
    await registerChainsWormholeRelayer(chains[i])
  }
}

async function registerChainsWormholeRelayer(chain: ChainInfo) {
  console.log("registerChainsWormholeRelayer " + chain.chainId)

  const coreRelayer = getWormholeRelayer(chain)
  await coreRelayer
    .setDefaultRelayProvider(createDefaultRelayProviderVAA(chain))
    .then(wait)
  for (let i = 0; i < chains.length; i++) {
    await coreRelayer
      .registerWormholeRelayerContract(createRegisterChainVAA(chains[i]))
      .then(wait);
  }

  console.log("Did all contract registrations for the core relayer on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
