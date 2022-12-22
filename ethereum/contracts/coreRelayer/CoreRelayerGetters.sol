// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormhole.sol";
import "../interfaces/IGasOracle.sol";
import "./CoreRelayerStructs.sol";

import "./CoreRelayerState.sol";

contract CoreRelayerGetters is CoreRelayerState {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function consistencyLevel() public view returns (uint8) {
        return _state.consistencyLevel;
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

    function registeredRelayer(uint16 chain) public view returns (bytes32) {
        return _state.registeredRelayers[chain];
    }

    function gasOracle() internal view returns (IGasOracle) {
        return IGasOracle(_state.gasOracle);
    }

    function getSelectedGasOracle(bytes memory relayerParams) internal view returns (IGasOracle) {
        if(relayerParams.length == 0){
            return gasOracle();
        } else {
            return gasOracle();
            //TODO parse relayerParams & instantiate IGasOracle. If that fails, explode.
        }
    } 

    function gasOracleAddress() public view returns (address) {
        return _state.gasOracle;
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
