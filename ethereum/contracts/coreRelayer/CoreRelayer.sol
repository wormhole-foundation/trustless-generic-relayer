// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeRelayer.sol";
import "../interfaces/IWormholeReceiver.sol";
import "../interfaces/IDelivery.sol";
import "./CoreRelayerGovernance.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayer is CoreRelayerGovernance {
    enum DeliveryStatus {
        SUCCESS,
        RECEIVER_FAILURE,
        FORWARD_REQUEST_FAILURE,
        FORWARD_REQUEST_SUCCESS,
        INVALID_REDELIVERY
    }

    event Delivery(
        address indexed recipientContract,
        uint16 indexed sourceChain,
        uint64 indexed sequence,
        bytes32 deliveryVaaHash,
        DeliveryStatus status
    );

    function send(IWormholeRelayer.Send memory request, uint32 nonce, address relayProvider)
        public
        payable
        returns (uint64 sequence)
    {
        return multichainSend(multichainSendContainer(request, relayProvider), nonce);
    }

    function forward(IWormholeRelayer.Send memory request, uint32 nonce, address relayProvider) public payable {
        return multichainForward(multichainSendContainer(request, relayProvider), nonce);
    }

    function resend(IWormholeRelayer.ResendByTx memory request, uint32 nonce, address relayProvider)
        public
        payable
        returns (uint64 sequence)
    {
        IWormhole wormhole = wormhole();
        bool isSufficient = request.newMaxTransactionFee + request.newReceiverValue + wormhole.messageFee() <= msg.value;
        if (!isSufficient) {
            revert IWormholeRelayer.MsgValueTooLow();
        }

        IRelayProvider provider = IRelayProvider(relayProvider);
        RedeliveryByTxHashInstruction memory instruction = convertResendToRedeliveryInstruction(request, provider);
        checkRedeliveryInstruction(instruction, provider);

        uint256 wormholeMessageFee = wormhole.messageFee();

        sequence = wormhole.publishMessage{value: wormholeMessageFee}(
            nonce, encodeRedeliveryByTxHashInstruction(instruction), provider.getConsistencyLevel()
        );

        //Send the delivery fees to the specified address of the provider.
        pay(provider.getRewardAddress(), msg.value - wormholeMessageFee);
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
    function multichainSend(IWormholeRelayer.MultichainSend memory deliveryRequests, uint32 nonce)
        public
        payable
        returns (uint64 sequence)
    {
        uint256 totalFee = getTotalFeeMultichainSend(deliveryRequests);
        if (totalFee > msg.value) {
            revert IWormholeRelayer.MsgValueTooLow();
        }
        if (nonce == 0) {
            revert IWormholeRelayer.NonceIsZero();
        }
        IRelayProvider relayProvider = IRelayProvider(deliveryRequests.relayProviderAddress);
        DeliveryInstructionsContainer memory container =
            convertMultichainSendToDeliveryInstructionContainer(deliveryRequests);
        checkInstructions(container, IRelayProvider(deliveryRequests.relayProviderAddress));
        container.sufficientlyFunded = true;

        // emit delivery message
        IWormhole wormhole = wormhole();
        uint256 wormholeMessageFee = wormhole.messageFee();
        sequence = wormhole.publishMessage{value: wormholeMessageFee}(
            nonce, encodeDeliveryInstructionsContainer(container), relayProvider.getConsistencyLevel()
        );

        //pay fee to provider
        pay(relayProvider.getRewardAddress(), totalFee - wormholeMessageFee);
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
    function multichainForward(IWormholeRelayer.MultichainSend memory deliveryRequests, uint32 nonce) public payable {
        if (!isContractLocked()) {
            revert IWormholeRelayer.NoDeliveryInProgress();
        }
        if (getForwardInstruction().isValid) {
            revert IWormholeRelayer.MultipleForwardsRequested();
        }
        if (nonce == 0) {
            revert IWormholeRelayer.NonceIsZero();
        }
        if (msg.sender != lockedTargetAddress()) {
            revert IWormholeRelayer.ForwardRequestFromWrongAddress();
        }

        uint256 totalFee = getTotalFeeMultichainSend(deliveryRequests);
        DeliveryInstructionsContainer memory container =
            convertMultichainSendToDeliveryInstructionContainer(deliveryRequests);
        checkInstructions(container, IRelayProvider(deliveryRequests.relayProviderAddress));

        setForwardInstruction(
            ForwardInstruction({
                container: container,
                nonce: nonce,
                msgValue: msg.value,
                totalFee: totalFee,
                sender: msg.sender,
                relayProvider: deliveryRequests.relayProviderAddress,
                isValid: true
            })
        );
    }

    function emitForward(uint256 refundAmount, ForwardInstruction memory forwardInstruction) internal returns (bool) {
        DeliveryInstructionsContainer memory container = forwardInstruction.container;

        //Add any additional funds which were passed in to the refund amount
        refundAmount = refundAmount + forwardInstruction.msgValue;

        //make sure the refund amount covers the native gas amounts
        bool funded = (refundAmount >= forwardInstruction.totalFee);
        container.sufficientlyFunded = funded;

        IRelayProvider relayProvider = IRelayProvider(forwardInstruction.relayProvider);

        if (funded) {
            // the rollover chain is the chain in the first request
            uint256 amountUnderMaximum = relayProvider.quoteMaximumBudget(container.instructions[0].targetChain)
                - (
                    wormhole().messageFee() + container.instructions[0].maximumRefundTarget
                        + container.instructions[0].receiverValueTarget
                );
            uint256 convertedExtraAmount = calculateTargetDeliveryMaximumRefund(
                container.instructions[0].targetChain, refundAmount - forwardInstruction.totalFee, relayProvider
            );
            container.instructions[0].maximumRefundTarget +=
                (amountUnderMaximum > convertedExtraAmount) ? convertedExtraAmount : amountUnderMaximum;
        }

        //emit forwarding instruction
        bytes memory encoded = encodeDeliveryInstructionsContainer(container);
        IWormhole wormhole = wormhole();
        uint64 sequence = wormhole.publishMessage{value: wormhole.messageFee()}(
            forwardInstruction.nonce, encoded, relayProvider.getConsistencyLevel()
        );

        // if funded, pay out reward to provider. Otherwise, the delivery code will handle sending a refund.
        if (funded) {
            pay(relayProvider.getRewardAddress(), refundAmount);
        }

        //clear forwarding request from cache
        clearForwardInstruction();

        return funded;
    }

    function multichainSendContainer(IWormholeRelayer.Send memory request, address relayProvider)
        internal
        pure
        returns (IWormholeRelayer.MultichainSend memory container)
    {
        IWormholeRelayer.Send[] memory requests = new IWormholeRelayer.Send[](1);
        requests[0] = request;
        container = IWormholeRelayer.MultichainSend({relayProviderAddress: relayProvider, requests: requests});
    }

    function _executeDelivery(
        IWormhole wormhole,
        DeliveryInstruction memory internalInstruction,
        bytes[] memory encodedVMs,
        bytes32 deliveryVaaHash,
        address payable relayerRefund,
        uint16 sourceChain,
        uint64 sourceSequence
    ) internal {
        //REVISE Decide whether we want to remove the DeliveryInstructionContainer from encodedVMs.

        // lock the contract to prevent reentrancy
        if (isContractLocked()) {
            revert IDelivery.ReentrantCall();
        }
        setContractLock(true);
        setLockedTargetAddress(fromWormholeFormat(internalInstruction.targetAddress));
        // store gas budget pre target invocation to calculate unused gas budget
        uint256 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        (bool success,) = fromWormholeFormat(internalInstruction.targetAddress).call{
            gas: internalInstruction.executionParameters.gasLimit,
            value: internalInstruction.receiverValueTarget
        }(abi.encodeCall(IWormholeReceiver.receiveWormholeMessages, (encodedVMs, new bytes[](0))));

        uint256 postGas = gasleft();
        // There's no easy way to measure the exact cost of the CALL instruction.
        // This is due to the fact that the compiler probably emits DUPN or MSTORE instructions
        // to setup the arguments for the call just after our measurement.
        // This means the refund could be off by a few units of gas.
        // Thus, we ensure the overhead doesn't cause an overflow in our refund formula here.
        uint256 gasUsed = (preGas - postGas) > internalInstruction.executionParameters.gasLimit
            ? internalInstruction.executionParameters.gasLimit
            : (preGas - postGas);

        // refund unused gas budget
        uint256 weiToRefund = internalInstruction.receiverValueTarget;
        if (success) {
            weiToRefund = (internalInstruction.executionParameters.gasLimit - gasUsed)
                * internalInstruction.maximumRefundTarget / internalInstruction.executionParameters.gasLimit;
        }

        // unlock the contract
        setContractLock(false);

        ForwardInstruction memory forwardingRequest = getForwardInstruction();
        DeliveryStatus status;
        bool forwardSucceeded = false;
        if (forwardingRequest.isValid) {
            forwardSucceeded = emitForward(weiToRefund, forwardingRequest);
            status = forwardSucceeded ? DeliveryStatus.FORWARD_REQUEST_SUCCESS : DeliveryStatus.FORWARD_REQUEST_FAILURE;
        } else {
            status = success ? DeliveryStatus.SUCCESS : DeliveryStatus.RECEIVER_FAILURE;
        }

        if (!forwardSucceeded) {
            bool sent = pay(payable(fromWormholeFormat(internalInstruction.refundAddress)), weiToRefund);
            if (!sent) {
                // if refunding fails, pay out full refund to relayer
                weiToRefund = 0;
            }
        }

        emit Delivery({
            recipientContract: fromWormholeFormat(internalInstruction.targetAddress),
            sourceChain: sourceChain,
            sequence: sourceSequence,
            deliveryVaaHash: deliveryVaaHash,
            status: status
        });

        uint256 receiverValuePaid = (success ? internalInstruction.receiverValueTarget : 0);
        uint256 wormholeFeePaid = forwardingRequest.isValid ? wormhole.messageFee() : 0;
        uint256 relayerRefundAmount = msg.value - weiToRefund - receiverValuePaid - wormholeFeePaid;
        // refund the rest to relayer
        pay(relayerRefund, relayerRefundAmount);
    }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        return registeredCoreRelayerContract(vm.emitterChainId) == vm.emitterAddress;
    }

    function getDefaultRelayProvider() public view returns (IRelayProvider) {
        return defaultRelayProvider();
    }

    function redeliverSingle(IDelivery.TargetRedeliveryByTxHashParamsSingle memory targetParams) public payable {
        //cache wormhole
        IWormhole wormhole = wormhole();

        //validate the redelivery VM
        (IWormhole.VM memory redeliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.redeliveryVM);
        if (!valid) {
            revert IDelivery.InvalidRedeliveryVM(reason);
        }
        if (!verifyRelayerVM(redeliveryVM)) {
            // Redelivery VM has an invalid emitter
            revert IDelivery.InvalidEmitterInRedeliveryVM();
        }

        RedeliveryByTxHashInstruction memory redeliveryInstruction =
            decodeRedeliveryByTxHashInstruction(redeliveryVM.payload);

        //validate the original delivery VM
        IWormhole.VM memory originalDeliveryVM;
        (originalDeliveryVM, valid, reason) =
            wormhole.parseAndVerifyVM(targetParams.sourceEncodedVMs[redeliveryInstruction.deliveryIndex]);
        if (!valid) {
            revert IDelivery.InvalidVaa(redeliveryInstruction.deliveryIndex);
        }
        if (!verifyRelayerVM(originalDeliveryVM)) {
            // Original Delivery VM has a invalid emitter
            revert IDelivery.InvalidEmitterInOriginalDeliveryVM(redeliveryInstruction.deliveryIndex);
        }

        DeliveryInstruction memory instruction;
        (instruction, valid) = validateRedeliverySingle(
            redeliveryInstruction,
            decodeDeliveryInstructionsContainer(originalDeliveryVM.payload).instructions[redeliveryInstruction
                .multisendIndex]
        );

        if (!valid) {
            emit Delivery({
                recipientContract: fromWormholeFormat(instruction.targetAddress),
                sourceChain: redeliveryVM.emitterChainId,
                sequence: redeliveryVM.sequence,
                deliveryVaaHash: redeliveryVM.hash,
                status: DeliveryStatus.INVALID_REDELIVERY
            });
            pay(targetParams.relayerRefundAddress, msg.value);
            return;
        }

        _executeDelivery(
            wormhole,
            instruction,
            targetParams.sourceEncodedVMs,
            originalDeliveryVM.hash,
            targetParams.relayerRefundAddress,
            originalDeliveryVM.emitterChainId,
            originalDeliveryVM.sequence
        );
    }

    function validateRedeliverySingle(
        RedeliveryByTxHashInstruction memory redeliveryInstruction,
        DeliveryInstruction memory originalInstruction
    ) internal view returns (DeliveryInstruction memory deliveryInstruction, bool isValid) {
        // All the same checks as delivery single, with a couple additional

        // The same relay provider must be specified when doing a single VAA redeliver.
        address providerAddress = fromWormholeFormat(redeliveryInstruction.executionParameters.providerDeliveryAddress);
        if (providerAddress != fromWormholeFormat(originalInstruction.executionParameters.providerDeliveryAddress)) {
            revert IDelivery.MismatchingRelayProvidersInRedelivery();
        }

        // relayer must have covered the necessary funds
        if (
            msg.value
                < redeliveryInstruction.newMaximumRefundTarget + redeliveryInstruction.newReceiverValueTarget
                    + wormhole().messageFee()
        ) {
            revert IDelivery.InsufficientRelayerFunds();
        }

        uint16 whChainId = chainId();
        // msg.sender must be the provider
        // "Relay provider differed from the specified address");
        isValid = msg.sender == providerAddress
        // redelivery must target this chain
        // "Redelivery request does not target this chain.");
        && whChainId == redeliveryInstruction.targetChain
        // original delivery must target this chain
        // "Original delivery request did not target this chain.");
        && whChainId == originalInstruction.targetChain
        // gasLimit & receiverValue must be at least as large as the initial delivery
        // "New receiver value is smaller than the original"
        && originalInstruction.receiverValueTarget <= redeliveryInstruction.newReceiverValueTarget
        // "New gasLimit is smaller than the original"
        && originalInstruction.executionParameters.gasLimit <= redeliveryInstruction.executionParameters.gasLimit;

        // Overwrite compute budget and application budget on the original request and proceed.
        deliveryInstruction = originalInstruction;
        deliveryInstruction.maximumRefundTarget = redeliveryInstruction.newMaximumRefundTarget;
        deliveryInstruction.receiverValueTarget = redeliveryInstruction.newReceiverValueTarget;
        deliveryInstruction.executionParameters = redeliveryInstruction.executionParameters;
    }

    function deliverSingle(IDelivery.TargetDeliveryParametersSingle memory targetParams) public payable {
        // cache wormhole instance
        IWormhole wormhole = wormhole();

        // validate the deliveryIndex
        (IWormhole.VM memory deliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);
        if (!valid) {
            revert IDelivery.InvalidVaa(targetParams.deliveryIndex);
        }
        if (!verifyRelayerVM(deliveryVM)) {
            revert IDelivery.InvalidEmitter();
        }

        DeliveryInstructionsContainer memory container = decodeDeliveryInstructionsContainer(deliveryVM.payload);
        //ensure this is a funded delivery, not a failed forward.
        if (!container.sufficientlyFunded) {
            revert IDelivery.SendNotSufficientlyFunded();
        }

        // parse the deliveryVM payload into the DeliveryInstructions struct
        DeliveryInstruction memory deliveryInstruction = container.instructions[targetParams.multisendIndex];

        //make sure the specified relayer is the relayer delivering this message
        if (fromWormholeFormat(deliveryInstruction.executionParameters.providerDeliveryAddress) != msg.sender) {
            revert IDelivery.UnexpectedRelayer();
        }

        //make sure relayer passed in sufficient funds
        if (
            msg.value
                < deliveryInstruction.maximumRefundTarget + deliveryInstruction.receiverValueTarget + wormhole.messageFee()
        ) {
            revert IDelivery.InsufficientRelayerFunds();
        }

        //make sure this delivery is intended for this chain
        if (chainId() != deliveryInstruction.targetChain) {
            revert IDelivery.TargetChainIsNotThisChain(deliveryInstruction.targetChain);
        }

        _executeDelivery(
            wormhole,
            deliveryInstruction,
            targetParams.encodedVMs,
            deliveryVM.hash,
            targetParams.relayerRefundAddress,
            deliveryVM.emitterChainId,
            deliveryVM.sequence
        );
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

    function quoteGas(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 deliveryQuote)
    {
        deliveryQuote = provider.quoteDeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain));
    }

    function quoteGasResend(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 redeliveryQuote)
    {
        redeliveryQuote =
            provider.quoteRedeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain));
    }

    //If the integrator pays at least nativeQuote, they should receive at least targetAmount as their application budget
    function quoteReceiverValue(uint16 targetChain, uint256 targetAmount, IRelayProvider provider)
        public
        view
        returns (uint256 nativeQuote)
    {
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);
        nativeQuote = assetConversionHelper(
            targetChain, targetAmount, chainId(), uint256(0) + denominator + buffer, denominator, true, provider
        );
    }

    function pay(address payable receiver, uint256 amount) internal returns (bool success) {
        if (amount > 0) {
            (success,) = receiver.call{value: amount}("");
        } else {
            success = true;
        }
    }
}
