// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IForwardWrapper {
    function receiveWormholeMessages(bytes[] memory signedVaas, bytes[] memory additionalData) external payable;
}
