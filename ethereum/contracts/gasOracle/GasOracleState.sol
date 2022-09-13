// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract GasOracleStorage {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
    }

    struct PriceData {
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    struct State {
        Provider provider;
        address owner;
        mapping(address => bool) initializedImplementations;
        mapping(uint16 => PriceData) data;
    }
}

contract GasOracleState {
    GasOracleStorage.State _state;
}
