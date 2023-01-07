import {
  deployCoreRelayerImplementation,
  deployCoreRelayerProxy,
  deployCoreRelayerSetup,
} from "../helpers/deployments"
import {
  init,
  loadChains,
  writeOutputFiles,
  getRelayProviderAddress,
} from "../helpers/env"

const processName = "deployCoreRelayer"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  const output: any = {
    coreRelayerImplementations: [],
    coreRelayerSetups: [],
    coreRelayerProxies: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const coreRelayerImplementation = await deployCoreRelayerImplementation(chains[i])
    const coreRelayerSetup = await deployCoreRelayerSetup(chains[i])
    const coreRelayerProxy = await deployCoreRelayerProxy(
      chains[i],
      coreRelayerSetup.address,
      coreRelayerImplementation.address,
      chains[i].wormholeAddress,
      getRelayProviderAddress(chains[i])
    )

    output.coreRelayerImplementations.push(coreRelayerImplementation)
    output.coreRelayerSetups.push(coreRelayerSetup)
    output.coreRelayerProxies.push(coreRelayerProxy)
  }

  writeOutputFiles(output, processName)
}

run().then(() => console.log("Done! " + processName))
