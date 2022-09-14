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
  return JSON.parse(fs.readFileSync(configPath, "utf8"));
}
