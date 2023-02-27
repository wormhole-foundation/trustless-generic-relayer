// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./WormholeRelayerState.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./WormholeRelayerStructs.sol";
import {IWormhole} from "../interfaces/IWormhole.sol";

contract WormholeRelayerSetters is WormholeRelayerState, Context {
    error InvalidEvmChainId();

    function setInitialized(address implementation) internal {
        _state.initializedImplementations[implementation] = true;
    }

    function setConsumedGovernanceAction(bytes32 hash) internal {
        _state.consumedGovernanceActions[hash] = true;
    }

    function setGovernanceChainId(uint16 chainId) internal {
        _state.provider.governanceChainId = chainId;
    }

    function setGovernanceContract(bytes32 governanceContract) internal {
        _state.provider.governanceContract = governanceContract;
    }

    function setChainId(uint16 chainId_) internal {
        _state.provider.chainId = chainId_;
    }

    function setWormhole(address wh) internal {
        _state.provider.wormhole = payable(wh);
    }

    function updateWormholeMessageFee() internal {
        _state.provider.wormholeMessageFee = IWormhole(_state.provider.wormhole).messageFee();
    }

    function setRelayProvider(address defaultRelayProvider) internal {
        _state.defaultRelayProvider = defaultRelayProvider;
    }

    function setRegisteredWormholeRelayerContract(uint16 chainId, bytes32 relayerAddress) internal {
        _state.registeredWormholeRelayerContract[chainId] = relayerAddress;
    }

    function setForwardInstruction(WormholeRelayerStructs.ForwardInstruction memory request) internal {
        _state.forwardInstruction = request;
    }

    function clearForwardInstruction() internal {
        delete _state.forwardInstruction;
    }

    function setContractLock(bool status) internal {
        _state.contractLock = status;
    }

    function setLockedTargetAddress(address targetAddress) internal {
        _state.targetAddress = targetAddress;
    }

    function setEvmChainId(uint256 evmChainId) internal {
        if (evmChainId != block.chainid) {
            revert InvalidEvmChainId();
        }
        _state.evmChainId = evmChainId;
    }
}
