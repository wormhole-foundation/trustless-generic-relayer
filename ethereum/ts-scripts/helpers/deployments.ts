import { RelayProviderProxy__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderProxy__factory"
import { RelayProviderSetup__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderSetup__factory"
import { RelayProviderImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderImplementation__factory"
import { MockRelayerIntegration__factory } from "../../../sdk/src"
import { CoreRelayerProxy__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerProxy__factory"
import { CoreRelayerSetup__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerSetup__factory"
import { CoreRelayerImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/CoreRelayerImplementation__factory"

import {
  init,
  loadChains,
  loadPrivateKey,
  writeOutputFiles,
  ChainInfo,
  Deployment,
  getSigner,
  getCoreRelayerAddress,
} from "./env"
import { ethers } from "ethers"

export async function deployRelayProviderImplementation(
  chain: ChainInfo
): Promise<Deployment> {
  console.log("deployRelayProviderImplementation " + chain.chainId)
  const signer = getSigner(chain)

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
  const signer = getSigner(chain)
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

  const signer = getSigner(chain)
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

export async function deployMockIntegration(chain: ChainInfo): Promise<Deployment> {
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

export async function deployCoreRelayerImplementation(
  chain: ChainInfo
): Promise<Deployment> {
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
export async function deployCoreRelayerSetup(chain: ChainInfo): Promise<Deployment> {
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
export async function deployCoreRelayerProxy(
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
