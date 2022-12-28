// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IWormholeReceiver {
    // TODO: Take additional data?
    function receiveWormholeMessages(bytes[] memory vaas) external;
}
