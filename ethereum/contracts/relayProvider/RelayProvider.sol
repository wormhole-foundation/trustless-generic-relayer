// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./RelayProviderGetters.sol";
import "./RelayProviderSetters.sol";
import "./RelayProviderGovernance.sol";
import "../interfaces/IRelayProvider.sol";

//TODO refactor/ rename to provider
contract RelayProvider is RelayProviderGovernance, IRelayProvider {
    
    constructor(uint16 chainId) {
        setOwner(_msgSender());
        setChainId(chainId);
    }


    function quoteEvmDeliveryPrice(uint16 chainId, uint256 gasLimit) public override view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(chainId, gasLimit + deliverGasOverhead(chainId)) + wormholeFee(chainId);
    }

    function quoteTargetEvmGas(uint16 targetChain, uint256 computeBudget ) public override view returns (uint32 gasAmount) {
        if(computeBudget <= wormholeFee(targetChain)) {
            return 0;
        } else {
            uint256 remainder = computeBudget - wormholeFee(targetChain);
            uint256 gas = (remainder / computeGasCost(targetChain, 1));
            if(gas <= deliverGasOverhead(targetChain)) {
                return 0;
            }
            return uint32(gas - deliverGasOverhead(targetChain));
        }
    }

    function assetConversionAmount(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) public override view returns (uint256 targetAmount) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(sourceChain);
        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChain);

        targetAmount = (sourceAmount * srcNativeCurrencyPrice /  dstNativeCurrencyPrice); 
    }

    function getRewardAddress(uint16 targetChain) public override view returns (bytes32 whAddress) {
        return rewardAddress(targetChain);
    }

    function getMaximumBudget(uint16 targetChain) public override view returns (uint256 maximumTargetBudget) {
        return maximumBudget(targetChain);
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
