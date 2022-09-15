import fs from "fs";

export interface OracleConfig {
  name: string;
  rpc: string;
  chainId: number;
  forgeBroadcast: string;
  coingeckoId: string;
}

export interface Config {
  owner: string;
  updateGasOracleInterval: number;
  fetchPricesInterval: number;
  oracles: OracleConfig[];
}

export function readConfig(configPath: string): Config {
  const config: Config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  // check that there are no duplicate chainIds or rpcs
  const chainIds = new Set<number>();
  const rpcs = new Set<string>();
  for (const oracleConfig of config.oracles) {
    // chainId
    const chainId = oracleConfig.chainId;
    if (chainIds.has(chainId)) {
      throw new Error("duplicate chainId found");
    }
    chainIds.add(chainId);
    // rpc
    const rpc = oracleConfig.rpc;
    if (rpcs.has(rpc)) {
      throw new Error("duplicate rpc found");
    }
    rpcs.add(rpc);
  }
  return config;
}
