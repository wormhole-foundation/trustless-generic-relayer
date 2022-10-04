// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerStructs.sol";
import "./CoreRelayerGovernance.sol";

contract CoreRelayer is CoreRelayerGovernance {
    using BytesLib for bytes;

    /**
     * @dev `estimateEvmCost` computes the estimated cost of delivering a batch VAA to a target chain.
     * it fetches the gas price in native currency for one unit of gas on the target chain
     */
    function estimateEvmCost(uint16 chainId, uint256 gasLimit) public view returns (uint256 gasEstimate) {
        return (gasOracle().computeGasCost(chainId, gasLimit + evmDeliverGasOverhead()) + wormhole().messageFee());
    }

    /**
     * @dev `send` generates a VAA with DeliveryInstructions to be delivered to the specified target
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */

    function send(DeliveryParameters memory deliveryParams) public payable returns (uint64 sequence) {
        // decode the relay parameters
        RelayParameters memory relayParams = decodeRelayParameters(deliveryParams.relayParameters);

        require(relayParams.deliveryGasLimit > 0, "invalid deliveryGasLimit in relayParameters");

        // Estimate the gas costs of the delivery, and confirm the user sent the right amount of gas.
        // The user needs to make sure to send a little extra value to cover the wormhole messageFee on this chain.
        uint256 deliveryCostEstimate = estimateEvmCost(deliveryParams.targetChain, relayParams.deliveryGasLimit);

        require(
            relayParams.nativePayment == deliveryCostEstimate && msg.value == deliveryCostEstimate,
            "insufficient fee specified in msg.value"
        );

        // sanity check a few of the values before composing the DeliveryInstructions
        require(deliveryParams.targetAddress != bytes32(0), "invalid targetAddress");
        require(deliveryParams.nonce > 0, "nonce must be > 0");

        // encode the DeliveryInstructions
        bytes memory deliveryInstructions = encodeDeliveryInstructions(deliveryParams);

        // emit delivery message
        IWormhole wormhole = wormhole();
        sequence = wormhole.publishMessage{value: wormhole.messageFee()}(
            deliveryParams.nonce, deliveryInstructions, deliveryParams.consistencyLevel
        );
    }

    // TODO: WIP
    function resend(bytes memory encodedVm, bytes memory newRelayerParams) public payable returns (uint64 sequence) {
        IWormhole wormhole = wormhole();
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(encodedVm);

        require(valid, reason);
        require(verifyRelayerVM(vm), "invalid emitter");

        DeliveryStatus memory status = parseDeliveryStatus(vm.payload);

        require(status.deliverySuccess == false, "delivery already succeeded");

        bytes32 deliveryHash = keccak256(abi.encodePacked(status.batchHash, status.emitterAddress, status.sequence));
        uint256 redeliveryAttempt = redeliveryAttemptCount(deliveryHash);
        require(status.deliveryCount - 1 == redeliveryAttempt, "old delivery status receipt presented");
        require(status.deliveryCount == type(uint16).max, "too many retries");
        incrementRedeliveryAttempt(deliveryHash);

        RelayParameters memory relayParams = decodeRelayParameters(newRelayerParams);
        collectRelayerParameterPayment(relayParams, vm.emitterChainId, relayParams.deliveryGasLimit);

        RedeliveryInstructions memory redeliveryInstructions = RedeliveryInstructions({
            payloadID: 3,
            batchHash: status.batchHash,
            emitterAddress: status.emitterAddress,
            sequence: status.sequence,
            deliveryCount: status.deliveryCount,
            relayParameters: newRelayerParams
        });

        // emit delivery status message
        sequence = wormhole.publishMessage{value: msg.value}(
            0, encodeRedeliveryInstructions(redeliveryInstructions), consistencyLevel()
        );
    }

    // TODO: WIP
    function collectRelayerParameterPayment(
        RelayParameters memory relayParams,
        uint16 targetChain,
        uint32 targetGasLimit
    ) internal {
        require(relayParams.deliveryGasLimit > 0, "invalid deliveryGasLimit in relayParameters");

        // Estimate the gas costs of the delivery, and confirm the user sent the right amount of gas.
        uint256 deliveryCostEstimate = estimateEvmCost(targetChain, targetGasLimit);

        require(
            relayParams.nativePayment == deliveryCostEstimate && msg.value == deliveryCostEstimate,
            "insufficient fee specified in msg.value"
        );
    }

    /**
     * @dev `deliver` verifies batch VAAs and forwards the VAAs to a target contract specified in the
     * DeliveryInstruction VAA.
     * it locates the DeliveryInstructions VAA in the batch
     * it checks to see if the batch has been delivered already
     * it verifies that the delivery instructions were generated by a registered relayer contract
     * it verifies that the delivered batch contains all VAAs specified in the deliveryList (if it's a partial batch)
     * it forwards the array of VAAs in the batch to the target contract by calling the `wormholeReceiver` endpoint
     * it records the specified relayer fees for the caller
     * it emits a DeliveryStatus message containing the results of the delivery
     */
    function deliver(TargetDeliveryParameters memory targetParams) public payable returns (uint64 sequence) {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // parse the batch VAA
        IWormhole.VM2 memory batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // cache the deliveryVM
        IWormhole.VM memory deliveryVM = batchVM.indexedObservations[targetParams.deliveryIndex].vm3;
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        AllowedEmitterSequence memory deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstructions memory deliveryInstructions = decodeDeliveryInstructions(deliveryVM.payload);

        // parse the relayParams
        RelayParameters memory relayParams = decodeRelayParameters(deliveryInstructions.relayParameters);

        // Override the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > relayParams.deliveryGasLimit) {
            relayParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        return _deliver(wormhole, batchVM, deliveryInstructions, deliveryId, relayParams, 0);
    }

    // TODO: WIP
    function redeliver(TargetDeliveryParameters memory targetParams, bytes memory encodedRedeliveryVm)
        public
        payable
        returns (uint64 sequence)
    {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // parse the batch
        IWormhole.VM2 memory batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // cache the deliveryVM
        IWormhole.VM memory deliveryVM = batchVM.indexedObservations[targetParams.deliveryIndex].vm3;
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        AllowedEmitterSequence memory deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstructions memory deliveryInstructions = decodeDeliveryInstructions(deliveryVM.payload);

        (IWormhole.VM memory redeliveryVm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedRedeliveryVm);
        require(valid, reason);
        require(verifyRelayerVM(redeliveryVm), "invalid emitter");

        RedeliveryInstructions memory redeliveryInstructions = parseRedeliveryInstructions(redeliveryVm.payload);
        require(redeliveryInstructions.batchHash == batchVM.hash, "invalid batch");
        require(redeliveryInstructions.emitterAddress == deliveryVM.emitterAddress, "invalid delivery");
        require(redeliveryInstructions.sequence == deliveryVM.sequence, "invalid delivery");

        // overwrite the DeliveryInstruction's relayParams
        deliveryInstructions.relayParameters = redeliveryInstructions.relayParameters;

        // parse the new relayParams
        RelayParameters memory relayParams = decodeRelayParameters(redeliveryInstructions.relayParameters);

        // Overwrite the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > relayParams.deliveryGasLimit) {
            relayParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        return _deliver(
            wormhole, batchVM, deliveryInstructions, deliveryId, relayParams, redeliveryInstructions.deliveryCount
        );
    }

    function _deliver(
        IWormhole wormhole,
        IWormhole.VM2 memory batchVM,
        DeliveryInstructions memory deliveryInstructions,
        AllowedEmitterSequence memory deliveryId,
        RelayParameters memory relayParams,
        uint16 attempt
    ) internal returns (uint64 sequence) {
        require(msg.value == wormhole.messageFee(), "insufficient msg.value to pay wormhole messageFee");

        // Compute the hash(batchHash, deliveryId) and check to see if the batch
        // was successfully delivered already. Revert if it was.
        bytes32 deliveryHash = keccak256(abi.encodePacked(batchVM.hash, deliveryId.emitterAddress, deliveryId.sequence));
        require(!isDeliveryCompleted(deliveryHash), "batch already delivered");

        // confirm this is the correct destination chain
        require(chainId() == deliveryInstructions.targetChain, "targetChain is not this chain");

        // confirm the correct delivery attempt sequence
        uint256 attemptedDeliveryCount = attemptedDeliveryCount(deliveryHash);
        require(attempt == attemptedDeliveryCount, "wrong delivery attempt index");

        // Check to see if a deliveryList is specified. If not, confirm that all VAAs made it to this contract.
        // If a deliveryList is specified, forward the list of VAAs to the receiving contract.
        IWormhole.VM[] memory targetVMs;
        {
            // bypass stack-too-deep
            uint256 deliveryListLength = deliveryInstructions.deliveryList.length;
            if (deliveryListLength > 0) {
                targetVMs =
                    preparePartialBatchForDelivery(batchVM.indexedObservations, deliveryInstructions.deliveryList);
            } else {
                targetVMs =
                    prepareBatchForDelivery(batchVM.indexedObservations, relayParams.maximumBatchSize, deliveryId);
            }
        }

        // verify the batchVM before calling the receiver
        (bool valid, string memory reason) = wormhole.verifyBatchVM(batchVM, true);
        require(valid, reason);

        // lock the contract to prevent reentrancy
        require(!isContractLocked(), "reentrant call");
        setContractLock(true);

        // process the delivery by calling the wormholeReceiver endpoint on the target contract
        (bool success,) = address(uint160(uint256(deliveryInstructions.targetAddress))).call{
            gas: relayParams.deliveryGasLimit
        }(
            abi.encodeWithSignature(
                "wormholeReceiver((uint8,uint32,uint32,uint16,bytes32,uint64,uint8,bytes,uint32,(bytes32,bytes32,uint8,uint8)[],bytes32)[],uint16,bytes32,bytes)",
                targetVMs,
                deliveryInstructions.fromChain,
                deliveryInstructions.fromAddress,
                deliveryInstructions.payload
            )
        );

        // unlock the contract
        setContractLock(false);

        /**
         * If the delivery was successful, mark the delivery as completed in the contract state.
         *
         * If the delivery was unsuccessful, uptick the attempted delivery counter for this delivery hash.
         */
        if (success) {
            markAsDelivered(deliveryHash);
        } else {
            incrementAttemptedDelivery(deliveryHash);
        }

        // increment the relayer rewards
        incrementRelayerRewards(msg.sender, deliveryInstructions.fromChain, relayParams.nativePayment);

        // clear the cache to reduce gas overhead
        wormhole.clearBatchCache(batchVM.hashes);

        // emit delivery status message
        DeliveryStatus memory status = DeliveryStatus({
            payloadID: 2,
            batchHash: batchVM.hash,
            emitterAddress: deliveryId.emitterAddress,
            sequence: deliveryId.sequence,
            deliveryCount: uint16(attemptedDeliveryCount + 1),
            deliverySuccess: success
        });
        // set the nonce to zero so a batch VAA is not created
        sequence = wormhole.publishMessage{value: msg.value}(0, encodeDeliveryStatus(status), consistencyLevel());
    }

    // TODO: WIP
    function rewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce)
        public
        payable
        returns (uint64 sequence)
    {
        uint256 amount = relayerRewards(msg.sender, rewardChain);

        require(amount > 0, "no current accrued rewards");

        resetRelayerRewards(msg.sender, rewardChain);

        sequence = wormhole().publishMessage{value: msg.value}(
            nonce,
            encodeRewardPayout(
                RewardPayout({
                    payloadID: 100,
                    fromChain: chainId(),
                    chain: rewardChain,
                    amount: amount,
                    receiver: receiver
                })
            ),
            20
        );
    }

    // TODO: WIP
    function finaliseRewardPayout(bytes memory encodedVm) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

        require(valid, reason);
        require(verifyRelayerVM(vm), "invalid emitter");

        RewardPayout memory payout = parseRewardPayout(vm.payload);

        require(payout.chain == chainId());

        payable(address(uint160(uint256(payout.receiver)))).transfer(payout.amount);
    }

    function prepareBatchForDelivery(
        IWormhole.IndexedObservation[] memory indexedObservations,
        uint8 maximumBatchSize,
        AllowedEmitterSequence memory deliveryId
    ) internal pure returns (IWormhole.VM[] memory batch) {
        // array that will hold the resulting VAAs
        batch = new IWormhole.VM[](maximumBatchSize);

        uint8 observationCount = 0;
        uint256 observationsLen = indexedObservations.length;
        for (uint256 i = 0; i < observationsLen;) {
            // parse the VM
            IWormhole.VM memory vm = indexedObservations[i].vm3;

            // make sure not to include any deliveryVMs
            if (vm.emitterAddress != deliveryId.emitterAddress) {
                batch[i] = vm;
                observationCount += 1;
            }

            unchecked {
                i += 1;
            }
        }

        // confirm that the whole batch was sent
        require(observationCount == maximumBatchSize, "invalid batch size");
    }

    function preparePartialBatchForDelivery(
        IWormhole.IndexedObservation[] memory indexedObservations,
        AllowedEmitterSequence[] memory deliveryList
    ) internal pure returns (IWormhole.VM[] memory partialBatch) {
        // cache deliveryList length
        uint256 deliveryListLen = deliveryList.length;

        // final array with the individual VMs
        partialBatch = new IWormhole.VM[](deliveryListLen);

        // cache observationsLen to save on gas
        uint256 observationsLen = indexedObservations.length;

        // loop through the delivery list and save VAAs if they are included in the batch
        for (uint256 i = 0; i < deliveryListLen;) {
            for (uint256 j = 0; j < observationsLen;) {
                // parse the VM
                IWormhole.VM memory vm = indexedObservations[j].vm3;

                // save if there is a match
                if (vm.emitterAddress == deliveryList[i].emitterAddress && vm.sequence == deliveryList[i].sequence) {
                    partialBatch[i] = vm;
                    break;
                }

                unchecked {
                    j += 1;
                }
            }
            unchecked {
                i += 1;
            }
        }
        // confirm that the whole batch was sent
        require(partialBatch.length == deliveryListLen, "invalid batch size");
    }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        if (registeredRelayer(vm.emitterChainId) == vm.emitterAddress) {
            return true;
        }

        return false;
    }
}
