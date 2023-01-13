import { expect } from "chai";
import { ethers } from "ethers";
import {
  BSC_FORGE_BROADCAST,
  BSC_RPC,
  WORMHOLE_RPCS,
  ETH_FORGE_BROADCAST,
  ETH_RPC,
  DEPLOYER_PRIVATE_KEY,
  ZERO_ADDRESS_BYTES,
  TARGET_GAS_LIMIT,
} from "./helpers/consts";
import { RelayerArgs } from "./helpers/structs";
import {
  makeCoreRelayerFromForgeBroadcast,
  makeGasOracleFromForgeBroadcast,
  makeMockRelayerIntegrationFromForgeBroadcast,
  resolvePath,
} from "./helpers/utils";
import {
  CHAIN_ID_BSC,
  CHAIN_ID_ETH,
  getSignedBatchVAAWithRetry,
  tryNativeToUint8Array,
  tryNativeToHexString,
} from "@certusone/wormhole-sdk";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";

describe("ETH <> BSC Generic Relayer Integration Test", () => {
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_RPC);
  const bscProvider = new ethers.providers.StaticJsonRpcProvider(BSC_RPC);

  // core relayers
  const ethCoreRelayer = makeCoreRelayerFromForgeBroadcast(
    resolvePath(ETH_FORGE_BROADCAST),
    new ethers.Wallet(DEPLOYER_PRIVATE_KEY, ethProvider)
  );

  const bscCoreRelayer = makeCoreRelayerFromForgeBroadcast(
    resolvePath(BSC_FORGE_BROADCAST),
    new ethers.Wallet(DEPLOYER_PRIVATE_KEY, bscProvider)
  );

  // relayer integrators
  const ethRelayerIntegrator = makeMockRelayerIntegrationFromForgeBroadcast(
    resolvePath(ETH_FORGE_BROADCAST),
    new ethers.Wallet(DEPLOYER_PRIVATE_KEY, ethProvider)
  );

  const bscRelayerIntegrator = makeMockRelayerIntegrationFromForgeBroadcast(
    resolvePath(BSC_FORGE_BROADCAST),
    new ethers.Wallet(DEPLOYER_PRIVATE_KEY, bscProvider)
  );

  // gas oracles
  const ownedGasOracles = [
    // eth
    makeGasOracleFromForgeBroadcast(
      resolvePath(ETH_FORGE_BROADCAST),
      new ethers.Wallet(DEPLOYER_PRIVATE_KEY, ethProvider)
    ),
    // bsc
    makeGasOracleFromForgeBroadcast(
      resolvePath(BSC_FORGE_BROADCAST),
      new ethers.Wallet(DEPLOYER_PRIVATE_KEY, bscProvider)
    ),
  ];

  const readonlyGasOracles = [
    // eth
    makeGasOracleFromForgeBroadcast(resolvePath(ETH_FORGE_BROADCAST), ethProvider),
    // bsc
    makeGasOracleFromForgeBroadcast(resolvePath(BSC_FORGE_BROADCAST), bscProvider),
  ];

  const ethPrice = ethers.utils.parseUnits("2000.00", 8);
  const bscPrice = ethers.utils.parseUnits("400.00", 8);

  before("Setup Gas Oracle Prices And Register Relayer Contracts", async () => {
    // now fetch gas prices from each provider
    const gasPrices = await Promise.all(ownedGasOracles.map((oracle) => oracle.provider.getGasPrice()));

    const updates = [
      {
        chainId: CHAIN_ID_ETH,
        gasPrice: gasPrices.at(0)!,
        nativeCurrencyPrice: ethPrice,
      },
      {
        chainId: CHAIN_ID_BSC,
        gasPrice: gasPrices.at(1)!,
        nativeCurrencyPrice: bscPrice,
      },
    ];

    const oracleTxs = await Promise.all(
      ownedGasOracles.map((oracle) => oracle.updatePrices(updates).then((tx: ethers.ContractTransaction) => tx.wait()))
    );

    // query the core relayer contracts to see if relayers have been registered
    const registeredCoreRelayerOnBsc = await bscCoreRelayer.registeredRelayer(CHAIN_ID_ETH);
    const registeredCoreRelayerOnEth = await ethCoreRelayer.registeredRelayer(CHAIN_ID_BSC);

    // register the core relayer contracts
    if (registeredCoreRelayerOnBsc == ZERO_ADDRESS_BYTES) {
      await bscCoreRelayer
        .registerChain(CHAIN_ID_ETH, tryNativeToUint8Array(ethCoreRelayer.address, CHAIN_ID_ETH))
        .then((tx) => tx.wait());
    }

    if (registeredCoreRelayerOnEth == ZERO_ADDRESS_BYTES) {
      await ethCoreRelayer
        .registerChain(CHAIN_ID_BSC, tryNativeToUint8Array(bscCoreRelayer.address, CHAIN_ID_BSC))
        .then((tx) => tx.wait());
    }
  });

  describe("Send from Ethereum and Deliver to BSC", () => {
    // batch Vaa payloads to relay to the target contract
    let batchVaaPayloads: ethers.utils.BytesLike[] = [];

    // save the batch VAA info
    let batchToBscReceipt: ethers.ContractReceipt;
    let batchVaaFromEth: ethers.utils.BytesLike;

    it("Check Gas Oracles", async () => {
      const chainIds = await Promise.all(readonlyGasOracles.map((oracle) => oracle.chainId()));
      expect(chainIds.at(0)).is.not.undefined;
      expect(chainIds.at(0)!).to.equal(CHAIN_ID_ETH);
      expect(chainIds.at(1)).is.not.undefined;
      expect(chainIds.at(1)!).to.equal(CHAIN_ID_BSC);

      const ethPrices = await Promise.all(readonlyGasOracles.map((oracle) => oracle.gasPrice(CHAIN_ID_ETH)));
      const bscPrices = await Promise.all(readonlyGasOracles.map((oracle) => oracle.gasPrice(CHAIN_ID_BSC)));
      for (let i = 0; i < 2; ++i) {
        expect(ethPrices.at(i)).is.not.undefined;
        expect(ethPrices.at(i)?.toString()).to.equal("20000000000");
        expect(bscPrices.at(i)).is.not.undefined;
        expect(bscPrices.at(i)?.toString()).to.equal("20000000000");
      }
    });

    it("Generate batch VAA with delivery instructions on Ethereum", async () => {
      // estimate the relayer cost to relay a batch to BSC
      const estimatedGasCost = await ethRelayerIntegrator.estimateRelayCosts(CHAIN_ID_BSC, TARGET_GAS_LIMIT);

      // create an array of messages to deliver to the BSC target contract
      batchVaaPayloads = [
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff0")),
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff1")),
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff2")),
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff3")),
      ];
      const batchVaaConsistencyLevels = [15, 15, 15, 15];

      // create relayerArgs interface to call the mock integration contract with
      const relayerArgs: RelayerArgs = {
        nonce: 69,
        targetChainId: CHAIN_ID_BSC,
        targetAddress: bscRelayerIntegrator.address,
        targetGasLimit: TARGET_GAS_LIMIT,
        consistencyLevel: batchVaaConsistencyLevels[0],
      };

      // call the mock integration contract and send the batch VAA
      batchToBscReceipt = await ethRelayerIntegrator
        .sendBatchToTargetChain(batchVaaPayloads, batchVaaConsistencyLevels, relayerArgs, {
          value: estimatedGasCost,
        })
        .then((tx) => tx.wait());
    });

    it("Fetch batch VAA from Ethereum", async () => {
      // fetch the batch VAA with getSignedBatchVAAWithRetry
      const batchVaaRes = await getSignedBatchVAAWithRetry(
        WORMHOLE_RPCS,
        CHAIN_ID_ETH,
        batchToBscReceipt.transactionHash,
        {
          transport: NodeHttpTransport(),
        }
      );
      batchVaaFromEth = batchVaaRes.batchVaaBytes;
    });

    it("Wait for off-chain relayer to deliver the batch VAA to BSC", async () => {
      // parse the batch VAA
      const parsedBatch = await ethRelayerIntegrator.parseWormholeBatch(batchVaaFromEth);

      // Check to see if the batch VAA was delivered by querying the contract
      // for the first payload sent in the batch.
      let isBatchDelivered: boolean = false;
      const targetVm3 = await ethRelayerIntegrator.parseWormholeObservation(parsedBatch.observations[0]);
      while (!isBatchDelivered) {
        // query the contract to see if the batch was delivered
        const storedPayload = await bscRelayerIntegrator.getPayload(targetVm3.hash);
        if (storedPayload == targetVm3.payload) {
          isBatchDelivered = true;
        }
      }

      // confirm that the remaining payloads are stored in the contract
      for (const observation of parsedBatch.observations) {
        const vm3 = await bscRelayerIntegrator.parseWormholeObservation(observation);

        // skip delivery instructions VM
        if (vm3.emitterAddress == "0x" + tryNativeToHexString(ethCoreRelayer.address, CHAIN_ID_ETH)) {
          continue;
        }

        // query the contract to see if the batch was delivered
        const storedPayload = await bscRelayerIntegrator.getPayload(vm3.hash);
        expect(storedPayload).to.equal(vm3.payload);

        // clear the payload from the mock integration contract
        await bscRelayerIntegrator.clearPayload(vm3.hash);
        const emptyStoredPayload = await bscRelayerIntegrator.getPayload(vm3.hash);
        expect(emptyStoredPayload).to.equal("0x");
      }
    });
  });
});
