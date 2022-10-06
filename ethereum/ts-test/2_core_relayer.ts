import {expect} from "chai";
import {ethers} from "ethers";
import {TargetDeliveryParameters, TestResults} from "./helpers/structs";
import {ChainId, tryNativeToHexString} from "@certusone/wormhole-sdk";
import {
  CHAIN_ID_ETH,
  CORE_RELAYER_ADDRESS,
  LOCALHOST,
  RELAYER_DEPLOYER_PRIVATE_KEY,
  MOCK_RELAYER_INTEGRATION_ADDRESS,
} from "./helpers/consts";
import {makeContract} from "./helpers/io";
import {
  getSignedBatchVaaFromReceiptOnEth,
  getSignedVaaFromReceiptOnEth,
  verifyDeliveryStatusPayload,
} from "./helpers/utils";

const ETHEREUM_ROOT = `${__dirname}/..`;

describe("Core Relayer Integration Test", () => {
  const provider = new ethers.providers.StaticJsonRpcProvider(LOCALHOST);

  // signers
  const wallet = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, provider);

  const coreRelayerAbiPath = `${ETHEREUM_ROOT}/build/CoreRelayer.sol/CoreRelayer.json`;
  const coreRelayer = makeContract(wallet, CORE_RELAYER_ADDRESS, coreRelayerAbiPath);

  const mockContractAbi = `${ETHEREUM_ROOT}/build/MockRelayerIntegration.sol/MockRelayerIntegration.json`;
  const mockContract = makeContract(wallet, MOCK_RELAYER_INTEGRATION_ADDRESS, mockContractAbi);

  // test batch VAA information
  const batchVAAPayloads: ethers.BytesLike[] = [
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff0")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff1")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff2")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff3")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff5")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff6")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff7")),
    ethers.utils.hexlify(ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff8")),
  ];
  const batchVAAConsistencyLevels: number[] = [15, 10, 2, 15, 1, 6, 3, 5];
  const batchNonce: number = 69;
  const deliveryVAAConsistencyLevel: number = 15;

  describe("Core Relayer Interaction", () => {
    // for the sake of this test, the target/source chain and address will be the same
    const TARGET_CONTRACT_ADDRESS = MOCK_RELAYER_INTEGRATION_ADDRESS;
    const TARGET_CHAIN_ID: ChainId = CHAIN_ID_ETH;
    const SOURCE_CONTRACT_ADDRESS = TARGET_CONTRACT_ADDRESS;
    const SOURCE_CHAIN_ID: ChainId = TARGET_CHAIN_ID;
    const TARGET_GAS_LIMIT = 1000000;
    const RELAYER_EMITTER_ADDRESS: ethers.utils.BytesLike = ethers.utils.hexlify(
      "0x" + tryNativeToHexString(coreRelayer.address, SOURCE_CHAIN_ID)
    );

    // test variables that are used throughout the test suite
    let fullBatchTest: TestResults = {} as TestResults;
    let partialBatchTest: TestResults = {} as TestResults;

    it("Should register a relayer contract", async () => {
      // should register the target contract address
      await coreRelayer
        .registerChain(TARGET_CHAIN_ID, RELAYER_EMITTER_ADDRESS)
        .then((tx: ethers.ContractTransaction) => tx.wait());

      const actualRegisteredRelayer = await coreRelayer.registeredRelayer(SOURCE_CHAIN_ID);
      const expectedRegisteredRelayer: ethers.utils.BytesLike = ethers.utils.hexlify(RELAYER_EMITTER_ADDRESS);
      expect(actualRegisteredRelayer).to.equal(expectedRegisteredRelayer);
    });

    it("Should update EVM deliver gas overhead", async () => {
      // the new evmGasOverhead value
      const newEvmGasOverhead = 500000;

      // query the EVM gas overhead before updating it
      const evmGasOverheadBefore = await coreRelayer.evmDeliverGasOverhead();
      expect(evmGasOverheadBefore).to.equal(0);

      // should update the EVM gas overhead
      await coreRelayer.updateEvmDeliverGasOverhead(newEvmGasOverhead);

      // query the EVM gas overhead after updating it
      const evmGasOverheadAfter = await coreRelayer.evmDeliverGasOverhead();
      expect(evmGasOverheadAfter).to.equal(newEvmGasOverhead);
    });

    it("Should create a batch VAA with a DeliveryInstructions VAA", async () => {
      // estimate the cost of submitting the batch on the target chain
      fullBatchTest.targetChainGasEstimate = await coreRelayer.estimateEvmCost(TARGET_CHAIN_ID, TARGET_GAS_LIMIT);

      // relayer args
      fullBatchTest.relayerArgs = {
        nonce: batchNonce,
        targetChainId: TARGET_CHAIN_ID,
        targetAddress: TARGET_CONTRACT_ADDRESS,
        targetGasLimit: TARGET_GAS_LIMIT,
        consistencyLevel: deliveryVAAConsistencyLevel,
      };

      // call the mock integration contract to create a batch
      const sendReceipt: ethers.ContractReceipt = await mockContract
        .sendBatchToTargetChain(batchVAAPayloads, batchVAAConsistencyLevels, fullBatchTest.relayerArgs, {
          value: fullBatchTest.targetChainGasEstimate,
        })
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // fetch the signedBatchVAA
      fullBatchTest.signedBatchVM = await getSignedBatchVaaFromReceiptOnEth(
        sendReceipt,
        SOURCE_CHAIN_ID,
        0 // guardianSetIndex
      );
    });

    it("Should deserialize and validate the full batch DeliveryInstructions VAA values", async () => {
      // parse the batchVM and verify the values
      const parsedBatchVM = await mockContract.parseWormholeBatch(fullBatchTest.signedBatchVM);

      // validate the individual messages
      const observations = parsedBatchVM.observations;
      const batchLen = parsedBatchVM.observations.length;
      for (let i = 0; i < batchLen - 2; ++i) {
        const parsedVM = await mockContract.parseWormholeObservation(observations[i]);
        expect(parsedVM.nonce).to.equal(batchNonce);
        expect(parsedVM.consistencyLevel).to.equal(batchVAAConsistencyLevels[i]);
        expect(parsedVM.payload).to.equal(batchVAAPayloads[i]);
      }

      // validate the mock integration instructions
      const integratorMessage = await mockContract.parseWormholeObservation(observations[batchLen - 2]);
      expect(integratorMessage.nonce).to.equal(batchNonce);
      expect(integratorMessage.consistencyLevel).to.equal(1);
      const integratorMessagePayload = Buffer.from(ethers.utils.arrayify(integratorMessage.payload));
      expect(integratorMessagePayload.readUInt16BE(0)).to.equal(2);
      expect(integratorMessagePayload.readUInt8(2)).to.equal(batchLen - 2);

      // validate the delivery instructions VAA
      const deliveryVM = await mockContract.parseWormholeObservation(observations[batchLen - 1]);
      expect(deliveryVM.nonce).to.equal(batchNonce);
      expect(deliveryVM.consistencyLevel).to.equal(fullBatchTest.relayerArgs.consistencyLevel);

      // deserialize the delivery instruction payload and validate the values
      const deliveryInstructions = await coreRelayer.decodeDeliveryInstructions(deliveryVM.payload);
      expect(deliveryInstructions.payloadID).to.equal(1);
      expect(deliveryInstructions.fromAddress).to.equal(
        "0x" + tryNativeToHexString(SOURCE_CONTRACT_ADDRESS, CHAIN_ID_ETH)
      );
      expect(deliveryInstructions.fromChain).to.equal(SOURCE_CHAIN_ID);
      expect(deliveryInstructions.targetAddress).to.equal(
        "0x" + tryNativeToHexString(TARGET_CONTRACT_ADDRESS, CHAIN_ID_ETH)
      );
      expect(deliveryInstructions.targetChain).to.equal(TARGET_CHAIN_ID);

      // deserialize the deliveryParameters and confirm the values
      const relayParameters = await coreRelayer.decodeRelayParameters(deliveryInstructions.relayParameters);
      expect(relayParameters.version).to.equal(1);
      expect(relayParameters.deliveryGasLimit).to.equal(TARGET_GAS_LIMIT);
      expect(relayParameters.maximumBatchSize).to.equal(batchVAAPayloads.length + 1);
      expect(relayParameters.nativePayment.toString()).to.equal(fullBatchTest.targetChainGasEstimate.toString());
    });

    it("Should deliver the batch VAA and call the wormholeReceiver endpoint on the mock contract", async () => {
      // create the TargetDeliveryParameters
      const targetDeliveryParams: TargetDeliveryParameters = {
        encodedVM: fullBatchTest.signedBatchVM,
        deliveryIndex: batchVAAPayloads.length + 1,
        targetCallGasOverride: ethers.BigNumber.from(TARGET_GAS_LIMIT),
      };

      // call the deliver method on the relayer contract
      const deliveryReceipt: ethers.ContractReceipt = await coreRelayer
        .deliver(targetDeliveryParams)
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // confirm that the batch VAA payloads were stored in a map in the mock contract
      const parsedBatchVM = await mockContract.parseWormholeBatch(fullBatchTest.signedBatchVM);

      const observations = parsedBatchVM.observations;
      const batchLen = observations.length;
      for (let i = 0; i < batchLen - 1; ++i) {
        const parsedVM = await mockContract.parseWormholeObservation(observations[i]);

        // query the contract for the saved payload
        const verifiedPayload = await mockContract.getPayload(parsedVM.hash);
        expect(verifiedPayload).to.equal(parsedVM.payload);

        // clear the payload from storage for future tests
        await mockContract.clearPayload(parsedVM.hash).then((tx: ethers.ContractTransaction) => tx.wait());

        // confirm that the payload was cleared
        const emptyPayload = await mockContract.getPayload(parsedVM.hash);
        expect(emptyPayload).to.equal("0x");
      }

      // fetch and save the delivery status VAA
      fullBatchTest.deliveryStatusVM = await getSignedVaaFromReceiptOnEth(
        deliveryReceipt,
        TARGET_CHAIN_ID as ChainId,
        0 // guardianSetIndex
      );
    });

    it("Should correctly emit a DeliveryStatus message upon full batch delivery", async () => {
      // parse the delivery status VAA payload
      const parsedDeliveryStatus = await mockContract.parseWormholeObservation(fullBatchTest.deliveryStatusVM);
      const deliveryStatusPayload = parsedDeliveryStatus.payload;

      // parse the batch VAA (need to use the batch hash)
      const parsedBatchVM = await mockContract.parseWormholeBatch(fullBatchTest.signedBatchVM);

      // grab the deliveryVM index, which is the last VM in the batch
      const deliveryVM = await mockContract.parseWormholeObservation(parsedBatchVM.observations.at(-1)!);

      // expected values in the DeliveryStatus payload
      const expectedDeliveryAttempts = 1;
      const expectedSuccessBoolean = 1;

      const success = verifyDeliveryStatusPayload(
        deliveryStatusPayload,
        parsedBatchVM.hash,
        RELAYER_EMITTER_ADDRESS,
        deliveryVM.sequence,
        expectedDeliveryAttempts,
        expectedSuccessBoolean
      );
      expect(success).to.be.true;
    });

    it("Should increment relayer fees upon delivery", async () => {
      // query the contract to check the balance of the relayer fees
      const queriedRelayerFees = await coreRelayer.relayerRewards(wallet.address, TARGET_CHAIN_ID);
      expect(queriedRelayerFees.toString()).to.equal(fullBatchTest.targetChainGasEstimate.toString());
    });
  });
});
