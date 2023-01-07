// contracts/Setup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "./CoreRelayerGovernance.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract CoreRelayerSetup is CoreRelayerSetters, ERC1967Upgrade {
    function setup(address implementation, uint16 chainId, address wormhole, address defaultRelayProvider, uint16 governanceChainId, bytes32 governanceContract, uint256 evmChainId) public {
        // sanity check initial values
        require(implementation != address(0), "1"); //"implementation cannot be address(0)");
        require(wormhole != address(0), "2"); //wormhole cannot be address(0)");
        require(defaultRelayProvider != address(0), "3"); //default relay provider cannot be address(0)");

        setChainId(chainId);

        setWormhole(wormhole);

        setRelayProvider(defaultRelayProvider);

        setGovernanceChainId(governanceChainId);
        setGovernanceContract(governanceContract);
        setEvmChainId(evmChainId);

        //setRegisteredCoreRelayerContract(chainId, bytes32(uint256(uint160(address(this)))));

        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
