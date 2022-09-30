// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./CoreRelayerState.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract CoreRelayerSetters is CoreRelayerState, Context {
    function setOwner(address owner_) internal {
        _state.owner = owner_;
    }

    function setConsistencyLevel(uint8 consistencyLevel_) internal {
        _state.consistencyLevel = consistencyLevel_;
    }

    function setPendingOwner(address newOwner) internal {
        _state.pendingOwner = newOwner;
    }

    function setInitialized(address implementation) internal {
        _state.initializedImplementations[implementation] = true;
    }

    function setChainId(uint16 chainId_) internal {
        _state.provider.chainId = chainId_;
    }

    function setWormhole(address wh) internal {
        _state.provider.wormhole = payable(wh);
    }

    function setGasOracle(address oracle) internal {
        _state.gasOracle = oracle;
    }

    function setRegisteredRelayer(uint16 chainId, bytes32 relayerAddress) internal {
        _state.registeredRelayers[chainId] = relayerAddress;
    }

    function setEvmDeliverGasOverhead(uint32 gasOverhead) internal {
        _state.evmDeliverGasOverhead = gasOverhead;
    }

    function markAsDelivered(bytes32 deliveryHash) internal {
        _state.completedDeliveries[deliveryHash] = true;
    }

    function setContractLock(bool status) internal {
        _state.contractLock = status;
    }

    function incrementAttemptedDelivery(bytes32 deliveryHash) internal {
        _state.attemptedDeliveries[deliveryHash] += 1;
    }

    function incrementRedeliveryAttempt(bytes32 deliveryHash) internal {
        _state.redeliveryAttempts[deliveryHash] += 1;
    }

    function incrementRelayerRewards(address relayer, uint16 rewardChain, uint256 rewardAmount) internal {
        _state.relayerRewards[relayer][rewardChain] += rewardAmount;
    }

    function resetRelayerRewards(address relayer, uint16 rewardChain) internal {
        _state.relayerRewards[relayer][rewardChain] = 0;
    }
}
