import { tryNativeToHexString } from "@certusone/wormhole-sdk"
import {
  init,
  loadChains,
  ChainInfo,
  getCoreRelayer,
  getRelayProviderAddress,
  getCoreRelayerAddress,
} from "../helpers/env"

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
  const relayProviderAddress = getRelayProviderAddress(chain)

  await coreRelayer.setDefaultRelayProvider(relayProviderAddress)

  for (let i = 0; i < chains.length; i++) {
    await coreRelayer.registerCoreRelayerContract(
      chains[i].chainId,
      "0x" + tryNativeToHexString(getCoreRelayerAddress(chains[i]), "ethereum")
    )
  }

  console.log("Did all contract registrations for the core relayer on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
