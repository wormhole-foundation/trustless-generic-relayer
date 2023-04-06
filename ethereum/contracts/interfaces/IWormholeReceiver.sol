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

    function receiveWormholeMessages(DeliveryData memory deliveryInfo, bytes[] memory signedVaas) external payable;

}
