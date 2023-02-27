import { RelayProviderProxy__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderProxy__factory"
import { RelayProviderSetup__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderSetup__factory"
import { RelayProviderImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/RelayProviderImplementation__factory"
import { MockRelayerIntegration__factory } from "../../../sdk/src"
import { WormholeRelayerProxy__factory } from "../../../sdk/src/ethers-contracts/factories/WormholeRelayerProxy__factory"
import { WormholeRelayerSetup__factory } from "../../../sdk/src/ethers-contracts/factories/WormholeRelayerSetup__factory"
import { WormholeRelayerImplementation__factory } from "../../../sdk/src/ethers-contracts/factories/WormholeRelayerImplementation__factory"
import { WormholeRelayerLibrary__factory } from "../../../sdk/src/ethers-contracts/factories/WormholeRelayerLibrary__factory"

import {
  init,
  loadChains,
  loadPrivateKey,
  writeOutputFiles,
  ChainInfo,
  Deployment,
  getSigner,
  getWormholeRelayerAddress,
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
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}

export async function deployRelayProviderSetup(chain: ChainInfo): Promise<Deployment> {
  console.log("deployRelayProviderSetup " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = RelayProviderSetup__factory.createInterface()
  const bytecode = RelayProviderSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
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
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}

export async function deployMockIntegration(chain: ChainInfo): Promise<Deployment> {
  console.log("deployMockIntegration " + chain.chainId)

  let signer = getSigner(chain)
  const contractInterface = MockRelayerIntegration__factory.createInterface()
  const bytecode = MockRelayerIntegration__factory.bytecode
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy(
    chain.wormholeAddress,
    getWormholeRelayerAddress(chain)
  )
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}

export async function deployWormholeRelayerLibrary(chain: ChainInfo): Promise<Deployment> {
  console.log("deployWormholeRelayerLibrary " + chain.chainId)

  let signer = getSigner(chain)
  const contractInterface = WormholeRelayerLibrary__factory.createInterface()
  const bytecode = WormholeRelayerLibrary__factory.bytecode
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}

export async function deployWormholeRelayerImplementation(
  chain: ChainInfo,
  coreRelayerLibraryAddress: string
): Promise<Deployment> {
  console.log("deployWormholeRelayerImplementation " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = WormholeRelayerImplementation__factory.createInterface()
  const bytecode: string = WormholeRelayerImplementation__factory.bytecode

  /*
  Linked libraries in EVM are contained in the bytecode and linked at compile time.
  However, the linked address of the WormholeRelayerLibrary is not known until deployment time,
  So, rather that recompiling the contracts with a static link, we modify the bytecode directly 
  once we have the CoreRelayLibraryAddress.
  */
  const bytecodeWithLibraryLink = link(
    bytecode,
    "WormholeRelayerLibrary",
    coreRelayerLibraryAddress
  )

  //@ts-ignore
  const factory = new ethers.ContractFactory(
    contractInterface,
    bytecodeWithLibraryLink,
    signer
  )
  const contract = await factory.deploy()
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}
export async function deployWormholeRelayerSetup(chain: ChainInfo): Promise<Deployment> {
  console.log("deployWormholeRelayerSetup " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = WormholeRelayerSetup__factory.createInterface()
  const bytecode = WormholeRelayerSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}
export async function deployWormholeRelayerProxy(
  chain: ChainInfo,
  coreRelayerSetupAddress: string,
  coreRelayerImplementationAddress: string,
  wormholeAddress: string,
  relayProviderProxyAddress: string
): Promise<Deployment> {
  console.log("deployWormholeRelayerProxy " + chain.chainId)
  const signer = getSigner(chain)
  const contractInterface = WormholeRelayerProxy__factory.createInterface()
  const bytecode = WormholeRelayerProxy__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)

  const governanceChainId = 1
  const governanceContract =
    "0x0000000000000000000000000000000000000000000000000000000000000004"

  let ABI = ["function setup(address,uint16,address,address,uint16,bytes32,uint256)"]
  let iface = new ethers.utils.Interface(ABI)
  let encodedData = iface.encodeFunctionData("setup", [
    coreRelayerImplementationAddress,
    chain.chainId,
    wormholeAddress,
    relayProviderProxyAddress,
    governanceChainId,
    governanceContract,
    chain.evmNetworkId,
  ])

  const contract = await factory.deploy(coreRelayerSetupAddress, encodedData)
  const result = await contract.deployed()
  console.log("Successfully deployed contract at " + result.address)
  return { address: result.address, chainId: chain.chainId }
}
function link(bytecode: string, libName: String, libAddress: string) {
  //This doesn't handle the libName, because Forge embed a psuedonym into the bytecode, like
  //__$a7dd444e34bd28bbe3641e0101a6826fa7$__
  //This means we can't link more than one library per bytecode
  //const example = "__$a7dd444e34bd28bbe3641e0101a6826fa7$__"
  let symbol = /__.*?__/g
  return bytecode.replace(symbol, libAddress.toLowerCase().substr(2))
}
