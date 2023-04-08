// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IRelayProvider {
    function quoteDeliveryOverhead(uint16 targetChain) external view returns (uint256 deliveryOverhead);

    function quoteGasPrice(uint16 targetChain) external view returns (uint256 gasPriceSource);

    function quoteAssetPrice(uint16 chainId) external view returns (uint256 usdPrice);

    function getAssetConversionBuffer(uint16 targetChain)
        external
        view
        returns (uint16 tolerance, uint16 toleranceDenominator);

    function quoteMaximumBudget(uint16 targetChain) external view returns (uint256 maximumTargetBudget);

    function getRewardAddress() external view returns (address payable rewardAddress);

    function getConsistencyLevel() external view returns (uint8 consistencyLevel);

    function isChainSupported(uint16 targetChainId) external view returns (bool supported);

    function getTargetChainAddress(uint16 targetChainId) external view returns (bytes32 relayProviderAddress);
}
