// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./CoreRelayerState.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayerSetters is CoreRelayerState, Context {
    function setOwner(address owner_) internal {
        _state.owner = owner_;
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

    function setRelayProvider(address defaultRelayProvider) internal {
        _state.defaultRelayProvider = defaultRelayProvider;
    }

    function setRegisteredCoreRelayerContract(uint16 chainId, bytes32 relayerAddress) internal {
        _state.registeredCoreRelayerContract[chainId] = relayerAddress;
    }

    function setForwardingRequest(CoreRelayerStructs.ForwardingRequest memory request) internal {
        _state.forwardingRequest = request;
    }

    function clearForwardingRequest() internal {
        delete _state.forwardingRequest; //TODO is this the best way to accomplish this?
    }

    function markAsDelivered(bytes32 deliveryHash) internal {
        _state.completedDeliveries[deliveryHash] = true;
    }

    function setContractLock(bool status) internal {
        _state.contractLock = status;
    }
}
