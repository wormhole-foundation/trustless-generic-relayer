// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

contract CoreRelayerStructs {
    struct AllowedEmitterSequence {
        // wormhole emitter address
        bytes32 emitterAddress;
        // wormhole message sequence
        uint64 sequence;
    }

    struct TargetDeliveryParameters {
        // encoded batchVM to be delivered on the target chain
        bytes encodedVM;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        uint8 multisendIndex;
        uint32 targetCallGasOverride;
    }

    struct DeliveryInstructionsContainer {
        uint8 payloadID; // payloadID = 1
        DeliveryInstructions[] instructions;
    }

    struct DeliveryInstructions {
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint16 targetChain;
        bytes relayParameters;
    }

    struct InternalDeliveryParameters {
        IWormhole.VM2 batchVM;
        DeliveryInstructions deliveryInstructions;
        AllowedEmitterSequence deliveryId;
        RelayParameters relayParams;
        uint8 deliveryIndex;
        uint16 deliveryAttempts;
        uint16 fromChain;
    }

    // TODO: WIP
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

    struct RelayParameters {
        // version = 1
        uint8 version;
        // gasLimit to call the receiving contract with
        uint32 deliveryGasLimit;
        // maximum batch size
        uint8 maximumBatchSize;
        // the payment made on the source chain, which is later paid to the relayer
        uint256 nativePayment;
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
