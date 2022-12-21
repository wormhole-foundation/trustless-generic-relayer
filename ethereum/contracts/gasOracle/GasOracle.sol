// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./GasOracleGetters.sol";
import "./GasOracleSetters.sol";
import "./GasOracleGovernance.sol";

//TODO refactor/ rename to provider
contract GasOracle is GasOracleGovernance {
    
    constructor(uint16 chainId) {
        setOwner(_msgSender());
        setChainId(chainId);
    }

    function assetConversionAmount(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) public view returns (uint256 targetAmount) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(sourceChain);
        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChain);

        targetAmount = (sourceAmount * srcNativeCurrencyPrice /  dstNativeCurrencyPrice); 
    }

    function quoteEvmDeliveryPrice(uint16 chainId, uint256 gasLimit) public view returns (uint256 nativePriceQuote) {
        nativePriceQuote = computeGasCost(chainId, gasLimit + deliverGasOverhead(chainId)) + wormholeFee(chainId);
    }

    function quoteTargetEvmGas(uint16 targetChain, uint256 computeBudget ) public view returns (uint32 gasAmount) {
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

    function getRelayerAddressSingle(uint16 targetChain) public view returns (bytes32 whAddress) {
        return relayerAddress(targetChain);
    }

    struct UpdatePrice {
        uint16 chainId;
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    function updatePrice(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice)
        public
        onlyOwner
    {
        require(updateChainId > 0, "updateChainId == 0");
        require(updateGasPrice > 0, "updateGasPrice == 0");
        require(updateNativeCurrencyPrice > 0, "updateNativeCurrencyPrice == 0");
        setPriceInfo(updateChainId, updateGasPrice, updateNativeCurrencyPrice);
    }

    function updatePrices(UpdatePrice[] memory updates) public onlyOwner {
        uint256 pricesLen = updates.length;
        for (uint256 i = 0; i < pricesLen;) {
            updatePrice(updates[i].chainId, updates[i].gasPrice, updates[i].nativeCurrencyPrice);
            unchecked {
                i += 1;
            }
        }
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
