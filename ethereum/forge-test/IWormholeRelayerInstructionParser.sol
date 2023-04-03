// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/interfaces/IWormholeRelayer.sol";

interface IWormholeRelayerInstructionParser {
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
        ExecutionParameters executionParameters;
    }

    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
        bytes32 providerDeliveryAddress;
    }

    function decodeDeliveryInstructionsContainer(bytes memory encoded)
        external
        pure
        returns (DeliveryInstructionsContainer memory);


    function toWormholeFormat(address addr) external pure returns (bytes32 whFormat);

    function fromWormholeFormat(bytes32 whFormatAddress) external pure returns (address addr);
}
