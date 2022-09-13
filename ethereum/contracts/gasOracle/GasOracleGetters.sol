// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

import "./GasOracleState.sol";

contract GasOracleGetters is GasOracleState {
    function isInitialized(address implementation) public view returns (bool) {
        return _state.initializedImplementations[implementation];
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function gasPrice(uint16 targetChainId) public view returns (uint128) {
        return _state.data[targetChainId].gasPrice;
    }

    function nativeCurrencyPrice(uint16 targetChainId) public view returns (uint128) {
        return _state.data[targetChainId].nativeCurrencyPrice;
    }

    function owner() public view returns (address) {
        return _state.owner;
    }
}
