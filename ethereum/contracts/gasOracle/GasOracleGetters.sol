// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

import "./GasOracleState.sol";

abstract contract GasOracleGetters is GasOracleState {
    function isInitialized(address implementation) public view returns (bool) {
        return _state.initializedImplementations[implementation];
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function gasPrice(uint16 targetChainId) public view returns (uint256) {
        return _state.gasPrices[targetChainId];
    }

    function nativeCurrencyPrice(uint16 targetChainId) public view returns (uint256) {
        return _state.nativeCurrencyPrices[targetChainId];
    }

    function owner() public view returns (address) {
        return _state.owner;
    }
}
