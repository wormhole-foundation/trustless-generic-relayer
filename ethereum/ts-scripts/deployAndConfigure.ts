import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk"

import { CoreRelayer__factory } from "../../sdk/src/ethers-contracts/factories/CoreRelayer__factory"
import { CoreRelayerProxy__factory } from "../../sdk/src/ethers-contracts/factories/CoreRelayerProxy__factory"
import { CoreRelayerSetup__factory } from "../../sdk/src/ethers-contracts/factories/CoreRelayerSetup__factory"
import { CoreRelayerImplementation__factory } from "../../sdk/src/ethers-contracts/factories/CoreRelayerImplementation__factory"
import { RelayProvider__factory } from "../../sdk/src/ethers-contracts/factories/RelayProvider__factory"
import { RelayProviderProxy__factory } from "../../sdk/src/ethers-contracts/factories/RelayProviderProxy__factory"
import { RelayProviderSetup__factory } from "../../sdk/src/ethers-contracts/factories/RelayProviderSetup__factory"
import { RelayProviderImplementation__factory } from "../../sdk/src/ethers-contracts/factories/RelayProviderImplementation__factory"
import { MockRelayerIntegration__factory } from "../../sdk/src/ethers-contracts/factories/MockRelayerIntegration__factory"

import { ethers } from "ethers"
import fs from "fs"

type Deployment = { chainId: ChainId; address: string }

function get_env_var(env: string): string {
  const v = process.env[env]
  return v || ""
}

const env = get_env_var("ENV")
if (!env) {
  console.log("No environment was specified, using default environment files")
}

import * as dotenv from "dotenv"
dotenv.config({
  path: `./ts-scripts/.env${env ? "." + env : ""}`,
})

const configFile = fs.readFileSync(`./ts-scripts/config/${env ? env : "config"}.json`)
const config = JSON.parse(configFile.toString())
const guardianKey = get_env_var("GUARDIAN_KEY")
const privateKey = get_env_var("WALLET_KEY")

if (!config) {
  console.log("Failed to pull config file.")
}
if (!guardianKey) {
  console.log("Failed to pull guardian key.")
}
if (!privateKey) {
  console.log("Failed to pull wallet pk.")
}

async function run() {
  console.log("Start!")
  const output: any = {
    relayProviderImplementations: [],
    relayProviderSetups: [],
    relayProviderProxys: [],
    coreRelayerImplementations: [],
    coreRelayerSetups: [],
    coreRelayerProxys: [],
    mockRelayerIntegrations: [],
  }

  for (let i = 0; i < config.chains.length; i++) {
    const relayProviderImplementation = await deployRelayProviderImplementation(
      config.chains[i]
    )
    const relayProviderSetup = await deployRelayProviderSetup(config.chains[i])
    const relayProviderProxy = await deployRelayProviderProxy(
      config.chains[i],
      relayProviderSetup.address,
      relayProviderImplementation.address
    )
    const coreRelayerImplementation = await deployCoreRelayerImplementation(
      config.chains[i]
    )
    const coreRelayerSetup = await deployCoreRelayerSetup(config.chains[i])
    const coreRelayerProxy = await deployCoreRelayerProxy(
      config.chains[i],
      coreRelayerSetup.address,
      coreRelayerImplementation.address,
      config.chains[i].wormholeAddress,
      relayProviderProxy.address
    )
    const mockRelayerIntegration = await deployMockRelayerIntegration(
      config.chains[i],
      config.chains[i].wormholeAddress,
      coreRelayerProxy.address
    )

    output.relayProviderImplementations.push(relayProviderImplementation)
    output.relayProviderSetups.push(relayProviderSetup)
    output.relayProviderProxys.push(relayProviderProxy)
    output.coreRelayerImplementations.push(coreRelayerImplementation)
    output.coreRelayerSetups.push(coreRelayerSetup)
    output.coreRelayerProxys.push(coreRelayerProxy)
    output.mockRelayerIntegrations.push(mockRelayerIntegration)
  }

  for (let i = 0; i < config.chains.length; i++) {
    await configureCoreRelayer(config.chains[i], output.coreRelayerProxys)
    await configureRelayProvider(
      output.relayProviderProxys.find(
        (x: any) => x.chainId == config.chains[i].wormholeId
      ),
      config.chains
    )
  }

  writeOutputFiles(output)
}

async function deployRelayProviderImplementation(chain: any): Promise<Deployment> {
  console.log("deployRelayProviderImplementation " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)

  const contractInterface = RelayProviderImplementation__factory.createInterface()
  const bytecode = RelayProviderImplementation__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}

async function deployRelayProviderSetup(chain: any): Promise<Deployment> {
  console.log("deployRelayProviderSetup " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = RelayProviderSetup__factory.createInterface()
  const bytecode = RelayProviderSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}
async function deployRelayProviderProxy(
  chain: any,
  relayProviderSetupAddress: string,
  relayProviderImplementationAddress: string
): Promise<Deployment> {
  console.log("deployRelayProviderProxy " + chain.wormholeId)

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
    chain.wormholeId,
  ])

  const contract = await factory.deploy(relayProviderSetupAddress, encodedData)
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}
async function deployCoreRelayerImplementation(chain: any): Promise<Deployment> {
  console.log("deployCoreRelayerImplementation " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = CoreRelayerImplementation__factory.createInterface()
  const bytecode = CoreRelayerImplementation__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}
async function deployCoreRelayerSetup(chain: any): Promise<Deployment> {
  console.log("deployCoreRelayerSetup " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = CoreRelayerSetup__factory.createInterface()
  const bytecode = CoreRelayerSetup__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy()
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}
async function deployCoreRelayerProxy(
  chain: any,
  coreRelayerSetupAddress: string,
  coreRelayerImplementationAddress: string,
  wormholeAddress: string,
  relayProviderProxyAddress: string
): Promise<Deployment> {
  console.log("deployCoreRelayerProxy " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = CoreRelayerProxy__factory.createInterface()
  const bytecode = CoreRelayerProxy__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)

  let ABI = ["function setup(address,uint16,address,address)"]
  let iface = new ethers.utils.Interface(ABI)
  let encodedData = iface.encodeFunctionData("setup", [
    coreRelayerImplementationAddress,
    chain.wormholeId,
    wormholeAddress,
    relayProviderProxyAddress,
  ])

  const contract = await factory.deploy(coreRelayerSetupAddress, encodedData)
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}
async function deployMockRelayerIntegration(
  chain: any,
  wormholeAddress: string,
  coreRelayerProxy: string
): Promise<Deployment> {
  console.log("deployMockRelayerIntegration " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contractInterface = MockRelayerIntegration__factory.createInterface()
  const bytecode = MockRelayerIntegration__factory.bytecode
  //@ts-ignore
  const factory = new ethers.ContractFactory(contractInterface, bytecode, signer)
  const contract = await factory.deploy(wormholeAddress, coreRelayerProxy)
  return await contract.deployed().then((result) => {
    console.log("Successfully deployed contract at " + result.address)
    return { address: result.address, chainId: chain.wormholeId }
  })
}

async function configureCoreRelayer(chain: any, contracts: Deployment[]) {
  console.log("configureCoreRelayer " + chain.wormholeId)
  let provider = new ethers.providers.StaticJsonRpcProvider(chain.rpc)
  let signer = new ethers.Wallet(privateKey, provider)
  const contract = CoreRelayer__factory.connect(
    contracts.find((x) => x.chainId == chain.wormholeId)?.address || "",
    signer
  )
  for (let i = 0; i < config.chains.length; i++) {
    await contract.registerCoreRelayerContract(
      contracts[i].chainId,
      "0x" + tryNativeToHexString(contracts[i].address, "ethereum")
    )
  }
  console.log("registered all core relayers for " + chain.wormholeId)
}

async function configureRelayProvider(deployment: Deployment, chains: any) {
  console.log("configureCoreRelayer " + deployment.chainId)
  let provider = new ethers.providers.StaticJsonRpcProvider(
    chains.find((x: any) => x.wormholeId == deployment.chainId).rpc || ""
  )
  let signer = new ethers.Wallet(privateKey, provider)
  const contract = RelayProvider__factory.connect(deployment.address, signer)
  const walletAddress = signer.address
  const walletAddresswh = "0x" + tryNativeToHexString(walletAddress, "ethereum")

  await contract.updateRewardAddress(walletAddress)

  for (let i = 0; i < config.chains.length; i++) {
    await contract.updateDeliverGasOverhead(
      chains[i].wormholeId,
      config.defaultRelayProviderConfig.deliverGasOverhead
    )
    await contract.updateDeliveryAddress(chains[i].wormholeId, walletAddresswh)
    await contract.updateMaximumBudget(
      chains[i].wormholeId,
      config.defaultRelayProviderConfig.maximumBudget
    )
    await contract.updatePrice(
      chains[i].wormholeId,
      config.defaultRelayProviderConfig.updatePriceGas,
      config.defaultRelayProviderConfig.updatePriceNative
    )
  }

  console.log("configured relay provider for " + deployment.chainId)
}

function writeOutputFiles(output: any) {
  fs.mkdirSync("./ts-scripts/output/deployAndConfigure/", { recursive: true })
  fs.writeFileSync(
    `./ts-scripts/output/deployAndConfigure/zlastrun-${env}.json`,
    JSON.stringify(output),
    { flag: "w" }
  )
  fs.writeFileSync(
    `./ts-scripts/output/deployAndConfigure/${Date.now()}-${env}.json`,
    JSON.stringify(output),
    { flag: "w" }
  )
}

run().then(() => console.log("Done!"))
