// contracts/Setup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "./GasOracleGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract GasOracleSetup is GasOracleSetters, ERC1967Upgrade {
    function setup(address implementation, address owner, address wormhole, uint16 srcChainId) public {
        setupInitialState(owner, wormhole, srcChainId);

        require(implementation != address(0), "implementation == address(0)");
        _upgradeTo(implementation);
    }

    function setupInitialState(address owner, address wormhole, uint16 srcChainId) internal {
        require(owner != address(0), "owner == address(0)");
        setOwner(owner);
        require(srcChainId > 0, "srcChainId == 0");
        setChainId(srcChainId);
        // might use this later to consume price data via VAAs?
        require(wormhole != address(0), "wormhole == address(0)");
        setWormhole(wormhole);
    }
}
