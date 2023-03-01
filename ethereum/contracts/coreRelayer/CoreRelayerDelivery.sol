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

    /**
     * @notice The relay provider calls 'redeliverSingle' to relay messages as described by one redelivery instruction
     * 
     * The instruction specifies, among other things, the target chain (must be this chain), refund address, new maximum refund (in this chain's currency),
     * new receiverValue (in this chain's currency), new upper bound on gas
     * 
     * The relay provider must pass in the original signed wormhole messages from the source chain of the same nonce
     * (the wormhole message with the original delivery instructions (the delivery VAA) must be one of these messages)
     * as well as the wormhole message with the new redelivery instruction (the redelivery VAA)
     * 
     * The messages will be relayed to the target address (with the specified gas limit and receiver value) iff the following checks are met:
     * - the redelivery VAA (targetParams.redeliveryVM) has a valid signature
     * - the redelivery VAA's emitter is one of these CoreRelayer contracts
     * - the original delivery VAA has a valid signature
     * - the original delivery VAA's emitter is one of these CoreRelayer contracts
     * - the new redelivery instruction's upper bound on gas >= the original instruction's upper bound on gas
     * - the new redelivery instruction's 'receiver value' amount >= the original instruction's 'receiver value' amount
     * - the redelivery instruction's target chain = this chain
     * - the original instruction's target chain = this chain
     * - for the redelivery instruction, the relay provider passed in at least [(one wormhole message fee) + instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget] of this chain's currency as msg.value 
     * - msg.sender is the permissioned address allowed to execute this redelivery instruction
     * - the permissioned address allowed to execute this redelivery instruction is the permissioned address allowed to execute the old instruction 
     * 
     * @param targetParams struct containing the signed wormhole messages and encoded redelivery instruction (and other information)
     */
    function redeliverSingle(IDelivery.TargetRedeliveryByTxHashParamsSingle memory targetParams) public payable {

        IWormhole wormhole = wormhole();

        (IWormhole.VM memory redeliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.redeliveryVM);

        // Check that the redelivery VAA (targetParams.redeliveryVM) has a valid signature
        if (!valid) {
            revert IDelivery.InvalidRedeliveryVM(reason);
        }

        // Check that the redelivery VAA's emitter is one of these CoreRelayer contracts
        if (!verifyRelayerVM(redeliveryVM)) {
            revert IDelivery.InvalidEmitterInRedeliveryVM();
        }

        RedeliveryByTxHashInstruction memory redeliveryInstruction = decodeRedeliveryInstruction(redeliveryVM.payload);

        // Obtain the original delivery VAA 
        IWormhole.VM memory originalDeliveryVM;
        (originalDeliveryVM, valid, reason) =
            wormhole.parseAndVerifyVM(targetParams.sourceEncodedVMs[redeliveryInstruction.deliveryIndex]);

        // Check that the original delivery VAA has a valid signature
        if (!valid) {
            revert IDelivery.InvalidVaa(redeliveryInstruction.deliveryIndex, reason);
        }

        // Check that the original delivery VAA's emitter is one of these CoreRelayer contracts
        if (!verifyRelayerVM(originalDeliveryVM)) {
            revert IDelivery.InvalidEmitterInOriginalDeliveryVM(redeliveryInstruction.deliveryIndex);
        }

        // Obtain the specific old instruction that was originally executed (and is meant to be re-executed with new parameters)
        // specifying the the target chain (must be this chain), target address, refund address, old maximum refund (in this chain's currency),
        // old receiverValue (in this chain's currency), old upper bound on gas, and the permissioned address allowed to execute this instruction
        DeliveryInstruction memory originalInstruction = decodeDeliveryInstructionsContainer(originalDeliveryVM.payload).instructions[redeliveryInstruction
                .multisendIndex];
        
        // Perform the following checks:
        // - the new redelivery instruction's upper bound on gas >= the original instruction's upper bound on gas
        // - the new redelivery instruction's 'receiver value' amount >= the original instruction's 'receiver value' amount
        // - the redelivery instruction's target chain = this chain
        // - the original instruction's target chain = this chain
        // - for the redelivery instruction, the relay provider passed in at least [(one wormhole message fee) + instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget] of this chain's currency as msg.value 
        // - msg.sender is the permissioned address allowed to execute this redelivery instruction
        // - the permissioned address allowed to execute this redelivery instruction is the permissioned address allowed to execute the old instruction 
        valid = checkRedeliveryInstructionTarget(
            redeliveryInstruction, originalInstruction
        );

        // Emit an 'Invalid Redelivery' event if one of the following five checks failed:
        // - msg.sender is the permissioned address allowed to execute this redelivery instruction
        // - the redelivery instruction's target chain = this chain
        // - the original instruction's target chain = this chain
        // - the new redelivery instruction's 'receiver value' amount >= the original instruction's 'receiver value' amount
        // - the new redelivery instruction's upper bound on gas >= the original instruction's upper bound on gas
        if (!valid) {
            emit Delivery({
                recipientContract: fromWormholeFormat(originalInstruction.targetAddress),
                sourceChain: originalDeliveryVM.emitterChainId,
                sequence: originalDeliveryVM.sequence,
                deliveryVaaHash: originalDeliveryVM.hash,
                status: DeliveryStatus.INVALID_REDELIVERY
            });
            pay(targetParams.relayerRefundAddress, msg.value);
            return;
        }

        // Replace maximumRefund, receiverValue, and the gasLimit on the original request 
        originalInstruction.maximumRefundTarget = redeliveryInstruction.newMaximumRefundTarget;
        originalInstruction.receiverValueTarget = redeliveryInstruction.newReceiverValueTarget;
        originalInstruction.executionParameters = redeliveryInstruction.executionParameters;

        _executeDelivery(
            originalInstruction,
            targetParams.sourceEncodedVMs,
            originalDeliveryVM.hash,
            targetParams.relayerRefundAddress,
            originalDeliveryVM.emitterChainId,
            originalDeliveryVM.sequence
        );
    }

    /**
     * Check that:
     * - the new redelivery instruction's upper bound on gas >= the original instruction's upper bound on gas
     * - the new redelivery instruction's 'receiver value' amount >= the original instruction's 'receiver value' amount
     * - the redelivery instruction's target chain = this chain
     * - the original instruction's target chain = this chain
     * - for the redelivery instruction, the relay provider passed in at least [(one wormhole message fee) + instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget] of this chain's currency as msg.value 
     * - msg.sender is the permissioned address allowed to execute this redelivery instruction
     * - the permissioned address allowed to execute this redelivery instruction is the permissioned address allowed to execute the old instruction 
     * @param redeliveryInstruction redelivery instruction
     * @param originalInstruction old instruction
     */
    function checkRedeliveryInstructionTarget(
        RedeliveryByTxHashInstruction memory redeliveryInstruction,
        DeliveryInstruction memory originalInstruction
    ) internal view returns (bool isValid) {

        address providerAddress = fromWormholeFormat(redeliveryInstruction.executionParameters.providerDeliveryAddress);

        // Check that the permissioned address allowed to execute this redelivery instruction is the permissioned address allowed to execute the old instruction 
        if ((providerAddress != fromWormholeFormat(originalInstruction.executionParameters.providerDeliveryAddress))) {
            revert IDelivery.MismatchingRelayProvidersInRedelivery();
        }

        uint256 wormholeMessageFee = wormhole().messageFee();

        // Check that for the redelivery instruction, the relay provider passed in at least [(one wormhole message fee) + instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget] of this chain's currency as msg.value 
        if (
            msg.value
                < redeliveryInstruction.newMaximumRefundTarget + redeliveryInstruction.newReceiverValueTarget
                    + wormholeMessageFee
        ) {
            revert IDelivery.InsufficientRelayerFunds();
        }

        uint16 whChainId = chainId();
        
        // Check that msg.sender is the permissioned address allowed to execute this redelivery instruction
        isValid = msg.sender == providerAddress
        
        // Check that the redelivery instruction's target chain = this chain
        && whChainId == redeliveryInstruction.targetChain
        
        // Check that the original instruction's target chain = this chain
        && whChainId == originalInstruction.targetChain
        
        // Check that the new redelivery instruction's 'receiver value' amount >= the original instruction's 'receiver value' amount
        && originalInstruction.receiverValueTarget <= redeliveryInstruction.newReceiverValueTarget
        
        // Check that the new redelivery instruction's upper bound on gas >= the original instruction's upper bound on gas
        && originalInstruction.executionParameters.gasLimit <= redeliveryInstruction.executionParameters.gasLimit;
    }

    /**
     * @notice The relay provider calls 'deliverSingle' to relay messages as described by one delivery instruction
     * 
     * The instruction specifies the target chain (must be this chain), target address, refund address, maximum refund (in this chain's currency),
     * receiver value (in this chain's currency), upper bound on gas, and the permissioned address allowed to execute this instruction
     * 
     * The relay provider must pass in the signed wormhole messages (VAAs) from the source chain of the same nonce
     * (the wormhole message with the delivery instructions (the delivery VAA) must be one of these messages)
     * as well as identify which of these messages is the delivery VAA and which of the many instructions in the multichainSend container is meant to be executed 
     * 
     * The messages will be relayed to the target address (with the specified gas limit and receiver value) iff the following checks are met:
     * - the delivery VAA has a valid signature
     * - the delivery VAA's emitter is one of these CoreRelayer contracts
     * - the delivery instruction container in the delivery VAA was fully funded
     * - the instruction's target chain is this chain
     * - the relay provider passed in at least [(one wormhole message fee) + instruction.maximumRefundTarget + instruction.receiverValueTarget] of this chain's currency as msg.value 
     * - msg.sender is the permissioned address allowed to execute this instruction
     * 
     * @param targetParams struct containing the signed wormhole messages and encoded delivery instruction container (and other information)
     */
    function deliverSingle(IDelivery.TargetDeliveryParametersSingle memory targetParams) public payable {

        IWormhole wormhole = wormhole();

        // Obtain the delivery VAA 
        (IWormhole.VM memory deliveryVM, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(targetParams.encodedVMs[targetParams.deliveryIndex]);

        // Check that the delivery VAA has a valid signature
        if (!valid) {
            revert IDelivery.InvalidVaa(targetParams.deliveryIndex, reason);
        }

        // Check that the delivery VAA's emitter is one of these CoreRelayer contracts
        if (!verifyRelayerVM(deliveryVM)) {
            revert IDelivery.InvalidEmitter();
        }

        DeliveryInstructionsContainer memory container = decodeDeliveryInstructionsContainer(deliveryVM.payload);

        // Check that the delivery instruction container in the delivery VAA was fully funded
        if (!container.sufficientlyFunded) {
            revert IDelivery.SendNotSufficientlyFunded();
        }

        // Obtain the specific instruction that is intended to be executed in this function
        // specifying the the target chain (must be this chain), target address, refund address, maximum refund (in this chain's currency),
        // receiverValue (in this chain's currency), upper bound on gas, and the permissioned address allowed to execute this instruction
        DeliveryInstruction memory deliveryInstruction = container.instructions[targetParams.multisendIndex];

        // Check that msg.sender is the permissioned address allowed to execute this instruction
        if (fromWormholeFormat(deliveryInstruction.executionParameters.providerDeliveryAddress) != msg.sender) {
            revert IDelivery.UnexpectedRelayer();
        }

        uint256 wormholeMessageFee = wormhole.messageFee();

        // Check that the relay provider passed in at least [(one wormhole message fee) + instruction.maximumRefund + instruction.receiverValue] of this chain's currency as msg.value
        if (
            msg.value
                < deliveryInstruction.maximumRefundTarget + deliveryInstruction.receiverValueTarget + wormholeMessageFee
        ) {
            revert IDelivery.InsufficientRelayerFunds();
        }

        // Check that the instruction's target chain is this chain
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

    /**
     * @notice Helper function that converts an EVM address to wormhole format
     * @param addr (EVM 20-byte address)
     * @return whFormat (32-byte address in Wormhole format)
     */
    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice Helper function that converts an Wormhole format (32-byte) address to the EVM 'address' 20-byte format
     * @param whFormatAddress (32-byte address in Wormhole format)
     * @return addr (EVM 20-byte address)
     */
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
