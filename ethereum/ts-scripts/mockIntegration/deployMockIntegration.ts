import {
  init,
  loadChains,
  loadPrivateKey,
  writeOutputFiles,
  ChainInfo,
  Deployment,
} from "../helpers/env"

import { ethers } from "ethers"
import { getCoreRelayerAddress, getSigner } from "../helpers/env"
import { MockRelayerIntegration__factory } from "../../../sdk/src"

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

async function deployMockIntegration(chain: ChainInfo): Promise<Deployment> {
  console.log("deployMockIntegration " + chain.chainId)

  let signer = getSigner(chain)
  const contractInterface = MockRelayerIntegration__factory.createInterface()
  const bytecode = MockRelayerIntegration__factory.bytecode
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy(
    chain.wormholeAddress,
    getCoreRelayerAddress(chain)
  )
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

run().then(() => console.log("Done!"))
