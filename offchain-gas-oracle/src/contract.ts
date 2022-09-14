import { ethers } from "ethers";
import fs from "fs";
import { Config, OracleConfig } from "./config";

export async function makeOracleContracts(
  config: Config,
  broadcastPath: string,
  abiPath: string
): Promise<ethers.Contract[]> {
  const abi = readAbi(abiPath);

  const oracles: ethers.Contract[] = [];
  for (const oracleConfig of config.oracles) {
    const oracleReadOnly = makeOracleContract(oracleConfig, broadcastPath, abi);
    const chainId = await oracleReadOnly.chainId();
    if (oracleConfig.chainId != chainId) {
      return Promise.reject("oracleConfig.chainId != chainId()");
    }

    // make wallet
    const wallet = new ethers.Wallet(config.owner, oracleReadOnly.provider);
    const oracle = oracleReadOnly.connect(wallet);
    oracles.push(oracle);
  }
  return oracles;
}

function makeOracleContract(oracleConfig: OracleConfig, broadcastPath: string, abi: any): ethers.Contract {
  const broadcast = JSON.parse(fs.readFileSync(`${broadcastPath}/${oracleConfig.forgeBroadcast}`, "utf8"));
  const transactions = broadcast.transactions as any[];
  const transaction = transactions.find(
    (transaction: any) => transaction.transactionType == "CREATE" && transaction.contractName == "GasOracle"
  );
  if (transaction === undefined) {
    throw Error("transaction === undefined");
  }

  const provider = new ethers.providers.StaticJsonRpcProvider(oracleConfig.rpc);
  return new ethers.Contract(transaction.contractAddress, abi, provider);
}

function readAbi(abiPath: string): any {
  return JSON.parse(fs.readFileSync(abiPath, "utf8"));
}
