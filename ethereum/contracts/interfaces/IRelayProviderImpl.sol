// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "./IRelayProvider.sol";

interface IRelayProviderImpl {

    function setRewardAddress(uint16 targetChain, bytes32 newRewardAddress) external;

    function updatePrice(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) external;

    struct UpdatePrice {
        uint16 chainId;
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }

    function updatePrices(UpdatePrice[] memory updates) external;

    function updateDeliverGasOverhead(uint16 chainId, uint32 newGasOverhead) external;

    function updateMaximumBudget(uint16 targetChainId, uint256 maximumTotalBudget) external;

    function updateWormholeFee(uint16 chainId, uint32 newWormholeFee) external;

}
