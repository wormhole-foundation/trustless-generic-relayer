import axios from "axios";
import { ethers } from "ethers";
import { OracleConfig, readConfig } from "./config";
import { makeOracleContracts } from "./contract";
import { sleepFor } from "./utils";

async function main() {
  const ethereumPath = `${__dirname}/../../ethereum`;
  const abiPath = `${ethereumPath}/build/GasOracle.sol/GasOracle.abi.json`;
  console.log("abiPath", abiPath);

  const configPath = process.env.CONFIG!;
  console.log("config", configPath);

  const broadcastPath = `${ethereumPath}/broadcast`;
  console.log("broadcastPath", broadcastPath);

  const config = readConfig(configPath);

  // connect to GasOracle contracts w/ signer
  const oracles = await makeOracleContracts(config, broadcastPath, abiPath);

  // get relevant Coingecko IDs based on config
  const coingeckoIds = config.oracles.map((oracleConfig) => oracleConfig.coingeckoId).join(",");

  const updateGasOracleInterval = config.updateGasOracleInterval;
  const fetchPricesInterval = config.fetchPricesInterval;

  console.log("updateGasOracleInterval", updateGasOracleInterval);
  console.log("fetchPricesInterval", fetchPricesInterval);

  // get er done
  let retrieveCount = 0;
  const updatesTracker = new Map<number, PriceUpdate>();
  while (true) {
    // first get currency prices vs usd
    const coingeckoPrices = await getCoingeckoPrices(coingeckoIds).catch((_) => null);
    if (coingeckoPrices !== null) {
      // now fetch gas prices from each provider
      const gasPrices = await Promise.all(oracles.map((oracle) => oracle.provider.getGasPrice()));

      // produce price update array
      const priceUpdates = makeNativeCurrencyPrices(config.oracles, coingeckoPrices, gasPrices);
      for (const update of priceUpdates) {
        updatesTracker.set(update.chainId, update);
      }
    }

    if (++retrieveCount % (updateGasOracleInterval / fetchPricesInterval) == 0) {
      if (updatesTracker.size > 0) {
        const updates = Array.from(updatesTracker.values());
        const txs = await Promise.all(
          oracles.map((oracle) => oracle.updatePrices(updates).then((tx: ethers.ContractTransaction) => tx.wait()))
        );

        const balances = await Promise.all(
          oracles.map(async (oracle) => {
            const address = await oracle.signer.getAddress();
            const balance = await oracle.provider.getBalance(address);
            return ethers.utils.formatUnits(balance);
          })
        );
        console.log("retrieveCount", retrieveCount, "txs.length", txs.length, "balances", balances);

        updatesTracker.clear();
      }
    }

    await sleepFor(fetchPricesInterval);
  }
}

interface PriceUpdate {
  chainId: number;
  gasPrice: ethers.BigNumber;
  nativeCurrencyPrice: ethers.BigNumber;
}

function makeNativeCurrencyPrices(oracleConfigs: OracleConfig[], coingeckoPrices: any, gasPrices: ethers.BigNumber[]) {
  const priceUpdates: PriceUpdate[] = [];
  for (let i = 0; i < oracleConfigs.length; ++i) {
    const config = oracleConfigs.at(i)!;
    const id = config.coingeckoId;
    if (id in coingeckoPrices) {
      priceUpdates.push({
        chainId: config.chainId,
        gasPrice: gasPrices.at(i)!,
        nativeCurrencyPrice: ethers.utils.parseUnits(coingeckoPrices[id].usd.toString(), 8),
      });
    }
  }
  return priceUpdates;
}

async function getCoingeckoPrices(coingeckoIds: string) {
  const { data, status } = await axios.get(
    `https://api.coingecko.com/api/v3/simple/price?ids=${coingeckoIds}&vs_currencies=usd`,
    {
      headers: {
        Accept: "application/json",
      },
    }
  );
  if (status != 200) {
    return Promise.reject("status != 200");
  }

  return data;
}

main();
