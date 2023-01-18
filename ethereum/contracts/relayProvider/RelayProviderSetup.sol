// contracts/Setup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./RelayProviderGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract RelayProviderSetup is RelayProviderSetters, ERC1967Upgrade {
    /// @notice Attempted to call function setup with implementation=address(0).
    error ImplementationAddressIsZero();
    /// @notice Failed to initialize the implementation behind the proxy.
    /// @param reason A string that further identifies the cause of failure.
    error FailedToInitializeImplementation(string reason);

    function setup(address implementation, uint16 chainId) public {
        // sanity check initial values
        if (implementation == address(0)) {
            revert ImplementationAddressIsZero();
        }

        setOwner(_msgSender());

        setChainId(chainId);

        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        if (!success) {
            revert FailedToInitializeImplementation(string(reason));
        }
    }
}
