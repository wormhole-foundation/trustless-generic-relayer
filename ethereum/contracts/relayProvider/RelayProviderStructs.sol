// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

abstract contract RelayProviderStructs {
    struct UpdatePrice {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        /**
         * Gas price in ´chainId´ chain.
         */
        uint128 gasPrice;
        /**
         * Price of the native currency in ´chainId´ chain.
         * Native currency is typically used to pay for gas.
         */
        uint128 nativeCurrencyPrice;
    }

    struct SenderApprovalUpdate {
        /**
         * Sender address
         */
        address sender;
        /**
         * Whether the ´sender´ address is approved to relay VAAs.
         */
        bool approved;
    }

    struct DeliveryAddressUpdate {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        /**
         * Wormhole address of the relay provider in the ´chainId´ chain.
         */
        bytes32 newAddress;
    }

    struct MaximumBudgetUpdate {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        /**
         * Maximum total budget for a delivery in ´chainId´ chain.
         */
        uint256 maximumTotalBudget;
    }

    struct WormholeFeeUpdate {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        /**
         * Wormhole fee for ´chainId´ chain.
         */
        uint32 newWormholeFee;
    }

    struct DeliverGasOverheadUpdate {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        /**
         * The gas overhead for a delivery in ´chainId´ chain.
         */
        uint32 newGasOverhead;
    }

    struct AssetConversionBufferUpdate {
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        // See RelayProviderState.AssetConversion
        uint16 buffer;
        uint16 bufferDenominator;
    }

    struct Update {
        bool updateAssetConversionBuffer;
        bool updateWormholeFee;
        bool updateDeliverGasOverhead;
        bool updatePrice;
        bool updateDeliveryAddress;
        bool updateMaximumBudget;
        /**
         * Wormhole chain id
         */
        uint16 chainId;
        // AssetConversionBufferUpdate
        // See RelayProviderState.AssetConversion
        uint16 buffer;
        uint16 bufferDenominator;
        // WormholeFeeUpdate
        /**
         * Wormhole fee for ´chainId´ chain.
         */
        uint32 newWormholeFee;
        // DeliverGasOverheadUpdate
        /**
         * The gas overhead for a delivery in ´chainId´ chain.
         */
        uint32 newGasOverhead;
        // UpdatePrice
        /**
         * Gas price in ´chainId´ chain.
         */
        uint128 gasPrice;
        /**
         * Price of the native currency in ´chainId´ chain.
         * Native currency is typically used to pay for gas.
         */
        uint128 nativeCurrencyPrice;
        // DeliveryAddressUpdate
        /**
         * Wormhole address of the relay provider in the ´chainId´ chain.
         */
        bytes32 newAddress;
        // MaximumBudgetUpdate
        /**
         * Maximum total budget for a delivery in ´chainId´ chain.
         */
        uint256 maximumTotalBudget;
    }

    struct CoreConfig {
        bool updateCoreRelayer;
        bool updateRewardAddress;
        /**
         * Address of the CoreRelayer contract
         */
        address coreRelayer;
        /**
         * Address where rewards are sent for successful relays and sends
         */
        address payable rewardAddress;
    }
}
