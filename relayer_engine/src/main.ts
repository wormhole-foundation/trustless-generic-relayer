import { EVMChainId } from "@certusone/wormhole-sdk"
import * as relayerEngine from "@wormhole-foundation/relayer-engine"
import GenericRelayerPluginDef, {
  ChainInfo,
  GenericRelayerPluginConfig,
} from "./plugin/src/plugin"

type ContractConfigEntry = { chainId: EVMChainId; address: "string" }
type ContractsJson = {
  relayProviders: ContractConfigEntry[]
  coreRelayers: ContractConfigEntry[]
  mockIntegrations: ContractConfigEntry[]
}

async function main() {
  // load plugin config
  const envType = selectPluginConfig(process.argv[2] ?? "")
  const pluginConfig = (await relayerEngine.loadFileAndParseToObject(
    `./src/plugin/config/${envType}.json`
  )) as GenericRelayerPluginConfig

  // generate supportedChains config from contracts.json
  const contracts = (await relayerEngine.loadFileAndParseToObject(
    `../ethereum/ts-scripts/config/${envType.replace("devnet", "testnet")}/contracts.json`
  )) as ContractsJson
  pluginConfig.supportedChains = transfromContractsToSupportedChains(
    contracts,
    pluginConfig.supportedChains as any
  ) as any

  // run relayer engine
  await relayerEngine.run({
    configs: "./engine_config/" + envType.toLowerCase(),
    plugins: [GenericRelayerPluginDef.init(pluginConfig)],
    mode: relayerEngine.Mode.BOTH,
  })
}

function selectPluginConfig(flag: string): string {
  switch (flag) {
    case "--testnet":
      return relayerEngine.EnvType.DEVNET.toLowerCase()
    case "--mainnet":
      return relayerEngine.EnvType.MAINNET.toLowerCase()
    case "--tilt":
      return relayerEngine.EnvType.TILT.toLowerCase()
    case "--k8s-testnet":
      return "k8s-testnet"
    default:
      return relayerEngine.EnvType.TILT.toLowerCase()
  }
}

function transfromContractsToSupportedChains(
  contracts: ContractsJson,
  supportedChains: Record<EVMChainId, ChainInfo>
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
  return supportedChains
}

// allow main to be an async function and block until it rejects or resolves
main().catch((e) => {
  console.error(e)
  process.exit(1)
})
