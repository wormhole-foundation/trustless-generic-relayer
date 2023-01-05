import * as relayerEngine from "@wormhole-foundation/relayer-engine"
import GenericRelayerPluginDef, { GenericRelayerPluginConfig } from "./plugin/src/plugin"

async function main() {
  // load plugin config
  const envType = selectPluginConfig(process.argv[2] || "")
  const pluginConfig = (await relayerEngine.loadFileAndParseToObject(
    `./src/plugin/config/${envType.toLowerCase()}.json`
  )) as GenericRelayerPluginConfig

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
