// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

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
        // Index of the delivery VM in a batch. Does not have to match the
        // index in the corresponding indexedObservation when converted into a partial batch.
        uint8 deliveryIndex;
        uint32 targetCallGasOverride;
    }

    struct DeliveryParameters {
        uint16 targetChain;
        bytes32 targetAddress;
        AllowedEmitterSequence[] deliveryList;
        bytes relayParameters;
        uint32 nonce;
        uint8 consistencyLevel;
    }

    struct DeliveryInstructions {
        uint8 payloadID; // payloadID = 1;
        bytes32 fromAddress;
        uint16 fromChain;
        bytes32 targetAddress;
        uint16 targetChain;
        AllowedEmitterSequence[] deliveryList;
        bytes relayParameters;
    }

    // TODO: WIP
    struct RedeliveryInstructions {
        uint8 payloadID; // payloadID = 3;
        // Hash of the batch to re-deliver
        bytes32 batchHash;
        // Point to the original delivery instruction
        bytes32 emitterAddress;
        uint64 sequence;
        // Current deliverycount
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
