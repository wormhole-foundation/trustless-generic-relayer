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
        uint8 consistencyLevel,
        address gasOracle
    ) public {
        // sanity check initial values
        require(implementation != address(0), "implementation cannot be address(0)");
        require(wormhole != address(0), "wormhole cannot be address(0)");
        require(gasOracle != address(0), "gasOracle cannot be address(0)");

        setOwner(_msgSender());

        setConsistencyLevel(consistencyLevel);

        setChainId(chainId);

        setWormhole(wormhole);

        setGasOracle(gasOracle);

        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
