// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

abstract contract GasOracleStorage {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
    }

    struct State {
        Provider provider;
        address owner;
        mapping(address => bool) initializedImplementations;
        mapping(uint16 => uint256) gasPrices;
        mapping(uint16 => uint256) nativeCurrencyPrices;
    }
}

abstract contract GasOracleState {
    GasOracleStorage.State _state;
}
