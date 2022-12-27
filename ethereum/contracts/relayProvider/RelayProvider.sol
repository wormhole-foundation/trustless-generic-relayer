// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./RelayProviderGovernance.sol";
import "./RelayProviderStructs.sol";
import "../interfaces/IRelayProvider.sol";

contract RelayProvider is RelayProviderGovernance, IRelayProvider {
    
    function quoteDeliveryOverhead(uint16 targetChain) public override view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(targetChain, deliverGasOverhead(targetChain)) + wormholeFee(targetChain);
    }

    function quoteRedeliveryOverhead(uint16 targetChain) public override view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(targetChain, deliverGasOverhead(targetChain)) + wormholeFee(targetChain);
    }

    function quoteGasPrice(uint16 targetChain) public override view returns (uint256 gasPrice) {
        computeGasCost(targetChain, uint256(1));
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
