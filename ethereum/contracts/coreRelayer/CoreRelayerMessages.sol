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
    error InvalidSendsPayload(uint256 length);

    function convertToEncodedRedeliveryByTxHashInstruction(
        IWormholeRelayer.ResendByTx memory request,
        uint256 receiverValueTarget,
        uint256 maximumRefund,
        uint16 targetChain, 
        uint256 newMaxTransactionFee,
        IRelayProvider provider
    ) internal view returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            uint8(2), //version payload number
            uint16(request.sourceChain),
            bytes32(request.sourceTxHash),
            uint32(request.sourceNonce),
            uint16(request.targetChain),
            uint8(request.deliveryIndex),
            uint8(request.multisendIndex),
            maximumRefund,
            receiverValueTarget,
            uint8(1), //version for ExecutionParameters
            calculateTargetGasRedeliveryAmount(targetChain, newMaxTransactionFee, provider),
            provider.getDeliveryAddress(request.targetChain)
        );
    }

    function convertToEncodedDeliveryInstructions(IWormholeRelayer.MultichainSend memory container, bool isFunded)
        internal
        view
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            uint8(1), //version payload number
            uint8(isFunded ? 1 : 0), // sufficiently funded
            uint8(container.requests.length) //number of requests in the array
        );

        // TODO: this probably results in a quadratic algorithm. Further optimization can be done here.
        // Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {
            encoded = appendDeliveryInstruction(
                encoded, container.requests[i], IRelayProvider(container.relayProviderAddress)
            );
        }
    }

    function appendDeliveryInstruction(bytes memory encoded, IWormholeRelayer.Send memory request, IRelayProvider provider)
        internal
        view
        returns (bytes memory newEncoded)
    {
        newEncoded = abi.encodePacked(
            encoded,
            request.targetChain,
            request.targetAddress,
            request.refundAddress,
            calculateTargetDeliveryMaximumRefund(request.targetChain, request.maxTransactionFee, provider),
            convertApplicationBudgetAmount(request.receiverValue, request.targetChain, provider),
            uint8(1), //version for ExecutionParameters
            calculateTargetGasDeliveryAmount(request.targetChain, request.maxTransactionFee, provider),
            provider.getDeliveryAddress(request.targetChain)
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
    function convertApplicationBudgetAmount(uint256 sourceAmount, uint16 targetChain, IRelayProvider provider)
        internal
        view
        returns (uint256 targetAmount)
    {
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);

        targetAmount = assetConversionHelper(
            chainId(), sourceAmount, targetChain, denominator, uint256(0) + denominator + buffer, false, provider
        );
    }

    function decodeRedeliveryByTxHashInstruction(bytes memory encoded)
        internal
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
        internal
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

    function encodeMultichainSend(IWormholeRelayer.MultichainSend memory container) internal pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            uint8(1), //version payload number
            address(container.relayProviderAddress),
            uint8(container.requests.length) //number of requests in the array
        );

        //Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {
            IWormholeRelayer.Send memory request = container.requests[i];

            encoded = abi.encodePacked(
                encoded,
                request.targetChain,
                request.targetAddress,
                request.refundAddress,
                request.maxTransactionFee,
                request.receiverValue,
                uint8(request.relayParameters.length),
                request.relayParameters
            );
        }
    }

    function decodeMultichainSend(bytes memory encoded) internal pure returns (IWormholeRelayer.MultichainSend memory) {
        uint256 index = 0;

        uint8 payloadId = encoded.toUint8(index);
        if (payloadId != 1) {
            revert InvalidPayloadId(payloadId);
        }
        index += 1;
        address relayProviderAddress = encoded.toAddress(index);
        index += 20;
        uint8 arrayLen = encoded.toUint8(index);
        index += 1;

        IWormholeRelayer.Send[] memory requestArray = new IWormholeRelayer.Send[](arrayLen);

        for (uint8 i = 0; i < arrayLen; i++) {
            IWormholeRelayer.Send memory request;

            // target chain of the delivery request
            request.targetChain = encoded.toUint16(index);
            index += 2;

            // target contract address
            request.targetAddress = encoded.toBytes32(index);
            index += 32;

            // address to send the refund to
            request.refundAddress = encoded.toBytes32(index);
            index += 32;

            request.maxTransactionFee = encoded.toUint256(index);
            index += 32;

            request.receiverValue = encoded.toUint256(index);
            index += 32;

            uint8 relayParametersLength = encoded.toUint8(index);

            index += 1;

            request.relayParameters = encoded.slice(index, relayParametersLength);

            index += relayParametersLength;

            requestArray[i] = request;
        }

        if (index != encoded.length) {
            revert InvalidSendsPayload(encoded.length);
        }

        return IWormholeRelayer.MultichainSend({relayProviderAddress: relayProviderAddress, requests: requestArray});
    }
}
