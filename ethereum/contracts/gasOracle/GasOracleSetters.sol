// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

import "./GasOracleState.sol";

contract GasOracleSetters is Context, GasOracleState {
    function setChainId(uint16 oracleChainId) internal {
        _state.provider.chainId = oracleChainId;
    }

    function setWormhole(address wormhole) internal {
        _state.provider.wormhole = payable(wormhole);
    }

    function setOwner(address owner) internal {
        _state.owner = owner;
    }

    function setPriceInfo(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) internal {
        _state.data[updateChainId].gasPrice = updateGasPrice;
        _state.data[updateChainId].nativeCurrencyPrice = updateNativeCurrencyPrice;
    }
}
