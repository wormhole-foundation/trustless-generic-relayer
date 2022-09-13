// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

import "./GasOracleState.sol";

abstract contract GasOracleSetters is Context, GasOracleState {
    function setInitialized(address implementation) internal {
        _state.initializedImplementations[implementation] = true;
    }

    function setChainId(uint16 oracleChainId) internal {
        _state.provider.chainId = oracleChainId;
    }

    function setWormhole(address wormhole) internal {
        _state.provider.wormhole = payable(wormhole);
    }

    function setOwner(address owner) internal {
        _state.owner = owner;
    }

    function setPriceInfo(uint16 updateChainId, uint256 updateGasPrice, uint256 updateNativeCurrencyPrice) internal {
        _state.gasPrices[updateChainId] = updateGasPrice;
        _state.nativeCurrencyPrices[updateChainId] = updateNativeCurrencyPrice;
    }
}
