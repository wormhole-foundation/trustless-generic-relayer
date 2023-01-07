// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

contract RelayProviderStorage {
    struct PriceData {
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    struct State {
        uint16 chainId;
        address owner;
        address pendingOwner;
        address payable coreRelayer;
        mapping(address => bool) initializedImplementations;
        mapping(uint16 => PriceData) data;
        mapping(uint16 => uint32) deliverGasOverhead;
        mapping(uint16 => uint32) wormholeFee;
        mapping(uint16 => uint256) maximumBudget;
        mapping(uint16 => bytes32) deliveryAddressMap;
        mapping(address => bool) approvedSenders;
        address rewardAddress;
    }
}

contract RelayProviderState {
    RelayProviderStorage.State _state;
}
