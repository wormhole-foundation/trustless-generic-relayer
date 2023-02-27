import {
  deployWormholeRelayerImplementation,
  deployWormholeRelayerLibrary,
  deployWormholeRelayerProxy,
  deployWormholeRelayerSetup,
} from "../helpers/deployments"
import {
  init,
  loadChains,
  writeOutputFiles,
  getRelayProviderAddress,
} from "../helpers/env"

const processName = "deployWormholeRelayer"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  const output: any = {
    coreRelayerLibraries: [],
    coreRelayerImplementations: [],
    coreRelayerSetups: [],
    coreRelayerProxies: [],
  }

  for (let i = 0; i < chains.length; i++) {
    console.log(`Deploying for chain ${chains[i].chainId}...`)
    const coreRelayerLibrary = await deployWormholeRelayerLibrary(chains[i])
    const coreRelayerImplementation = await deployWormholeRelayerImplementation(
      chains[i],
      coreRelayerLibrary.address
    )
    const coreRelayerSetup = await deployWormholeRelayerSetup(chains[i])
    const coreRelayerProxy = await deployWormholeRelayerProxy(
      chains[i],
      coreRelayerSetup.address,
      coreRelayerImplementation.address,
      chains[i].wormholeAddress,
      getRelayProviderAddress(chains[i])
    )

    output.coreRelayerLibraries.push(coreRelayerLibrary)
    output.coreRelayerImplementations.push(coreRelayerImplementation)
    output.coreRelayerSetups.push(coreRelayerSetup)
    output.coreRelayerProxies.push(coreRelayerProxy)
    console.log("")
  }

  writeOutputFiles(output, processName)
}

run().then(() => console.log("Done! " + processName))
