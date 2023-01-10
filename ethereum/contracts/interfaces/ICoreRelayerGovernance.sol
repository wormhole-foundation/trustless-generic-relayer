// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./IRelayProvider.sol";

interface ICoreRelayerGovernance {
    function setDefaultRelayProvider(bytes memory vaa) external;

    function registerCoreRelayerContract(bytes memory vaa) external;
}
