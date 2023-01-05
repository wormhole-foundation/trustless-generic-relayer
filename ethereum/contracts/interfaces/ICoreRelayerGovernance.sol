// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
import "./IRelayProvider.sol";

interface ICoreRelayerGovernance {
    
    function setDefaultRelayProvider(address relayProvider) external;

    function registerCoreRelayerContract(uint16 chainId, bytes32 relayerAddress) external;

}
