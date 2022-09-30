// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IGasOracle {
    function computeGasCost(uint16 targetChainId, uint256 gasLimit) external view returns (uint256 quote);

    function computeTransactionCost(uint16 targetChainId, uint256 transactionFee)
        external
        view
        returns (uint256 quote);
}
