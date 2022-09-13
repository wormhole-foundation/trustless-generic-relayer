// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./GasOracleGetters.sol";
import "./GasOracleSetters.sol";

contract GasOracle is GasOracleGetters, GasOracleSetters {
    struct UpdatePrice {
        uint16 chainId;
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    constructor(address wormhole, uint16 srcChainId) {
        setupInitialState(_msgSender(), wormhole, srcChainId);
    }

    function setupInitialState(address owner, address wormhole, uint16 srcChainId) internal {
        require(owner != address(0), "owner == address(0)");
        setOwner(owner);
        require(srcChainId > 0, "srcChainId == 0");
        setChainId(srcChainId);
        // might use this later to consume price data via VAAs?
        require(wormhole != address(0), "wormhole == address(0)");
        setWormhole(wormhole);
    }

    function getPrice(uint16 targetChainId) public view returns (uint256 quote) {
        uint256 srcNativeCurrencyPrice = nativeCurrencyPrice(chainId());
        require(srcNativeCurrencyPrice > 0, "srcNativeCurrencyPrice == 0");

        uint256 dstNativeCurrencyPrice = nativeCurrencyPrice(targetChainId);
        require(dstNativeCurrencyPrice > 0, "dstNativeCurrencyPrice == 0");

        quote = (gasPrice(targetChainId) * dstNativeCurrencyPrice) / srcNativeCurrencyPrice;
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

    modifier onlyOwner() {
        require(owner() == _msgSender(), "owner() != _msgSender()");
        _;
    }
}
