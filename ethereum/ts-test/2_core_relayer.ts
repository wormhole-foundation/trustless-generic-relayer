import { expect } from "chai";
import { ethers } from "ethers";
import { TargetDeliveryParameters, TestResults } from "./helpers/structs";
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  CHAIN_ID_ETH,
  CORE_RELAYER_ADDRESS,
  LOCALHOST,
  RELAYER_DEPLOYER_PRIVATE_KEY,
  MOCK_RELAYER_INTEGRATION_ADDRESS,
} from "./helpers/consts";
import { makeContract } from "./helpers/io";
import {
  getSignedBatchVaaFromReceiptOnEth,
  getSignedVaaFromReceiptOnEth,
  removeObservationFromBatch,
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

    it("Register trusted senders in the mock integration contract", async () => {
      // create hex address for the mock contract
      const targetMockContractAddressBytes = "0x" + tryNativeToHexString(mockContract.address, TARGET_CHAIN_ID);

      // register the trusted sender with the mock integration contract
      await mockContract
        .registerTrustedSender(TARGET_CHAIN_ID, targetMockContractAddressBytes)
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // query the mock integration contract to confirm the trusted sender registration worked
      const trustedSender = await mockContract.trustedSender(TARGET_CHAIN_ID);
      expect(trustedSender).to.equal(targetMockContractAddressBytes);
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
        deliveryListIndices: [] as number[],
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
      const parsedBatchVM = await mockContract.parseBatchVM(fullBatchTest.signedBatchVM);

      // validate the individual messages
      const batchLen = parsedBatchVM.indexedObservations.length;
      for (let i = 0; i < batchLen - 1; i++) {
        const parsedVM = await parsedBatchVM.indexedObservations[i].vm3;
        expect(parsedVM.nonce).to.equal(batchNonce);
        expect(parsedVM.consistencyLevel).to.equal(batchVAAConsistencyLevels[i]);
        expect(parsedVM.payload).to.equal(batchVAAPayloads[i]);
      }

      // validate the delivery instructions VAA
      const deliveryVM = parsedBatchVM.indexedObservations[batchLen - 1].vm3;
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
      expect(deliveryInstructions.deliveryList.length).to.equal(0);

      // deserialize the deliveryParameters and confirm the values
      const relayParameters = await coreRelayer.decodeRelayParameters(deliveryInstructions.relayParameters);
      expect(relayParameters.version).to.equal(1);
      expect(relayParameters.deliveryGasLimit).to.equal(TARGET_GAS_LIMIT);
      expect(relayParameters.maximumBatchSize).to.equal(batchVAAPayloads.length);
      expect(relayParameters.nativePayment.toString()).to.equal(fullBatchTest.targetChainGasEstimate.toString());
    });

    it("Should deliver the batch VAA and call the wormholeReceiver endpoint on the mock contract", async () => {
      // create the TargetDeliveryParameters
      const targetDeliveryParams: TargetDeliveryParameters = {
        encodedVM: fullBatchTest.signedBatchVM,
        deliveryIndex: batchVAAPayloads.length,
        targetCallGasOverride: ethers.BigNumber.from(TARGET_GAS_LIMIT),
      };

      // call the deliver method on the relayer contract
      const deliveryReceipt: ethers.ContractReceipt = await coreRelayer
        .deliver(targetDeliveryParams)
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // confirm that the batch VAA payloads were stored in a map in the mock contract
      const parsedBatchVM = await mockContract.parseBatchVM(fullBatchTest.signedBatchVM);
      const batchLen = parsedBatchVM.indexedObservations.length;
      for (let i = 0; i < batchLen - 1; i++) {
        const parsedVM = parsedBatchVM.indexedObservations[i].vm3;

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
      const parsedDeliveryStatus = await mockContract.parseVM(fullBatchTest.deliveryStatusVM);
      const deliveryStatusPayload = parsedDeliveryStatus.payload;

      // parse the batch VAA (need to use the batch hash)
      const parsedBatchVM = await mockContract.parseBatchVM(fullBatchTest.signedBatchVM);

      // grab the deliveryVM index, which is the last VM in the batch
      const deliveryVMIndex = parsedBatchVM.indexedObservations.length - 1;
      const deliveryVM = parsedBatchVM.indexedObservations[deliveryVMIndex].vm3;

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

    it("Should create a batch VAA with a DeliveryInstructions VAA (with a AllowedEmitterSequence deliveryList)", async () => {
      // estimate the gas of submitting the partial batch on the target chain
      partialBatchTest.targetChainGasEstimate = await coreRelayer.estimateEvmCost(TARGET_CHAIN_ID, TARGET_GAS_LIMIT);

      // randomly select four indices to put in the delivery list (not including the delivery VAA)
      let deliveryListIndices: number[] = [];
      for (let i = 0; i < batchVAAPayloads.length; i++) {
        deliveryListIndices.push(i);
      }
      deliveryListIndices = deliveryListIndices.sort(() => 0.5 - Math.random()).slice(4);

      // relayer args
      partialBatchTest.relayerArgs = {
        nonce: batchNonce,
        targetChainId: TARGET_CHAIN_ID,
        targetAddress: TARGET_CONTRACT_ADDRESS,
        targetGasLimit: TARGET_GAS_LIMIT,
        consistencyLevel: deliveryVAAConsistencyLevel,
        deliveryListIndices: deliveryListIndices,
      };

      // call the mock integration contract to create a batch
      const sendReceipt: ethers.ContractReceipt = await mockContract
        .sendBatchToTargetChain(batchVAAPayloads, batchVAAConsistencyLevels, partialBatchTest.relayerArgs, {
          value: partialBatchTest.targetChainGasEstimate,
        })
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // fetch the signedBatchVAA
      partialBatchTest.signedBatchVM = await getSignedBatchVaaFromReceiptOnEth(
        sendReceipt,
        SOURCE_CHAIN_ID as ChainId,
        0 // guardianSetIndex
      );
    });

    it("Should deserialize and validate the partial batch DeliveryInstructions VAA values", async () => {
      // parse the batchVM and verify the values
      const parsedBatchVM = await mockContract.parseBatchVM(partialBatchTest.signedBatchVM);

      // validate the individual messages
      const batchLen = parsedBatchVM.indexedObservations.length;
      for (let i = 0; i < batchLen - 1; i++) {
        const parsedVM = await parsedBatchVM.indexedObservations[i].vm3;
        expect(parsedVM.nonce).to.equal(batchNonce);
        expect(parsedVM.consistencyLevel).to.equal(batchVAAConsistencyLevels[i]);
        expect(parsedVM.payload).to.equal(batchVAAPayloads[i]);
      }

      // validate the delivery instructions VAA
      const deliveryVM = parsedBatchVM.indexedObservations[batchLen - 1].vm3;
      expect(deliveryVM.nonce).to.equal(batchNonce);
      expect(deliveryVM.consistencyLevel).to.equal(partialBatchTest.relayerArgs.consistencyLevel);

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
      expect(deliveryInstructions.deliveryList.length).to.equal(4);

      // deserialize the deliveryParameters and confirm the values
      const relayParameters = await coreRelayer.decodeRelayParameters(deliveryInstructions.relayParameters);
      expect(relayParameters.version).to.equal(1);
      expect(relayParameters.deliveryGasLimit).to.equal(TARGET_GAS_LIMIT);
      expect(relayParameters.maximumBatchSize).to.equal(batchVAAPayloads.length);
      expect(relayParameters.nativePayment.toString()).to.equal(partialBatchTest.targetChainGasEstimate.toString());
    });

    it("Should create a partial batch based on the deliveryList in the DeliveryInstructions VAA", async () => {
      // parse the batchVM and deserialize the DeliveryInstructions
      const parsedBatchVM = await mockContract.parseBatchVM(partialBatchTest.signedBatchVM);

      // Delivery VAA starting index (before pruning the batch). It should be the
      // last VAA in the batch.
      const deliveryVAAIndex: number = batchVAAPayloads.length;

      // The delivery VAA is the last message in the batch. Relayers will not know this,
      // and will have to iterate through the batch to find the AllowedEmitterSequence.
      const deliveryInstructionsPayload = await coreRelayer.decodeDeliveryInstructions(
        parsedBatchVM.indexedObservations[deliveryVAAIndex].vm3.payload
      );

      // Loop through the deliveryList in the DeliveryInstructions and find the indices to deliver. Store
      // the delivery index to make sure that it is not removed from the batch.
      let indicesToKeep: number[] = [deliveryVAAIndex];
      for (const deliveryId of deliveryInstructionsPayload.deliveryList) {
        for (const indexedObservations of parsedBatchVM.indexedObservations) {
          let vm3 = indexedObservations.vm3;
          if (
            vm3.emitterAddress == deliveryId.emitterAddress &&
            vm3.sequence.toString() == deliveryId.sequence.toString()
          ) {
            indicesToKeep.push(indexedObservations.index);
          }
        }
      }

      // prune the batch
      for (const indexedObservations of parsedBatchVM.indexedObservations) {
        const index = indexedObservations.index;
        if (!indicesToKeep.includes(index)) {
          // prune the batch
          partialBatchTest.signedBatchVM = removeObservationFromBatch(index, partialBatchTest.signedBatchVM);
        }
      }

      // confirm that the indices that we care about are still in the VAA
      const prunedBatchVM = await mockContract.parseBatchVM(partialBatchTest.signedBatchVM);
      for (const indexedObservations of prunedBatchVM.indexedObservations) {
        expect(indicesToKeep.includes(indexedObservations.index)).to.be.true;
      }
    });

    it("Should deliver the partial batch VAA and call the wormholeReceiver endpoint on the mock contract", async () => {
      // The delivery VAA index has changed since the batch was pruned, find the new delivery VAA index.
      // It should still be the last VAA in the batch.
      const prunedBatchVM = await mockContract.parseBatchVM(partialBatchTest.signedBatchVM);
      const deliveryVAAIndex = prunedBatchVM.indexedObservations.length - 1;
      expect(prunedBatchVM.indexedObservations[deliveryVAAIndex].vm3.emitterAddress).to.equal(RELAYER_EMITTER_ADDRESS);

      // create the TargetDeliveryParameters
      const targetDeliveryParams: TargetDeliveryParameters = {
        encodedVM: partialBatchTest.signedBatchVM,
        deliveryIndex: deliveryVAAIndex,
        targetCallGasOverride: ethers.BigNumber.from(TARGET_GAS_LIMIT),
      };

      // call the deliver method on the relayer contract
      const deliveryReceipt: ethers.ContractReceipt = await coreRelayer
        .deliver(targetDeliveryParams)
        .then((tx: ethers.ContractTransaction) => tx.wait());

      // confirm that the batch VM payloads were stored in a map in the mock contract
      const batchLen = prunedBatchVM.indexedObservations.length;
      for (let i = 0; i < batchLen - 1; i++) {
        const parsedVM = prunedBatchVM.indexedObservations[i].vm3;

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
      partialBatchTest.deliveryStatusVM = await getSignedVaaFromReceiptOnEth(
        deliveryReceipt,
        TARGET_CHAIN_ID,
        0 // guardianSetIndex
      );
    });

    it("Should correctly emit a DeliveryStatus message upon partial batch delivery", async () => {
      // parse the VM payload
      const parsedDeliveryStatus = await mockContract.parseVM(partialBatchTest.deliveryStatusVM);
      const deliveryStatusPayload = parsedDeliveryStatus.payload;

      // parse the batch VAA (need to use the batch hash)
      const parsedBatchVM = await mockContract.parseBatchVM(partialBatchTest.signedBatchVM);

      // grab the deliveryVM based, which is the last VM in the batch
      const deliveryVMIndex = parsedBatchVM.indexedObservations.length - 1;
      const deliveryVM = parsedBatchVM.indexedObservations[deliveryVMIndex].vm3;

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
  });
});
