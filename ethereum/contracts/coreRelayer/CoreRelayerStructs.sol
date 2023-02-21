// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

abstract contract CoreRelayerStructs {
    
    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bool sufficientlyFunded;
        DeliveryInstruction[] instructions;
    }

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 maximumRefundTarget;
        uint256 receiverValueTarget;
        ExecutionParameters executionParameters; //Has the gas limit to execute with
    }

    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
        bytes32 providerDeliveryAddress;
    }

    struct RedeliveryByTxHashInstruction {
        uint8 payloadId; //2
        uint16 sourceChain;
        bytes32 sourceTxHash;
        uint32 sourceNonce;
        uint16 targetChain;
        uint8 deliveryIndex;
        uint8 multisendIndex;
        uint256 newMaximumRefundTarget;
        uint256 newReceiverValueTarget;
        ExecutionParameters executionParameters;
    }

    struct ForwardingRequest {
        bytes deliveryRequestsContainer;
        uint32 nonce;
        address sender;
        uint256 msgValue;
        bool isValid;
    }
}
