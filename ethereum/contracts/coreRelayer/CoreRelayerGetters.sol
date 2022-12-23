// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";
import "../interfaces/IRelayProvider.sol";
import "./CoreRelayerStructs.sol";

import "./CoreRelayerState.sol";

contract CoreRelayerGetters is CoreRelayerState {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function pendingOwner() public view returns (address) {
        return _state.pendingOwner;
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

    function registeredCoreRelayerContract(uint16 chain) public view returns (bytes32) {
        return _state.registeredCoreRelayerContract[chain];
    }

    function defaultRelayProvider() internal view returns (IRelayProvider) {
        return IRelayProvider(_state.defaultRelayProvider);
    }

    function getSelectedRelayProvider(bytes memory relayerParams) internal view returns (IRelayProvider) {
        if(relayerParams.length == 0){
            return defaultRelayProvider();
        } else {
            return defaultRelayProvider();
            //TODO parse relayerParams & instantiate IRelayProvider. If that fails, explode.
        }
    } 

    function getDefaultRelayProviderAddress() public view returns (address) {
        return _state.defaultRelayProvider;
    }

    function getForwardingRequest() internal view returns (CoreRelayerStructs.ForwardingRequest memory) {
        return _state.forwardingRequest;
    }

    function isDeliveryCompleted(bytes32 deliveryHash) public view returns (bool) {
        return _state.completedDeliveries[deliveryHash];
    }

    function isContractLocked() internal view returns (bool) {
        return _state.contractLock;
    }

    function attemptedDeliveryCount(bytes32 deliveryHash) public view returns (uint16) {
        return _state.attemptedDeliveries[deliveryHash];
    }

    function redeliveryAttemptCount(bytes32 deliveryHash) public view returns (uint16) {
        return _state.redeliveryAttempts[deliveryHash];
    }

    function relayerRewards(address relayer, uint16 rewardChain) public view returns (uint256) {
        return _state.relayerRewards[relayer][rewardChain];
    }
}
