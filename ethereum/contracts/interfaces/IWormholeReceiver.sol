// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeReceiver {
    struct DeliveryData {
        bytes32 sourceAddress;
        uint16 sourceChain;
        uint256 maximumRefund;
        bytes32 deliveryHash;
        bytes payload;
    }

    /**
     * @notice When a 'send' or 'forward' is performed with this contract as the target, this function will be invoked by the WormholeDelivery contract.
     * 
     * NOTE: This function must be restricted such that only the WormholeDelivery contract may call it.
     * 
     * Deliveries should be expected to be performed *at least once*, and potentially multiple times. NOTE: This function should also only be callable by the 
     * WormholeDelivery address for the chain it's deployed on, otherwise callers could potentially bypass the delivery logic, which would prevent the 
     * refund and forwarding mechanisms from functioning.
     * 
     * msg.value for this call will be equal to the receiverValue specified in the send request.
     * 
     * @param deliveryData - This struct contains information about the delivery which is being performed.
     * - sourceAddress - the (wormhole format) address on the sending chain which requested this delivery. Any contract / wallet is able to initiate a delivery anywhere by default.
     * - sourceChain - the wormhole chain ID where this delivery was requested.
     * - maximumRefund - the maximum refund that can possibly be awarded at the end of this delivery, assuming no gas is used by receiveWormholeMessages.
     * - deliveryHash - the VAA hash of the deliveryVAA. If you do not want to potentially process this delivery multiple times, you should store this hash in state for replay protection.
     * - payload - an optional arbitrary message which was included in the delivery by the requester.
     * @param signedVaas - Additional VAAs which were requested to be included in this delivery. They are guaranteed to all be included and in the same order as was specified in the delivery request.
     * NOTE: These signedVaas are NOT verified by the Wormhole core contract prior to being provided to this call. 
     * Always make sure parseAndVerify is called on the Wormhole core contract before trusting the content of a raw VAA,
     * otherwise the VAA may be invalid or malicious.
     */
    function receiveWormholeMessages(DeliveryData memory deliveryData, bytes[] memory signedVaas) external payable;
}
