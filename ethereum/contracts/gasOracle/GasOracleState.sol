// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract GasOracleStorage {

    struct PriceData {
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    struct State {
        uint16 chainId;
        address owner;
        address pendingOwner;

        mapping(uint16 => PriceData) data;
        mapping(uint16 => uint32) deliverGasOverhead;
        mapping(uint16 => uint32) wormholeFee;

        mapping(uint16 => bytes32) permissionedRelayerAddress;


    }
}

contract GasOracleState {
    GasOracleStorage.State _state;
}
