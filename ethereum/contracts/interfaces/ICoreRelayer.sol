// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "./IRelayProvider.sol";

interface ICoreRelayer {
    
    /**
    * @dev This is the basic function for requesting delivery
    */
    function requestDelivery(DeliveryRequest memory request, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function requestForward(DeliveryRequest memory request, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) external;

    function requestRedelivery(RedeliveryByTxHashRequest memory request, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function requestMultidelivery(DeliveryRequestsContainer memory deliveryRequests, uint32 nonce, uint8 consistencyLevel) external payable returns (uint64 sequence);

    /**
    @dev When requesting a multiforward, the rollover chain is the chain where any remaining funds should be sent once all
        the requested budgets have been covered. The remaining funds will be added to the computeBudget of the rollover chain.
     */
    function requestMultiforward(DeliveryRequestsContainer memory deliveryRequests, uint16 rolloverChain, uint32 nonce, uint8 consistencyLevel) external;

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams) external payable returns (uint64 sequence);

    function redeliverSingle(TargetRedeliveryByTxHashParamsSingle memory targetParams) external payable returns (uint64 sequence);

    function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) external payable returns (uint64 sequence);

    function collectRewards(bytes memory encodedVm) external;

    function getDefaultRelayProvider() external returns (IRelayProvider);

    function toWormholeFormat(address addr) external pure returns (bytes32 whFormat);

    function fromWormholeFormat(bytes32 whFormatAddress) external pure returns(address addr);
    
    function getDefaultRelayParams() external pure returns(bytes memory relayParams);

    function makeRelayerParams(address relayProvider) external pure returns(bytes memory relayerParams);

    function getDeliveryInstructionsContainer(bytes memory encoded) external view returns (DeliveryInstructionsContainer memory container);

    struct DeliveryRequestsContainer {
        uint8 payloadId; // payloadID = 1
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

    struct RedeliveryByTxHashRequest {
        uint16 sourceChain;
        bytes32 sourceTxHash;
        uint32 sourceNonce; 
        uint16 targetChain;
        uint256 newComputeBudget; 
        uint256 newApplicationBudget;
        bytes newRelayParameters;
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

    struct TargetRedeliveryByTxHashParamsSingle {
        bytes redeliveryVM;
        bytes[] sourceEncodedVMs;
        uint8 deliveryIndex;
        uint8 multisendIndex;
    }

    struct RelayParameters {
        uint8 version; //1
        bytes32 oracleAddressOverride;
    }

    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bool sufficientlyFunded; 
        DeliveryInstruction[] instructions;
    }

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 computeBudgetTarget;
        uint256 applicationBudgetTarget;
        uint256 sourceReward;
        uint16 sourceChain;
        ExecutionParameters executionParameters; //Has the gas limit to execute with
    }
    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
        bytes32 relayerAddress;
    }

}
