// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./RelayProviderGovernance.sol";
import "./RelayProviderStructs.sol";
import "../interfaces/IRelayProvider.sol";
import "../interfaces/ICoreRelayer.sol";

contract RelayProvider is RelayProviderGovernance, IRelayProvider {
    modifier onlyApprovedSender() {
        require(approvedSender(_msgSender()), "_msgSender() not approved");
        _;
    }

    //Returns the delivery overhead fee required to deliver a message to targetChain, denominated in this chain's wei.
    function quoteDeliveryOverhead(uint16 targetChain) public view override returns (uint256 nativePriceQuote) {
        uint256 targetFees = deliverGasOverhead(targetChain) * gasPrice(targetChain) + wormholeFee(targetChain);
        return quoteAssetConversion(targetChain, targetFees, chainId());
    }

    //Returns the redelivery overhead fee required to deliver a message to targetChain, denominated in this chain's wei.
    function quoteRedeliveryOverhead(uint16 targetChain) public view override returns (uint256 nativePriceQuote) {
        return quoteDeliveryOverhead(targetChain);
    }

    //Returns the price of purchasing 1 unit of gas on targetChain, denominated in this chain's wei.
    function quoteGasPrice(uint16 targetChain) public view override returns (uint256) {
        return quoteAssetConversion(targetChain, gasPrice(targetChain), chainId());
    }

    //Returns the price of chainId's native currency in USD * 10^6
    //TODO decide on USD decimals
    function quoteAssetPrice(uint16 chainId) public view override returns (uint256) {
        return nativeCurrencyPrice(chainId);
    }

    //Returns the maximum budget that is allowed for a delivery on target chain, denominated in the targetChain's wei.
    function quoteMaximumBudget(uint16 targetChain) public view override returns (uint256 maximumTargetBudget) {
        return maximumBudget(targetChain);
    }

    //Returns the address (in wormhole format) which is allowed to deliver VAAs for this provider on targetChain
    function getDeliveryAddress(uint16 targetChain) public view override returns (bytes32 whAddress) {
        return deliveryAddress(targetChain);
    }

    //Returns the address on this chain that rewards should be sent to
    function getRewardAddress() public view override returns (address) {
        return rewardAddress();
    }

    //returns the consistency level that should be put on delivery VAAs
    function getConsistencyLevel() public view override returns (uint8 consistencyLevel) {
        return 200; //REVISE consider adding state variable for this
    }

    //Returns a a buffer amount, and a buffer denominator, whereby the bufferAmount / bufferDenominator will be reduced from
    //applicationBudget conversions, giving an overhead to the provider on each conversion
    function assetConversionBuffer(uint16 sourceChain, uint16 targetChain)
        public
        view
        override
        returns (uint16 tolerance, uint16 toleranceDenominator)
    {
        return (5, 100);
    }

    /**
     *
     * HELPER METHODS
     *
     */

    // relevant for chains that have dynamic execution pricing (e.g. Ethereum)
    function quoteAssetConversion(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain)
        internal
        view
        returns (uint256 targetAmount)
    {
        uint256 srcNativeCurrencyPrice = quoteAssetPrice(sourceChain);
        uint256 dstNativeCurrencyPrice = quoteAssetPrice(targetChain);

        // round up
        return (sourceAmount * srcNativeCurrencyPrice + dstNativeCurrencyPrice - 1) / dstNativeCurrencyPrice;
    }

    //Internal delivery proxies
    function redeliverSingle(ICoreRelayer.TargetRedeliveryByTxHashParamsSingle memory targetParams)
        public
        payable
        onlyApprovedSender
        returns (uint64 sequence)
    {
        ICoreRelayer cr = ICoreRelayer(coreRelayer());
        return cr.redeliverSingle{value: msg.value}(targetParams);
    }

    function deliverSingle(ICoreRelayer.TargetDeliveryParametersSingle memory targetParams)
        public
        payable
        onlyApprovedSender
        returns (uint64 sequence)
    {
        ICoreRelayer cr = ICoreRelayer(coreRelayer());
        return cr.deliverSingle{value: msg.value}(targetParams);
    }
}
