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

    function getTotalFeeMultichainSend(IWormholeRelayer.MultichainSend memory sendContainer)
        internal
        view
        returns (uint256 totalFee)
    {
        totalFee = wormhole().messageFee();
        for (uint256 i = 0; i < sendContainer.requests.length; i++) {
            totalFee += sendContainer.requests[i].maxTransactionFee + sendContainer.requests[i].receiverValue;
        }
    }

    function convertMultichainSendToDeliveryInstructionsContainer(IWormholeRelayer.MultichainSend memory sendContainer)
        internal
        view
        returns (DeliveryInstructionsContainer memory instructionsContainer)
    {
        instructionsContainer.payloadId = 1;
        IRelayProvider relayProvider = IRelayProvider(sendContainer.relayProviderAddress);
        instructionsContainer.instructions = new DeliveryInstruction[](sendContainer.requests.length);
        for (uint256 i = 0; i < sendContainer.requests.length; i++) {
            instructionsContainer.instructions[i] =
                convertSendToDeliveryInstruction(sendContainer.requests[i], relayProvider);
        }
    }

    function convertSendToDeliveryInstruction(IWormholeRelayer.Send memory send, IRelayProvider relayProvider)
        internal
        view
        returns (DeliveryInstruction memory instruction)
    {
        instruction.targetChain = send.targetChain;
        instruction.targetAddress = send.targetAddress;
        instruction.refundAddress = send.refundAddress;
        instruction.maximumRefundTarget =
            calculateTargetDeliveryMaximumRefund(send.targetChain, send.maxTransactionFee, relayProvider);
        instruction.receiverValueTarget =
            convertReceiverValueAmount(send.receiverValue, send.targetChain, relayProvider);
        instruction.executionParameters = ExecutionParameters({
            version: 1,
            gasLimit: calculateTargetGasDeliveryAmount(send.targetChain, send.maxTransactionFee, relayProvider),
            providerDeliveryAddress: relayProvider.getDeliveryAddress(send.targetChain)
        });
    }

    function checkInstructions(DeliveryInstructionsContainer memory container, IRelayProvider relayProvider)
        internal
        view
    {
        for (uint8 i = 0; i < container.instructions.length; i++) {
            if (container.instructions[i].executionParameters.gasLimit == 0) {
                revert IWormholeRelayer.MaxTransactionFeeNotEnough(i);
            }
            if (
                container.instructions[i].maximumRefundTarget + container.instructions[i].receiverValueTarget
                    + wormhole().messageFee() > relayProvider.quoteMaximumBudget(container.instructions[i].targetChain)
            ) {
                revert IWormholeRelayer.FundsTooMuch(i);
            }
        }
    }

    function checkRedeliveryInstruction(RedeliveryByTxHashInstruction memory instruction, IRelayProvider relayProvider)
        internal
        view
    {
        if (instruction.executionParameters.gasLimit == 0) {
            revert IWormholeRelayer.MaxTransactionFeeNotEnough(0);
        }
        if (
            instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget + wormhole().messageFee()
                > relayProvider.quoteMaximumBudget(instruction.targetChain)
        ) {
            revert IWormholeRelayer.FundsTooMuch(0);
        }
    }

    function convertResendToRedeliveryInstruction(IWormholeRelayer.ResendByTx memory send, IRelayProvider relayProvider)
        internal
        view
        returns (RedeliveryByTxHashInstruction memory instruction)
    {
        instruction.payloadId = 2;
        instruction.sourceChain = send.sourceChain;
        instruction.sourceTxHash = send.sourceTxHash;
        instruction.sourceNonce = send.sourceNonce;
        instruction.targetChain = send.targetChain;
        instruction.deliveryIndex = send.deliveryIndex;
        instruction.multisendIndex = send.multisendIndex;
        instruction.newMaximumRefundTarget =
            calculateTargetRedeliveryMaximumRefund(send.targetChain, send.newMaxTransactionFee, relayProvider);
        instruction.newReceiverValueTarget =
            convertReceiverValueAmount(send.newReceiverValue, send.targetChain, relayProvider);
        instruction.executionParameters = ExecutionParameters({
            version: 1,
            gasLimit: calculateTargetGasRedeliveryAmount(send.targetChain, send.newMaxTransactionFee, relayProvider),
            providerDeliveryAddress: relayProvider.getDeliveryAddress(send.targetChain)
        });
    }

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
     * should be.
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
     * should be.
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

    function calculateTargetRedeliveryMaximumRefund(
        uint16 targetChain,
        uint256 maxTransactionFee,
        IRelayProvider provider
    ) internal view returns (uint256 maximumRefund) {
        maximumRefund = calculateTargetDeliveryMaximumRefundHelper(
            targetChain, maxTransactionFee, provider.quoteRedeliveryOverhead(targetChain), provider
        );
    }

    function calculateTargetGasDeliveryAmountHelper(
        uint16 targetChain,
        uint256 maxTransactionFee,
        uint256 deliveryOverhead,
        IRelayProvider provider
    ) internal view returns (uint32 gasAmount) {
        if (maxTransactionFee <= deliveryOverhead) {
            gasAmount = 0;
        } else {
            uint256 gas = (maxTransactionFee - deliveryOverhead) / provider.quoteGasPrice(targetChain);
            if (gas > type(uint32).max) {
                gasAmount = type(uint32).max;
            } else {
                gasAmount = uint32(gas);
            }
        }
    }

    function calculateTargetDeliveryMaximumRefundHelper(
        uint16 targetChain,
        uint256 maxTransactionFee,
        uint256 deliveryOverhead,
        IRelayProvider provider
    ) internal view returns (uint256 maximumRefund) {
        if (maxTransactionFee >= deliveryOverhead) {
            uint256 remainder = maxTransactionFee - deliveryOverhead;
            maximumRefund = assetConversionHelper(chainId(), remainder, targetChain, 1, 1, false, provider);
        } else {
            maximumRefund = 0;
        }
    }

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

    //This should invert quoteApplicationBudgetAmount, I.E when a user pays the sourceAmount, they receive at least the value of targetAmount they requested from
    //quoteReceiverValue.
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
