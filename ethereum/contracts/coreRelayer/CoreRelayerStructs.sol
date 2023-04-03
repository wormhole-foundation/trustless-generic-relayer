// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeRelayer.sol";

abstract contract CoreRelayerStructs {
    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bytes32 requesterAddress;
        IWormholeRelayer.MessageInfo[] messages;
        DeliveryInstruction[] instructions;
    }

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 maximumRefundTarget;
        uint256 receiverValueTarget;
        bytes32 provider;
        ExecutionParameters executionParameters;
    }

    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
    }

    struct ForwardInstruction {
        bytes container;
        address sender;
        uint256 msgValue;
        uint256 totalFee;
        address relayProvider;
        bool isValid;
    }

    struct DeliveryVAAInfo {
        uint16 sourceChain;
        uint64 sourceSequence;
        bytes32 deliveryVaaHash;
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
}
