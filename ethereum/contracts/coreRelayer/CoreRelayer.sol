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

        // estimate relay cost and check to see if the user sent enough eth to cover the relay
        collectRelayerParameterPayment(relayParams, deliveryParams.targetChain, relayParams.deliveryGasLimit);

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

        // estimate relay cost and check to see if the user sent enough eth to cover the relay
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
     * it forwards the array of VAAs in the batch to the target contract by calling the `receiveWormholeMessages` endpoint
     * it records the specified relayer fees for the caller
     * it emits a DeliveryStatus message containing the results of the delivery
     */
    function deliver(TargetDeliveryParameters memory targetParams) public payable returns (uint64 sequence) {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // build InternalDelivery struct to reduce local variable count
        InternalDeliveryParams memory internalParams;

        // parse the batch VAA
        internalParams.batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // cache the deliveryVM
        IWormhole.VM memory deliveryVM =
            parseWormholeObservation(internalParams.batchVM.observations[targetParams.deliveryIndex]);
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        internalParams.deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        internalParams.deliveryInstructions = decodeDeliveryInstructions(deliveryVM.payload);

        // parse the relayParams
        internalParams.relayParams = decodeRelayParameters(internalParams.deliveryInstructions.relayParameters);

        // override the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > internalParams.relayParams.deliveryGasLimit) {
            internalParams.relayParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        // set the remaining values in the InternalDeliveryParams struct
        internalParams.deliveryIndex = targetParams.deliveryIndex;
        internalParams.deliveryAttempts = 0;

        return _deliver(wormhole, internalParams);
    }

    // TODO: WIP
    function redeliver(TargetDeliveryParameters memory targetParams, bytes memory encodedRedeliveryVm)
        public
        payable
        returns (uint64 sequence)
    {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // build InternalDeliveryParams struct to reduce local variable count
        InternalDeliveryParams memory internalParams;

        // parse the batch
        internalParams.batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // cache the deliveryVM
        IWormhole.VM memory deliveryVM =
            parseWormholeObservation(internalParams.batchVM.observations[targetParams.deliveryIndex]);
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        internalParams.deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        internalParams.deliveryInstructions = decodeDeliveryInstructions(deliveryVM.payload);

        // parse and verify the encoded redelivery message
        (IWormhole.VM memory redeliveryVm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedRedeliveryVm);
        require(valid, reason);
        require(verifyRelayerVM(redeliveryVm), "invalid emitter");

        // parse the RedeliveryInstructions
        RedeliveryInstructions memory redeliveryInstructions = parseRedeliveryInstructions(redeliveryVm.payload);
        require(redeliveryInstructions.batchHash == internalParams.batchVM.hash, "invalid batch");
        require(
            redeliveryInstructions.emitterAddress == internalParams.deliveryId.emitterAddress,
            "invalid delivery emitter"
        );
        require(redeliveryInstructions.sequence == internalParams.deliveryId.sequence, "invalid delivery sequence");

        // override the DeliveryInstruction's relayParams
        internalParams.deliveryInstructions.relayParameters = redeliveryInstructions.relayParameters;

        // parse the new relayParams
        internalParams.relayParams = decodeRelayParameters(redeliveryInstructions.relayParameters);

        // override the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > internalParams.relayParams.deliveryGasLimit) {
            internalParams.relayParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        // set the remaining values in the InternalDeliveryParams struct
        internalParams.deliveryIndex = targetParams.deliveryIndex;
        internalParams.deliveryAttempts = redeliveryInstructions.deliveryCount;

        return _deliver(wormhole, internalParams);
    }

    function _deliver(IWormhole wormhole, InternalDeliveryParams memory internalParams)
        internal
        returns (uint64 sequence)
    {
        require(msg.value == wormhole.messageFee(), "insufficient msg.value to pay wormhole messageFee");

        // Compute the hash(batchHash, deliveryId) and check to see if the batch
        // was successfully delivered already. Revert if it was.
        bytes32 deliveryHash = keccak256(
            abi.encodePacked(
                internalParams.batchVM.hash,
                internalParams.deliveryId.emitterAddress,
                internalParams.deliveryId.sequence
            )
        );
        require(!isDeliveryCompleted(deliveryHash), "batch already delivered");

        // confirm this is the correct destination chain
        require(chainId() == internalParams.deliveryInstructions.targetChain, "targetChain is not this chain");

        // confirm the correct delivery attempt sequence
        uint256 attemptedDeliveryCount = attemptedDeliveryCount(deliveryHash);
        require(internalParams.deliveryAttempts == attemptedDeliveryCount, "wrong delivery attempt index");

        // verify the batchVM before calling the receiver
        (bool valid, string memory reason) = wormhole.verifyBatchVM(internalParams.batchVM, true);
        require(valid, reason);

        // remove the deliveryVM from the array of observations in the batch
        uint256 numObservations = internalParams.batchVM.observations.length;
        bytes[] memory targetObservations = new bytes[](numObservations - 1);
        uint256 lastIndex = 0;
        for (uint256 i = 0; i < numObservations;) {
            if (i != internalParams.deliveryIndex) {
                targetObservations[lastIndex] = internalParams.batchVM.observations[i];
                unchecked {
                    lastIndex += 1;
                }
            }
            unchecked {
                i += 1;
            }
        }

        // lock the contract to prevent reentrancy
        require(!isContractLocked(), "reentrant call");
        setContractLock(true);

        // call the receiveWormholeMessages endpoint on the target contract
        (bool success,) = address(uint160(uint256(internalParams.deliveryInstructions.targetAddress))).call{
            gas: internalParams.relayParams.deliveryGasLimit
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[])", targetObservations));

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
        incrementRelayerRewards(
            msg.sender, internalParams.deliveryInstructions.fromChain, internalParams.relayParams.nativePayment
        );

        // clear the cache to reduce gas overhead
        wormhole.clearBatchCache(internalParams.batchVM.hashes);

        // emit delivery status message
        DeliveryStatus memory status = DeliveryStatus({
            payloadID: 2,
            batchHash: internalParams.batchVM.hash,
            emitterAddress: internalParams.deliveryId.emitterAddress,
            sequence: internalParams.deliveryId.sequence,
            deliveryCount: uint16(attemptedDeliveryCount + 1),
            deliverySuccess: success
        });
        // set the nonce to zero so a batch VAA is not created
        sequence = wormhole.publishMessage{value: msg.value}(0, encodeDeliveryStatus(status), consistencyLevel());
    }

    // TODO: WIP
    function collectRewards(uint16 rewardChain, bytes32 receiver, uint32 nonce)
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
    function payRewards(bytes memory encodedVm) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

        require(valid, reason);
        require(verifyRelayerVM(vm), "invalid emitter");

        RewardPayout memory payout = parseRewardPayout(vm.payload);

        require(payout.chain == chainId());

        payable(address(uint160(uint256(payout.receiver)))).transfer(payout.amount);
    }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        if (registeredRelayer(vm.emitterChainId) == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function parseWormholeObservation(bytes memory observation) public view returns (IWormhole.VM memory) {
        return wormhole().parseVM(observation);
    }
}
