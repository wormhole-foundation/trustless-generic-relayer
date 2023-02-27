import {
  deployWormholeRelayerImplementation,
  deployWormholeRelayerLibrary,
} from "../helpers/deployments"
import { init, loadChains, writeOutputFiles } from "../helpers/env"

const processName = "deployWormholeRelayerImpl"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  const output: any = {
    coreRelayerLibraries: [],
    coreRelayerImplementations: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const coreRelayerLibrary = await deployWormholeRelayerLibrary(chains[i])
    const coreRelayerImplementation = await deployWormholeRelayerImplementation(
      chains[i],
      coreRelayerLibrary.address
    )
    output.coreRelayerImplementations.push(coreRelayerImplementation)
    output.coreRelayerLibraries.push(coreRelayerLibrary)
  }

  writeOutputFiles(output, processName)
}

run().then(() => console.log("Done! " + processName))
