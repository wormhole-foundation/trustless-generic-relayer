import {ChainId, coalesceChainName, CONTRACTS, EVMChainId,} from "@certusone/wormhole-sdk"
import * as relayerEngine from "@wormhole-foundation/relayer-engine"
import {validateStringEnum} from "@wormhole-foundation/relayer-engine"
import {ChainInfo, GenericRelayerPlugin, GenericRelayerPluginConfig,} from "./plugin/src/plugin"

type ContractConfigEntry = { chainId: EVMChainId; address: "string" }
type ContractsJson = {
  relayProviders: ContractConfigEntry[]
  coreRelayers: ContractConfigEntry[]
  mockIntegrations: ContractConfigEntry[]
}

enum Flag {
  Tilt = "--tilt",
  Testnet = "--testnet",
  K8sTestnet = "--k8s-testnet",
  Mainnet = "--mainnet",
}

async function main() {
  // todo: turn flag into enum
  const flag: Flag = validateStringEnum(Flag, process.argv[2])

  // load plugin config
  const envType = selectPluginConfig(flag)
  const pluginConfig = (await relayerEngine.loadFileAndParseToObject(
    `./src/plugin/config/${envType}.json`
  )) as GenericRelayerPluginConfig

  // generate supportedChains config from contracts.json
  const contracts = (await relayerEngine.loadFileAndParseToObject(
    `../ethereum/ts-scripts/config/${envType.replace("devnet", "testnet")}/contracts.json`
  )) as ContractsJson
  pluginConfig.supportedChains = transfromContractsToSupportedChains(
    contracts,
    pluginConfig.supportedChains as any,
    flag
  ) as any

  // run relayer engine
  await relayerEngine.run({
    configs: "./engine_config/" + envType.toLowerCase(),
    plugins: {
      [GenericRelayerPlugin.pluginName]: (engineConfig, logger) => new GenericRelayerPlugin(engineConfig, pluginConfig, logger)
    },
    mode: relayerEngine.Mode.BOTH,
  })
}

function transfromContractsToSupportedChains(
  contracts: ContractsJson,
  supportedChains: Record<EVMChainId, ChainInfo>,
  flag: Flag
): Record<EVMChainId, ChainInfo> {
  contracts.relayProviders.forEach(
    ({ chainId, address }: ContractConfigEntry) =>
      (supportedChains[chainId].relayProvider = address)
  )
  contracts.coreRelayers.forEach(
    ({ chainId, address }: ContractConfigEntry) =>
      (supportedChains[chainId].relayerAddress = address)
  )
  contracts.mockIntegrations.forEach(
    ({ chainId, address }: ContractConfigEntry) =>
      (supportedChains[chainId].mockIntegrationContractAddress = address)
  )
  const whContracts = CONTRACTS[flagToWormholeContracts(flag)]
  for (const [chain, entry] of Object.entries(supportedChains)) {
    const chainName = coalesceChainName(Number(chain) as ChainId)
    entry.coreContract = whContracts[chainName].core!
  }
  return supportedChains
}

function selectPluginConfig(flag: Flag): string {
  switch (flag) {
    case Flag.Testnet:
      return relayerEngine.EnvType.DEVNET.toLowerCase()
    case Flag.Mainnet:
      return relayerEngine.EnvType.MAINNET.toLowerCase()
    case Flag.Tilt:
      return relayerEngine.EnvType.TILT.toLowerCase()
    case Flag.K8sTestnet:
      return "k8s-testnet"
    default:
      return relayerEngine.EnvType.TILT.toLowerCase()
  }
}

function flagToWormholeContracts(flag: string): "MAINNET" | "TESTNET" | "DEVNET" {
  switch (flag) {
    case Flag.K8sTestnet:
      return "TESTNET"
    case Flag.Testnet:
      return "TESTNET"
    case Flag.Mainnet:
      return "MAINNET"
    case Flag.Tilt:
      return "DEVNET"
    default:
      throw new Error("Unexpected flag ")
  }
}

// allow main to be an async function and block until it rejects or resolves
main().catch((e) => {
  console.error(e)
  process.exit(1)
})
