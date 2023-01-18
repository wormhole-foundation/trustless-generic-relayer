// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGetters.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayerMessages is CoreRelayerStructs, CoreRelayerGetters {
    using BytesLib for bytes;

    /// @notice Unexpected payloadId found in delivery instructions.
    /// @param payloadId The payload ID found in the delivery instructions container.
    error InvalidPayloadId(uint8 payloadId);
    /// @notice Delivery instructions payload has an invalid length.
    /// @param length The size in bytes of the delivery instructions.
    error InvalidDeliveryInstructionsPayload(uint256 length);
    /// @notice Delivery requests payload has an invalid length.
    /// @param length The size in bytes of the delivery requests.
    error InvalidDeliveryRequestsPayload(uint256 length);

    function decodeRedeliveryByTxHashInstruction(bytes memory encoded)
        internal
        pure
        returns (RedeliveryByTxHashInstruction memory instruction)
    {
        uint256 index = 0;

        instruction.payloadId = encoded.toUint8(index);
        index += 1;

        instruction.sourceChain = encoded.toUint16(index);
        index += 2;

        instruction.sourceTxHash = encoded.toBytes32(index);
        index += 32;

        instruction.sourceNonce = encoded.toUint32(index);
        index += 4;

        instruction.targetChain = encoded.toUint16(index);
        index += 2;

        instruction.newMaximumRefundTarget = encoded.toUint256(index);
        index += 32;

        instruction.newApplicationBudgetTarget = encoded.toUint256(index);
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

            instruction.applicationBudgetTarget = encoded.toUint256(index);
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

    function encodeDeliveryRequestsContainer(DeliveryRequestsContainer memory container)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            uint8(1), //version payload number
            address(container.relayProviderAddress),
            uint8(container.requests.length) //number of requests in the array
        );

        //Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {
            DeliveryRequest memory request = container.requests[i];

            encoded = abi.encodePacked(
                encoded,
                request.targetChain,
                request.targetAddress,
                request.refundAddress,
                request.computeBudget,
                request.applicationBudget,
                uint8(request.relayParameters.length),
                request.relayParameters
            );
        }
    }

    function decodeDeliveryRequestsContainer(bytes memory encoded)
        internal
        pure
        returns (DeliveryRequestsContainer memory)
    {
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

        DeliveryRequest[] memory requestArray = new DeliveryRequest[](arrayLen);

        for (uint8 i = 0; i < arrayLen; i++) {
            DeliveryRequest memory request;

            // target chain of the delivery request
            request.targetChain = encoded.toUint16(index);
            index += 2;

            // target contract address
            request.targetAddress = encoded.toBytes32(index);
            index += 32;

            // address to send the refund to
            request.refundAddress = encoded.toBytes32(index);
            index += 32;

            request.computeBudget = encoded.toUint256(index);
            index += 32;

            request.applicationBudget = encoded.toUint256(index);
            index += 32;

            uint8 relayParametersLength = encoded.toUint8(index);

            index += 1;

            request.relayParameters = encoded.slice(index, relayParametersLength);

            index += relayParametersLength;

            requestArray[i] = request;
        }

        if (index != encoded.length) {
            revert InvalidDeliveryRequestsPayload(encoded.length);
        }

        return DeliveryRequestsContainer({
            payloadId: payloadId,
            relayProviderAddress: relayProviderAddress,
            requests: requestArray
        });
    }
}
