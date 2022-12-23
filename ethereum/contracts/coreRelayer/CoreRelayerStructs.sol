// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

contract CoreRelayerStructs {
    //This first group of structs are external facing API objects,
    //which should be considered untrusted and unmodifiable

    struct DeliveryRequestsContainer {
        uint8 payloadId; // payloadID = 1
        DeliveryRequest[] requests;
    }

    struct TargetDeliveryParameters {
        // encoded batchVM to be delivered on the target chain
        bytes encodedVM;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        uint8 multisendIndex;
        //uint32 targetCallGasOverride;
    }

    struct TargetDeliveryParametersSingle {
        // encoded batchVM to be delivered on the target chain
        bytes[] encodedVMs;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        // Index of the target chain inside the delivery VM
        uint8 multisendIndex;
        // Optional gasOverride which can be supplied by the relayer
        // uint32 targetCallGasOverride;
    }

    struct DeliveryRequest {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 computeBudget;
        uint256 applicationBudget;
        bytes relayParameters;
    }

    struct RelayParameters {
        uint8 version; //1
        bytes32 oracleAddressOverride;
    }

    //Below this are internal structs




    //Wire Types
    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bool sufficientlyFunded; //TODO add to encode&decode
        DeliveryInstruction[] instructions;
    }

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 computeBudgetTarget;
        uint256 applicationBudgetTarget;
        uint256 sourceReward;
        uint16 sourceChain;
        ExecutionParameters executionParameters; //Has the gas limit to execute with
    }

    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
        bytes32 relayerAddress;
    }

    //End Wire Types






    //Internal usage structs

    struct AllowedEmitterSequence {
        // wormhole emitter address
        bytes32 emitterAddress;
        // wormhole message sequence
        uint64 sequence;
    }

    struct ForwardingRequest {
        bytes deliveryRequestsContainer;
        uint16 rolloverChain;
        uint32 nonce;
        uint8 consistencyLevel;
        bool isValid;
    }

    struct InternalDeliveryParameters {
        IWormhole.VM2 batchVM;
        DeliveryInstruction internalInstruction;
        AllowedEmitterSequence deliveryId;
        uint8 deliveryIndex;
        uint16 deliveryAttempts; //TODO unused?
        uint16 fromChain;
        uint32 deliveryGasLimit;
    }

    // TODO: Add single VAA variant
    struct RedeliveryInstructions {
        uint8 payloadID; // payloadID = 3;
        // Hash of the batch to re-deliver
        bytes32 batchHash;
        // Point to the original delivery instruction
        bytes32 emitterAddress;
        uint64 sequence;
        // Current number of delivery attempts
        uint16 deliveryCount;
        // New Relayer-Specific Parameters
        bytes relayParameters;
    }

    struct DeliveryStatus {
        uint8 payloadID; // payloadID = 2;
        bytes32 batchHash;
        bytes32 emitterAddress;
        uint64 sequence;
        uint16 deliveryCount;
        bool deliverySuccess;
    }

    // TODO: WIP
    struct RewardPayout {
        uint8 payloadID; // payloadID = 100; prevent collisions with new blueprint payloads
        uint16 fromChain;
        uint16 chain;
        uint256 amount;
        bytes32 receiver;
    }
}
