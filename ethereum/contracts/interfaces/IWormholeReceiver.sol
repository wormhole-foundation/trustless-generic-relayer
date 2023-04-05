// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeReceiver {
    function receiveWormholeMessages(bytes[] memory signedVaas) external payable;
}
