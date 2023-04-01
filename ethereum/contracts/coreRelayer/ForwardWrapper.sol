// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../interfaces/IWormholeReceiver.sol";
import "./CoreRelayerStructs.sol";

contract ForwardWrapper {
    
    IForwardInstructionViewer forwardInstructionViewer;
    error RequesterNotCoreRelayer();

    constructor(address _wormholeRelayer) {
        forwardInstructionViewer = IForwardInstructionViewer(_wormholeRelayer);
        locked = false;
    }

    function executeInstruction(DeliveryInstruction memory instruction, bytes[] memory encodedVMs) public returns (uint256 leftoverMaxTransactionFee, bool callSuceeded) {
        
        if(msg.sender != address(forwardInstructionViewer)) {
            revert RequesterNotCoreRelayer();
        }

        uint256 preGas = gasleft();

        // Calls the 'receiveWormholeMessages' endpoint on the contract 'instruction.targetAddress'
        // (with the gas limit and value specified in instruction, and 'encodedVMs' as the input)
        (bool callToTargetContractSucceeded,) = fromWormholeFormat(instruction.targetAddress).call{
            gas: instruction.executionParameters.gasLimit,
            value: instruction.receiverValueTarget
        }(abi.encodeCall(IWormholeReceiver.receiveWormholeMessages, (encodedVMs, new bytes[](0))));

        uint256 postGas = gasleft();

        // Calculate the amount of gas used in the call (upperbounding at the gas limit, which shouldn't have been exceeded)
        uint256 gasUsed = (preGas - postGas) > instruction.executionParameters.gasLimit
            ? instruction.executionParameters.gasLimit
            : (preGas - postGas);

        // Calculate the amount of maxTransactionFee to refund (multiply the maximum refund by the fraction of gas unused)
        uint256 transactionFeeRefundAmount = (instruction.executionParameters.gasLimit - gasUsed)
            * instruction.maximumRefundTarget / instruction.executionParameters.gasLimit;

        ForwardInstruction memory forwardingRequest = forwardInstructionViewer.getForwardInstruction();



    }

}
