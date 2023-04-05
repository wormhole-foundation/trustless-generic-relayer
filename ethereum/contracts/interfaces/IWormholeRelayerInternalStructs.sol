// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeRelayer.sol";

interface IWormholeRelayerInternalStructs {
    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bytes32 senderAddress;
        bytes32 relayProviderAddress;
        IWormholeRelayer.MessageInfo[] messageInfos;
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
}
