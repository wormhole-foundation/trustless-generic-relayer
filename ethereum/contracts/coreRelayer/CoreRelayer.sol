// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGovernance.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayer is CoreRelayerGovernance {
    using BytesLib for bytes;

    /// @notice msg.value was too low.
    /// @param reason An internal error code that further identifies the cause of failure.
    error InsufficientFunds(string reason);
    /// @notice msg.value must cover the budget specified.
    error MsgValueTooLow();
    error NonceIsZero();
    error NoDeliveryInProcess();
    error CantRequestMultipleForwards();
    error RelayProviderDoesNotSupportTargetChain();
    /// @notice Rollover chain was not included in the forwarding request.
    error RolloverChainNotIncluded();
    /// @notice Required chain not found in the delivery requests.
    /// @param chainId the required chain ID.
    error ChainNotFoundInDeliveryRequests(uint16 chainId);
    error ReentrantCall();
    error InvalidEmitterInOriginalDeliveryVM();
    /// @notice Tried to redeliver a VM that is invalid.
    /// @param reason An error string further detailing the reason why the VM is invalid.
    error InvalidRedeliveryVM(string reason);
    error InvalidEmitterInRedeliveryVM();
    /// @notice The same relay provider must be specified when doing a single VAA redeliver.
    error MismatchingRelayProvidersInRedelivery();
    /// @notice msg.sender must be the provider.
    error ProviderAddressIsNotSender();
    error RedeliveryRequestDoesNotTargetThisChain();
    error OriginalDeliveryRequestDidNotTargetThisChain();
    /// @notice Invalid VAA at delivery index.
    /// @param deliveryIndex the delivery index at which the invalid VAA was found.
    error InvalidVaa(uint256 deliveryIndex);
    error InvalidEmitter();
    /// @notice This delivery request was not sufficiently funded, and must request redelivery.
    error DeliveryRequestNotSufficientlyFunded();
    /// @notice Specified relayer is not the relayer delivering the message.
    error UnexpectedRelayer();
    /// @notice The relayer didn't pass sufficient funds (msg.value does not cover the necessary budget fees).
    error InsufficientRelayerFunds();
    /// @notice The message was already delivered.
    error AlreadyDelivered();
    /// @notice The destination chain is not this chain.
    /// @param targetChainId the destination chain ID found in the message.
    error TargetChainIsNotThisChain(uint16 targetChainId);
    error SrcNativeCurrencyPriceIsZero();
    error DstNativeCurrencyPriceIsZero();

    event DeliverySuccess(bytes32 deliveryVaaHash, address recipientContract);
    event DeliveryFailure(bytes32 deliveryVaaHash, address recipientContract);
    event ForwardRequestFailure(bytes32 deliveryVaaHash, address recipientContract);
    event ForwardRequestSuccess(bytes32 deliveryVaaHash, address recipientContract);

    function requestDelivery(DeliveryRequest memory request, uint32 nonce, IRelayProvider provider)
        public
        payable
        returns (uint64 sequence)
    {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container =
            DeliveryRequestsContainer({payloadId: 1, relayProviderAddress: address(provider), requests: requests});
        return requestMultidelivery(container, nonce);
    }

    function requestForward(DeliveryRequest memory request, uint16 rolloverChain, uint32 nonce, IRelayProvider provider)
        public
        payable
    {
        DeliveryRequest[] memory requests = new DeliveryRequest[](1);
        requests[0] = request;
        DeliveryRequestsContainer memory container =
            DeliveryRequestsContainer({payloadId: 1, relayProviderAddress: address(provider), requests: requests});
        return requestMultiforward(container, rolloverChain, nonce);
    }

    //REVISE consider adding requestMultiRedeliveryByTxHash
    function requestRedelivery(RedeliveryByTxHashRequest memory request, uint32 nonce, IRelayProvider provider)
        public
        payable
        returns (uint64 sequence)
    {
        (
            uint256 requestFee,
            uint256 maximumRefund,
            uint256 applicationBudgetTarget,
            bool isSufficient,
            string memory reason
        ) = verifyFunding(
            VerifyFundingCalculation({
                provider: provider,
                sourceChain: chainId(),
                targetChain: request.targetChain,
                computeBudgetSource: request.newComputeBudget,
                applicationBudgetSource: request.newApplicationBudget,
                isDelivery: false
            })
        );
        if (!isSufficient) {
            revert InsufficientFunds(reason);
        }
        uint256 totalFee = requestFee + wormhole().messageFee();

        //Make sure the msg.value covers the budget they specified
        if (msg.value < totalFee) {
            revert MsgValueTooLow();
        }

        emitRedelivery(request, nonce, provider.getConsistencyLevel(), applicationBudgetTarget, maximumRefund, provider);

        //Send the delivery fees to the specified address of the provider.
        provider.getRewardAddress().call{value: msg.value - wormhole().messageFee()}("");
    }

    function emitRedelivery(
        RedeliveryByTxHashRequest memory request,
        uint32 nonce,
        uint8 consistencyLevel,
        uint256 applicationBudgetTarget,
        uint256 maximumRefund,
        IRelayProvider provider
    ) internal returns (uint64 sequence) {
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
        if (!isSufficient) {
            revert InsufficientFunds(cause);
        }
        if (nonce == 0) {
            revert NonceIsZero();
        }

        // encode the DeliveryInstructions
        bytes memory container = convertToEncodedDeliveryInstructions(deliveryRequests, true);

        // emit delivery message
        IWormhole wormhole = wormhole();
        IRelayProvider provider = IRelayProvider(deliveryRequests.relayProviderAddress);

        sequence =
            wormhole.publishMessage{value: wormhole.messageFee()}(nonce, container, provider.getConsistencyLevel());

        //pay fee to provider
        provider.getRewardAddress().call{value: totalCost - wormhole.messageFee()}("");
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
    function requestMultiforward(DeliveryRequestsContainer memory deliveryRequests, uint16 rolloverChain, uint32 nonce)
        public
        payable
    {
        // Can only forward while a delivery is in process.
        if (!isContractLocked()) {
            revert NoDeliveryInProcess();
        }
        if (getForwardingRequest().isValid) {
            revert CantRequestMultipleForwards();
        }

        //We want to catch malformed requests in this function, and only underfunded requests when emitting.
        verifyForwardingRequest(deliveryRequests, rolloverChain, nonce);

        bytes memory encodedDeliveryRequestsContainer = encodeDeliveryRequestsContainer(deliveryRequests);
        setForwardingRequest(
            ForwardingRequest({
                deliveryRequestsContainer: encodedDeliveryRequestsContainer,
                rolloverChain: rolloverChain,
                nonce: nonce,
                msgValue: msg.value,
                isValid: true
            })
        );
    }

    function emitForward(uint256 refundAmount) internal returns (uint64, bool) {
        ForwardingRequest memory forwardingRequest = getForwardingRequest();
        DeliveryRequestsContainer memory container =
            decodeDeliveryRequestsContainer(forwardingRequest.deliveryRequestsContainer);

        //Add any additional funds which were passed in to the refund amount
        refundAmount = refundAmount + forwardingRequest.msgValue;

        //make sure the refund amount covers the native gas amounts
        (uint256 totalMinimumFees, bool funded,) = sufficientFundsHelper(container, refundAmount);

        //REVISE consider deducting the cost of this process from the refund amount?

        if (funded) {
            //find the delivery instruction for the rollover chain
            uint16 rolloverInstructionIndex = findDeliveryIndex(container, forwardingRequest.rolloverChain);

            //calc how much budget is used by chains other than the rollover chain
            uint256 rolloverChainCostEstimate = container.requests[rolloverInstructionIndex].computeBudget
                + container.requests[rolloverInstructionIndex].applicationBudget;
            //uint256 nonrolloverBudget = totalMinimumFees - rolloverChainCostEstimate; //stack too deep
            uint256 rolloverBudget = refundAmount - (totalMinimumFees - rolloverChainCostEstimate)
                - container.requests[rolloverInstructionIndex].applicationBudget;

            //overwrite the gas budget on the rollover chain to the remaining budget amount
            container.requests[rolloverInstructionIndex].computeBudget = rolloverBudget;
        }

        //emit forwarding instruction
        bytes memory reencoded = convertToEncodedDeliveryInstructions(container, funded);
        IRelayProvider provider = IRelayProvider(container.relayProviderAddress);
        IWormhole wormhole = wormhole();
        uint64 sequence = wormhole.publishMessage{value: wormhole.messageFee()}(
            forwardingRequest.nonce, reencoded, provider.getConsistencyLevel()
        );

        // if funded, pay out reward to provider. Otherwise, the delivery code will handle sending a refund.
        if (funded) {
            provider.getRewardAddress().call{value: refundAmount}("");
        }

        //clear forwarding request from cache
        clearForwardingRequest();

        return (sequence, funded);
    }

    function verifyForwardingRequest(DeliveryRequestsContainer memory container, uint16 rolloverChain, uint32 nonce)
        internal
        view
    {
        if (nonce == 0) {
            revert NonceIsZero();
        }

        bool foundRolloverChain = false;
        IRelayProvider selectedProvider = IRelayProvider(container.relayProviderAddress);

        for (uint16 i = 0; i < container.requests.length; i++) {
            if (selectedProvider.getDeliveryAddress(container.requests[i].targetChain) == 0) {
                revert RelayProviderDoesNotSupportTargetChain();
            }
            if (container.requests[i].targetChain == rolloverChain) {
                foundRolloverChain = true;
            }
        }

        if (!foundRolloverChain) {
            revert RolloverChainNotIncluded();
        }
    }

    function findDeliveryIndex(DeliveryRequestsContainer memory container, uint16 chainId)
        internal
        pure
        returns (uint16 deliveryRequestIndex)
    {
        for (uint16 i = 0; i < container.requests.length; i++) {
            if (container.requests[i].targetChain == chainId) {
                deliveryRequestIndex = i;
                return deliveryRequestIndex;
            }
        }

        revert ChainNotFoundInDeliveryRequests(chainId);
    }

    /*
    By the time this function completes, we must be certain that the specified funds are sufficient to cover
    delivery for each one of the deliveryRequests with at least 1 gas on the target chains.
    */
    function sufficientFundsHelper(DeliveryRequestsContainer memory deliveryRequests, uint256 funds)
        internal
        view
        returns (uint256 totalFees, bool isSufficient, string memory reason)
    {
        totalFees = wormhole().messageFee();
        IRelayProvider provider = IRelayProvider(deliveryRequests.relayProviderAddress);

        for (uint256 i = 0; i < deliveryRequests.requests.length; i++) {
            DeliveryRequest memory request = deliveryRequests.requests[i];

            (
                uint256 requestFee,
                uint256 applicationBudgetTarget,
                uint256 maximumRefund,
                bool isSufficient,
                string memory reason
            ) = verifyFunding(
                VerifyFundingCalculation({
                    provider: provider,
                    sourceChain: chainId(),
                    targetChain: request.targetChain,
                    computeBudgetSource: request.computeBudget,
                    applicationBudgetSource: request.applicationBudget,
                    isDelivery: true
                })
            );

            if (!isSufficient) {
                return (0, false, reason);
            }

            totalFees = totalFees + requestFee;
            if (funds < totalFees) {
                return (0, false, "25"); //"Insufficient funds were provided to cover the delivery fees.");
            }
        }

        return (totalFees, true, "");
    }

    struct VerifyFundingCalculation {
        IRelayProvider provider;
        uint16 sourceChain;
        uint16 targetChain;
        uint256 computeBudgetSource;
        uint256 applicationBudgetSource;
        bool isDelivery;
    }

    function verifyFunding(VerifyFundingCalculation memory args)
        internal
        view
        returns (
            uint256 requestFee,
            uint256 applicationBudgetTarget,
            uint256 maximumRefund,
            bool isSufficient,
            string memory reason
        )
    {
        requestFee = args.computeBudgetSource + args.applicationBudgetSource;
        applicationBudgetTarget =
            convertApplicationBudgetAmount(args.applicationBudgetSource, args.targetChain, args.provider);
        uint256 overheadFeeSource = args.isDelivery
            ? args.provider.quoteDeliveryOverhead(args.targetChain)
            : args.provider.quoteRedeliveryOverhead(args.targetChain);
        uint256 overheadBudgetTarget =
            quoteAssetConversion(args.sourceChain, overheadFeeSource, args.targetChain, args.provider);
        maximumRefund = args.isDelivery
            ? calculateTargetDeliveryMaximumRefund(args.targetChain, args.computeBudgetSource, args.provider)
            : calculateTargetRedeliveryMaximumRefund(args.targetChain, args.computeBudgetSource, args.provider);

        //Make sure the computeBudget covers the minimum delivery cost to the targetChain
        if (args.computeBudgetSource < overheadFeeSource) {
            isSufficient = false;
            reason = "26"; //Insufficient msg.value to cover minimum delivery costs.";
        }
        //Make sure the budget does not exceed the maximum for the provider on that chain; //This added value is totalBudgetTarget
        else if (
            args.provider.quoteMaximumBudget(args.targetChain)
                < (maximumRefund + overheadBudgetTarget + applicationBudgetTarget)
        ) {
            isSufficient = false;
            reason = "27"; //"Specified budget exceeds the maximum allowed by the provider";
        } else {
            isSufficient = true;
            reason = "";
        }
    }

    function _executeDelivery(
        IWormhole wormhole,
        DeliveryInstruction memory internalInstruction,
        bytes[] memory encodedVMs,
        bytes32 deliveryVaaHash
    ) internal returns (uint64 sequence) {
        //REVISE Decide whether we want to remove the DeliveryInstructionContainer from encodedVMs.

        // lock the contract to prevent reentrancy
        if (isContractLocked()) {
            revert ReentrantCall();
        }
        setContractLock(true);

        // store gas budget pre target invocation to calculate unused gas budget
        uint256 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        (bool success,) = fromWormholeFormat(internalInstruction.targetAddress).call{
            gas: internalInstruction.executionParameters.gasLimit,
            value: internalInstruction.applicationBudgetTarget
        }(abi.encodeWithSignature("receiveWormholeMessages(bytes[],bytes[])", encodedVMs, new bytes[](0)));

        uint256 postGas = gasleft();

        // refund unused gas budget
        uint256 weiToRefund = internalInstruction.applicationBudgetTarget;
        if (success) {
            weiToRefund = (internalInstruction.executionParameters.gasLimit - (preGas - postGas))
                * internalInstruction.maximumRefundTarget / internalInstruction.executionParameters.gasLimit;
        }

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

        if (getForwardingRequest().isValid) {
            (sequence, success) = emitForward(weiToRefund);
            if (success) {
                emit ForwardRequestSuccess(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            } else {
                (bool sent,) = fromWormholeFormat(internalInstruction.refundAddress).call{value: weiToRefund}("");

                if (!sent) {
                    // if refunding fails, pay out full refund to relayer
                    weiToRefund = 0;
                }
                emit ForwardRequestFailure(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            }
        } else {
            (bool sent,) = fromWormholeFormat(internalInstruction.refundAddress).call{value: weiToRefund}("");

            if (!sent) {
                // if refunding fails, pay out full refund to relayer
                weiToRefund = 0;
            }

            if (success) {
                emit DeliverySuccess(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            } else {
                emit DeliveryFailure(deliveryVaaHash, fromWormholeFormat(internalInstruction.targetAddress));
            }
        }

        uint256 applicationBudgetPaid = (success ? internalInstruction.applicationBudgetTarget : 0);
        uint256 wormholeFeePaid = getForwardingRequest().isValid ? wormhole.messageFee() : 0;
        uint256 relayerRefundAmount = msg.value - weiToRefund - applicationBudgetPaid - wormholeFeePaid;
        // refund the rest to relayer
        msg.sender.call{value: relayerRefundAmount}("");
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

    function redeliverSingle(TargetRedeliveryByTxHashParamsSingle memory targetParams)
        public
        payable
        returns (uint64 sequence)
    {
        //cache wormhole
        IWormhole wormhole = wormhole();

        //validate the original delivery VM
        (IWormhole.VM memory originalDeliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.sourceEncodedVMs[targetParams.deliveryIndex]);
        if (!valid) {
            revert InvalidVaa(targetParams.deliveryIndex);
        }
        if (!verifyRelayerVM(originalDeliveryVM)) {
            // Original Delivery VM has a invalid emitter
            revert InvalidEmitterInOriginalDeliveryVM();
        }

        //validate the redelivery VM
        IWormhole.VM memory redeliveryVM;
        (redeliveryVM, valid, reason) = wormhole.parseAndVerifyVM(targetParams.redeliveryVM);
        if (!valid) {
            revert InvalidRedeliveryVM(reason);
        }
        if (!verifyRelayerVM(redeliveryVM)) {
            // Redelivery VM has an invalid emitter
            revert InvalidEmitterInRedeliveryVM();
        }

        DeliveryInstruction memory instruction = validateRedeliverySingle(
            decodeRedeliveryByTxHashInstruction(redeliveryVM.payload),
            decodeDeliveryInstructionsContainer(originalDeliveryVM.payload).instructions[targetParams.multisendIndex]
        );

        //redelivery request cannot have already been attempted
        if (isDeliveryCompleted(redeliveryVM.hash)) {
            revert AlreadyDelivered();
        }

        //mark redelivery as attempted
        markAsDelivered(redeliveryVM.hash);

        return _executeDelivery(wormhole, instruction, targetParams.sourceEncodedVMs, originalDeliveryVM.hash);
    }

    function validateRedeliverySingle(
        RedeliveryByTxHashInstruction memory redeliveryInstruction,
        DeliveryInstruction memory originalInstruction
    ) internal view returns (DeliveryInstruction memory deliveryInstruction) {
        //All the same checks as delivery single, with a couple additional

        // The same relay provider must be specified when doing a single VAA redeliver.
        address providerAddress = fromWormholeFormat(redeliveryInstruction.executionParameters.providerDeliveryAddress);
        if (providerAddress != fromWormholeFormat(originalInstruction.executionParameters.providerDeliveryAddress)) {
            revert MismatchingRelayProvidersInRedelivery();
        }

        // msg.sender must be the provider
        if (msg.sender != providerAddress) {
            revert ProviderAddressIsNotSender();
        }

        //redelivery must target this chain
        if (chainId() != redeliveryInstruction.targetChain) {
            revert RedeliveryRequestDoesNotTargetThisChain();
        }

        //original delivery request must target this chain
        if (chainId() != originalInstruction.targetChain) {
            revert OriginalDeliveryRequestDidNotTargetThisChain();
        }

        //relayer must have covered the necessary funds
        if (
            msg.value
                < redeliveryInstruction.newMaximumRefundTarget + redeliveryInstruction.newApplicationBudgetTarget
                    + wormhole().messageFee()
        ) {
            revert InsufficientRelayerFunds();
        }

        //Overwrite compute budget and application budget on the original request and proceed.
        originalInstruction.maximumRefundTarget = redeliveryInstruction.newMaximumRefundTarget;
        originalInstruction.applicationBudgetTarget = redeliveryInstruction.newApplicationBudgetTarget;
        originalInstruction.executionParameters = redeliveryInstruction.executionParameters;
        deliveryInstruction = originalInstruction;
    }

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams)
        public
        payable
        returns (uint64 sequence)
    {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // validate the deliveryIndex
        (IWormhole.VM memory deliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);
        if (!valid) {
            revert InvalidVaa(targetParams.deliveryIndex);
        }
        if (!verifyRelayerVM(deliveryVM)) {
            revert InvalidEmitter();
        }

        DeliveryInstructionsContainer memory container = decodeDeliveryInstructionsContainer(deliveryVM.payload);
        //ensure this is a funded delivery, not a failed forward.
        if (!container.sufficientlyFunded) {
            revert DeliveryRequestNotSufficientlyFunded();
        }

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstruction memory deliveryInstruction = container.instructions[targetParams.multisendIndex];

        //make sure the specified relayer is the relayer delivering this message
        if (fromWormholeFormat(deliveryInstruction.executionParameters.providerDeliveryAddress) != msg.sender) {
            revert UnexpectedRelayer();
        }

        //make sure relayer passed in sufficient funds
        if (
            msg.value
                < deliveryInstruction.maximumRefundTarget + deliveryInstruction.applicationBudgetTarget
                    + wormhole.messageFee()
        ) {
            revert InsufficientRelayerFunds();
        }

        //make sure this has not already been delivered
        if (isDeliveryCompleted(deliveryVM.hash)) {
            revert AlreadyDelivered();
        }

        //mark as delivered, so it can't be reattempted
        markAsDelivered(deliveryVM.hash);

        //make sure this delivery is intended for this chain
        if (chainId() != deliveryInstruction.targetChain) {
            revert TargetChainIsNotThisChain(deliveryInstruction.targetChain);
        }

        return _executeDelivery(wormhole, deliveryInstruction, targetParams.encodedVMs, deliveryVM.hash);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns (address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function getDefaultRelayParams() public pure returns (bytes memory relayParams) {
        return new bytes(0);
    }

    function makeRelayerParams(IRelayProvider provider) public pure returns (bytes memory relayerParams) {
        //current version is just 1,
        relayerParams = abi.encode(1, toWormholeFormat(address(provider)));
    }

    function getDeliveryInstructionsContainer(bytes memory encoded)
        public
        view
        returns (DeliveryInstructionsContainer memory container)
    {
        container = decodeDeliveryInstructionsContainer(encoded);
    }

    function getRedeliveryByTxHashInstruction(bytes memory encoded)
        public
        view
        returns (RedeliveryByTxHashInstruction memory instruction)
    {
        instruction = decodeRedeliveryByTxHashInstruction(encoded);
    }

    /**
     * Given a targetChain, computeBudget, and a relay provider, this function calculates what the gas limit of the delivery transaction
     *     should be.
     */
    function calculateTargetGasDeliveryAmount(uint16 targetChain, uint256 computeBudget, IRelayProvider provider)
        internal
        view
        returns (uint32 gasAmount)
    {
        IWormhole wormhole = wormhole();
        if (computeBudget <= provider.quoteDeliveryOverhead(targetChain)) {
            return 0;
        } else {
            uint256 remainder = computeBudget - provider.quoteDeliveryOverhead(targetChain);
            uint256 gas = remainder / provider.quoteGasPrice(targetChain);

            if (gas >= 2 ** 32) return uint32(2 ** 32 - 1);
            return uint32(gas);
        }
    }

    function calculateTargetDeliveryMaximumRefund(uint16 targetChain, uint256 computeBudget, IRelayProvider provider)
        internal
        view
        returns (uint256 maximumRefund)
    {
        uint256 deliveryOverhead = provider.quoteDeliveryOverhead(targetChain);
        if (computeBudget >= deliveryOverhead) {
            uint256 remainder = computeBudget - deliveryOverhead;
            maximumRefund = quoteAssetConversion(chainId(), remainder, targetChain, provider);
        } else {
            maximumRefund = 0;
        }
    }

    /**
     * Given a targetChain, computeBudget, and a relay provider, this function calculates what the gas limit of the redelivery transaction
     *     should be.
     */
    function calculateTargetGasRedeliveryAmount(uint16 targetChain, uint256 computeBudget, IRelayProvider provider)
        internal
        view
        returns (uint32 gasAmount)
    {
        IWormhole wormhole = wormhole();
        if (computeBudget <= wormhole.messageFee() + provider.quoteRedeliveryOverhead(targetChain)) {
            return 0;
        } else {
            uint256 remainder = computeBudget - wormhole.messageFee() - provider.quoteRedeliveryOverhead(targetChain);
            uint256 gas = remainder / provider.quoteGasPrice(targetChain);

            if (gas >= 2 ** 32) return uint32(2 ** 32 - 1);
            return uint32(gas);
        }
    }

    function calculateTargetRedeliveryMaximumRefund(uint16 targetChain, uint256 computeBudget, IRelayProvider provider)
        internal
        view
        returns (uint256 maximumRefund)
    {
        uint256 remainder = computeBudget - provider.quoteRedeliveryOverhead(targetChain);
        maximumRefund = quoteAssetConversion(chainId(), remainder, targetChain, provider);
    }

    function quoteGasDeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 deliveryQuote)
    {
        return provider.quoteDeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain))
            + wormhole().messageFee();
    }

    function quoteGasRedeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 redeliveryQuote)
    {
        return provider.quoteRedeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain))
            + wormhole().messageFee();
    }

    //This is used internally to calculate the exchange rate for the provider without deducting the buffer amount
    function quoteAssetConversion(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain, IRelayProvider provider)
        internal
        view
        returns (uint256 targetAmount)
    {
        uint256 srcNativeCurrencyPrice = provider.quoteAssetPrice(sourceChain);
        if (srcNativeCurrencyPrice == 0) {
            revert SrcNativeCurrencyPriceIsZero();
        }

        uint256 dstNativeCurrencyPrice = provider.quoteAssetPrice(targetChain);
        if (dstNativeCurrencyPrice == 0) {
            revert DstNativeCurrencyPriceIsZero();
        }

        return sourceAmount * srcNativeCurrencyPrice / dstNativeCurrencyPrice;
    }

    //If the integrator pays at least nativeQuote, they should receive at least targetAmount as their application budget
    function quoteApplicationBudgetFee(uint16 targetChain, uint256 targetAmount, IRelayProvider provider)
        public
        view
        returns (uint256 nativeQuote)
    {
        uint256 sourceAmount = quoteAssetConversion(targetChain, targetAmount, chainId(), provider);
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);
        nativeQuote = (sourceAmount * (denominator + buffer) + denominator - 1) / denominator;
    }

    //This should invert quoteApplicationBudgetAmount, I.E when a user pays the sourceAmount, they receive at least the value of targetAmount they requested from
    //quoteApplicationBudgetFee.
    function convertApplicationBudgetAmount(uint256 sourceAmount, uint16 targetChain, IRelayProvider provider)
        internal
        view
        returns (uint256 targetAmount)
    {
        uint256 amount = quoteAssetConversion(chainId(), sourceAmount, targetChain, provider);
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);
        targetAmount = amount * denominator / (denominator + buffer);
    }

    function convertToEncodedRedeliveryByTxHashInstruction(
        RedeliveryByTxHashRequest memory request,
        uint256 applicationBudgetTarget,
        uint256 maximumRefund,
        uint32 gasLimit,
        IRelayProvider provider
    ) internal view returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            uint8(2), //version payload number
            uint16(request.sourceChain),
            bytes32(request.sourceTxHash),
            uint32(request.sourceNonce),
            uint16(request.targetChain)
        );
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
            uint8(isFunded ? 1 : 0), // sufficiently funded
            uint8(container.requests.length) //number of requests in the array
        );

        //Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {
            encoded = appendDeliveryInstruction(
                encoded, container.requests[i], IRelayProvider(container.relayProviderAddress)
            );
        }
    }

    function appendDeliveryInstruction(bytes memory encoded, DeliveryRequest memory request, IRelayProvider provider)
        internal
        view
        returns (bytes memory newEncoded)
    {
        newEncoded = abi.encodePacked(encoded, request.targetChain, request.targetAddress, request.refundAddress);
        newEncoded = abi.encodePacked(
            newEncoded,
            calculateTargetDeliveryMaximumRefund(request.targetChain, request.computeBudget, provider),
            quoteAssetConversion(chainId(), request.applicationBudget, request.targetChain, provider)
        );
        newEncoded = abi.encodePacked(
            newEncoded,
            uint8(1), //version for ExecutionParameters
            calculateTargetGasDeliveryAmount(request.targetChain, request.computeBudget, provider),
            provider.getDeliveryAddress(request.targetChain)
        );
    }
}
