import { tryNativeToHexString } from "@certusone/wormhole-sdk"
import {
  init,
  loadChains,
  ChainInfo,
  getCoreRelayer,
  getRelayProviderAddress,
  getCoreRelayerAddress,
} from "../helpers/env"
import { wait } from "../helpers/utils"
import { createRegisterChainVAA, createDefaultRelayProviderVAA } from "../helpers/vaa"

const processName = "registerChainsCoreRelayer"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  for (let i = 0; i < chains.length; i++) {
    await registerChainsCoreRelayer(chains[i])
  }
}

async function registerChainsCoreRelayer(chain: ChainInfo) {
  console.log("registerChainsCoreRelayer " + chain.chainId)

  const coreRelayer = getCoreRelayer(chain)
  await coreRelayer
    .setDefaultRelayProvider(createDefaultRelayProviderVAA(chain))
    .then(wait)
  for (let i = 0; i < chains.length; i++) {
    await coreRelayer
      .registerCoreRelayerContract(createRegisterChainVAA(chains[i]))
      .then(wait);
  }

  console.log("Did all contract registrations for the core relayer on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
