// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

import "./RelayProviderState.sol";

contract RelayProviderSetters is Context, RelayProviderState {
    function setChainId(uint16 thisChain) internal {
        _state.chainId = thisChain;
    }


    function setOwner(address owner) internal {
        _state.owner = owner;
    }

    function setPendingOwner(address pendingOwner) internal {
        _state.pendingOwner = pendingOwner;
    }

    function setDeliverGasOverhead(uint16 chainId, uint32 deliverGasOverhead) internal {
        _state.deliverGasOverhead[chainId] = deliverGasOverhead;
    }

    function setWormholeFee(uint16 chainId, uint32 wormholeFee) internal {
        _state.wormholeFee[chainId] = wormholeFee;
    }

    function setRewardAddressInternal(uint16 chainId, bytes32 rewardAddress) internal {
        _state.rewardAddressMap[chainId] = rewardAddress;
    }

    function setMaximumBudget(uint16 targetChainId, uint256 amount) internal {
        _state.maximumBudget[targetChainId] = amount;
    }

    function setPriceInfo(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) internal {
        _state.data[updateChainId].gasPrice = updateGasPrice;
        _state.data[updateChainId].nativeCurrencyPrice = updateNativeCurrencyPrice;
    }
}
