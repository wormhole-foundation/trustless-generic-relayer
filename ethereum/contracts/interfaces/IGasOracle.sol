// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IGasOracle {
    function getPrice(uint16 targetChainId) external view returns (uint256 quote);
}
