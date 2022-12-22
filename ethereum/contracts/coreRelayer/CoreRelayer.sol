// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";


import "./CoreRelayerGovernance.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayer is CoreRelayerGovernance {
    using BytesLib for bytes;

    event DeliverySuccess(bytes32 deliveryVaaHash, address recipientContract);
    event DeliveryFailure(bytes32 deliveryVaaHash, address recipientContract);
    event ForwardRequestFailure(bytes32 deliveryVaaHash, address recipientContract);
    event ForwardRequestSuccess(bytes32 deliveryVaaHash, address recipientContract);

    function requestDelivery(DeliveryRequest memory request, uint32 nonce, uint8 consistencyLevel) public payable returns (uint64 sequence) {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, requests);
        return requestMultidelivery(container, nonce, consistencyLevel);
    }

    function requestForward(DeliveryRequest memory request, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) public payable {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, requests);
        return requestMultiforward(container, rolloverChain, nonce, consistencyLevel);
    }

    function requestRedelivery(bytes32 transactionHash, uint32 originalNonce, uint256 newComputeBudget, uint256 newNativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) external payable returns (uint64 sequence) {

    }

    /**
     * TODO: Correct this comment
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
        (uint256 totalCost, bool isSufficient, string memory cause) = sufficientFundsHelper(deliveryRequests, msg.value);
        require(isSufficient, cause);
        require(nonce > 0, "nonce must be > 0");

        // encode the DeliveryInstructions
        bytes memory container = convertToEncodedDeliveryInstructions(deliveryRequests, true);

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
    function requestMultiforward(DeliveryRequestsContainer memory deliveryRequests, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) public {
        require(isContractLocked(), "Can only forward while a delivery is in process.");
        require(getForwardingRequest().isValid != true, "Cannot request multiple forwards.");

        //We want to catch malformed requests in this function, and only underfunded requests when emitting.
        verifyForwardingRequest(deliveryRequests, rolloverChain, nonce);

        setForwardingRequest(ForwardingRequest(encodeDeliveryRequestsContainer(deliveryRequests), rolloverChain, nonce, consistencyLevel, true));
    }

    function emitForward(uint256 refundAmount) internal returns (uint64, bool) {
        ForwardingRequest memory forwardingRequest = getForwardingRequest();
        DeliveryRequestsContainer memory container = decodeDeliveryRequestsContainer(forwardingRequest.deliveryRequestsContainer);
        

        //make sure the refund amount covers the native gas amounts
        (uint256 totalMinimumFees, bool isSufficient,) = sufficientFundsHelper(container, refundAmount);
        
        //REVISE consider deducting the cost of these calculations from the refund amount?


        //find the delivery instruction for the rollover chain
        uint16 rolloverInstructionIndex = findDeliveryIndex(container, forwardingRequest.rolloverChain);

        //calc how much budget is used by chains other than the rollover chain
        uint256 rolloverChainCostEstimate = container.requests[rolloverInstructionIndex].computeBudget + container.requests[rolloverInstructionIndex].applicationBudget;
        //uint256 nonrolloverBudget = totalMinimumFees - rolloverChainCostEstimate; //stack too deep
        uint256 rolloverBudget = refundAmount - (totalMinimumFees - rolloverChainCostEstimate) - container.requests[rolloverInstructionIndex].applicationBudget;


        //overwrite the gas budget on the rollover chain to the remaining budget amount
        container.requests[rolloverInstructionIndex].computeBudget = rolloverBudget;

        //emit forwarding instruction
        bytes memory reencoded = convertToEncodedDeliveryInstructions(container, isSufficient);
        IWormhole wormhole = wormhole();
        uint64 sequence = wormhole.publishMessage{value: wormhole.messageFee()}(forwardingRequest.nonce, reencoded, forwardingRequest.consistencyLevel);

        //clear forwarding request from cache
        clearForwardingRequest();

        return (sequence, isSufficient);
    }

    function verifyForwardingRequest(DeliveryRequestsContainer memory container, uint16 rolloverChain, uint32 nonce) internal view {
        require(nonce > 0, "nonce must be > 0");

        bool foundRolloverChain = false;

        for(uint16 i = 0; i < container.requests.length; i++) {
            IGasOracle selectedOracle = getSelectedGasOracle(container.requests[i].relayParameters);
            require(selectedOracle.getRelayerAddress(container.requests[i].targetChain) != 0, "Specified relayer does not support the target chain" );
            if(container.requests[i].targetChain == rolloverChain) {
                foundRolloverChain = true;
            }
        }

        require(foundRolloverChain, "Rollover chain was not included in the forwarding request.");
    }

    function findDeliveryIndex(DeliveryRequestsContainer memory container, uint16 chainId) internal pure returns (uint16 deliveryRequestIndex) {
        for(uint16 i = 0; i < container.requests.length; i++) {
            if(container.requests[i].targetChain == chainId) {
                deliveryRequestIndex = i;
                return deliveryRequestIndex;
            }
        }

        revert("Required chain not found in the delivery requests"); 
    }

    /*
    By the time this function completes, we must be certain that the specified funds are sufficient to cover
    delivery for each one of the deliveryRequests with at least 1 gas on the target chains.
    */
    function sufficientFundsHelper(DeliveryRequestsContainer memory deliveryRequests, uint256 funds) internal view returns (uint256 totalFees, bool isSufficient, string memory reason) {
        totalFees = wormhole().messageFee();
        for (uint256 i = 0; i < deliveryRequests.requests.length; i++) {
            DeliveryRequest memory request = deliveryRequests.requests[i];

            IGasOracle selectedProvider = getSelectedGasOracle(request.relayParameters);
            uint256 computeOverhead = selectedProvider.quoteEvmDeliveryPrice(request.targetChain, 1);

            // estimate relay cost and check to see if the user sent enough eth to cover the relay
            if(request.computeBudget < computeOverhead) {
                return(0, false, "Insufficient compute budget specified to cover required overheads");
            } 

            // TODO add function to provider interface to retrieve this on a per-chain basis
            if(request.applicationBudget > request.computeBudget){
                return (0, false, "applicationBudget value is larger than allowed");
            }

            totalFees = totalFees + request.computeBudget + request.applicationBudget;

            if( funds < totalFees ) {
                return (0, false, "Insufficient funds were provided to cover the delivery fees.");
            }

            //additional sanity checks
            if (request.targetAddress == bytes32(0)){
                return (0, false, "invalid targetAddress");
            } 
        }

        return (totalFees, true, "");
    }

    function _executeDelivery(IWormhole wormhole, DeliveryInstruction memory internalInstruction, bytes[] memory encodedVMs, bytes32 deliveryVaaHash)
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
        uint256 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        (bool success,) = fromWormholeFormat(internalInstruction.targetAddress).call{
            gas: internalInstruction.executionParameters.gasLimit, value:internalInstruction.applicationBudgetTarget
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[])", encodedVMs));

        uint256 postGas = gasleft();

        // refund unused gas budget
        //TODO currently in gas units, needs to be converted to wei by multiplying the percentage remaining times the
        //compute budget
        uint256 weiToRefund = internalInstruction.executionParameters.gasLimit - (preGas - postGas);

        // unlock the contract
        setContractLock(false);

        // increment the relayer rewards
        incrementRelayerRewards(msg.sender, internalInstruction.sourceChain, internalInstruction.sourceReward);

        //TODO decide if we want to always emit a VAA, or only when forwarding
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

        if(getForwardingRequest().isValid) {
            (sequence, success) = emitForward(weiToRefund);
            if(success){
                emit ForwardRequestSuccess(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            } else {
                emit ForwardRequestFailure(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            }
        } else {
            (bool sent,) =
                fromWormholeFormat(internalInstruction.refundAddress).call{value: weiToRefund}("");

            if (!sent) {
                // if refunding fails, pay out full refund to relayer
                weiToRefund = 0;
            }

            if(success){
                emit DeliverySuccess(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            } else {
                emit DeliveryFailure(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            }
        }


        // refund the rest to relayer
        msg.sender.call{value: msg.value - weiToRefund - internalInstruction.applicationBudgetTarget - wormhole.messageFee()}("");
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
        console.logBytes32(vm.emitterAddress);
        console.log("above is the emitter address");
        console.log("should be");
        console.logBytes32(registeredCoreRelayerContract(vm.emitterChainId));
        return registeredCoreRelayerContract(vm.emitterChainId) == vm.emitterAddress;
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
        (IWormhole.VM memory deliveryVM, bool valid, string memory reason) = wormhole.parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);
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

        return _executeDelivery(wormhole, deliveryInstruction, targetParams.encodedVMs, deliveryVM.hash);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns(address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function setDefaultGasOracle(address gasOracle) public onlyOwner {
        setGasOracle(gasOracle);
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
