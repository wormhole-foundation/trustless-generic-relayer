// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";
import "../interfaces/IRelayProvider.sol";
import "./CoreRelayerStructs.sol";

import "./CoreRelayerState.sol";
import "../libraries/external/BytesLib.sol";

contract CoreRelayerGetters is CoreRelayerState {
    using BytesLib for bytes;

    function governanceActionIsConsumed(bytes32 hash) public view returns (bool) {
        return _state.consumedGovernanceActions[hash];
    }

    function governanceChainId() public view returns (uint16){
        return _state.provider.governanceChainId;
    }

    function governanceContract() public view returns (bytes32){
        return _state.provider.governanceContract;
    }

    function isInitialized(address impl) public view returns (bool) {
        return _state.initializedImplementations[impl];
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function evmChainId() public view returns (uint256) {
        return _state.evmChainId;
    }

    function isFork() public view returns (bool) {
        return evmChainId() != block.chainid;
    }

    function registeredCoreRelayerContract(uint16 chain) public view returns (bytes32) {
        return _state.registeredCoreRelayerContract[chain];
    }

    function defaultRelayProvider() internal view returns (IRelayProvider) {
        return IRelayProvider(_state.defaultRelayProvider);
    }

    // function getSelectedRelayProvider(bytes memory relayerParams) internal view returns (IRelayProvider) {
    //     if(relayerParams.length == 0){
    //         return defaultRelayProvider();
    //     } else {
    //         require(relayerParams.length == 33, "Wrong length of relayerParams");
    //         if(relayerParams.toUint8(0) == 0) {
    //             return defaultRelayProvider();
    //         }
    //         return IRelayProvider(address(uint160(uint256(relayerParams.toBytes32(1)))));
    //     }
    // }

    function getForwardingRequest() internal view returns (CoreRelayerStructs.ForwardingRequest memory) {
        return _state.forwardingRequest;
    }

    function isDeliveryCompleted(bytes32 deliveryHash) public view returns (bool) {
        return _state.completedDeliveries[deliveryHash];
    }

    function isContractLocked() internal view returns (bool) {
        return _state.contractLock;
    }
}
