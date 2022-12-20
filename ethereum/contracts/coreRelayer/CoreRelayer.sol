// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerStructs.sol";
import "./CoreRelayerGovernance.sol";

contract CoreRelayer is CoreRelayerGovernance {
    using BytesLib for bytes;

    /**
     * @dev `quoteEvmDeliveryPrice` returns the amount in wei that must be paid to the core relayer contract 
     * in order to request delivery of a batch to chainId with gasLimit.
     */
    function quoteEvmDeliveryPrice(uint16 chainId, uint256 gasLimit) public view returns (uint256 nativePriceQuote) {
        nativePriceQuote = gasOracle().quoteEvmDeliveryPrice(chainId, gasLimit);
    }

    /**
    * @dev this is the inverse of "quoteEvmDeliveryPrice". 
    * Given a computeBudget (denominated in the wei of this chain), and a target chain, this function returns what
    * amount of gas on the target chain this compute budget corresponds to.
    */
    function quoteTargetEvmGas(uint16 targetChain, uint256 computeBudget ) public view returns (uint32 gasAmount) {
        gasAmount = gasOracle().quoteTargetEvmGas(targetChain, computeBudget);
    }

    function assetConversionAmount(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) public view returns (uint256 targetAmount) {
        targetAmount = gasOracle().assetConversionAmount(sourceChain, sourceAmount, targetChain);
    }

    function requestForward(uint16 targetChain, bytes32 targetAddress, bytes32 refundAddress, uint256 minimumComputeBudget, uint256 nativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) public payable {
        //TODO adjust to new function args
        DeliveryInstruction memory instruction = DeliveryInstruction(targetChain, targetAddress, refundAddress, minimumComputeBudget, nativeBudget, relayParameters);
        DeliveryInstruction[] memory instructionArray = new DeliveryInstruction[](1);
        instructionArray[0] = instruction;
        DeliveryInstructionsContainer memory container = DeliveryInstructionsContainer(1, instructionArray);
        multiforward(container, targetChain, nonce, consistencyLevel);
    }

    /**
     * @dev `forward` queues up a 'send' which will be executed after the present delivery is complete 
     * & uses the gas refund to cover the costs.
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function multiforward(DeliveryInstructionsContainer memory deliveryInstructions, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) public {
        require(isContractLocked(), "Can only forward while a delivery is in process.");
        require(getForwardingInstructions().isValid != true, "Cannot request multiple forwards.");

        //TODO ensure rollover chain is included in delivery instructions;

        setForwardingInstructions(ForwardingInstructions(encodeDeliveryInstructionsContainer(deliveryInstructions), rolloverChain, nonce, consistencyLevel, true));
    }

    function emitForward(uint256 refundAmount) internal returns (uint64 sequence) {
        ForwardingInstructions memory forwardingInstructions = getForwardingInstructions();
        DeliveryInstructionsContainer memory container = decodeDeliveryInstructionsContainer(forwardingInstructions.deliveryInstructionsContainer);

        //make sure the refund amount covers the native gas amounts
        uint256 totalMinimumFees = sufficientFundsHelper(container, refundAmount);

        //find the delivery instruction for the rollover chain
        uint16 rolloverInstructionIndex = findDeliveryIndex(container, forwardingInstructions.rolloverChain);

        //calc how much budget is used by chains other than the rollover chain
        uint256 rolloverChainCostEstimate = container.instructions[rolloverInstructionIndex].computeBudget + container.instructions[rolloverInstructionIndex].nativeBudget;
        uint256 nonrolloverBudget = totalMinimumFees - rolloverChainCostEstimate;
        uint256 rolloverBudget = refundAmount - nonrolloverBudget - container.instructions[rolloverInstructionIndex].nativeBudget;

        //TODO deduct gas cost of this operation from the rollover amount?

        //overwrite the gas budget on the rollover chain to the remaining budget amount
        container.instructions[rolloverInstructionIndex].computeBudget = rolloverBudget;

        //emit delivery request message
        require(forwardingInstructions.nonce > 0, "nonce must be > 0");
        bytes memory reencoded = encodeDeliveryInstructionsContainer(container);
        IWormhole wormhole = wormhole();
        sequence = wormhole.publishMessage{value: wormhole.messageFee()}(forwardingInstructions.nonce, reencoded, forwardingInstructions.consistencyLevel);

        //clear forwarding request from cache
        clearForwardingInstructions();
    }

    function findDeliveryIndex(DeliveryInstructionsContainer memory container, uint16 chainId) internal pure returns (uint16 deliveryInstructionIndex) {
        for(uint16 i = 0; i < container.instructions.length; i++) {
            if(container.instructions[i].targetChain == chainId) {
                deliveryInstructionIndex = i;
                return deliveryInstructionIndex;
            }
        }
    }

    function sufficientFundsHelper(DeliveryInstructionsContainer memory deliveryInstructions, uint256 funds) internal view returns (uint256 totalFees) {
        totalFees = wormhole().messageFee();
        for (uint256 i = 0; i < deliveryInstructions.instructions.length; i++) {
            uint256 currentOverhead = getGasOracle().deliverGasOverhead(deliveryInstructions.instructions[i].targetChain);

            // estimate relay cost and check to see if the user sent enough eth to cover the relay
            require(deliveryInstructions.instructions[i].computeBudget > currentOverhead, "Insufficient compute budget specified to cover required overheads");

            totalFees = totalFees + deliveryInstructions.instructions[i].computeBudget + deliveryInstructions.instructions[i].nativeBudget;

            require(
                funds >= totalFees,
                "Insufficient funds were provided to cover the delivery fees."
            );

            // sanity check a few of the values before composing the DeliveryInstructions
            require(deliveryInstructions.instructions[i].targetAddress != bytes32(0), "invalid targetAddress");
        }
    }

    function requestDelivery(uint16 targetChain, bytes32 targetAddress, bytes32 refundAddress, uint256 computeBudget, uint256 nativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) public payable returns (uint64 sequence) {
        //TODO should maximum batch size be removed from relay parameters, or is that a valuable protection? It's not currently enforced.
        // RelayParameters memory relayParameters = RelayParameters(1,estimateEvmGas(gasBudget), 0, gasBudget);
        //TODO should encode relay parameters take in relay parameters? Should relay parameters still exist?
        DeliveryInstruction memory instruction = DeliveryInstruction(targetChain, targetAddress, refundAddress, computeBudget, nativeBudget, relayParameters);
        DeliveryInstruction[] memory instructionArray = new DeliveryInstruction[](1);
        instructionArray[0] = instruction;
        DeliveryInstructionsContainer memory container = DeliveryInstructionsContainer(1, instructionArray);
        return multisend(container, nonce, consistencyLevel);
    }

    /**
     * @dev `multisend` generates a VAA with DeliveryInstructions to be delivered to the specified target
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function multisend(DeliveryInstructionsContainer memory deliveryInstructions, uint32 nonce, uint8 consistencyLevel)
        public
        payable
        returns (uint64 sequence)
    {
        sufficientFundsHelper(deliveryInstructions, msg.value);
        require(nonce > 0, "nonce must be > 0");

        // encode the DeliveryInstructions
        bytes memory container = encodeDeliveryInstructionsContainer(deliveryInstructions);

        // emit delivery message
        IWormhole wormhole = wormhole();
        sequence = wormhole.publishMessage{value: wormhole.messageFee()}(nonce, container, consistencyLevel);
    }

    // TODO: WIP
    function resend(bytes memory deliveryStatusVm, bytes memory newRelayerParams)
        public
        payable
        returns (uint64 sequence)
    {
        // IWormhole wormhole = wormhole();
        // (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(deliveryStatusVm);

        // require(valid, reason);
        // require(verifyRelayerVM(vm), "invalid emitter");

        // DeliveryStatus memory status = parseDeliveryStatus(vm.payload);

        // require(status.deliverySuccess == false, "delivery already succeeded");

        // bytes32 deliveryHash = keccak256(abi.encodePacked(status.batchHash, status.emitterAddress, status.sequence));
        // uint256 redeliveryAttempt = redeliveryAttemptCount(deliveryHash);
        // require(status.deliveryCount - 1 == redeliveryAttempt, "old delivery status receipt presented");
        // require(status.deliveryCount <= type(uint16).max, "too many retries");
        // incrementRedeliveryAttempt(deliveryHash);

        // RelayParameters memory relayParams = decodeRelayParameters(newRelayerParams);

        // // estimate relay cost and check to see if the user sent enough eth to cover the relay
        // collectRelayerParameterPayment(relayParams, vm.emitterChainId, relayParams.deliveryGasLimit);

        // RedeliveryInstructions memory redeliveryInstructions = RedeliveryInstructions({
        //     payloadID: 3,
        //     batchHash: status.batchHash,
        //     emitterAddress: status.emitterAddress,
        //     sequence: status.sequence,
        //     deliveryCount: status.deliveryCount,
        //     relayParameters: newRelayerParams
        // });

        // // emit delivery status message and set nonce to zero to opt out of batching
        // sequence = wormhole.publishMessage{value: msg.value}(
        //     0,
        //     encodeRedeliveryInstructions(redeliveryInstructions),
        //     consistencyLevel() //TODO user configurable?
        // );

        return 0;
    }

    // TODO: WIP
    function collectRelayerPayment(
        uint16 targetChain,
        uint256 computeBudget,
        uint256 nativeBudget
    ) internal {
        require(computeBudget > (getGasOracle().deliverGasOverhead(targetChain) + wormhole().messageFee()), "Insufficient compute budget!");
        
        //TODO also implement a cap on the compute budget.
        require(nativeBudget < computeBudget, "Native budget cannot be more than the compute budget.");

        require(
            msg.value == (computeBudget + nativeBudget),
            "Fee in msg.value does not cover the specified budget."
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
        InternalDeliveryParameters memory internalParams;

        // parse the batch VAA
        internalParams.batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // validate the deliveryIndex and cache the delivery VAA
        IWormhole.VM memory deliveryVM =
            parseWormholeObservation(internalParams.batchVM.observations[targetParams.deliveryIndex]);
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        internalParams.deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        internalParams.internalInstruction =
            decodeDeliveryPayload(deliveryVM.payload).instructions[targetParams.multisendIndex];

        //calc how much gas to put on the delivery
        //TODO fix this to reflect the proper wire type
        internalParams.deliveryGasLimit = internalParams.deliveryGasLimit;

        // override the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > internalParams.relayParams.deliveryGasLimit) {
            internalParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        // set the remaining values in the InternalDeliveryParameters struct
        internalParams.deliveryIndex = targetParams.deliveryIndex;
        internalParams.deliveryAttempts = 0;
        internalParams.fromChain = deliveryVM.emitterChainId;

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

        // build InternalDeliveryParameters struct to reduce local variable count
        InternalDeliveryParameters memory internalParams;

        // parse the batch
        internalParams.batchVM = wormhole.parseBatchVM(targetParams.encodedVM);

        // validate the deliveryIndex and cache the delivery VAA
        IWormhole.VM memory deliveryVM =
            parseWormholeObservation(internalParams.batchVM.observations[targetParams.deliveryIndex]);
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // create the AllowedEmitterSequence for the delivery VAA
        // TODO this is not a unique key
        internalParams.deliveryId =
            AllowedEmitterSequence({emitterAddress: deliveryVM.emitterAddress, sequence: deliveryVM.sequence});

        // parse the deliveryVM payload into the DeliveryInstructions struct
        internalParams.deliveryInstructions =
            decodeDeliveryInstructionsContainer(deliveryVM.payload).instructions[targetParams.multisendIndex];

        internalParams.fromChain = deliveryVM.emitterChainId;

        // parse and verify the encoded redelivery message
        (IWormhole.VM memory redeliveryVm, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedRedeliveryVm);
        require(valid, reason);
        require(verifyRelayerVM(redeliveryVm), "invalid emitter");

        // parse the RedeliveryInstructions
        RedeliveryInstructions memory redeliveryInstructions = parseRedeliveryInstructions(redeliveryVm.payload);
        require(redeliveryInstructions.batchHash == internalParams.batchVM.hash, "invalid batch");

        // check that the redelivery instructions are for the original deliveryVM
        require(
            redeliveryInstructions.emitterAddress == internalParams.deliveryId.emitterAddress,
            "invalid delivery emitter"
        );
        require(redeliveryInstructions.sequence == internalParams.deliveryId.sequence, "invalid delivery sequence");

        // override the DeliveryInstruction's relayParams with redelivery relayParams
        internalParams.deliveryInstructions.relayParameters = redeliveryInstructions.relayParameters;

        // parse the new relayParams
        // internalParams.relayParams = decodeRelayParameters(redeliveryInstructions.relayParameters);

        // override the target gas if requested by the relayer
        if (targetParams.targetCallGasOverride > internalParams.relayParams.deliveryGasLimit) {
            internalParams.relayParams.deliveryGasLimit = targetParams.targetCallGasOverride;
        }

        // set the remaining values in the InternalDeliveryParameters struct
        internalParams.deliveryIndex = targetParams.deliveryIndex;
        internalParams.deliveryAttempts = redeliveryInstructions.deliveryCount;

        return _deliver(wormhole, internalParams);
    }

    struct StackTooDeep {
        bytes32 deliveryHash;
        uint256 gasBudgetInWei;
        uint256 attemptedDeliveryCount;
        uint256 preGas;
    }

    function _deliver(IWormhole wormhole, InternalDeliveryParameters memory internalParams)
        internal
        returns (uint64 sequence)
    {
        StackTooDeep memory stackTooDeep;

        // todo: confirm unit is in wei
        // todo: change deliverGasLimit to be 2 separate fields so that if relayer overrides it, it does not end up
        //       giving too large a refund

        stackTooDeep.gasBudgetInWei = gasOracle().computeGasCost(chainId(), internalParams.relayParams.deliveryGasLimit);
        require(
            msg.value >= wormhole.messageFee() + stackTooDeep.gasBudgetInWei,
            "insufficient msg.value to pay wormhole messageFee and cover gas refund"
        );

        // Compute the hash(batchHash, deliveryId) and check to see if the batch
        // was successfully delivered already. Revert if it was.
        stackTooDeep.deliveryHash = keccak256(
            abi.encodePacked(
                internalParams.batchVM.hash,
                internalParams.deliveryId.emitterAddress,
                internalParams.deliveryId.sequence
            )
        );
        require(!isDeliveryCompleted(stackTooDeep.deliveryHash), "batch already delivered");

        // confirm this is the correct destination chain
        require(chainId() == internalParams.deliveryInstructions.targetChain, "targetChain is not this chain");

        // confirm the correct delivery attempt sequence
        stackTooDeep.attemptedDeliveryCount = attemptedDeliveryCount(stackTooDeep.deliveryHash);
        require(internalParams.deliveryAttempts == stackTooDeep.attemptedDeliveryCount, "wrong delivery attempt index");

        // verify the batchVM before calling the receiver
        (bool valid, string memory reason) = wormhole.verifyBatchVM(internalParams.batchVM, true);
        require(valid, reason);

        // remove the deliveryVM from the array of observations in the batch
        // TODO consider removing this?
        bytes[] memory targetObservations = new bytes[](internalParams.batchVM.observations.length - 1);
        uint256 lastIndex = 0;
        for (uint256 i = 0; i < internalParams.batchVM.observations.length;) {
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

        // store gas budget pre target invocation to calculate unused gas budget
        stackTooDeep.preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        // TODO catch revert?
        (bool success,) = address(uint160(uint256(internalParams.deliveryInstructions.targetAddress))).call{
            gas: internalParams.relayParams.deliveryGasLimit
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[])", targetObservations));

        // refund unused gas budget
        uint256 weiToSend =
            (stackTooDeep.gasBudgetInWei - gasOracle().computeGasCost(chainId(), stackTooDeep.preGas - gasleft()));

        //TODO handle the case where the refund amount is insufficient
        //should result in success for this chain, but a delivery failure for the target.
        if(getForwardingInstructions().isValid) {
            emitForward(weiToSend);
        } else {
            (bool sent,) =
                address(uint160(uint256(internalParams.deliveryInstructions.refundAddress))).call{value: weiToSend}("");

            if (!sent) {
                // if refunding fails, pay out full refund to relayer
                weiToSend = 0;
            }
        }


        // refund the rest to relayer
        msg.sender.call{value: msg.value - weiToSend - wormhole.messageFee()}("");

        // unlock the contract
        setContractLock(false);

        /**
         * If the delivery was successful, mark the delivery as completed in the contract state.
         *
         * If the delivery was unsuccessful, uptick the attempted delivery counter for this delivery hash.
         */
        if (success) {
            markAsDelivered(stackTooDeep.deliveryHash);
        } else {
            incrementAttemptedDelivery(stackTooDeep.deliveryHash);
        }

        // increment the relayer rewards
        incrementRelayerRewards(msg.sender, internalParams.fromChain, internalParams.relayParams.nativePayment);

        // clear the cache to reduce gas overhead
        wormhole.clearBatchCache(internalParams.batchVM.hashes);

        // emit delivery status message
        DeliveryStatus memory status = DeliveryStatus({
            payloadID: 2,
            batchHash: internalParams.batchVM.hash,
            emitterAddress: internalParams.deliveryId.emitterAddress,
            sequence: internalParams.deliveryId.sequence,
            deliveryCount: uint16(stackTooDeep.attemptedDeliveryCount + 1),
            deliverySuccess: success
        });
        // set the nonce to zero so a batch VAA is not created
        sequence =
            wormhole.publishMessage{value: wormhole.messageFee()}(0, encodeDeliveryStatus(status), consistencyLevel());
    }

    function _deliverChecks() internal {}

    // TODO: WIP
    function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce)
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
    function collectRewards(bytes memory encodedVm) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

        require(valid, reason);
        require(verifyRelayerVM(vm), "invalid emitter");

        RewardPayout memory payout = parseRewardPayout(vm.payload);

        require(payout.chain == chainId());

        payable(address(uint160(uint256(payout.receiver)))).transfer(payout.amount);
    }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        return registeredRelayer(vm.emitterChainId) == vm.emitterAddress;
    }

    function parseWormholeObservation(bytes memory observation) public view returns (IWormhole.VM memory) {
        return wormhole().parseVM(observation);
    }

    function getGasOracle() public view returns (IGasOracle) {
        return gasOracle();
    }

    function getSelectedGasOracle(bytes relayerParams) public view returns (IGasOracle) {
        if(relayerParams == 0 || relayerParams.length == 0){
            return getGasOracle();
        } else {
            //TODO parse relayerParams & instantiate IGasOracle. If that fails, explode.
        }
    } 
}
