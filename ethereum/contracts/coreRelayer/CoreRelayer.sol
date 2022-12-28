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

    function requestDelivery(DeliveryRequest memory request, uint32 nonce, IRelayProvider provider) public payable returns (uint64 sequence) {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, address(provider), requests);
        return requestMultidelivery(container, nonce);
    }

    function requestForward(DeliveryRequest memory request, uint16 rolloverChain, uint32 nonce, IRelayProvider provider) public {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container = DeliveryRequestsContainer(1, address(provider), requests);
        return requestMultiforward(container, rolloverChain, nonce);
    }

    //REVISE consider adding requestMultiRedeliveryByTxHash
    function requestRedelivery(RedeliveryByTxHashRequest memory request, uint32 nonce, IRelayProvider provider) public payable returns (uint64 sequence) {

        (uint256 requestFee, uint256 maximumRefund, uint256 applicationBudgetTarget, bool isSufficient, string memory reason)= 
            verifyFunding(provider, chainId(), request.targetChain, request.newComputeBudget, request.newApplicationBudget);
        require(isSufficient, reason);
        uint256 totalFee = requestFee + wormhole().messageFee();

        //Make sure the msg.value covers the budget they specified
        require(msg.value >= totalFee, "1"); //"Msg.value does not cover the specified budget");

        emitRedelivery(request, nonce, provider.getConsistencyLevel(), applicationBudgetTarget, maximumRefund, provider);

        
        //Send the delivery fees to the specified address of the provider.
        provider.getRewardAddress().call{value: msg.value - wormhole().messageFee()}("");
    }

    function emitRedelivery(RedeliveryByTxHashRequest memory request, uint32 nonce, uint8 consistencyLevel, uint256 applicationBudgetTarget, uint256 maximumRefund, IRelayProvider provider) internal returns (uint64 sequence) {

        bytes memory instruction = convertToEncodedRedeliveryByTxHashInstruction(
            request, 
            applicationBudgetTarget, 
            maximumRefund, 
            calculateTargetGasRedeliveryAmount(request.targetChain, request.newComputeBudget, provider),
            provider
        );

        sequence = wormhole().publishMessage{value: wormhole().messageFee()}(nonce, instruction, consistencyLevel);
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
    function requestMultidelivery(DeliveryRequestsContainer memory deliveryRequests, uint32 nonce)
        public 
        payable
        returns (uint64 sequence)
    {
        (uint256 totalCost, bool isSufficient, string memory cause) = sufficientFundsHelper(deliveryRequests, msg.value);
        require(isSufficient, cause);
        require(nonce > 0, "2");//"nonce must be > 0");

        // encode the DeliveryInstructions
        bytes memory container = convertToEncodedDeliveryInstructions(deliveryRequests, true);

        // emit delivery message
        IWormhole wormhole = wormhole();
        IRelayProvider provider =  IRelayProvider(deliveryRequests.relayProviderAddress);

        sequence = wormhole.publishMessage{value: wormhole.messageFee()}(nonce, container, provider.getConsistencyLevel());

        //pay fee to provider
        provider.getRewardAddress().call{value: msg.value - wormhole.messageFee()}("");

    }

    /**
     * TODO correct this comment
     * @dev `forward` queues up a 'send' which will be executed after the present delivery is complete 
     * & uses the gas refund to cover the costs.
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function requestMultiforward(DeliveryRequestsContainer memory deliveryRequests, uint16 rolloverChain, uint32 nonce) public payable {
        require(isContractLocked(), "3");//"Can only forward while a delivery is in process.");
        require(getForwardingRequest().isValid != true, "4");//"Cannot request multiple forwards.");

        //We want to catch malformed requests in this function, and only underfunded requests when emitting.
        verifyForwardingRequest(deliveryRequests, rolloverChain, nonce);

        bytes memory encodedDeliveryRequestsContainer = encodeDeliveryRequestsContainer(deliveryRequests);
        setForwardingRequest(ForwardingRequest(encodedDeliveryRequestsContainer, rolloverChain, nonce, msg.value, true));
    }

    function emitForward(uint256 refundAmount) internal returns (uint64, bool) {

        ForwardingRequest memory forwardingRequest = getForwardingRequest();
        DeliveryRequestsContainer memory container = decodeDeliveryRequestsContainer(forwardingRequest.deliveryRequestsContainer);

        //Add any additional funds which were passed in to the refund amount
        refundAmount = refundAmount + forwardingRequest.msgValue;
        
        //make sure the refund amount covers the native gas amounts
        (uint256 totalMinimumFees, bool funded, ) = sufficientFundsHelper(container, refundAmount);
        
        //REVISE consider deducting the cost of this process from the refund amount?

        //find the delivery instruction for the rollover chain
        uint16 rolloverInstructionIndex = findDeliveryIndex(container, forwardingRequest.rolloverChain);

        //calc how much budget is used by chains other than the rollover chain
        uint256 rolloverChainCostEstimate = container.requests[rolloverInstructionIndex].computeBudget + container.requests[rolloverInstructionIndex].applicationBudget;
        //uint256 nonrolloverBudget = totalMinimumFees - rolloverChainCostEstimate; //stack too deep
        uint256 rolloverBudget = refundAmount - (totalMinimumFees - rolloverChainCostEstimate) - container.requests[rolloverInstructionIndex].applicationBudget;

        //overwrite the gas budget on the rollover chain to the remaining budget amount
        container.requests[rolloverInstructionIndex].computeBudget = rolloverBudget;

        //emit forwarding instruction
        bytes memory reencoded = convertToEncodedDeliveryInstructions(container, funded);
        IRelayProvider provider = IRelayProvider(container.relayProviderAddress);
        IWormhole wormhole = wormhole();
        uint64 sequence = wormhole.publishMessage{value: wormhole.messageFee()}(forwardingRequest.nonce, reencoded, provider.getConsistencyLevel());

        // if funded, pay out reward to provider. Otherwise, the delivery code will handle sending a refund.
        if(funded) {
            address(provider).call{value: refundAmount}("");
        }
        
        //clear forwarding request from cache
        clearForwardingRequest();

        return (sequence, funded);

    }

    function verifyForwardingRequest(DeliveryRequestsContainer memory container, uint16 rolloverChain, uint32 nonce) internal view {
        require(nonce > 0, "2");//"nonce must be > 0");

        bool foundRolloverChain = false;
        IRelayProvider selectedProvider = IRelayProvider(container.relayProviderAddress);

        for(uint16 i = 0; i < container.requests.length; i++) {
            require(selectedProvider.getDeliveryAddress(container.requests[i].targetChain) != 0, "5");//"Specified relay provider does not support the target chain" );
            if(container.requests[i].targetChain == rolloverChain) {
                foundRolloverChain = true;
            }
        }

        require(foundRolloverChain, "6");//"Rollover chain was not included in the forwarding request.");
    }

    function findDeliveryIndex(DeliveryRequestsContainer memory container, uint16 chainId) internal pure returns (uint16 deliveryRequestIndex) {
        for(uint16 i = 0; i < container.requests.length; i++) {
            if(container.requests[i].targetChain == chainId) {
                deliveryRequestIndex = i;
                return deliveryRequestIndex;
            }
        }

        revert("7");//"Required chain not found in the delivery requests"); 
    }

    /*
    By the time this function completes, we must be certain that the specified funds are sufficient to cover
    delivery for each one of the deliveryRequests with at least 1 gas on the target chains.
    */
    function sufficientFundsHelper(DeliveryRequestsContainer memory deliveryRequests, uint256 funds) internal view returns (uint256 totalFees, bool isSufficient, string memory reason) {
        totalFees = wormhole().messageFee();
        IRelayProvider provider = IRelayProvider(deliveryRequests.relayProviderAddress);

        for (uint256 i = 0; i < deliveryRequests.requests.length; i++) {
            DeliveryRequest memory request = deliveryRequests.requests[i];

            (uint256 requestFee, uint256 applicationBudgetTarget, uint256 maximumReund, bool isSufficient, string memory reason) =
                verifyFunding(provider, chainId(), request.targetChain, request.computeBudget, request.applicationBudget);

            if(!isSufficient){
                return (0, false, reason);
            }

            totalFees = totalFees + requestFee;

            if( funds < totalFees ) {
                return (0, false, "25");//"Insufficient funds were provided to cover the delivery fees.");
            }
        }

        return (totalFees, true, "");
    }

    function verifyFunding(IRelayProvider provider, uint16 sourceChain, uint16 targetChain, uint256 computeBudgetSource, uint256 applicationBudgetSource) 
        internal view returns(uint256 requestFee, uint256 applicationBudgetTarget, uint256 maximumRefund, bool isSufficient, string memory reason){
        requestFee = computeBudgetSource + applicationBudgetSource;
        applicationBudgetTarget = provider.quoteAssetConversion(sourceChain, applicationBudgetSource, targetChain);
        uint256 overheadFeeSource = provider.quoteRedeliveryOverhead(targetChain);
        uint256 overheadBudgetTarget = provider.quoteAssetConversion(sourceChain, overheadFeeSource,targetChain);
        maximumRefund = calculateTargetRedeliveryMaximumRefund(targetChain, computeBudgetSource, provider);
        uint256 totalBudgetTarget = maximumRefund + overheadBudgetTarget + applicationBudgetTarget;

        //Make sure the computeBudget covers the minimum delivery cost to the targetChain
        if(computeBudgetSource < overheadFeeSource){
            isSufficient = false;
            reason = "26";//Insufficient msg.value to cover minimum delivery costs.";
        }

        //Make sure the budget does not exceed the maximum for the provider on that chain;
        else if(provider.quoteMaximumBudget(targetChain) < totalBudgetTarget){
            isSufficient = false;
            reason = "27";//"Specified budget exceeds the maximum allowed by the provider"; 
        }

        else {
            isSufficient = true;
            reason = ""; 
        }

    }

    function _executeDelivery(IWormhole wormhole, DeliveryInstruction memory internalInstruction, bytes[] memory encodedVMs, bytes32 deliveryVaaHash)
        internal
        returns (uint64 sequence)
    {
        //REVISE Decide whether we want to remove the DeliveryInstructionContainer from encodedVMs.

        // lock the contract to prevent reentrancy
        require(!isContractLocked(), "8");//"reentrant call");
        setContractLock(true);

        // store gas budget pre target invocation to calculate unused gas budget
        uint256 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        (bool success,) = fromWormholeFormat(internalInstruction.targetAddress).call{
            gas: internalInstruction.executionParameters.gasLimit, value:internalInstruction.applicationBudgetTarget
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[])", encodedVMs));

        uint256 postGas = gasleft();

        // refund unused gas budget
        uint256 weiToRefund = (internalInstruction.executionParameters.gasLimit - (preGas - postGas)) * internalInstruction.maximumRefundTarget / internalInstruction.executionParameters.gasLimit;

        // unlock the contract
        setContractLock(false);

        //REVISE decide if we want to always emit a VAA, or only emit a msg when forwarding
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
                (bool sent,) =
                fromWormholeFormat(internalInstruction.refundAddress).call{value: weiToRefund}("");

                if (!sent) {
                    // if refunding fails, pay out full refund to relayer
                    weiToRefund = 0;
                 }
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
        msg.sender.call{value: msg.value - weiToRefund - internalInstruction.applicationBudgetTarget - (getForwardingRequest().isValid ? wormhole.messageFee() : 0)}("");
    }

    //REVISE, consider implementing this system into the RelayProvider. 
    // function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce)
    //     public 
    //     payable
    //     returns (uint64 sequence)
    // {
    //     uint256 amount = relayerRewards(msg.sender, rewardChain);

    //     require(amount > 0, "no current accrued rewards");

    //     resetRelayerRewards(msg.sender, rewardChain);

    //     sequence = wormhole().publishMessage{value: msg.value}(
    //         nonce,
    //         encodeRewardPayout(
    //             RewardPayout({
    //                 payloadID: 100,
    //                 fromChain: chainId(),
    //                 chain: rewardChain,
    //                 amount: amount,
    //                 receiver: receiver
    //             })
    //         ),
    //         20 //REVISE encode finality
    //     );
    // }
    

    // function collectRewards(bytes memory encodedVm) public {
    //     (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVm);

    //     require(valid, reason);
    //     require(verifyRelayerVM(vm), "invalid emitter");

    //     RewardPayout memory payout = parseRewardPayout(vm.payload);

    //     require(payout.chain == chainId());

    //     payable(address(uint160(uint256(payout.receiver)))).transfer(payout.amount);
    // }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        return registeredCoreRelayerContract(vm.emitterChainId) == vm.emitterAddress;
    }

    function getDefaultRelayProvider() public view returns (IRelayProvider) {
        return defaultRelayProvider();
    }


    function redeliverSingle(TargetRedeliveryByTxHashParamsSingle memory targetParams) public payable returns (uint64 sequence){
        //cache wormhole
        IWormhole wormhole = wormhole();

        //validate the original delivery VM
        (IWormhole.VM memory originalDeliveryVM, bool valid, string memory reason) = wormhole.parseAndVerifyVM(targetParams.sourceEncodedVMs[targetParams.deliveryIndex]);
        require(valid, "9");//"Invalid VAA at delivery index");
        require(verifyRelayerVM(originalDeliveryVM), "10");//"Original Delivery VM has a invalid emitter");

        //validate the redelivery VM
        IWormhole.VM memory redeliveryVM;
        (redeliveryVM, valid, reason) = wormhole.parseAndVerifyVM(targetParams.redeliveryVM);
        require(valid, "11");//"Redelivery VM is invalid");
        require(verifyRelayerVM(redeliveryVM), "12");//"Redelivery VM has an invalid emitter");

        DeliveryInstruction memory instruction = validateRedeliverySingle(decodeRedeliveryByTxHashInstruction(redeliveryVM.payload), decodeDeliveryInstructionsContainer(originalDeliveryVM.payload).instructions[targetParams.multisendIndex]);

        //redelivery request cannot have already been attempted
        require(!isDeliveryCompleted(redeliveryVM.hash));

        //mark redelivery as attempted
        markAsDelivered(redeliveryVM.hash);

        return _executeDelivery(wormhole, instruction, targetParams.sourceEncodedVMs, originalDeliveryVM.hash);
    }

    function validateRedeliverySingle(RedeliveryByTxHashInstruction memory redeliveryInstruction, DeliveryInstruction memory originalInstruction) internal view returns (DeliveryInstruction memory deliveryInstruction) {
        //All the same checks as delivery single, with a couple additional

        //providers must match on both
        address providerAddress = fromWormholeFormat(redeliveryInstruction.executionParameters.providerDeliveryAddress);
        require(providerAddress == 
            fromWormholeFormat(originalInstruction.executionParameters.providerDeliveryAddress), 
            "13");//"The same relay provider must be specified when doing a single VAA redeliver");

        //msg.sender must be the provider
        require (msg.sender == providerAddress, "14");//"Relay provider differed from the specified address");

        //redelivery must target this chain
        require (chainId() == redeliveryInstruction.targetChain, "15");//"Redelivery request does not target this chain.");

        //original delivery must target this chain
        require (chainId() == originalInstruction.targetChain, "16");//"Original delivery request did not target this chain.");

        //relayer must have covered the necessary funds
        require (msg.value >= redeliveryInstruction.newMaximumRefundTarget + redeliveryInstruction.newApplicationBudgetTarget + wormhole().messageFee(), 
        "17");//"Msg.value does not cover the necessary budget fees");

        //Overwrite compute budget and application budget on the original request and proceed.
        originalInstruction.maximumRefundTarget = redeliveryInstruction.newMaximumRefundTarget;
        originalInstruction.applicationBudgetTarget = redeliveryInstruction.newApplicationBudgetTarget;
        originalInstruction.executionParameters = redeliveryInstruction.executionParameters;
        deliveryInstruction = originalInstruction;

    }

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams) public payable returns (uint64 sequence) {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // validate the deliveryIndex 
        (IWormhole.VM memory deliveryVM, bool valid, string memory reason) = wormhole.parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);
        require(valid, "18");//"Invalid VAA at delivery index");
        require(verifyRelayerVM(deliveryVM), "19");//"invalid emitter");

        DeliveryInstructionsContainer memory container = decodeDeliveryInstructionsContainer(deliveryVM.payload);
        //ensure this is a funded delivery, not a failed forward.
        require(container.sufficientlyFunded, "20");//"This delivery request was not sufficiently funded, and must request redelivery.");

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstruction memory deliveryInstruction =
            container.instructions[targetParams.multisendIndex];

        //make sure the specified relayer is the relayer delivering this message
        require(fromWormholeFormat(deliveryInstruction.executionParameters.providerDeliveryAddress) == msg.sender, 
        "21");//"Specified relayer is not the relayer delivering the message");

        //make sure relayer passed in sufficient funds
        require(msg.value >= deliveryInstruction.maximumRefundTarget + deliveryInstruction.applicationBudgetTarget + wormhole.messageFee(), 
        "22");//"Relayer did not pass in sufficient funds");

        //make sure this has not already been delivered
        require(!isDeliveryCompleted(deliveryVM.hash), 
        "23");//"delivery is already completed");

        //mark as delivered, so it can't be reattempted
        markAsDelivered(deliveryVM.hash);

        //make sure this delivery is intended for this chain
        require(chainId() == deliveryInstruction.targetChain, 
        "24");//"targetChain is not this chain");

        return _executeDelivery(wormhole, deliveryInstruction, targetParams.encodedVMs, deliveryVM.hash);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns(address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function getDefaultRelayParams() public pure returns(bytes memory relayParams) {
        return new bytes(0);
    }

    function makeRelayerParams(IRelayProvider provider) public pure returns(bytes memory relayerParams) {
        //current version is just 1,
        relayerParams = abi.encode(1, toWormholeFormat(address(provider)));
    }

    function getDeliveryInstructionsContainer(bytes memory encoded) public view returns (DeliveryInstructionsContainer memory container) {
        container = decodeDeliveryInstructionsContainer(encoded);
    }

    /**
        Given a targetChain, computeBudget, and a relay provider, this function calculates what the gas limit of the delivery transaction
        should be.
    */
    function calculateTargetGasDeliveryAmount(uint16 targetChain, uint256 computeBudget, IRelayProvider provider) internal view returns (uint32 gasAmount) {
        IWormhole wormhole = wormhole();
        if(computeBudget <= wormhole.messageFee() + provider.quoteDeliveryOverhead(targetChain)) {
            return 0;
        } else {
            uint256 remainder = computeBudget - wormhole.messageFee()  - provider.quoteDeliveryOverhead(targetChain);
            uint256 gas = remainder / provider.quoteGasPrice(targetChain);

            if(gas >= 2 ** 32) return uint32(2 ** 32 - 1);
            return uint32(gas);
        }
    }

    function calculateTargetDeliveryMaximumRefund(uint16 targetChain, uint256 computeBudget, IRelayProvider provider) internal view returns (uint256 maximumRefund) {
        uint256 remainder = computeBudget - provider.quoteDeliveryOverhead(targetChain);
        maximumRefund = provider.quoteAssetConversion(chainId(), remainder, targetChain);
    }

    /**
        Given a targetChain, computeBudget, and a relay provider, this function calculates what the gas limit of the redelivery transaction
        should be.
    */
    function calculateTargetGasRedeliveryAmount(uint16 targetChain, uint256 computeBudget, IRelayProvider provider) internal view returns (uint32 gasAmount) {
        IWormhole wormhole = wormhole();
        if(computeBudget <= wormhole.messageFee() + provider.quoteRedeliveryOverhead(targetChain)) {
            return 0;
        } else {
            uint256 remainder = computeBudget - wormhole.messageFee() - provider.quoteRedeliveryOverhead(targetChain);
            uint256 gas = remainder / provider.quoteGasPrice(targetChain);

            if(gas >= 2 ** 32) return uint32(2 ** 32 - 1);
            return uint32(gas);
        }
    }

    function calculateTargetRedeliveryMaximumRefund(uint16 targetChain, uint256 computeBudget, IRelayProvider provider) internal view returns (uint256 maximumRefund) {
        uint256 remainder = computeBudget - provider.quoteRedeliveryOverhead(targetChain);
        maximumRefund = provider.quoteAssetConversion(chainId(), remainder, targetChain);
    }

    function quoteGasDeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider provider) public view returns (uint256 deliveryQuote){
        return provider.quoteDeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain)) + wormhole().messageFee();
    }

    function quoteGasRedeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider provider) public view returns (uint256 redeliveryQuote){
        return provider.quoteRedeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain)) + wormhole().messageFee();
    }

    //If the integrator pays at least nativeQuote, they should receive at least targetAmount as their application budget
    function quoteApplicationBudgetFee(uint16 targetChain, uint256 targetAmount, IRelayProvider provider) public view returns (uint256 nativeQuote) {
        uint256 sourceAmount = provider.quoteAssetConversion(targetChain, targetAmount, chainId());
        (uint16 buffer, uint16 denominator) = provider.assetConversionBuffer(chainId(), targetChain);
        nativeQuote = (sourceAmount * (denominator + buffer) + denominator - 1) / denominator; 
    }

    //This should invert quoteApplicationBudgetAmount, I.E when a user pays the sourceAmount, they receive at least the value of targetAmount they requested from
    //quoteApplicationBudgetFee.
    function convertApplicationBudgetAmount(uint256 sourceAmount, uint16 targetChain, IRelayProvider provider) internal view returns (uint256 targetAmount) {
        uint256 amount = provider.quoteAssetConversion(chainId(), sourceAmount, targetChain);
        (uint16 buffer, uint16 denominator) = provider.assetConversionBuffer(chainId(), targetChain);
        targetAmount = amount * denominator / (denominator + buffer); 
    }

    function convertToEncodedRedeliveryByTxHashInstruction(RedeliveryByTxHashRequest memory request,
            uint256 applicationBudgetTarget, 
            uint256 maximumRefund, 
            uint32 gasLimit,
            IRelayProvider provider) internal view returns (bytes memory encoded) {

        encoded = abi.encodePacked(
            uint8(2), //version payload number
            uint16(request.sourceChain),
            bytes32(request.sourceTxHash),
            uint32(request.sourceNonce),
            uint16(request.targetChain));
        encoded = abi.encodePacked(
            encoded,
            maximumRefund, 
            applicationBudgetTarget,
            uint8(1), //version for ExecutionParameters
            gasLimit,
            provider.getDeliveryAddress(request.targetChain)
        ); 
        
        
    }

    function convertToEncodedDeliveryInstructions(DeliveryRequestsContainer memory container, bool isFunded)
        internal
        view
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            uint8(1), //version payload number
            uint8(isFunded? 1: 0), // sufficiently funded
            uint8(container.requests.length) //number of requests in the array
        ); 
        
        //Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {

            encoded = appendDeliveryInstruction(encoded, container.requests[i], IRelayProvider(container.relayProviderAddress));
            

        }
    }

    function appendDeliveryInstruction(bytes memory encoded, DeliveryRequest memory request, IRelayProvider provider) internal view returns (bytes memory newEncoded) {
            newEncoded = abi.encodePacked(
                encoded,
                request.targetChain,
                request.targetAddress,
                request.refundAddress);
            newEncoded = abi.encodePacked(newEncoded, 
                calculateTargetDeliveryMaximumRefund(request.targetChain, request.computeBudget, provider), 
                provider.quoteAssetConversion(chainId(), request.applicationBudget, request.targetChain));
            newEncoded = abi.encodePacked(newEncoded, 
                uint8(1), //version for ExecutionParameters
                calculateTargetGasDeliveryAmount(request.targetChain, request.computeBudget, provider),
                provider.getDeliveryAddress(request.targetChain));
    }

  }