import { init, loadChains, writeOutputFiles } from "../helpers/env"
import { deployMockIntegration } from "../helpers/deployments"

const processName = "deployMockIntegration"
init()
const chains = loadChains()

async function run() {
  console.log("Start!")
  const output: any = {
    mockIntegrations: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const mockIntegration = await deployMockIntegration(chains[i])

    output.mockIntegrations.push(mockIntegration)
  }

  writeOutputFiles(output, processName)
}

run().then(() => console.log("Done!"))
