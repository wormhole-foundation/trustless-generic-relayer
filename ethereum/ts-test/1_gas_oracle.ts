import { expect } from "chai";
import { ethers } from "ethers";
import { GasOracle__factory } from "../../sdk/src";
import {
  CHAIN_ID_AVAX,
  CHAIN_ID_ETH,
  GAS_ORACLE_ADDRESS,
  LOCALHOST,
  ORACLE_DEPLOYER_PRIVATE_KEY,
} from "./helpers/consts";

const ETHEREUM_ROOT = `${__dirname}/..`;

describe("Gas Oracle Integration Test", () => {
  const provider = new ethers.providers.StaticJsonRpcProvider(LOCALHOST);

  // signers
  const oracleDeployer = new ethers.Wallet(ORACLE_DEPLOYER_PRIVATE_KEY, provider);

  const gasOracleAbiPath = `${ETHEREUM_ROOT}/build/GasOracle.sol/GasOracle.json`;
  const gasOracle = GasOracle__factory.connect( GAS_ORACLE_ADDRESS, oracleDeployer);

  const ethPrice = ethers.utils.parseUnits("2000.00", 8);
  const ethereumGasPrice = ethers.utils.parseUnits("100", 9);

  const avaxPrice = ethers.utils.parseUnits("20.00", 8);
  const avalancheGasPrice = ethers.utils.parseUnits("100", 9);

  describe("Core Relayer Interaction", () => {
    it("updatePrices", async () => {
      const updates = [
        {
          chainId: CHAIN_ID_ETH,
          gasPrice: ethereumGasPrice,
          nativeCurrencyPrice: ethPrice,
        },
        {
          chainId: CHAIN_ID_AVAX,
          gasPrice: avalancheGasPrice,
          nativeCurrencyPrice: avaxPrice,
        },
      ];

      const updatePricesTx = await gasOracle.updatePrices(updates).then((tx: any) => tx.wait());

      // TODO: check getter
    });
  });
});
