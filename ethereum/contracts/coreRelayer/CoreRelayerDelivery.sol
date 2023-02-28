// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeReceiver.sol";
import "../interfaces/IDelivery.sol";
import "./CoreRelayerGovernance.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayerDelivery is CoreRelayerGovernance {
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

    function emitForward(uint256 transactionFeeRefundAmount, ForwardInstruction memory forwardInstruction)
        internal
        returns (bool forwardIsFunded)
    {
        DeliveryInstructionsContainer memory container = forwardInstruction.container;

        //Add any additional funds which were passed in to the refund amount
        transactionFeeRefundAmount = transactionFeeRefundAmount + forwardInstruction.msgValue;

        //make sure the refund amount covers the native gas amounts
        forwardIsFunded = (transactionFeeRefundAmount >= forwardInstruction.totalFee);
        container.sufficientlyFunded = forwardIsFunded;

        IRelayProvider relayProvider = IRelayProvider(forwardInstruction.relayProvider);

        IWormhole wormhole = wormhole();
        uint256 wormholeMessageFee = wormhole.messageFee();
        if (forwardIsFunded) {
            // the rollover chain is the chain in the first request
            uint256 amountUnderMaximum = relayProvider.quoteMaximumBudget(container.instructions[0].targetChain)
                - (
                    wormholeMessageFee + container.instructions[0].maximumRefundTarget
                        + container.instructions[0].receiverValueTarget
                );
            uint256 convertedExtraAmount = calculateTargetDeliveryMaximumRefund(
                container.instructions[0].targetChain,
                transactionFeeRefundAmount - forwardInstruction.totalFee,
                relayProvider
            );
            container.instructions[0].maximumRefundTarget +=
                (amountUnderMaximum > convertedExtraAmount) ? convertedExtraAmount : amountUnderMaximum;
        }

        //emit forwarding instruction
        wormhole.publishMessage{value: wormholeMessageFee}(
            forwardInstruction.nonce,
            encodeDeliveryInstructionsContainer(container),
            relayProvider.getConsistencyLevel()
        );

        // if funded, pay out reward to provider. Otherwise, the delivery code will handle sending a refund.
        if (forwardIsFunded) {
            pay(relayProvider.getRewardAddress(), transactionFeeRefundAmount);
        }

        //clear forwarding request from cache
        clearForwardInstruction();
    }

    function _executeDelivery(
        DeliveryInstruction memory internalInstruction,
        bytes[] memory encodedVMs,
        bytes32 deliveryVaaHash,
        address payable relayerRefund,
        uint16 sourceChain,
        uint64 sourceSequence
    ) internal {
        //REVISE Decide whether we want to remove the DeliveryInstructionsContainer from encodedVMs.

        // lock the contract to prevent reentrancy
        if (isContractLocked()) {
            revert IDelivery.ReentrantCall();
        }
        setContractLock(true);
        setLockedTargetAddress(fromWormholeFormat(internalInstruction.targetAddress));
        // store gas budget pre target invocation to calculate unused gas budget
        uint256 preGas = gasleft();

        // call the receiveWormholeMessages endpoint on the target contract
        (bool callToTargetContractSucceeded,) = fromWormholeFormat(internalInstruction.targetAddress).call{
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
        uint256 transactionFeeRefundAmount = (internalInstruction.executionParameters.gasLimit - gasUsed)
            * internalInstruction.maximumRefundTarget / internalInstruction.executionParameters.gasLimit;

        // unlock the contract
        setContractLock(false);

        ForwardInstruction memory forwardingRequest = getForwardInstruction();
        DeliveryStatus status;
        bool forwardIsFunded = false;
        if (forwardingRequest.isValid) {
            forwardIsFunded = emitForward(transactionFeeRefundAmount, forwardingRequest);
            status = forwardIsFunded ? DeliveryStatus.FORWARD_REQUEST_SUCCESS : DeliveryStatus.FORWARD_REQUEST_FAILURE;
        } else {
            status = callToTargetContractSucceeded ? DeliveryStatus.SUCCESS : DeliveryStatus.RECEIVER_FAILURE;
        }

        uint256 receiverValueRefundAmount =
            (callToTargetContractSucceeded ? 0 : internalInstruction.receiverValueTarget);
        uint256 refundToRefundAddress = receiverValueRefundAmount + (forwardIsFunded ? 0 : transactionFeeRefundAmount);

        bool refundPaidToRefundAddress =
            pay(payable(fromWormholeFormat(internalInstruction.refundAddress)), refundToRefundAddress);

        emit Delivery({
            recipientContract: fromWormholeFormat(internalInstruction.targetAddress),
            sourceChain: sourceChain,
            sequence: sourceSequence,
            deliveryVaaHash: deliveryVaaHash,
            status: status
        });

        uint256 wormholeMessageFee = wormhole().messageFee();
        uint256 extraRelayerFunds = (
            msg.value - internalInstruction.receiverValueTarget - internalInstruction.maximumRefundTarget
                - wormholeMessageFee
        );
        uint256 relayerRefundAmount = extraRelayerFunds
            + (internalInstruction.maximumRefundTarget - transactionFeeRefundAmount)
            + (forwardingRequest.isValid ? 0 : wormholeMessageFee) + (refundPaidToRefundAddress ? 0 : refundToRefundAddress);
        // refund the rest to relayer
        pay(relayerRefund, relayerRefundAmount);
    }

    function verifyRelayerVM(IWormhole.VM memory vm) internal view returns (bool) {
        return registeredCoreRelayerContract(vm.emitterChainId) == vm.emitterAddress;
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

        RedeliveryByTxHashInstruction memory redeliveryInstruction = decodeRedeliveryInstruction(redeliveryVM.payload);

        //validate the original delivery VM
        IWormhole.VM memory originalDeliveryVM;
        (originalDeliveryVM, valid, reason) =
            wormhole.parseAndVerifyVM(targetParams.sourceEncodedVMs[redeliveryInstruction.deliveryIndex]);
        if (!valid) {
            revert IDelivery.InvalidVaa(redeliveryInstruction.deliveryIndex, reason);
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

        uint256 wormholeMessageFee = wormhole().messageFee();
        // relayer must have covered the necessary funds
        if (
            msg.value
                < redeliveryInstruction.newMaximumRefundTarget + redeliveryInstruction.newReceiverValueTarget
                    + wormholeMessageFee
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
            revert IDelivery.InvalidVaa(targetParams.deliveryIndex, reason);
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

        uint256 wormholeMessageFee = wormhole.messageFee();
        //make sure relayer passed in sufficient funds
        if (
            msg.value
                < deliveryInstruction.maximumRefundTarget + deliveryInstruction.receiverValueTarget + wormholeMessageFee
        ) {
            revert IDelivery.InsufficientRelayerFunds();
        }

        //make sure this delivery is intended for this chain
        if (chainId() != deliveryInstruction.targetChain) {
            revert IDelivery.TargetChainIsNotThisChain(deliveryInstruction.targetChain);
        }

        _executeDelivery(
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

    function pay(address payable receiver, uint256 amount) internal returns (bool success) {
        if (amount > 0) {
            (success,) = receiver.call{value: amount}("");
        } else {
            success = true;
        }
    }
}
