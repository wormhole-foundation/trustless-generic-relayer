// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./IRelayProvider.sol";

interface ICoreRelayer {
    /**
     * @dev This is the basic function for requesting delivery
     */
    function requestDelivery(DeliveryRequest memory request, uint32 nonce, IRelayProvider provider)
        external
        payable
        returns (uint64 sequence);

    function requestForward(DeliveryRequest memory request, uint16 rolloverChain, uint32 nonce, IRelayProvider provider)
        external
        payable;

    function requestRedelivery(RedeliveryByTxHashRequest memory request, uint32 nonce, IRelayProvider provider)
        external
        payable
        returns (uint64 sequence);

    function requestMultidelivery(DeliveryRequestsContainer memory deliveryRequests, uint32 nonce)
        external
        payable
        returns (uint64 sequence);

    /**
     * @dev When requesting a multiforward, the rollover chain is the chain where any remaining funds should be sent once all
     *     the requested budgets have been covered. The remaining funds will be added to the computeBudget of the rollover chain.
     */
    function requestMultiforward(
        DeliveryRequestsContainer memory deliveryRequests,
        uint16 rolloverChain,
        uint32 nonce,
        IRelayProvider provider
    ) external payable;

    function deliverSingle(TargetDeliveryParametersSingle memory targetParams) external payable;

    function redeliverSingle(TargetRedeliveryByTxHashParamsSingle memory targetParams) external payable;

    // function requestRewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) external payable returns (uint64 sequence);

    // function collectRewards(bytes memory encodedVm) external;

    function toWormholeFormat(address addr) external pure returns (bytes32 whFormat);

    function fromWormholeFormat(bytes32 whFormatAddress) external pure returns (address addr);

    function getDefaultRelayProvider() external returns (IRelayProvider);

    function getDefaultRelayParams() external pure returns (bytes memory relayParams);

    function quoteGasDeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider relayProvider)
        external
        pure
        returns (uint256 deliveryQuote);

    function quoteGasRedeliveryFee(uint16 targetChain, uint32 gasLimit, IRelayProvider relayProvider)
        external
        pure
        returns (uint256 redeliveryQuote);

    function quoteApplicationBudgetFee(uint16 targetChain, uint256 targetAmount, IRelayProvider provider)
        external
        pure
        returns (uint256 nativeQuote);

    function getDeliveryInstructionsContainer(bytes memory encoded)
        external
        view
        returns (DeliveryInstructionsContainer memory container);

    function getRedeliveryByTxHashInstruction(bytes memory encoded)
        external
        view
        returns (RedeliveryByTxHashInstruction memory instruction);

    struct DeliveryRequestsContainer {
        uint8 payloadId; // payloadID = 1
        address relayProviderAddress;
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
        //refund address
        address payable relayerRefundAddress;
    }
    // Optional gasOverride which can be supplied by the relayer
    // uint32 targetCallGasOverride;

    struct TargetDeliveryParametersSingle {
        // encoded batchVM to be delivered on the target chain
        bytes[] encodedVMs;
        // Index of the delivery VM in a batch
        uint8 deliveryIndex;
        // Index of the target chain inside the delivery VM
        uint8 multisendIndex;
        //refund address
        address payable relayerRefundAddress;
    }
    // Optional gasOverride which can be supplied by the relayer
    // uint32 targetCallGasOverride;

    struct TargetRedeliveryByTxHashParamsSingle {
        bytes redeliveryVM;
        bytes[] sourceEncodedVMs;
        uint8 deliveryIndex;
        uint8 multisendIndex;
        address payable relayerRefundAddress;
    }

    //REVISE consider removing this, or keeping for future compatibility
    // struct RelayParameters {
    // }

    struct DeliveryInstructionsContainer {
        uint8 payloadId; //1
        bool sufficientlyFunded;
        DeliveryInstruction[] instructions;
    }

    struct DeliveryInstruction {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 maximumRefundTarget;
        uint256 applicationBudgetTarget;
        ExecutionParameters executionParameters; //Has the gas limit to execute with
    }

    struct RedeliveryByTxHashInstruction {
        uint8 payloadId; //2
        uint16 sourceChain;
        bytes32 sourceTxHash;
        uint32 sourceNonce;
        uint16 targetChain;
        uint256 newMaximumRefundTarget;
        uint256 newApplicationBudgetTarget;
        ExecutionParameters executionParameters;
    }

    struct ExecutionParameters {
        uint8 version;
        uint32 gasLimit;
        bytes32 providerDeliveryAddress;
    }
}
