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
} from "../__tests__/helpers/consts";
import { DeliveryStatus, RelayerArgs, TargetDeliveryParameters } from "../__tests__/helpers/structs";
import {
  makeCoreRelayerFromForgeBroadcast,
  makeGasOracleFromForgeBroadcast,
  makeMockRelayerIntegrationFromForgeBroadcast,
  resolvePath,
  getSignedVaaFromReceiptOnEth,
  parseDeliveryStatusVaa,
} from "../__tests__/helpers/utils";
import { CHAIN_ID_BSC, CHAIN_ID_ETH, tryNativeToHexString, getSignedBatchVAAWithRetry } from "@certusone/wormhole-sdk";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";

async function main() {
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

  // setup gas oracles and register if needed
  {
    const ethPrice = ethers.utils.parseUnits("2000.00", 8);
    const bscPrice = ethers.utils.parseUnits("400.00", 8);

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
      const bscRegistrationTx = await bscCoreRelayer.registerChain(
        CHAIN_ID_ETH,
        "0x" + tryNativeToHexString(ethCoreRelayer.address, CHAIN_ID_ETH)
      );
      await bscRegistrationTx.wait();
    }

    if (registeredCoreRelayerOnEth == ZERO_ADDRESS_BYTES) {
      const ethRegistrationTx = await ethCoreRelayer.registerChain(
        CHAIN_ID_BSC,
        "0x" + tryNativeToHexString(bscCoreRelayer.address, CHAIN_ID_BSC)
      );
      await ethRegistrationTx.wait();
    }

    // Query the mock relayer integration contracts to see if trusted mock relayer
    // integration contracts have been registered.
    const trustedSenderOnBsc = await bscRelayerIntegrator.trustedSender(CHAIN_ID_ETH);
    const trustedSenderOnEth = await ethRelayerIntegrator.trustedSender(CHAIN_ID_BSC);

    // register the trusted mock relayer integration contracts
    if (trustedSenderOnBsc == ZERO_ADDRESS_BYTES) {
      const bscRegistrationTx = await bscRelayerIntegrator.registerTrustedSender(
        CHAIN_ID_ETH,
        "0x" + tryNativeToHexString(ethRelayerIntegrator.address, CHAIN_ID_ETH)
      );
      await bscRegistrationTx.wait();
    }

    if (trustedSenderOnEth == ZERO_ADDRESS_BYTES) {
      const ethRegistrationTx = await ethRelayerIntegrator.registerTrustedSender(
        CHAIN_ID_BSC,
        "0x" + tryNativeToHexString(bscRelayerIntegrator.address, CHAIN_ID_BSC)
      );
      await ethRegistrationTx.wait();
    }
  }

  {
    // batch Vaa payloads to relay to the target contract
    let batchVaaPayloads: ethers.utils.BytesLike[] = [];

    // REVIEW: these should be removed when the off-chain relayer is implemented
    let batchToBscReceipt: ethers.ContractReceipt;
    let targetDeliveryParamsOnBsc: TargetDeliveryParameters = {} as TargetDeliveryParameters;

    {
      // estimate the relayer cost to relay a batch to BSC
      const estimatedGasCost: ethers.BigNumber = await ethRelayerIntegrator.estimateRelayCosts(
        CHAIN_ID_BSC,
        TARGET_GAS_LIMIT
      );

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
        deliveryListIndices: [] as number[], // no indices specified for full batch delivery
      };

      // call the mock integration contract and send the batch VAA
      const tx = await ethRelayerIntegrator.sendBatchToTargetChain(
        batchVaaPayloads,
        batchVaaConsistencyLevels,
        relayerArgs,
        {
          value: estimatedGasCost,
        }
      );
      batchToBscReceipt = await tx.wait();

      console.log("emitterChain", CHAIN_ID_ETH, "emitterAddress", ethCoreRelayer.address);
      console.log("transaction", batchToBscReceipt.transactionHash);
    }

    {
      // fetch the batch VAA with getSignedBatchVAAWithRetry
      const batchVaaRes = await getSignedBatchVAAWithRetry(
        WORMHOLE_RPCS,
        CHAIN_ID_ETH,
        batchToBscReceipt.transactionHash,
        {
          transport: NodeHttpTransport(),
        }
      );
      const batchVaaFromEth: ethers.utils.BytesLike = batchVaaRes.batchVaaBytes;
      console.log("vaa", Buffer.from(batchVaaFromEth as Uint8Array).toString("hex"));

      // parse the batch VAA
      const parsedBatch = await ethRelayerIntegrator.parseBatchVM(batchVaaFromEth);
      console.log("parsed", parsedBatch);
    }
  }
}

main();
