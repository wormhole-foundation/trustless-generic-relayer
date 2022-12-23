// contracts/Setup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "./CoreRelayerGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract CoreRelayerSetup is CoreRelayerSetters, ERC1967Upgrade {
    function setup(
        address implementation,
        uint16 chainId,
        address wormhole,
        address defaultRelayProvider
    ) public {
        // sanity check initial values
        require(implementation != address(0), "implementation cannot be address(0)");
        require(wormhole != address(0), "wormhole cannot be address(0)");
        require(defaultRelayProvider != address(0), "default relay provider cannot be address(0)");

        setOwner(_msgSender());

        setChainId(chainId);

        setWormhole(wormhole);

        setRelayProvider(defaultRelayProvider);

        setRegisteredCoreRelayerContract(chainId, bytes32(uint256(uint160(address(this)))));

        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
