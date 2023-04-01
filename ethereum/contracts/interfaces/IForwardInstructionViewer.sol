// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "../coreRelayer/CoreRelayerStructs.sol";

interface IForwardInstructionViewer {
    function getForwardingInstruction() external payable returns (CoreRelayerStructs.ForwardInstruction memory);
}
