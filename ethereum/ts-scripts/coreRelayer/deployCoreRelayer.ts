import { CoreRelayerProxy__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerProxy__factory"
import { CoreRelayerSetup__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerSetup__factory"
import { CoreRelayerImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerImplementation__factory"
import {
  init,
  loadChains,
  writeOutputFiles,
  ChainInfo,
  Deployment,
  getRelayProviderAddress,
  getSigner,
} from "../helpers/env"

import { ethers } from "ethers"

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

async function deployCoreRelayerImplementation(chain: ChainInfo): Promise<Deployment> {
  console.log("deployCoreRelayerImplementation " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = CoreRelayerImplementation__factory.createInterface()
  const bytecode = CoreRelayerImplementation__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}
async function deployCoreRelayerSetup(chain: ChainInfo): Promise<Deployment> {
  console.log("deployCoreRelayerSetup " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = CoreRelayerSetup__factory.createInterface()
  const bytecode = CoreRelayerSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}
async function deployCoreRelayerProxy(
  chain: ChainInfo,
  coreRelayerSetupAddress: string,
  coreRelayerImplementationAddress: string,
  wormholeAddress: string,
  relayProviderProxyAddress: string
): Promise<Deployment> {
  console.log("deployCoreRelayerProxy " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = CoreRelayerProxy__factory.createInterface()
  const bytecode = CoreRelayerProxy__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)

  let ABI = ["function setup(address,uint16,address,address)"]
  let iface = new ethers.utils.Interface(ABI)
  let encodedData = iface.encodeFunctionData("setup", [
    coreRelayerImplementationAddress,
    chain.chainId,
    wormholeAddress,
    relayProviderProxyAddress,
  ])

  const contract = await factory.deploy(coreRelayerSetupAddress, encodedData)
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

run().then(() => console.log("Done! " + processName))
