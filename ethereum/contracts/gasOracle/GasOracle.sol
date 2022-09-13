// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./GasOracleGetters.sol";
import "./GasOracleSetters.sol";
import "./GasOracleGovernance.sol";

abstract contract GasOracle is GasOracleGovernance {
    struct UpdatePrice {
        uint16 chainId;
        uint256 gasPrice;
        uint256 nativeCurrencyPrice;
    }

    function getPrice(uint16 targetChainId) public view returns (uint256 quote) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(chainId());
        require(srcNativeCurrencyPrice > 0, "srcNativeCurrencyPrice == 0");

        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChainId);
        require(dstNativeCurrencyPrice > 0, "dstNativeCurrencyPrice == 0");

        quote = gasPrice(targetChainId) * dstNativeCurrencyPrice / srcNativeCurrencyPrice;
    }

    function updatePrice(uint16 updateChainId, uint256 updateGasPrice, uint256 updateNativeCurrencyPrice)
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
}
