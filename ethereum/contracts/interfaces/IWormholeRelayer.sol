// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeRelayer {
    /**
     * @dev This is the basic function for requesting delivery
     */
    function send(
        uint16 targetChain,
        bytes32 targetAddress,
        bytes32 refundAddress,
        uint256 maxTransactionFee,
        uint256 receiverValue,
        uint32 nonce
    )
        external
        payable
        returns (uint64 sequence);

    function forward(
        uint16 targetChain,
        bytes32 targetAddress,
        bytes32 refundAddress,
        uint256 maxTransactionFee,
        uint256 receiverValue,
        uint32 nonce
    )
        external
        payable;

    function send(Send memory request, uint32 nonce, address relayProvider)
        external
        payable
        returns (uint64 sequence);

    function forward(Send memory request, uint32 nonce, address relayProvider) external payable;

    function resend(ResendByTx memory request, uint32 nonce, address relayProvider)
        external
        payable
        returns (uint64 sequence);

    function multichainSend(MultichainSend memory deliveryRequests, uint32 nonce)
        external
        payable
        returns (uint64 sequence);

    /**
     * @dev When requesting a multiforward, the rollover chain is the chain where any remaining funds should be sent once all
     * the requested budgets have been covered. The remaining funds will be added to the computeBudget of the rollover chain.
     */
    function multichainForward(MultichainSend memory deliveryRequests, uint16 rolloverChain, uint32 nonce)
        external
        payable;

    function toWormholeFormat(address addr) external pure returns (bytes32 whFormat);

    function fromWormholeFormat(bytes32 whFormatAddress) external pure returns (address addr);

    function getDefaultRelayProvider() external view returns (address relayProvider);

    function getDefaultRelayParams() external pure returns (bytes memory relayParams);

    function quoteGas(uint16 targetChain, uint32 gasLimit, address relayProvider)
        external
        pure
        returns (uint256 maxTransactionFee);

    function quoteGasResend(uint16 targetChain, uint32 gasLimit, address relayProvider)
        external
        pure
        returns (uint256 maxTransactionFee);

    function quoteReceiverValue(uint16 targetChain, uint256 targetAmount, address relayProvider)
        external
        pure
        returns (uint256 nativeQuote);

    struct MultichainSend {
        address relayProviderAddress;
        Send[] requests;
    }

    /**
     * targetChain - the chain to send to in Wormhole Chain ID format.
     * targetAddress - is the recipient contract address on the target chain (in Wormhole 32-byte address format).
     * refundAddress - is the address where any remaining computeBudget should be sent at the end of the transaction. (In Wormhole address format. Must be on the target chain.)
     * computeBudget - is the maximum amount (denominated in this chain's wei) that the relayer should spend on transaction fees (gas) for this delivery. Usually calculated from quoteEvmDeliveryPrice.
     * applicationBudget - this amount (denominated in this chain's wei) will be converted to the target native currency and given to the recipient contract at the beginning of the delivery execution.
     * relayParameters - optional payload which can alter relayer behavior.
     */
    struct Send {
        uint16 targetChain;
        bytes32 targetAddress;
        bytes32 refundAddress;
        uint256 maxTransactionFee;
        uint256 receiverValue;
        bytes relayParameters; 
    }

    struct ResendByTx {
        uint16 sourceChain;
        bytes32 sourceTxHash;
        uint32 sourceNonce;
        uint16 targetChain;
        uint8 deliveryIndex;
        uint8 multisendIndex;
        uint256 newMaxTransactionFee;
        uint256 newReceiverValue;
        bytes newRelayParameters;
    }

    error InsufficientFunds(string reason);
    error MsgValueTooLow(); // msg.value must cover the budget specified
    error NonceIsZero();
    error NoDeliveryInProcess();
    error MultipleForwardsRequested();
    error RelayProviderDoesNotSupportTargetChain();
    error RolloverChainNotIncluded(); // Rollover chain was not included in the forwarding request
    error ChainNotFoundInDeliveryRequests(uint16 chainId); // Required chain not found in the delivery requests
    error ReentrantCall();
}
