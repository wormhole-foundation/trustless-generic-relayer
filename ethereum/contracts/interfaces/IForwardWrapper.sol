// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../coreRelayer/CoreRelayerStructs.sol";

interface IForwardWrapper {
    function executeInstruction(CoreRelayerStructs.DeliveryInstruction memory instruction, bytes[] memory signedVaas)
        external
        payable
        returns (bool callToTargetContractSucceeded, uint256 transactionFeeRefundAmount);
}
