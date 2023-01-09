import { EVMChainId } from "@certusone/wormhole-sdk"
import * as relayerEngine from "@wormhole-foundation/relayer-engine"
import GenericRelayerPluginDef, {
  ChainInfo,
  GenericRelayerPluginConfig,
} from "./plugin/src/plugin"

async function main() {
  // load plugin config
  const envType = selectPluginConfig(process.argv[2] || "")
  const pluginConfig = (await relayerEngine.loadFileAndParseToObject(
    `./src/plugin/config/${envType.toLowerCase()}.json`
  )) as GenericRelayerPluginConfig

  const contracts = await relayerEngine.loadFileAndParseToObject(
    `../ethereum/ts-scripts/config/${envType
      .toLocaleLowerCase()
      .replace("devnet", "testnet")}/contracts.json`
  )
  const supportedChains = pluginConfig.supportedChains as unknown as Record<
    any,
    ChainInfo
  >
  contracts.coreRelayers.forEach(
    ({ chainId, address }: contractConfigEntry) =>
      (supportedChains[chainId].relayerAddress = address)
  )
  contracts.mockIntegrations.forEach(
    ({ chainId, address }: contractConfigEntry) =>
      (supportedChains[chainId].mockIntegrationContractAddress = address)
  )
  pluginConfig.supportedChains = supportedChains as any

  // run relayer engine
  await relayerEngine.run({
    configs: "./engine_config/" + envType.toLowerCase(),
    plugins: [GenericRelayerPluginDef.init(pluginConfig)],
    mode: relayerEngine.Mode.BOTH,
  })
}

function selectPluginConfig(flag: string) {
  switch (flag) {
    case "--testnet":
      return relayerEngine.EnvType.DEVNET
    case "--mainnet":
      return relayerEngine.EnvType.MAINNET
    case "--tilt":
      return relayerEngine.EnvType.TILT
    default:
      return relayerEngine.EnvType.TILT
  }
}

// allow main to be an async function and block until it rejects or resolves
main().catch((e) => {
  console.error(e)
  process.exit(1)
})

type contractConfigEntry = { chainId: EVMChainId; address: "string" }
