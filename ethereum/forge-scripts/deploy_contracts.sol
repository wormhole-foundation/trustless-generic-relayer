// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Migrations} from "wormhole/ethereum/contracts/Migrations.sol";
import {IWormhole} from "contracts/interfaces/IWormhole.sol";
import {GasOracle} from "contracts/gasOracle/GasOracle.sol";
import {CoreRelayerSetup} from "contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "contracts/coreRelayer/CoreRelayerProxy.sol";
import {MockRelayerIntegration} from "contracts/mock/MockRelayerIntegration.sol";

import "forge-std/console.sol";

contract ContractScript is Script {
    Migrations migrations;
    IWormhole wormhole;

    // GasOracle
    GasOracle gasOracle;

    // CoreRelayer
    CoreRelayerSetup coreRelayerSetup;
    CoreRelayerImplementation coreRelayerImplementation;
    CoreRelayerProxy coreRelayerProxy;

    // MockRelayerIntegration
    MockRelayerIntegration mockRelayerIntegration;

    function setUp() public {
        migrations = Migrations(0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab);
        wormhole = IWormhole(0xC89Ce4735882C9F0f0FE26686c53074E09B0D550);
    }

    function deployGasOracle() public {
        // deploy GasOracle
        gasOracle = new GasOracle(address(wormhole));

        // following is used just to roll to the next block
        migrations.setCompleted(69);
    }

    function deployCoreRelayer() public {
        // first Setup
        coreRelayerSetup = new CoreRelayerSetup();

        // next Implementation
        coreRelayerImplementation = new CoreRelayerImplementation();

        // setup Proxy using Implementation
        coreRelayerProxy = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,uint8,address,uint32)")),
                address(coreRelayerImplementation),
                wormhole.chainId(),
                address(wormhole),
                uint8(1), // consistencyLevel
                address(gasOracle),
                uint32(0) // EVMGasOverhead
            )
        );

        // following is used just to roll to the next block
        migrations.setCompleted(69);
    }

    function deployMockRelayerIntegration() public {
        // deploy the mock integration contract
        mockRelayerIntegration = new MockRelayerIntegration(
            address(wormhole),
            address(coreRelayerProxy)
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // GasOracle.sol
        deployGasOracle();

        // CoreRelayer.sol
        deployCoreRelayer();

        // MockRelayerIntegration.sol
        deployMockRelayerIntegration();

        // finished
        vm.stopBroadcast();
    }
}
