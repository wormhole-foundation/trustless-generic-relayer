import { deployCoreRelayerImplementation } from "../helpers/deployments"
import { init, loadChains, writeOutputFiles } from "../helpers/env"

const processName = "deployCoreRelayerImpl"
init()
const chains = loadChains()

async function run() {
  console.log("Start! " + processName)

  const output: any = {
    coreRelayerImplementations: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const coreRelayerImplementation = await deployCoreRelayerImplementation(chains[i])
    output.coreRelayerImplementations.push(coreRelayerImplementation)
  }

  writeOutputFiles(output, processName)
}

run().then(() => console.log("Done! " + processName))
