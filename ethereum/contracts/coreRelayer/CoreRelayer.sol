// contracts/Bridge.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeRelayer.sol";
import "./CoreRelayerDelivery.sol";
import "./CoreRelayerStructs.sol";

contract CoreRelayer is CoreRelayerDelivery {

    function send(IWormholeRelayer.Send memory request, uint32 nonce, address relayProvider)
        public
        payable
        returns (uint64 sequence)
    {
        return multichainSend(multichainSendContainer(request, relayProvider), nonce);
    }

    function forward(IWormholeRelayer.Send memory request, uint32 nonce, address relayProvider) public payable {
        return multichainForward(multichainSendContainer(request, relayProvider), nonce);
    }

    function resend(IWormholeRelayer.ResendByTx memory request, uint32 nonce, address relayProvider)
        public
        payable
        returns (uint64 sequence)
    {
        updateWormholeMessageFee();
        bool isSufficient = request.newMaxTransactionFee + request.newReceiverValue + wormholeMessageFee() <= msg.value;
        if (!isSufficient) {
            revert IWormholeRelayer.MsgValueTooLow();
        }

        IRelayProvider provider = IRelayProvider(relayProvider);
        RedeliveryByTxHashInstruction memory instruction = convertResendToRedeliveryInstruction(request, provider);
        checkRedeliveryInstruction(instruction, provider);

        sequence = wormhole().publishMessage{value: wormholeMessageFee()}(
            nonce, encodeRedeliveryInstruction(instruction), provider.getConsistencyLevel()
        );

        //Send the delivery fees to the specified address of the provider.
        pay(provider.getRewardAddress(), msg.value - wormholeMessageFee());
    }

    /**
     * TODO: Correct this comment
     * @dev `multisend` generates a VAA with DeliveryInstructions to be delivered to the specified target
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function multichainSend(IWormholeRelayer.MultichainSend memory deliveryRequests, uint32 nonce)
        public
        payable
        returns (uint64 sequence)
    {
        updateWormholeMessageFee();
        uint256 totalFee = getTotalFeeMultichainSend(deliveryRequests);
        if (totalFee > msg.value) {
            revert IWormholeRelayer.MsgValueTooLow();
        }
        if (nonce == 0) {
            revert IWormholeRelayer.NonceIsZero();
        }

        IRelayProvider relayProvider = IRelayProvider(deliveryRequests.relayProviderAddress);
        DeliveryInstructionsContainer memory container =
            convertMultichainSendToDeliveryInstructionsContainer(deliveryRequests);
        checkInstructions(container, IRelayProvider(deliveryRequests.relayProviderAddress));
        container.sufficientlyFunded = true;

        // emit delivery message
        sequence = wormhole().publishMessage{value: wormholeMessageFee()}(
            nonce, encodeDeliveryInstructionsContainer(container), relayProvider.getConsistencyLevel()
        );

        //pay fee to provider
        pay(relayProvider.getRewardAddress(), totalFee - wormholeMessageFee());
    }

    /**
     * TODO correct this comment
     * @dev `forward` queues up a 'send' which will be executed after the present delivery is complete
     * & uses the gas refund to cover the costs.
     * contract based on user parameters.
     * it parses the RelayParameters to determine the target chain ID
     * it estimates the cost of relaying the batch
     * it confirms that the user has passed enough value to pay the relayer
     * it checks that the passed nonce is not zero (VAAs with a nonce of zero will not be batched)
     * it generates a VAA with the encoded DeliveryInstructions
     */
    function multichainForward(IWormholeRelayer.MultichainSend memory deliveryRequests, uint32 nonce) public payable {
        if (!isContractLocked()) {
            revert IWormholeRelayer.NoDeliveryInProgress();
        }
        if (getForwardInstruction().isValid) {
            revert IWormholeRelayer.MultipleForwardsRequested();
        }
        if (nonce == 0) {
            revert IWormholeRelayer.NonceIsZero();
        }
        if (msg.sender != lockedTargetAddress()) {
            revert IWormholeRelayer.ForwardRequestFromWrongAddress();
        }

        uint256 totalFee = getTotalFeeMultichainSend(deliveryRequests);
        DeliveryInstructionsContainer memory container =
            convertMultichainSendToDeliveryInstructionsContainer(deliveryRequests);
        checkInstructions(container, IRelayProvider(deliveryRequests.relayProviderAddress));

        setForwardInstruction(
            ForwardInstruction({
                container: container,
                nonce: nonce,
                msgValue: msg.value,
                totalFee: totalFee,
                sender: msg.sender,
                relayProvider: deliveryRequests.relayProviderAddress,
                isValid: true
            })
        );
    }


    function multichainSendContainer(IWormholeRelayer.Send memory request, address relayProvider)
        internal
        pure
        returns (IWormholeRelayer.MultichainSend memory container)
    {
        IWormholeRelayer.Send[] memory requests = new IWormholeRelayer.Send[](1);
        requests[0] = request;
        container = IWormholeRelayer.MultichainSend({relayProviderAddress: relayProvider, requests: requests});
    }

    function getDefaultRelayProvider() public view returns (IRelayProvider) {
        return defaultRelayProvider();
    }

    function getDefaultRelayParams() public pure returns (bytes memory relayParams) {
        return new bytes(0);
    }

    function quoteGas(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 deliveryQuote)
    {
        deliveryQuote = provider.quoteDeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain));
    }

    function quoteGasResend(uint16 targetChain, uint32 gasLimit, IRelayProvider provider)
        public
        view
        returns (uint256 redeliveryQuote)
    {
        redeliveryQuote =
            provider.quoteRedeliveryOverhead(targetChain) + (gasLimit * provider.quoteGasPrice(targetChain));
    }

    //If the integrator pays at least nativeQuote, they should receive at least targetAmount as their application budget
    function quoteReceiverValue(uint16 targetChain, uint256 targetAmount, IRelayProvider provider)
        public
        view
        returns (uint256 nativeQuote)
    {
        (uint16 buffer, uint16 denominator) = provider.getAssetConversionBuffer(targetChain);
        nativeQuote = assetConversionHelper(
            targetChain, targetAmount, chainId(), uint256(0) + denominator + buffer, denominator, true, provider
        );
    }
}
