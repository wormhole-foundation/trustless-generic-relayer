// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {IRelayProvider} from "../contracts/interfaces/IRelayProvider.sol";
import {RelayProvider} from "../contracts/relayProvider/RelayProvider.sol";
import {RelayProviderSetup} from "../contracts/relayProvider/RelayProviderSetup.sol";
import {RelayProviderImplementation} from "../contracts/relayProvider/RelayProviderImplementation.sol";
import {RelayProviderProxy} from "../contracts/relayProvider/RelayProviderProxy.sol";
import {RelayProviderMessages} from "../contracts/relayProvider/RelayProviderMessages.sol";
import {RelayProviderStructs} from "../contracts/relayProvider/RelayProviderStructs.sol";
import {IWormholeRelayer} from "../contracts/interfaces/IWormholeRelayer.sol";
import {IDelivery} from "../contracts/interfaces/IDelivery.sol";
import {CoreRelayer} from "../contracts/coreRelayer/CoreRelayer.sol";
import {CoreRelayerStructs} from "../contracts/coreRelayer/CoreRelayerStructs.sol";
import {CoreRelayerSetup} from "../contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "../contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "../contracts/coreRelayer/CoreRelayerProxy.sol";
import {CoreRelayerMessages} from "../contracts/coreRelayer/CoreRelayerMessages.sol";
import {CoreRelayerStructs} from "../contracts/coreRelayer/CoreRelayerStructs.sol";
import {CoreRelayerGovernance} from "../contracts/coreRelayer/CoreRelayerGovernance.sol";
import {MockGenericRelayer} from "./MockGenericRelayer.sol";
import {MockWormhole} from "../contracts/mock/MockWormhole.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";
import {WormholeSimulator, FakeWormholeSimulator} from "./WormholeSimulator.sol";
import {IWormholeReceiver} from "../contracts/interfaces/IWormholeReceiver.sol";
import {AttackForwardIntegration} from "../contracts/mock/AttackForwardIntegration.sol";
import {MockRelayerIntegration, Structs} from "../contracts/mock/MockRelayerIntegration.sol";
import {ForwardTester} from "./ForwardTester.sol";
import {TestHelpers} from "./TestHelpers.sol";
import "../contracts/libraries/external/BytesLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract WormholeRelayerGovernanceTests is Test {
    using BytesLib for bytes;

    TestHelpers helpers;

    bytes32 relayerModule = 0x000000000000000000000000000000000000000000436F726552656C61796572;

    function setUp() public {

        helpers = new TestHelpers();

  
    }

    struct GovernanceStack { 
        IRelayProvider relayProvider;
        IWormhole wormhole;
        WormholeSimulator wormholeSimulator;
        IWormholeRelayer wormholeRelayer;
        bytes message;
        IWormhole.VM preSignedMessage;
        bytes signed;
    }

    function fillInGovernanceStack(bytes memory message) internal returns (GovernanceStack memory stack) {
        stack.relayProvider = helpers.setUpRelayProvider(1);

        (stack.wormhole, stack.wormholeSimulator) = helpers.setUpWormhole(1);
        stack.wormholeRelayer = helpers.setUpCoreRelayer(1, stack.wormhole, address(stack.relayProvider));
        stack.message = message;
        stack.preSignedMessage = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: stack.wormhole.governanceChainId(),
            emitterAddress: stack.wormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: message,
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });
        stack.signed = stack.wormholeSimulator.encodeAndSignMessage(stack.preSignedMessage);
    }

    function testSetDefaultRelayProvider() public {
        IRelayProvider relayProviderA = helpers.setUpRelayProvider(1);
        IRelayProvider relayProviderB = helpers.setUpRelayProvider(1);
        IRelayProvider relayProviderC = helpers.setUpRelayProvider(1);
        (IWormhole wormhole, WormholeSimulator simulator) = helpers.setUpWormhole(1);

        IWormholeRelayer wormholeRelayer = helpers.setUpCoreRelayer(1, wormhole, address(relayProviderA));

        assertTrue(wormholeRelayer.getDefaultRelayProvider() == address(relayProviderA));

        bytes memory message = abi.encodePacked(
            relayerModule, uint8(3), uint16(1), wormholeRelayer.toWormholeFormat(address(relayProviderB))
        );
        IWormhole.VM memory preSignedMessage = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: wormhole.governanceChainId(),
            emitterAddress: wormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: message,
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });

        bytes memory signed = simulator.encodeAndSignMessage(preSignedMessage);

        CoreRelayerGovernance(address(wormholeRelayer)).setDefaultRelayProvider(signed);

        assertTrue(wormholeRelayer.getDefaultRelayProvider() == address(relayProviderB));

        message = abi.encodePacked(
            relayerModule, uint8(3), uint16(1), wormholeRelayer.toWormholeFormat(address(relayProviderC))
        );

        preSignedMessage = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: wormhole.governanceChainId(),
            emitterAddress: wormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: message,
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });

        signed = simulator.encodeAndSignMessage(preSignedMessage);

        CoreRelayerGovernance(address(wormholeRelayer)).setDefaultRelayProvider(signed);

        assertTrue(wormholeRelayer.getDefaultRelayProvider() == address(relayProviderC));
    }

    function testRegisterChain() public {
        IRelayProvider relayProviderA = helpers.setUpRelayProvider(1);

        (IWormhole wormhole,) = helpers.setUpWormhole(1);

        IWormholeRelayer wormholeRelayer1 = helpers.setUpCoreRelayer(1, wormhole, address(relayProviderA));
        IWormholeRelayer wormholeRelayer2 = helpers.setUpCoreRelayer(1, wormhole, address(relayProviderA));
        IWormholeRelayer wormholeRelayer3 = helpers.setUpCoreRelayer(1, wormhole, address(relayProviderA));

        helpers.registerCoreRelayerContract(
            CoreRelayer(address(wormholeRelayer1)), wormhole, 1, 2, wormholeRelayer1.toWormholeFormat(address(wormholeRelayer2))
        );

        helpers.registerCoreRelayerContract(
            CoreRelayer(address(wormholeRelayer1)), wormhole,  1, 3, wormholeRelayer1.toWormholeFormat(address(wormholeRelayer3))
        );

        assertTrue(
            CoreRelayer(address(wormholeRelayer1)).registeredCoreRelayerContract(2)
                == wormholeRelayer1.toWormholeFormat(address(wormholeRelayer2))
        );

        assertTrue(
            CoreRelayer(address(wormholeRelayer1)).registeredCoreRelayerContract(3)
                == wormholeRelayer1.toWormholeFormat(address(wormholeRelayer3))
        );

        helpers.registerCoreRelayerContract(
            CoreRelayer(address(wormholeRelayer1)), wormhole, 1, 3, wormholeRelayer1.toWormholeFormat(address(wormholeRelayer2))
        );

        assertTrue(
            CoreRelayer(address(wormholeRelayer1)).registeredCoreRelayerContract(3)
                == wormholeRelayer1.toWormholeFormat(address(wormholeRelayer2))
        );
    }

    function testUpgradeContractToItself() public {
        IRelayProvider relayProvider = helpers.setUpRelayProvider(1);
        (IWormhole wormhole, WormholeSimulator simulator) = helpers.setUpWormhole(1);

        CoreRelayerSetup coreRelayerSetup = new CoreRelayerSetup();
        CoreRelayerImplementation coreRelayerImplementation = new CoreRelayerImplementation();
        CoreRelayerProxy myCoreRelayer = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeCall(
                CoreRelayerSetup.setup,
                (
                    address(coreRelayerImplementation),
                    1,
                    address(wormhole),
                    address(relayProvider),
                    wormhole.governanceChainId(),
                    wormhole.governanceContract(),
                    block.chainid
                )
            )
        );
        CoreRelayer wormholeRelayer = CoreRelayer(address(myCoreRelayer));

        for (uint256 i = 0; i < 10; i++) {
            CoreRelayerImplementation coreRelayerImplementationNew = new CoreRelayerImplementation();

            
            bytes memory message = abi.encodePacked(
                relayerModule,
                uint8(1),
                uint16(1),
                wormholeRelayer.toWormholeFormat(address(coreRelayerImplementationNew))
            );
            IWormhole.VM memory preSignedMessage = IWormhole.VM({
                version: 1,
                timestamp: uint32(block.timestamp),
                nonce: 0,
                emitterChainId: wormhole.governanceChainId(),
                emitterAddress: wormhole.governanceContract(),
                sequence: 0,
                consistencyLevel: 200,
                payload: message,
                guardianSetIndex: 0,
                signatures: new IWormhole.Signature[](0),
                hash: bytes32("")
            });

            bytes memory signed = simulator.encodeAndSignMessage(preSignedMessage);

            CoreRelayerGovernance(address(wormholeRelayer)).submitContractUpgrade(signed);
        }
    }
}
