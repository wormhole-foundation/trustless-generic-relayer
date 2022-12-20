// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";

import "./GasOracleState.sol";

contract GasOracleGetters is GasOracleState {


    function chainId() public view returns (uint16) {
        return _state.chainId;
    }

    function gasPrice(uint16 targetChainId) public view returns (uint128) {
        return _state.data[targetChainId].gasPrice;
    }

    function nativeCurrencyPrice(uint16 targetChainId) public view returns (uint128) {
        return _state.data[targetChainId].nativeCurrencyPrice;
    }

    function deliverGasOverhead(uint16 targetChainId) public view returns (uint32) {
        return _state.deliverGasOverhead[targetChainId];
    }

    function wormholeFee(uint16 targetChainId) public view returns (uint32) {
        return _state.wormholeFee[targetChainId];
    }

    function relayerAddress(uint16 targetChainId) public view returns (bytes32) {
        require(_state.permissionedRelayerAddress[targetChainId] != bytes32(0), "No permissioned relayer address");
        return _state.permissionedRelayerAddress[targetChainId];
    }

    function owner() public view returns (address) {
        return _state.owner;
    }

    function pendingOwner() public view returns (address) {
        return _state.pendingOwner;
    }
}
