import { tryNativeToHexString } from "@certusone/wormhole-sdk"
import {
  deployWormholeRelayerImplementation,
  deployWormholeRelayerLibrary,
} from "../helpers/deployments"
import {
  init,
  loadChains,
  ChainInfo,
  getWormholeRelayer,
  getRelayProviderAddress,
  getWormholeRelayerAddress,
  writeOutputFiles,
} from "../helpers/env"
import {
  createRegisterChainVAA,
  createDefaultRelayProviderVAA,
  createWormholeRelayerUpgradeVAA,
} from "../helpers/vaa"

const processName = "upgradeWormholeRelayerSelfSign"
init()
const chains = loadChains()

async function run() {
  console.log("Start!")
  const output: any = {
    coreRelayerImplementations: [],
    coreRelayerLibraries: [],
  }

  for (let i = 0; i < chains.length; i++) {
    const coreRelayerLibrary = await deployWormholeRelayerLibrary(chains[i])
    const coreRelayerImplementation = await deployWormholeRelayerImplementation(
      chains[i],
      coreRelayerLibrary.address
    )
    await upgradeWormholeRelayer(chains[i], coreRelayerImplementation.address)

    output.coreRelayerImplementations.push(coreRelayerImplementation)
    output.coreRelayerLibraries.push(coreRelayerLibrary)
  }

  writeOutputFiles(output, processName)
}

async function upgradeWormholeRelayer(chain: ChainInfo, newImplementationAddress: string) {
  console.log("upgradeWormholeRelayer " + chain.chainId)

  const coreRelayer = getWormholeRelayer(chain)

  await coreRelayer.submitContractUpgrade(
    createWormholeRelayerUpgradeVAA(chain, newImplementationAddress)
  )

  console.log("Successfully upgraded the core relayer contract on " + chain.chainId)
}

run().then(() => console.log("Done! " + processName))
