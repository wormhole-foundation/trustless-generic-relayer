import * as relayerEngine from "@wormhole-foundation/relayer-engine";
import GenericRelayerPluginDef, { GenericRelayerPluginConfig } from "./plugin/src/plugin";

async function main() {
  // load plugin config
  const pluginConfig = (await relayerEngine.loadFileAndParseToObject(
    `./src/plugin/config/${relayerEngine.EnvType.DEVNET.toLowerCase()}.json`
  )) as GenericRelayerPluginConfig;

  // run relayer engine
  await relayerEngine.run({
    configs: "./engine_config",
    plugins: [GenericRelayerPluginDef.init(pluginConfig)],
    mode: relayerEngine.Mode.BOTH,
  });
}

// allow main to be an async function and block until it rejects or resolves
main().catch((e) => {
  console.error(e);
  process.exit(1);
});
