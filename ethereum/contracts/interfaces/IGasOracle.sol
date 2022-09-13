// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IGasOracle {
    //Returns the price of one unit of gas on the wormhole targetChain, denominated in this chain's wei.
    function getPrice(uint16 targetChainId) external view returns (uint256 quote);

    function updatePrice(uint16 chainId, uint256 gasPrice, uint256 nativeCurrencyPrice) external;
}
