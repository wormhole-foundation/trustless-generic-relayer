// contracts/State.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./WormholeRelayerStructs.sol";

contract WormholeRelayerStorage {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        uint256 wormholeMessageFee;
        uint16 governanceChainId;
        bytes32 governanceContract;
    }

    struct State {
        Provider provider;
        // delivery lock for reentrancy protection
        bool contractLock;
        // the target address that is currently being delivered to (if contractLock = true)
        address targetAddress;
        // EIP-155 Chain ID
        uint256 evmChainId;
        // consumed governance VAAs
        mapping(bytes32 => bool) consumedGovernanceActions;
        // address of the default relay provider on this chain
        address defaultRelayProvider;
        // Request which will be forwarded from the current delivery.
        WormholeRelayerStructs.ForwardInstruction forwardInstruction;
        // mapping of initialized implementations
        mapping(address => bool) initializedImplementations;
        // mapping of relayer contracts on other chains
        mapping(uint16 => bytes32) registeredWormholeRelayerContract;
        // storage gap to reduce risk of storage collisions
        uint256[50] ______gap;
    }
}

contract WormholeRelayerState {
    WormholeRelayerStorage.State _state;
}
