// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "./IGasOracle.sol";

interface ICoreRelayer {
    
    /**
    * @dev This is the basic function for requesting delivery
    */
    function requestDelivery(DeliveryRequest memory request, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function requestForward(DeliveryRequest memory request, uint16 rolloverChainId, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function requestRedelivery(bytes32 transactionHash, uint32 originalNonce, uint256 newComputeBudget, uint256 newNativeBudget, uint32 nonce, uint8 consistencyLevel, bytes memory relayParameters) external payable returns (uint64 sequence);

    function requestMultidelivery(DeliveryRequestsContainer memory deliveryRequests, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    /**
    @dev When requesting a multiforward, the rollover chain is the chain where any remaining funds should be sent once all
        the requested budgets have been covered. The remaining funds will be added to the computeBudget of the rollover chain.
     */
    function requestMultiforward(DeliveryRequestsContainer memory deliveryRequests, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function deliver(TargetDeliveryParameters memory targetParams) external payable returns (uint64 sequence);

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams) external payable returns (uint64 sequence);

    function redeliver(TargetDeliveryParameters memory targetParams, bytes memory encodedRedeliveryVm) external payable returns (uint64 sequence);

    function redeliverSingle(TargetDeliveryParametersSingle memory targetParams, bytes memory encodedRedeliveryVm) external payable returns (uint64 sequence);

    function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) external payable returns (uint64 sequence);

    function collectRewards(bytes memory encodedVm) external;

    function getDefaultRelayProvider() external returns (IGasOracle);

    function setDefaultGasOracle(address gasOracle) external;

    function registerCoreRelayer(uint16 chainId, bytes32 relayerAddress) external;

    struct DeliveryRequestsContainer {
        uint8 payloadID; // payloadID = 1
        DeliveryRequest[] requests;
    }

    /**
    *  targetChain - the chain to send to in Wormhole Chain ID format.
    *  targetAddress - is the recipient contract address on the target chain (in Wormhole 32-byte address format).
    *  refundAddress - is the address where any remaining computeBudget should be sent at the end of the transaction. (In Wormhole address format. Must be on the target chain.)
    *  computeBudget - is the maximum amount (denominated in this chain's wei) that the relayer should spend on transaction fees (gas) for this delivery. Usually calculated from quoteEvmDeliveryPrice.
    *  applicationBudget - this amount (denominated in this chain's wei) will be converted to the target native currency and given to the recipient contract at the beginning of the delivery execution.
    *  relayParameters - optional payload which can alter relayer behavior.
    */
    struct DeliveryRequest {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 computeBudget;
        uint256 applicationBudget;
        bytes relayParameters; //Optional
    }

    struct TargetDeliveryParameters {
        // encoded batchVM to be delivered on the target chain
        bytes encodedVM;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        // Index of the target chain inside the delivery VM
        uint8 multisendIndex;
        // Optional gasOverride which can be supplied by the relayer
        // uint32 targetCallGasOverride;
    }

    struct TargetDeliveryParametersSingle {
        // encoded batchVM to be delivered on the target chain
        bytes[] encodedVMs;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        // Index of the target chain inside the delivery VM
        uint8 multisendIndex;
        // Optional gasOverride which can be supplied by the relayer
       // uint32 targetCallGasOverride;
    }

    struct RelayParameters {
        uint8 version; //1
        bytes32 oracleAddressOverride;
    }

}
