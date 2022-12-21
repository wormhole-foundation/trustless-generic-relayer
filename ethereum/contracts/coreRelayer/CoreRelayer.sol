// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerStructs.sol";
import "./CoreRelayerGovernance.sol";

contract CoreRelayer is CoreRelayerGovernance {
    using BytesLib for bytes;

    function requestDelivery(uint16 targetChain, bytes32 targetAddress, bytes32 refundAddress, uint256 computeBudget, uint256 applicationBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) public payable returns (uint64 sequence) {
        //TODO should maximum batch size be removed from relay parameters, or is that a valuable protection? It's not currently enforced.
        // RelayParameters memory relayParameters = RelayParameters(1,estimateEvmGas(gasBudget), 0, gasBudget);
        //TODO should encode relay parameters take in relay parameters? Should relay parameters still exist?
        DeliveryRequest memory request = DeliveryRequest(targetChain, targetAddress, refundAddress, computeBudget, applicationBudget, relayParameters);
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, requests);
        return requestMultidelivery(container, nonce, consistencyLevel);
    }

    function requestForward(uint16 targetChain, bytes32 targetAddress, bytes32 refundAddress, uint256 computeBudget, uint256 applicationBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) public payable {
        //TODO adjust to new function args
        DeliveryRequest memory request = DeliveryRequest(targetChain, targetAddress, refundAddress, computeBudget, applicationBudget, relayParameters);
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, requests);
        return requestMultiforward(container, targetChain, nonce, consistencyLevel);
    }

    //TODO this
    function requestRedelivery(bytes32 transactionHash, uint32 originalNonce, uint256 newComputeBudget, uint256 newNativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) external payable returns (uint64 sequence) {

    }

    //TODO this
    /**
     * TODO: Correct this spec
     * @dev `multisend` generates a VAA with DeliveryInstructions to be delivered to the specified target
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function requestMultidelivery(DeliveryRequestsContainer memory deliveryRequests, uint32 nonce, uint8 consistencyLevel)
        public
        payable
        returns (uint64 sequence)
    {
        sufficientFundsHelper(deliveryRequests, msg.value);
        require(nonce > 0, "nonce must be > 0");

        // encode the DeliveryInstructions
        bytes memory container = encodeDeliveryInstructionsContainer(deliveryRequests);

        // emit delivery message
        IWormhole wormhole = wormhole();
        sequence = wormhole.publishMessage{value: wormhole.messageFee()}(nonce, container, consistencyLevel);
    }

    //TODO this
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
    function requestMultiforward(DeliveryInstructionsContainer memory deliveryInstructions, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) public {
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

    function sufficientFundsHelper(DeliveryRequestsContainer memory deliveryRequests, uint256 funds) internal view returns (uint256 totalFees) {
        totalFees = wormhole().messageFee();
        for (uint256 i = 0; i < deliveryRequests.requests.length; i++) {
            DeliveryRequest request = deliveryRequests.requests[i];
            uint256 currentOverhead = getSelectedGasOracle(request.relayParameters).deliverGasOverhead(request.targetChain);

            // estimate relay cost and check to see if the user sent enough eth to cover the relay
            require(request.computeBudget > currentOverhead, "Insufficient compute budget specified to cover required overheads");

            totalFees = totalFees + request.computeBudget + request.applicationBudget;

            require(
                funds >= totalFees,
                "Insufficient funds were provided to cover the delivery fees."
            );

            // sanity check a few of the values before composing the DeliveryInstructions
            require(request.targetAddress != bytes32(0), "invalid targetAddress");
        }
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

    function _executeDelivery(IWormhole wormhole, DeliveryInstruction memory internalInstruction, bytes[] memory encodedVMs)
        internal
        returns (uint64 sequence)
    {
        // TODO decide if we want to do this or not
        // remove the deliveryVM from the array of observations in the batch
        // bytes[] memory targetObservations = new bytes[](internalParams.batchVM.observations.length - 1);
        // uint256 lastIndex = 0;
        // for (uint256 i = 0; i < internalParams.batchVM.observations.length;) {
        //     if (i != internalParams.deliveryIndex) {
        //         targetObservations[lastIndex] = internalParams.batchVM.observations[i];
        //         unchecked {
        //             lastIndex += 1;
        //         }
        //     }
        //     unchecked {
        //         i += 1;
        //     }
        // }

        // lock the contract to prevent reentrancy
        require(!isContractLocked(), "reentrant call");
        setContractLock(true);

        // store gas budget pre target invocation to calculate unused gas budget
        uint32 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        // TODO try/catch around this
        (bool success,) = fromWormholeFormat(internalInstruction.targetAddress).call{
            gas: internalInstruction.executionParameters.deliveryGasLimit, value:internalInstruction.applicationBudgetTarget
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[])", encodedVMs));

        // refund unused gas budget
        uint256 weiToRefund = internalInstruction.executionParameters.deliveryGasLimit - (preGas - gasleft());


        // unlock the contract
        setContractLock(false);

        // increment the relayer rewards
        incrementRelayerRewards(msg.sender, internalInstruction.sourceChain, internalInstruction.sourceReward);

        //TODO always emit one VAA, of four types when delivering
        //Delivery success, delivery failure, forward, or a forward failure

        //TODO decide if we want to actually do this
        // // emit delivery status message
        // DeliveryStatus memory status = DeliveryStatus({
        //     payloadID: 2,
        //     batchHash: internalParams.batchVM.hash,
        //     emitterAddress: internalParams.deliveryId.emitterAddress,
        //     sequence: internalParams.deliveryId.sequence,
        //     deliveryCount: uint16(stackTooDeep.attemptedDeliveryCount + 1),
        //     deliverySuccess: success
        // });
        // // set the nonce to zero so a batch VAA is not created
        // sequence =
        //     wormhole.publishMessage{value: wormhole.messageFee()}(0, encodeDeliveryStatus(status), consistencyLevel());

        if(getForwardingInstructions().isValid) {
            //TODO decide what to do in the case of an insufficient refund to cover these costs

            //TODO emit special delivery failure status when the delivery succeeded by the forward
            //failed, this delivery failure can be redelivered
            emitForward(weiToRefund);
        } else {
            (bool sent,) =
                fromWormholeFormat(internalInstruction.refundAddress).call{value: weiToRefund}("");

            if (!sent) {
                // if refunding fails, pay out full refund to relayer
                weiToRefund = 0;
            }
        }


        // refund the rest to relayer
        msg.sender.call{value: msg.value - weiToRefund - internalInstruction.applicationBudgetTarget - wormhole.messageFee()}("");

        //TODO emit evm event that the delivery happened
    }

    //REVISE Consider outputting a VAA which has rewards for every chain to reduce rebalancing complexity
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
            20 //REVISE encode finality
        );
    }

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


    function redeliverSingle(TargetDeliveryParametersSingle memory targetParams, bytes memory encodedRedeliveryVm) external payable returns (uint64 sequence){
        
    }

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams) external payable returns (uint64 sequence) {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // validate the deliveryIndex and cache the delivery VAA
        (IWormhole.VM memory deliveryVM, bool valid) = wormhole().parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);
        require(valid, "Invalid VAA at delivery index");
        require(verifyRelayerVM(deliveryVM), "invalid emitter");

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstruction memory deliveryInstruction =
            decodeDeliveryInstructionsContainer(deliveryVM.payload).instructions[targetParams.multisendIndex];

        //make sure the specified relayer is the relayer delivering this message
        require(fromWormholeFormat(deliveryInstruction.executionParameters.relayerAddress) == msg.sender);

        //make sure relayer passed in sufficient funds
        require(msg.value >= deliveryInstruction.computeBudgetTarget + deliveryInstruction.applicationBudgetTarget);

        //make sure this has not already been delivered
        require(!isDeliveryCompleted(deliveryVM.hash));

        //mark as delivered, so it can't be reattempted
        markAsDelivered(deliveryVM.hash);

        //make sure this delivery is intended for this chain
        require(chainId() == deliveryInstruction.targetChain, "targetChain is not this chain");

        return _executeDelivery(wormhole, deliveryInstruction, targetParams.encodedVMs);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns(address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }












    //Batch VAA entrypoints

    /*
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
     /*
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
*/
}
