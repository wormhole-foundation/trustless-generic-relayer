// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGetters.sol";
import "./CoreRelayerStructs.sol";


import "forge-std/Test.sol";

import "forge-std/console.sol";

contract CoreRelayerMessages is CoreRelayerStructs, CoreRelayerGetters {
    using BytesLib for bytes;

    // function encodeDeliveryStatus(DeliveryStatus memory ds) internal pure returns (bytes memory) {
    //     require(ds.payloadID == 2, "invalid DeliveryStatus");
    //     return abi.encodePacked(
    //         uint8(2), // payloadID = 2
    //         ds.batchHash,
    //         ds.emitterAddress,
    //         ds.sequence,
    //         ds.deliveryCount,
    //         ds.deliverySuccess ? uint8(1) : uint8(0)
    //     );
    // }

    function decodeRedeliveryByTxHashInstruction(bytes memory encoded) internal pure returns (RedeliveryByTxHashInstruction memory instruction) {

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

    // TODO: WIP
    function encodeRewardPayout(RewardPayout memory rp) internal pure returns (bytes memory) {
        require(rp.payloadID == 100, "invalid RewardPayout");
        return abi.encodePacked(uint8(100), rp.fromChain, rp.chain, rp.amount, rp.receiver);
    }

    /// @dev `decodeDeliveryInstructionsContainer` parses encoded delivery instructions into the DeliveryInstructions struct
    function decodeDeliveryInstructionsContainer(bytes memory encoded)
        public
        pure
        returns (DeliveryInstructionsContainer memory)
    {
        uint256 index = 0;

        uint8 payloadId = encoded.toUint8(index);
        require(payloadId == 1, "invalid payloadId");
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

        require(index == encoded.length, "invalid delivery instructions payload");

        return DeliveryInstructionsContainer(payloadId, sufficientlyFunded, instructionArray);
    }

    // function parseDeliveryStatus(bytes memory encoded) internal pure returns (DeliveryStatus memory ds) {
    //     uint256 index = 0;

    //     ds.payloadID = encoded.toUint8(index);
    //     index += 1;

    //     require(ds.payloadID == 2, "invalid DeliveryStatus");

    //     ds.batchHash = encoded.toBytes32(index);
    //     index += 32;

    //     ds.emitterAddress = encoded.toBytes32(index);
    //     index += 32;

    //     ds.sequence = encoded.toUint64(index);
    //     index += 8;

    //     ds.deliveryCount = encoded.toUint16(index);
    //     index += 2;

    //     ds.deliverySuccess = encoded.toUint8(index) != 0;
    //     index += 1;

    //     require(encoded.length == index, "invalid DeliveryStatus");
    // }

    function parseRewardPayout(bytes memory encoded) internal pure returns (RewardPayout memory rp) {
        uint256 index = 0;

        rp.payloadID = encoded.toUint8(index);
        index += 1;

        require(rp.payloadID == 100, "invalid RewardPayout");

        rp.fromChain = encoded.toUint16(index);
        index += 2;

        rp.chain = encoded.toUint16(index);
        index += 2;

        rp.amount = encoded.toUint256(index);
        index += 32;

        rp.receiver = encoded.toBytes32(index);
        index += 32;

        require(encoded.length == index, "invalid RewardPayout");
    }

    function encodeDeliveryRequestsContainer(DeliveryRequestsContainer memory container) internal view returns(bytes memory encoded) {
        encoded = abi.encodePacked(
            uint8(1), //version payload number
            address(container.relayProviderAddress),
            uint8(container.requests.length) //number of requests in the array
        ); 
        
        
        //Append all the messages to the array.
        for (uint256 i = 0; i < container.requests.length; i++) {
            DeliveryRequest memory request = container.requests[i];

            encoded = abi.encodePacked(encoded,
            request.targetChain,
            request.targetAddress,
            request.refundAddress,
            request.computeBudget,
            request.applicationBudget,
            request.relayParameters.length > 0 ? request.relayParameters.toUint8(0) : uint8(0),
            request.relayParameters.length > 0 ? request.relayParameters.toBytes32(1) : bytes32(uint256(uint160(address(0x0)))));
        }
    }

    function decodeDeliveryRequestsContainer(bytes memory encoded) internal view returns (DeliveryRequestsContainer memory) {
         uint256 index = 0;

        uint8 payloadId = encoded.toUint8(index);
        require(payloadId == 1, "invalid payloadId");
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

            request.relayParameters = encoded.slice(index, 33);

            index += 33;

            requestArray[i] = request;
        }

        require(index == encoded.length, "invalid delivery requests payload");

        return DeliveryRequestsContainer(payloadId, relayProviderAddress,  requestArray);
    
    }

   
}
