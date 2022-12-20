// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IGasOracle {

    /**
     * @dev `quoteEvmDeliveryPrice` returns the amount in wei that must be paid to the core relayer contract 
     * in order to request delivery of a batch of messages to chainId with a sufficient computeBudget to cover
     * the specified gasLimit.
     */
    function quoteEvmDeliveryPrice(uint16 chainId, uint256 gasLimit) external view returns (uint256 nativePriceQuote);

    /**
    * @dev this is the inverse of "quoteEvmDeliveryPrice". 
    * Given a computeBudget (denominated in the wei of this chain), and a target chain, this function returns the maximum
    * amount of gas on the target chain this compute budget will cover.
    */
    function quoteTargetEvmGas(uint16 targetChain, uint256 computeBudget ) external view returns (uint32 gasAmount);

    function assetConversionAmount(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) external view returns (uint256 targetAmount);

    function getRelayerAddressSingle(uint16 targetChain) external view returns (bytes32 whAddress);

    function wormholeFee(uint16 targetChainId) external view returns (uint32);

    //TODO add applicationBudget helper calculation function
}
