// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./RelayProviderGovernance.sol";
import "./RelayProviderStructs.sol";
import "../interfaces/IRelayProvider.sol";

import "forge-std/Test.sol";

import "forge-std/console.sol";

contract RelayProvider is RelayProviderGovernance, IRelayProvider {
    
    function quoteDeliveryOverhead(uint16 targetChain) public override view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(targetChain, deliverGasOverhead(targetChain)) + wormholeFee(targetChain);
    }

    function quoteRedeliveryOverhead(uint16 targetChain) public override view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(targetChain, deliverGasOverhead(targetChain)) + wormholeFee(targetChain);
    }

    function quoteGasPrice(uint16 targetChain) public override view returns (uint256 gasPrice) {
        gasPrice = computeGasCost(targetChain, uint256(1));
    }

    function quoteAssetPrice(uint16 chainId) public override view returns (uint256 usdPrice) {
        usdPrice = nativeCurrencyPrice(chainId);
    }

    function quoteMaximumBudget(uint16 targetChain) public override view returns (uint256 maximumTargetBudget) {
        return maximumBudget(targetChain);
    }

    function getDeliveryAddress(uint16 targetChain) public override view returns (bytes32 whAddress) {
        return deliveryAddress(targetChain);
    }

    function getRewardAddress() public override view returns (address) {
        return rewardAddress();
    }

    function getConsistencyLevel() public override view returns (uint8 consistencyLevel) {
        return 200; //REVISE consider adding state variable for this
    }

    function quoteAssetConversion(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) public override view returns (uint256 targetAmount) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(sourceChain);
        require(srcNativeCurrencyPrice > 0, "srcNativeCurrencyPrice == 0");

        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChain);
        require(dstNativeCurrencyPrice > 0, "dstNativeCurrencyPrice == 0");

        return sourceAmount * srcNativeCurrencyPrice / dstNativeCurrencyPrice;
    }

    function assetConversionBuffer(uint16 sourceChain, uint16 targetChain) public override view returns (uint16 tolerance, uint16 toleranceDenominator) {
        return (5, 100);
    }

    

    /************
     * HELPER METHODS    
     ************/

    // relevant for chains that have dynamic execution pricing (e.g. Ethereum)
    function computeGasCost(uint16 targetChainId, uint256 gasLimit) internal view returns (uint256 quote) {
        quote = computeTransactionCost(targetChainId, gasPrice(targetChainId) * gasLimit);
    }

    function computeTransactionCost(uint16 targetChainId, uint256 transactionFee) internal view returns (uint256 quote) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(chainId());
        require(srcNativeCurrencyPrice > 0, "srcNativeCurrencyPrice == 0");

        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChainId);
        require(dstNativeCurrencyPrice > 0, "dstNativeCurrencyPrice == 0");

        quote = (dstNativeCurrencyPrice * transactionFee + (srcNativeCurrencyPrice - 1)) / srcNativeCurrencyPrice;
    }
}
