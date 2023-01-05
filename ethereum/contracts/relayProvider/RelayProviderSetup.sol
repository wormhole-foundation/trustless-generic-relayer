// contracts/Setup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "./RelayProviderGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract RelayProviderSetup is RelayProviderSetters, ERC1967Upgrade {
    function setup(
        address implementation,
        uint16 chainId
    ) public {
        // sanity check initial values
        require(implementation != address(0), "implementation cannot be address(0)");

        setOwner(_msgSender());

        setChainId(chainId);

        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
