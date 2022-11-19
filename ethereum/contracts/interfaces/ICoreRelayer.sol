// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface ICoreRelayer {
    struct AllowedEmitterSequence {
        // VAA emitter address
        bytes32 emitterAddress;
        // VAA sequence
        uint64 sequence;
    }

    struct TargetDeliveryParameters {
        // encoded batchVM to be delivered on the target chain
        bytes encodedVM;
        // Index of the delivery VM in a batch. Does not have to match the
        // index in the corresponding indexedObservation when converted into a partial batch.
        uint8 deliveryIndex;
        uint256 targetCallGasOverride;
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

    struct RedeliveryParameters {
        // Hash of the batch VAA to deliver again
        bytes32 batchHash;
    }

    function estimateEvmCost(uint16 chainId, uint256 gasLimit) external view returns (uint256 gasEstimate);

    function forward(
        DeliveryInstructionsContainer memory deliveryInstructions, 
        uint16 rolloverChain, 
        uint32 nonce, 
        uint8 consistencyLevel) external;

    function send(
        DeliveryInstructionsContainer memory deliveryInstructionsContainer,
        uint32 nonce,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    function deliver(TargetDeliveryParameters memory targetParams) external payable returns (uint64);
}
