import { RelayProviderProxy__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderProxy__factory"
import { RelayProviderSetup__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderSetup__factory"
import { RelayProviderImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderImplementation__factory"
import {
  init,
  loadChains,
  loadPrivateKey,
  writeOutputFiles,
  ChainInfo,
  Deployment,
} from "../helpers/env"

import { ethers } from "ethers"

const processName = "deployRelayProvider"
init()
const chains = loadChains()
const privateKey = loadPrivateKey()

async function run() {
  console.log("Start!")
  const output: any = {
    relayProviderImplementations: [],
    relayProviderSetups: [],
    relayProviderProxies: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const relayProviderImplementation = await deployRelayProviderImplementation(chains[i])
    const relayProviderSetup = await deployRelayProviderSetup(chains[i])
    const relayProviderProxy = await deployRelayProviderProxy(
      chains[i],
      relayProviderSetup.address,
      relayProviderImplementation.address
    )

    output.relayProviderImplementations.push(relayProviderImplementation)
    output.relayProviderSetups.push(relayProviderSetup)
    output.relayProviderProxies.push(relayProviderProxy)
  }

  writeOutputFiles(output, processName)
}

export async function deployRelayProviderImplementation(
  chain: ChainInfo
): Promise<Deployment> {
  console.log("deployRelayProviderImplementation " + chain.chainId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)

  const contractInterface = RelayProviderImplementation__factory.createInterface()
  const bytecode = RelayProviderImplementation__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

export async function deployRelayProviderSetup(chain: ChainInfo): Promise<Deployment> {
  console.log("deployRelayProviderSetup " + chain.chainId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = RelayProviderSetup__factory.createInterface()
  const bytecode = RelayProviderSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}
export async function deployRelayProviderProxy(
  chain: ChainInfo,
  relayProviderSetupAddress: string,
  relayProviderImplementationAddress: string
): Promise<Deployment> {
  console.log("deployRelayProviderProxy " + chain.chainId)

  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = RelayProviderProxy__factory.createInterface()
  const bytecode = RelayProviderProxy__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)

  let ABI = ["function setup(address,uint16)"]
  let iface = new ethers.utils.Interface(ABI)
  let encodedData = iface.encodeFunctionData("setup", [
    relayProviderImplementationAddress,
    chain.chainId,
  ])

  const contract = await factory.deploy(relayProviderSetupAddress, encodedData)
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.chainId }
  })
}

run().then(() => console.log("Done!"))
