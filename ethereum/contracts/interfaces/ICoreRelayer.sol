// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface ICoreRelayer {
    
    /**
     * @dev `quoteEvmDeliveryPrice` returns the amount in wei that must be paid to the core relayer contract 
     * in order to request delivery of a batch of messages to chainId with a sufficient computeBudget to cover
     * the specified gasLimit.
     */
    function quoteEvmDeliveryPrice(uint16 chainId, uint256 gasLimit) external returns (uint256 nativePriceQuote);

    /**
    * @dev this is the inverse of "quoteEvmRelayPrice". 
    * Given a computeBudget (denominated in the wei of this chain), and a target chain, this function returns the maximum
    * amount of gas on the target chain this compute budget will cover.
    */
    function quoteTargetEvmGas(uint16 targetChain, uint256 computeBudget ) external returns (uint32 gasAmount);

    function assetConversionAmount(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) external returns (uint256 targetAmount);

    /**
    * @dev This is the basic function for requesting delivery
    */
    function requestDelivery(DeliveryInstructions memory instructions, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function requestForward(DeliveryInstructions memory instructions, uint32 nonce, uint8 consistencyLevel) external payable;

    function requestRedelivery(bytes32 transactionHash, uint256 newComputeBudget, uint256 newNativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) external payable;

    function requestMultidelivery(DeliveryInstructionsContainer memory deliveryInstructions, uint32 nonce, uint8 consistencyLevel) external payable;

    /**
    @dev When requesting a multiforward, the rollover chain is the chain where any remaining funds should be sent once all
        the requested budgets have been covered. The remaining funds will be added to the computeBudget of the rollover chain.
     */
    function requestMultiforward(DeliveryInstructionsContainer memory deliveryInstructions, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) external payable;

    function deliver(TargetDeliveryParameters memory targetParams) external payable returns (uint64 sequence);

    function redeliver(TargetDeliveryParameters memory targetParams, bytes memory encodedRedeliveryVm) external payable returns (uint64 sequence);

    function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) external payable returns (uint64 sequence);

    function collectRewards(bytes memory encodedVm) external;

    struct DeliveryInstructionsContainer {
        uint8 payloadID; // payloadID = 1
        DeliveryInstructions[] instructions;
    }

    struct TargetDeliveryParameters {
        // encoded batchVM to be delivered on the target chain
        bytes encodedVM;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        // Index of the target chain inside the delivery VM
        uint8 multisendIndex;
        // Optional gasOverride which can be supplied by the relayer
        uint32 targetCallGasOverride;
    }

    /**
    *  targetChain - the chain to send to in Wormhole Chain ID format.
    *  targetAddress - is the recipient contract address on the target chain (in Wormhole 32-byte address format).
    *  refundAddress - is the address where any remaining computeBudget should be sent at the end of the transaction. (In Wormhole address format. Must be on the target chain.)
    *  computeBudget - is the maximum amount (denominated in this chain's wei) that the relayer should spend executing this delivery. Usually calculated from quoteEvmDeliveryPrice.
    *  nativeBudget - this amount (denominated in this chain's wei) will be converted to the target native currency and given to the recipient contract at the beginning of the delivery execution.
    *  nonce - the nonce the delivery VAA should be emitted with - used for batching. All messages you want included in your batch must have the same non-zero nonce.
    *  consistencyLevel - the consistency level the delivery VAA should be emitted with. Usually either instant or finality. Behavior varies by chain.
    *  relayParameters - optional payload which can alter relayer behavior.
    */
    struct DeliveryInstructions {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 computeBudget;
        uint256 nativeBudget;
        bytes relayParameters;
    }

}
