// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGetters.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayerMessages is CoreRelayerStructs, CoreRelayerGetters {
    using BytesLib for bytes;

    function encodeDeliveryList(AllowedEmitterSequence[] memory deliveryList)
        internal
        pure
        returns (bytes memory encoded)
    {
        uint256 len = deliveryList.length;
        for (uint8 i = 0; i < len;) {
            encoded = abi.encodePacked(encoded, deliveryList[i].emitterAddress, deliveryList[i].sequence);
            unchecked {
                i += 1;
            }
        }
    }

    function encodeDeliveryInstructions(DeliveryParameters memory instructions)
        internal
        view
        returns (bytes memory encoded)
    {
        encoded = abi.encodePacked(
            uint8(1), // payloadID = 1
            bytes32(uint256(uint160(msg.sender))),
            chainId(),
            instructions.targetAddress,
            instructions.targetChain,
            uint16(instructions.deliveryList.length),
            encodeDeliveryList(instructions.deliveryList),
            uint16(instructions.relayParameters.length),
            instructions.relayParameters
        );
    }

    function encodeDeliveryStatus(DeliveryStatus memory ds) internal pure returns (bytes memory) {
        require(ds.payloadID == 2, "invalid DeliveryStatus");
        return abi.encodePacked(
            ds.payloadID,
            ds.batchHash,
            ds.emitterAddress,
            ds.sequence,
            ds.deliveryCount,
            ds.deliverySuccess ? uint8(1) : uint8(0)
        );
    }

    // TODO: WIP
    function encodeRedeliveryInstructions(RedeliveryInstructions memory rdi) internal pure returns (bytes memory) {
        require(rdi.payloadID == 3, "invalid RedeliveryInstructions");
        return abi.encodePacked(
            rdi.payloadID,
            rdi.batchHash,
            rdi.emitterAddress,
            rdi.sequence,
            rdi.deliveryCount,
            uint16(rdi.relayParameters.length),
            rdi.relayParameters
        );
    }

    // TODO: WIP
    function encodeRewardPayout(RewardPayout memory rp) internal pure returns (bytes memory) {
        require(rp.payloadID == 100, "invalid RewardPayout");
        return abi.encodePacked(rp.payloadID, rp.fromChain, rp.chain, rp.amount, rp.receiver);
    }

    /// @dev `decodedDeliveryInstructions` parses encoded delivery instructions into the DeliveryInstructions struct
    function decodeDeliveryInstructions(bytes memory encoded)
        public
        pure
        returns (DeliveryInstructions memory instructions)
    {
        uint256 index = 0;

        // version
        instructions.payloadID = encoded.toUint8(index);
        index += 1;
        require(instructions.payloadID == 1, "invalid version");

        // caller of the source chain relayer contract
        instructions.fromAddress = encoded.toBytes32(index);
        index += 32;

        // source chain of the delivery instructions
        instructions.fromChain = encoded.toUint16(index);
        index += 2;

        // target contract address
        instructions.targetAddress = encoded.toBytes32(index);
        index += 32;

        // target chain of the delivery instructions
        instructions.targetChain = encoded.toUint16(index);
        index += 2;

        // length of the deliveryList
        uint16 deliveryListLen = encoded.toUint16(index);
        index += 2;

        // list of VAAs to deliver
        instructions.deliveryList = new AllowedEmitterSequence[](deliveryListLen);
        for (uint16 i = 0; i < deliveryListLen;) {
            instructions.deliveryList[i].emitterAddress = encoded.toBytes32(index);
            index += 32;

            instructions.deliveryList[i].sequence = encoded.toUint64(index);
            index += 8;

            unchecked {
                i += 1;
            }
        }

        // length of relayParameters
        uint16 relayParametersLen = encoded.toUint16(index);
        index += 2;

        // relayParameters
        instructions.relayParameters = encoded.slice(index, relayParametersLen);
        index += relayParametersLen;

        require(index == encoded.length, "invalid delivery instructions payload");
    }

    /// @dev `decodeRelayParameters` parses encoded relay parameters into the RelayParameters struct
    function decodeRelayParameters(bytes memory encoded) public pure returns (RelayParameters memory relayParams) {
        uint256 index = 0;

        // version
        relayParams.version = encoded.toUint8(index);
        index += 1;
        require(relayParams.version == 1, "invalid version");

        // gas limit
        relayParams.deliveryGasLimit = encoded.toUint32(index);
        index += 4;

        // maximum batch size
        relayParams.maximumBatchSize = encoded.toUint8(index);
        index += 1;

        // payment made on the source chain
        relayParams.nativePayment = encoded.toUint256(index);
        index += 32;

        require(index == encoded.length, "invalid relay parameters");
    }

    // TODO: WIP
    function parseDeliveryStatus(bytes memory encoded) internal pure returns (DeliveryStatus memory ds) {
        uint256 index = 0;

        ds.payloadID = encoded.toUint8(index);
        index += 1;

        require(ds.payloadID == 2, "invalid DeliveryStatus");

        ds.batchHash = encoded.toBytes32(index);
        index += 32;

        ds.emitterAddress = encoded.toBytes32(index);
        index += 32;

        ds.sequence = encoded.toUint64(index);
        index += 8;

        ds.deliveryCount = encoded.toUint16(index);
        index += 2;

        ds.deliverySuccess = encoded.toUint8(index) != 0;
        index += 1;

        require(encoded.length == index, "invalid DeliveryStatus");
    }

    // TODO: WIP
    function parseRedeliveryInstructions(bytes memory encoded)
        internal
        pure
        returns (RedeliveryInstructions memory rdi)
    {
        uint256 index = 0;

        rdi.payloadID = encoded.toUint8(index);
        index += 1;

        require(rdi.payloadID == 3, "invalid RedeliveryInstructions");

        rdi.batchHash = encoded.toBytes32(index);
        index += 32;

        rdi.emitterAddress = encoded.toBytes32(index);
        index += 32;

        rdi.sequence = encoded.toUint64(index);
        index += 8;

        rdi.deliveryCount = encoded.toUint16(index);
        index += 2;

        uint16 len = encoded.toUint16(index);
        index += 2;

        rdi.relayParameters = encoded.slice(index, len);
        index += len;

        require(encoded.length == index, "invalid RedeliveryInstructions");
    }

    // TODO: WIP
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
}
