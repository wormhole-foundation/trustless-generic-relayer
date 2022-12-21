// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

//TODO refactor to IRelayProvider
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

    function getRelayerAddress(uint16 targetChain) external view returns (bytes32 whAddress);

    function setRelayerAddress(uint16 targetChain, bytes32 newRelayerAddress) external;

    function updatePrice(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) external;

    struct UpdatePrice {
        uint16 chainId;
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    function updatePrices(UpdatePrice[] memory updates) external;

    function updateDeliverGasOverhead(uint16 chainId, uint32 newGasOverhead) external;

    function updateWormholeFee(uint16 chainId, uint32 newWormholeFee) external;

    //TODO add applicationBudget helper calculation function
}
