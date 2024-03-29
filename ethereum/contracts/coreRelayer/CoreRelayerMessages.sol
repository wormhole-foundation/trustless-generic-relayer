// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGetters.sol";
import "./CoreRelayerStructs.sol";
import "../interfaces/IWormholeRelayer.sol";

contract CoreRelayerMessages is CoreRelayerStructs, CoreRelayerGetters {
    using BytesLib for bytes;

    error InvalidPayloadId(uint8 payloadId);
    error InvalidDeliveryInstructionsPayload(uint256 length);

    /**
     * @notice This function calculates the total fee to execute all of the Send requests in this MultichainSend container
     * @param sendContainer A MultichainSend struct describing all of the Send requests
     * @return totalFee
     */
    function getTotalFeeMultichainSend(IWormholeRelayer.MultichainSend memory sendContainer, uint256 wormholeMessageFee)
        internal
        view
        returns (uint256 totalFee)
    {
        totalFee = wormholeMessageFee;
        uint256 length = sendContainer.requests.length;
        for (uint256 i = 0; i < length; i++) {
            IWormholeRelayer.Send memory request = sendContainer.requests[i];
            totalFee += request.maxTransactionFee + request.receiverValue;
        }
    }

    /**
     * @notice This function converts a MultichainSend struct into a DeliveryInstructionsContainer struct that
     * describes to the relayer exactly how to relay for each of the Send requests.
     * Specifically, each Send is converted to a DeliveryInstruction, which is a struct that contains six fields:
     * 1) targetChain, 2) targetAddress, 3) refundAddress (all which are part of the Send struct),
     * 4) maximumRefundTarget: The maximum amount that can be refunded to 'refundAddress' (e.g. if the call to 'receiveWormholeMessages' takes 0 gas),
     * 5) receiverValueTarget: The amount that will be passed into 'receiveWormholeMessages' as value, in target chain currency
     * 6) executionParameters: a struct with information about execution, specifically:
     *    executionParameters.gasLimit: The maximum amount of gas 'receiveWormholeMessages' is allowed to use
     *    executionParameters.providerDeliveryAddress: The address of the relayer that will execute this Send request
     * The latter 3 fields are calculated using the relayProvider's getters
     * @param sendContainer A MultichainSend struct describing all of the Send requests
     * @return instructionsContainer A DeliveryInstructionsContainer struct
     */
    function convertMultichainSendToDeliveryInstructionsContainer(IWormholeRelayer.MultichainSend memory sendContainer)
        internal
        view
        returns (DeliveryInstructionsContainer memory instructionsContainer)
    {
        instructionsContainer.payloadId = 1;
        IRelayProvider relayProvider = IRelayProvider(sendContainer.relayProviderAddress);
        uint256 length = sendContainer.requests.length;
        instructionsContainer.instructions = new DeliveryInstruction[](length);
        for (uint256 i = 0; i < length; i++) {
            instructionsContainer.instructions[i] =
                convertSendToDeliveryInstruction(sendContainer.requests[i], relayProvider);
        }
    }

    /**
     * @notice This function converts a Send struct into a DeliveryInstruction struct that
     * describes to the relayer exactly how to relay for the Send.
     * Specifically, the DeliveryInstruction struct that contains six fields:
     * 1) targetChain, 2) targetAddress, 3) refundAddress (all which are part of the Send struct),
     * 4) maximumRefundTarget: The maximum amount that can be refunded to 'refundAddress' (e.g. if the call to 'receiveWormholeMessages' takes 0 gas),
     * 5) receiverValueTarget: The amount that will be passed into 'receiveWormholeMessages' as value, in target chain currency
     * 6) executionParameters: a struct with information about execution, specifically:
     *    executionParameters.gasLimit: The maximum amount of gas 'receiveWormholeMessages' is allowed to use
     *    executionParameters.providerDeliveryAddress: The address of the relayer that will execute this Send request
     * The latter 3 fields are calculated using the relayProvider's getters
     * @param send A Send struct
     * @param relayProvider The relay provider chosen for this Send
     * @return instruction A DeliveryInstruction
     */
    function convertSendToDeliveryInstruction(IWormholeRelayer.Send memory send, IRelayProvider relayProvider)
        internal
        view
        returns (DeliveryInstruction memory instruction)
    {
        instruction.targetChain = send.targetChain;
        instruction.targetAddress = send.targetAddress;
        instruction.refundAddress = send.refundAddress;
        bytes32 deliveryAddress = relayProvider.getDeliveryAddress(send.targetChain);
        if (deliveryAddress == bytes32(0x0)) {
            revert IWormholeRelayer.RelayProviderDoesNotSupportTargetChain();
        }
        instruction.maximumRefundTarget =
            calculateTargetDeliveryMaximumRefund(send.targetChain, send.maxTransactionFee, relayProvider);
        instruction.receiverValueTarget =
            convertReceiverValueAmount(send.receiverValue, send.targetChain, relayProvider);
        instruction.executionParameters = ExecutionParameters({
            version: 1,
            gasLimit: calculateTargetGasDeliveryAmount(send.targetChain, send.maxTransactionFee, relayProvider),
            providerDeliveryAddress: deliveryAddress
        });
    }

    /**
     * @notice Check if for each instruction in the DeliveryInstructionContainer,
     * - the total amount of target chain currency needed for execution of the instruction is within the maximum budget,
     *   i.e. (maximumRefundTarget + receiverValueTarget) <= (the relayProvider's maximum budget for the target chain)
     * - the gasLimit is greater than 0
     * @param container A DeliveryInstructionsContainer
     * @param relayProvider The relayProvider whos maximum budget we are checking against
     */
    function checkInstructions(DeliveryInstructionsContainer memory container, IRelayProvider relayProvider)
        internal
        view
    {
        uint256 length = container.instructions.length;
        for (uint8 i = 0; i < length; i++) {
            DeliveryInstruction memory instruction = container.instructions[i];
            if (instruction.executionParameters.gasLimit == 0) {
                revert IWormholeRelayer.MaxTransactionFeeNotEnough(i);
            }
            if (
                instruction.maximumRefundTarget + instruction.receiverValueTarget
                    > relayProvider.quoteMaximumBudget(instruction.targetChain)
            ) {
                revert IWormholeRelayer.FundsTooMuch(i);
            }
        }
    }

    /**
     * @notice Check if for a redelivery instruction,
     * - the total amount of target chain currency needed for execution of this instruction is within the maximum budget,
     *   i.e. (maximumRefundTarget + receiverValueTarget) <= (the relayProvider's maximum budget for the target chain)
     * - the gasLimit is greater than 0
     * @param instruction A RedeliveryByTxHashInstruction
     * @param relayProvider The relayProvider whos maximum budget we are checking against
     */
    function checkRedeliveryInstruction(RedeliveryByTxHashInstruction memory instruction, IRelayProvider relayProvider)
        internal
        view
    {
        if (instruction.executionParameters.gasLimit == 0) {
            revert IWormholeRelayer.MaxTransactionFeeNotEnough(0);
        }
        if (
            instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget
                > relayProvider.quoteMaximumBudget(instruction.targetChain)
        ) {
            revert IWormholeRelayer.FundsTooMuch(0);
        }
    }

    /**
     * @notice This function converts a ResendByTx struct into a RedeliveryByTxHashInstruction struct that
     * describes to the relayer exactly how to relay for the ResendByTx.
     * Specifically, the RedeliveryByTxHashInstruction struct that contains nine fields:
     * 1) sourceChain, 2) sourceTxHash, 3) sourceNonce, 4) targetChain, 5) deliveryIndex, 6) multisendIndex (all which are part of the ResendByTxHash struct),
     * 7) newMaximumRefundTarget: The new maximum amount that can be refunded to 'refundAddress' (e.g. if the call to 'receiveWormholeMessages' takes 0 gas),
     * 8) newReceiverValueTarget: The new amount that will be passed into 'receiveWormholeMessages' as value, in target chain currency
     * 9) executionParameters: a struct with information about execution, specifically:
     *    executionParameters.gasLimit: The maximum amount of gas 'receiveWormholeMessages' is allowed to use
     *    executionParameters.providerDeliveryAddress: The address of the relayer that will execute this ResendByTx request
     * The latter 3 fields are calculated using the relayProvider's getters
     * @param resend A ResendByTx struct
     * @param relayProvider The relay provider chosen for this ResendByTx
     * @return instruction A DeliveryInstruction
     */
    function convertResendToRedeliveryInstruction(
        IWormholeRelayer.ResendByTx memory resend,
        IRelayProvider relayProvider
    ) internal view returns (RedeliveryByTxHashInstruction memory instruction) {
        instruction.payloadId = 2;
        instruction.sourceChain = resend.sourceChain;
        instruction.sourceTxHash = resend.sourceTxHash;
        instruction.sourceNonce = resend.sourceNonce;
        instruction.targetChain = resend.targetChain;
        instruction.deliveryIndex = resend.deliveryIndex;
        instruction.multisendIndex = resend.multisendIndex;
        instruction.newMaximumRefundTarget =
            calculateTargetRedeliveryMaximumRefund(resend.targetChain, resend.newMaxTransactionFee, relayProvider);
        instruction.newReceiverValueTarget =
            convertReceiverValueAmount(resend.newReceiverValue, resend.targetChain, relayProvider);
        instruction.executionParameters = ExecutionParameters({
            version: 1,
            gasLimit: calculateTargetGasRedeliveryAmount(resend.targetChain, resend.newMaxTransactionFee, relayProvider),
            providerDeliveryAddress: relayProvider.getDeliveryAddress(resend.targetChain)
        });
    }

    // encode a 'RedeliveryByTxHashInstruction' into bytes
    function encodeRedeliveryInstruction(RedeliveryByTxHashInstruction memory instruction)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            instruction.payloadId,
            instruction.sourceChain,
            instruction.sourceTxHash,
            instruction.sourceNonce,
            instruction.targetChain,
            instruction.deliveryIndex,
            instruction.multisendIndex,
            instruction.newMaximumRefundTarget,
            instruction.newReceiverValueTarget,
            instruction.executionParameters.version,
            instruction.executionParameters.gasLimit,
            instruction.executionParameters.providerDeliveryAddress
        );
    }

    // encode a 'DeliveryInstructionsContainer' into bytes
    function encodeDeliveryInstructionsContainer(DeliveryInstructionsContainer memory container)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            container.payloadId, uint8(container.sufficientlyFunded ? 1 : 0), uint8(container.instructions.length)
        );

        for (uint256 i = 0; i < container.instructions.length; i++) {
            encoded = abi.encodePacked(encoded, encodeDeliveryInstruction(container.instructions[i]));
        }
    }

    // encode a 'DeliveryInstruction' into bytes
    function encodeDeliveryInstruction(DeliveryInstruction memory instruction)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            instruction.targetChain,
            instruction.targetAddress,
            instruction.refundAddress,
            instruction.maximumRefundTarget,
            instruction.receiverValueTarget,
            instruction.executionParameters.version,
            instruction.executionParameters.gasLimit,
            instruction.executionParameters.providerDeliveryAddress
        );
    }

    /**
     * Given a targetChain, maxTransactionFee, and a relay provider, this function calculates what the gas limit of the delivery transaction
     * should be
     *
     * It does this by calculating (maxTransactionFee - deliveryOverhead)/gasPrice
     * where 'deliveryOverhead' is the relayProvider's base fee for delivering to targetChain (in units of source chain currency)
     * and 'gasPrice' is the relayProvider's fee per unit of target chain gas (in units of source chain currency)
     *
     * @param targetChain target chain
     * @param maxTransactionFee uint256
     * @param provider IRelayProvider
     * @return gasAmount
     */
    function calculateTargetGasDeliveryAmount(uint16 targetChain, uint256 maxTransactionFee, IRelayProvider provider)
        internal
        view
        returns (uint32 gasAmount)
    {
        gasAmount = calculateTargetGasDeliveryAmountHelper(
            targetChain, maxTransactionFee, provider.quoteDeliveryOverhead(targetChain), provider
        );
    }

    /**
     * Given a targetChain, maxTransactionFee, and a relay provider, this function calculates what the maximum refund of the delivery transaction
     * should be, in terms of target chain currency
     *
     * The maximum refund is the amount that would be refunded to refundAddress if the call to 'receiveWormholeMessages' takes 0 gas
     *
     * It does this by calculating (maxTransactionFee - deliveryOverhead) and converting (using the relay provider's prices) to target chain currency
     * (where 'deliveryOverhead' is the relayProvider's base fee for delivering to targetChain [in units of source chain currency])
     *
     * @param targetChain target chain
     * @param maxTransactionFee uint256
     * @param provider IRelayProvider
     * @return maximumRefund uint256
     */
    function calculateTargetDeliveryMaximumRefund(
        uint16 targetChain,
        uint256 maxTransactionFee,
        IRelayProvider provider
    ) internal view returns (uint256 maximumRefund) {
        maximumRefund = calculateTargetDeliveryMaximumRefundHelper(
            targetChain, maxTransactionFee, provider.quoteDeliveryOverhead(targetChain), provider
        );
    }

    /**
     * Given a targetChain, maxTransactionFee, and a relay provider, this function calculates what the gas limit of the redelivery transaction
     * should be
     *
     * It does this by calculating (maxTransactionFee - redeliveryOverhead)/gasPrice
     * where 'redeliveryOverhead' is the relayProvider's base fee for redelivering to targetChain (in units of source chain currency)
     * and 'gasPrice' is the relayProvider's fee per unit of target chain gas (in units of source chain currency)
     *
     * @param targetChain target chain
     * @param maxTransactionFee uint256
     * @param provider IRelayProvider
     * @return gasAmount
     */
    function calculateTargetGasRedeliveryAmount(uint16 targetChain, uint256 maxTransactionFee, IRelayProvider provider)
        internal
        view
        returns (uint32 gasAmount)
    {
        gasAmount = calculateTargetGasDeliveryAmountHelper(
            targetChain, maxTransactionFee, provider.quoteRedeliveryOverhead(targetChain), provider
        );
    }

    /**
     * Given a targetChain, maxTransactionFee, and a relay provider, this function calculates what the maximum refund of the redelivery transaction
     * should be, in terms of target chain currency
     *
     * The maximum refund is the amount that would be refunded to refundAddress if the call to 'receiveWormholeMessages' takes 0 gas
     *
     * It does this by calculating (maxTransactionFee - redeliveryOverhead) and converting (using the relay provider's prices) to target chain currency
     * (where 'redeliveryOverhead' is the relayProvider's base fee for redelivering to targetChain [in units of source chain currency])
     *
     * @param targetChain target chain
     * @param maxTransactionFee uint256
     * @param provider IRelayProvider
     * @return maximumRefund uint256
     */
    function calculateTargetRedeliveryMaximumRefund(
        uint16 targetChain,
        uint256 maxTransactionFee,
        IRelayProvider provider
    ) internal view returns (uint256 maximumRefund) {
        maximumRefund = calculateTargetDeliveryMaximumRefundHelper(
            targetChain, maxTransactionFee, provider.quoteRedeliveryOverhead(targetChain), provider
        );
    }

    /**
     * Performs the calculation (maxTransactionFee - overhead)/(price of 1 unit of target chain gas, in source chain currency)
     * and bounds the result between 0 and 2^32-1, inclusive
     *
     * @param targetChain uint16
     * @param maxTransactionFee uint256
     * @param overhead uint256
     * @param provider IRelayProvider
     */
    function calculateTargetGasDeliveryAmountHelper(
        uint16 targetChain,
        uint256 maxTransactionFee,
        uint256 overhead,
        IRelayProvider provider
    ) internal view returns (uint32 gasAmount) {
        if (maxTransactionFee <= overhead) {
            gasAmount = 0;
        } else {
            uint256 gas = (maxTransactionFee - overhead) / provider.quoteGasPrice(targetChain);
            if (gas > type(uint32).max) {
                gasAmount = type(uint32).max;
            } else {
                gasAmount = uint32(gas);
            }
        }
    }

    /**
     * Converts (maxTransactionFee - overhead) from source to target chain currency, using the provider's prices
     *
     * @param targetChain uint16
     * @param maxTransactionFee uint256
     * @param overhead uint256
     * @param provider IRelayProvider
     */
    function calculateTargetDeliveryMaximumRefundHelper(
        uint16 targetChain,
        uint256 maxTransactionFee,
        uint256 overhead,
        IRelayProvider provider
    ) internal view returns (uint256 maximumRefund) {
        if (maxTransactionFee >= overhead) {
            uint256 remainder = maxTransactionFee - overhead;
            maximumRefund = assetConversionHelper(chainId(), remainder, targetChain, 1, 1, false, provider);
        } else {
            maximumRefund = 0;
        }
    }

    /**
     * Converts 'sourceAmount' of source chain currency to units of target chain currency
     * using the prices of 'provider'
     * and also multiplying by a specified fraction 'multiplier/multiplierDenominator',
     * rounding up or down specified by 'roundUp', and without performing intermediate rounding,
     * i.e. the result should be as if float arithmetic was done and the rounding performed at the end
     *
     * @param sourceChain source chain
     * @param sourceAmount amount of source chain currency to be converted
     * @param targetChain target chain
     * @param multiplier numerator of a fraction to multiply by
     * @param multiplierDenominator denominator of a fraction to multiply by
     * @param roundUp whether or not to round up
     * @param provider relay provider
     * @return targetAmount amount of target chain currency
     */
    function assetConversionHelper(
        uint16 sourceChain,
        uint256 sourceAmount,
        uint16 targetChain,
        uint256 multiplier,
        uint256 multiplierDenominator,
        bool roundUp,
        IRelayProvider provider
    ) internal view returns (uint256 targetAmount) {
        uint256 srcNativeCurrencyPrice = provider.quoteAssetPrice(sourceChain);
        if (srcNativeCurrencyPrice == 0) {
            revert IWormholeRelayer.RelayProviderDoesNotSupportTargetChain();
        }

        uint256 dstNativeCurrencyPrice = provider.quoteAssetPrice(targetChain);
        if (dstNativeCurrencyPrice == 0) {
            revert IWormholeRelayer.RelayProviderDoesNotSupportTargetChain();
        }
        uint256 numerator = sourceAmount * srcNativeCurrencyPrice * multiplier;
        uint256 denominator = dstNativeCurrencyPrice * multiplierDenominator;
        if (roundUp) {
            targetAmount = (numerator + denominator - 1) / denominator;
        } else {
            targetAmount = numerator / denominator;
        }
    }

    /**
     * If the user specifies (for 'receiverValue) 'sourceAmount' of source chain currency, with relay provider 'provider',
     * then this function calculates how much the relayer will pass into receiveWormholeMessages on the target chain (in target chain currency)
     *
     * The calculation simply converts this amount to target chain currency, but also applies a multiplier of 'denominator/(denominator + buffer)'
     * where these values are also specified by the relay provider 'provider'
     *
     * @param sourceAmount amount of source chain currency
     * @param targetChain target chain
     * @param provider relay provider
     * @return targetAmount amount of target chain currency
     */
    function convertReceiverValueAmount(uint256 sourceAmount, uint16 targetChain, IRelayProvider provider)
        internal
        view
        returns (uint256 targetAmount)
    {
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);

        targetAmount = assetConversionHelper(
            chainId(), sourceAmount, targetChain, denominator, uint256(0) + denominator + buffer, false, provider
        );
    }

    // decode a 'RedeliveryByTxHashInstruction' from bytes
    function decodeRedeliveryInstruction(bytes memory encoded)
        public
        pure
        returns (RedeliveryByTxHashInstruction memory instruction)
    {
        uint256 index = 0;

        instruction.payloadId = encoded.toUint8(index);
        if (instruction.payloadId != 2) {
            revert InvalidPayloadId(instruction.payloadId);
        }
        index += 1;

        instruction.sourceChain = encoded.toUint16(index);
        index += 2;

        instruction.sourceTxHash = encoded.toBytes32(index);
        index += 32;

        instruction.sourceNonce = encoded.toUint32(index);
        index += 4;

        instruction.targetChain = encoded.toUint16(index);
        index += 2;

        instruction.deliveryIndex = encoded.toUint8(index);
        index += 1;

        instruction.multisendIndex = encoded.toUint8(index);
        index += 1;

        instruction.newMaximumRefundTarget = encoded.toUint256(index);
        index += 32;

        instruction.newReceiverValueTarget = encoded.toUint256(index);
        index += 32;

        instruction.executionParameters.version = encoded.toUint8(index);
        index += 1;

        instruction.executionParameters.gasLimit = encoded.toUint32(index);
        index += 4;

        instruction.executionParameters.providerDeliveryAddress = encoded.toBytes32(index);
        index += 32;
    }

    // decode a 'DeliveryInstructionsContainer' from bytes
    function decodeDeliveryInstructionsContainer(bytes memory encoded)
        public
        pure
        returns (DeliveryInstructionsContainer memory)
    {
        uint256 index = 0;

        uint8 payloadId = encoded.toUint8(index);
        if (payloadId != 1) {
            revert InvalidPayloadId(payloadId);
        }
        index += 1;
        bool sufficientlyFunded = encoded.toUint8(index) == 1;
        index += 1;
        uint8 arrayLen = encoded.toUint8(index);
        index += 1;

        DeliveryInstruction[] memory instructionArray = new DeliveryInstruction[](arrayLen);

        for (uint8 i = 0; i < arrayLen; i++) {
            DeliveryInstruction memory instruction;

            // target chain of the delivery instruction
            instruction.targetChain = encoded.toUint16(index);
            index += 2;

            // target contract address
            instruction.targetAddress = encoded.toBytes32(index);
            index += 32;

            // address to send the refund to
            instruction.refundAddress = encoded.toBytes32(index);
            index += 32;

            instruction.maximumRefundTarget = encoded.toUint256(index);
            index += 32;

            instruction.receiverValueTarget = encoded.toUint256(index);
            index += 32;

            instruction.executionParameters.version = encoded.toUint8(index);
            index += 1;

            instruction.executionParameters.gasLimit = encoded.toUint32(index);
            index += 4;

            instruction.executionParameters.providerDeliveryAddress = encoded.toBytes32(index);
            index += 32;

            instructionArray[i] = instruction;
        }

        if (index != encoded.length) {
            revert InvalidDeliveryInstructionsPayload(encoded.length);
        }

        return DeliveryInstructionsContainer({
            payloadId: payloadId,
            sufficientlyFunded: sufficientlyFunded,
            instructions: instructionArray
        });
    }
}
