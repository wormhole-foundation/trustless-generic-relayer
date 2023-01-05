// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./CoreRelayerStructs.sol";

contract CoreRelayerStorage {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
    }

    struct State {
        Provider provider;
        // delivery lock for reentrancy protection
        bool contractLock;
        // authority of these contracts
        address owner;
        // intermediate state when transfering contract ownership
        address pendingOwner;
        // address of the default relay provider on this chain
        address defaultRelayProvider;
        // Request which will be forwarded from the current delivery.
        CoreRelayerStructs.ForwardingRequest forwardingRequest;
        // mapping of initialized implementations
        mapping(address => bool) initializedImplementations;
        // mapping of relayer contracts on other chains
        mapping(uint16 => bytes32) registeredCoreRelayerContract;
        // mapping of delivered relayer VAAs
        mapping(bytes32 => bool) completedDeliveries;
        // storage gap to reduce risk of storage collisions
        uint256[50] ______gap;
    }
}

contract CoreRelayerState {
    CoreRelayerStorage.State _state;
}
