// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Migrations} from "wormhole/ethereum/contracts/Migrations.sol";
import {Setup} from "wormhole/ethereum/contracts/Setup.sol";
import {Implementation} from "wormhole/ethereum/contracts/Implementation.sol";
import {Wormhole} from "wormhole/ethereum/contracts/Wormhole.sol";

import "forge-std/console.sol";

contract ContractScript is Script {
    Migrations migrations;
    Setup setup;
    Implementation implementation;
    Wormhole wormhole;

    function setUp() public {}

    function deployMigrations() public {
        migrations = new Migrations();

        // following is used just to roll to the next block
        migrations.setCompleted(1);
    }

    function deployWormhole() public {
        // deploy Setup
        setup = new Setup();

        // deploy Implementation
        implementation = new Implementation();

        address[] memory guardians = new address[](1);
        guardians[0] = 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe;

        // deploy Wormhole
        wormhole = new Wormhole(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address[],uint16,uint16,bytes32,uint256)")),
                address(implementation),
                guardians,
                uint16(2), // wormhole chain id
                uint16(1), // governance chain id
                0x0000000000000000000000000000000000000000000000000000000000000004, // governance contract
                block.chainid // evm chain id
            )
        );

        // following is used just to roll to the next block
        migrations.setCompleted(2);
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // Migrations.sol
        deployMigrations();

        // Setup.sol, Implementation.sol, Wormhole.sol
        deployWormhole();

        // TODO: Token Bridge, NFT Bridge

        // finish
        vm.stopBroadcast();
    }
}
