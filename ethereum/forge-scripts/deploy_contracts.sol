// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Migrations} from "wormhole/ethereum/contracts/Migrations.sol";
import {IWormhole} from "contracts/interfaces/IWormhole.sol";
import {GasOracle} from "contracts/gasOracle/GasOracle.sol";

import "forge-std/console.sol";

contract ContractScript is Script {
    Migrations migrations;
    IWormhole wormhole;
    GasOracle gasOracle;

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
        // TODO

        // following is used just to roll to the next block
        migrations.setCompleted(69);
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // GasOracle.sol
        deployGasOracle();

        // CoreRelayer.sol
        deployCoreRelayer();

        // finished
        vm.stopBroadcast();
    }
}
