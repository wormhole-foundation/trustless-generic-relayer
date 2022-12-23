// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/relayProvider/RelayProvider.sol";
import {ICoreRelayer} from "../contracts/interfaces/ICoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayerState.sol";
import {CoreRelayerSetup} from "../contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "../contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "../contracts/coreRelayer/CoreRelayerProxy.sol";
import {CoreRelayerMessages} from "../contracts/coreRelayer/CoreRelayerMessages.sol";
import {CoreRelayerStructs} from "../contracts/coreRelayer/CoreRelayerStructs.sol";
import {IRelayProvider} from "../contracts/interfaces/IRelayProvider.sol";
import {Setup as WormholeSetup} from "../wormhole/ethereum/contracts/Setup.sol";
import {Implementation as WormholeImplementation} from "../wormhole/ethereum/contracts/Implementation.sol";
import {Wormhole} from "../wormhole/ethereum/contracts/Wormhole.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";
import {IWormholeReceiver} from "../contracts/interfaces/IWormholeReceiver.sol";
import {MockRelayerIntegration} from "../contracts/mock/MockRelayerIntegration.sol";
import "../contracts/libraries/external/BytesLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract TestCoreRelayer is Test {
    using BytesLib for bytes;

    uint16 MAX_UINT16_VALUE = 65535;
    uint96 MAX_UINT96_VALUE = 79228162514264337593543950335;

    struct GasParameters {
        uint32 evmGasOverhead;
        uint32 targetGasLimit;
        uint64 targetGasPrice;
        uint64 targetNativePrice;
        uint64 sourceGasPrice;
        uint64 sourceNativePrice;
    }

    struct VMParams {
        uint32 nonce;
        uint8 consistencyLevel;
    }

    function setUpWormhole(uint16 chainId) internal returns (IWormhole wormholeContract, WormholeSimulator wormholeSimulator) {
         // deploy Setup
        WormholeSetup setup = new WormholeSetup();

        // deploy Implementation
        WormholeImplementation implementation = new WormholeImplementation();

        // set guardian set
        address[] memory guardians = new address[](1);
        guardians[0] = 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe;

        // deploy Wormhole
        Wormhole wormhole = new Wormhole(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address[],uint16,uint16,bytes32,uint256)")),
                address(implementation),
                guardians,
                chainId, // wormhole chain id
                uint16(1), // governance chain id
                0x0000000000000000000000000000000000000000000000000000000000000004, // governance contract
                block.chainid
            )
        );

        // replace Wormhole with the Wormhole Simulator contract (giving access to some nice helper methods for signing)
        wormholeSimulator = new WormholeSimulator(
            address(wormhole),
            uint256(0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0)
        );

        wormholeContract = IWormhole(wormholeSimulator.wormhole());
    }

    function setUpRelayProvider(uint16 chainId) internal returns (IRelayProvider relayProvider) {
        relayProvider = IRelayProvider(address(new RelayProvider(chainId)));
    }
 
    function setUpCoreRelayer(uint16 chainId, address wormhole, address defaultRelayProvider) internal returns (ICoreRelayer coreRelayer) {
        
        CoreRelayerSetup coreRelayerSetup = new CoreRelayerSetup();
        CoreRelayerImplementation coreRelayerImplementation = new CoreRelayerImplementation();
        CoreRelayerProxy myCoreRelayer = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,address)")),
                address(coreRelayerImplementation),
                chainId,
                wormhole,
                defaultRelayProvider
            )
        );

        coreRelayer = ICoreRelayer(address(myCoreRelayer));

    }


    function standardAssume(GasParameters memory gasParams, VMParams memory batchParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice  < halfMaxUint128 / gasParams.sourceGasPrice );
        vm.assume(gasParams.targetNativePrice < halfMaxUint128 / gasParams.targetGasPrice );
        vm.assume(batchParams.nonce > 0);
        vm.assume(batchParams.consistencyLevel > 0);
    }


    /**
    SENDING TESTS

    */

    struct Contracts {
        IWormhole wormhole;
        WormholeSimulator wormholeSimulator;
        IRelayProviderImpl relayProviderGovernance;
        IRelayProvider relayProvider;
        ICoreRelayer coreRelayer;     
        MockRelayerIntegration integration;  
    }

    function setUpTwoChains(uint16 chain1, uint16 chain2, address relayer) internal returns (Contracts memory source, Contracts memory target) {
        (source.wormhole, source.wormholeSimulator) = setUpWormhole(chain1);
        (target.wormhole, target.wormholeSimulator) = setUpWormhole(chain2);
        source.relayProvider = setUpRelayProvider(chain1);
        target.relayProvider = setUpRelayProvider(chain2);
        source.relayProviderGovernance = IRelayProviderImpl(address(source.relayProvider));
        target.relayProviderGovernance = IRelayProviderImpl(address(target.relayProvider));
        source.relayProviderGovernance.setRewardAddress(chain2, bytes32(uint256(uint160(relayer))));
        target.relayProviderGovernance.setRewardAddress(chain1, bytes32(uint256(uint160(relayer))));
        source.relayProviderGovernance.updateMaximumBudget(chain2, 2**128-1);
        target.relayProviderGovernance.updateMaximumBudget(chain1, 2**128-1);
        source.coreRelayer = setUpCoreRelayer(chain1, address(target.wormhole), address(source.relayProvider));
        target.coreRelayer = setUpCoreRelayer(chain2, address(target.wormhole), address(target.relayProvider));
        target.coreRelayer.registerCoreRelayer(chain1, bytes32(uint256(uint160(address(source.coreRelayer)))));
        source.coreRelayer.registerCoreRelayer(chain2, bytes32(uint256(uint160(address(target.coreRelayer)))));
        target.integration = new MockRelayerIntegration(address(target.wormhole), address(target.coreRelayer));
        source.integration = new MockRelayerIntegration(address(source.wormhole), address(source.coreRelayer));
    }

    function within(uint256 a, uint256 b, uint256 c) internal view returns (bool) {
        return (a/b <= c && b/a <= c);
    }
    // This test confirms that the `send` method generates the correct delivery Instructions payload
    // to be delivered on the target chain.
    function testSend(GasParameters memory gasParams, VMParams memory batchParams, bytes memory message, address relayer, bool forward) public {
        
        standardAssume(gasParams, batchParams);

        vm.assume(gasParams.targetGasLimit >= 1000000);
        vm.assume(relayer != address(0x0));
        //vm.assume(within(gasParams.targetGasPrice, gasParams.sourceGasPrice, 10**10));
        //vm.assume(within(gasParams.targetNativePrice, gasParams.sourceNativePrice, 10**10));
        
        uint16 SOURCE_CHAIN_ID = 3;
        uint16 TARGET_CHAIN_ID = 4;
        // initialize all contracts

        (Contracts memory source, Contracts memory target) = setUpTwoChains(SOURCE_CHAIN_ID, TARGET_CHAIN_ID, relayer);


        // set relayProvider prices
        source.relayProviderGovernance.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProviderGovernance.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        MockRelayerIntegration deliveryContract = new MockRelayerIntegration(address(target.wormhole), address(target.coreRelayer));

        // estimate the cost based on the intialized values
        uint256 computeBudget = source.relayProvider.quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);

        // start listening to events
        vm.recordLogs();

        // send an arbitrary wormhole message to be relayed
        source.wormhole.publishMessage{value: source.wormhole.messageFee()}(batchParams.nonce, abi.encodePacked(uint8(0), message), batchParams.consistencyLevel);

        // call the send function on the relayer contract

        ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest(TARGET_CHAIN_ID, bytes32(uint256(uint160(address(deliveryContract)))), bytes32(uint256(uint160(address(0x1)))), computeBudget, 0, bytes(""));

        source.coreRelayer.requestDelivery{value: source.wormhole.messageFee() + computeBudget}(request, batchParams.nonce, batchParams.consistencyLevel);

        // record the wormhole message emitted by the relayer contract
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes[] memory encodedVMs = new bytes[](2);
        encodedVMs[0] = source.wormholeSimulator.fetchSignedMessageFromLogs(entries[0], SOURCE_CHAIN_ID, address(source.coreRelayer));
        encodedVMs[1] = source.wormholeSimulator.fetchSignedMessageFromLogs(entries[1], SOURCE_CHAIN_ID, address(source.coreRelayer));
        genericRelayOne(encodedVMs, relayer, target.coreRelayer, target.wormhole);
        assertTrue(keccak256(deliveryContract.getPayload(keccak256(abi.encodePacked(keccak256(encodedVMs[0].slice(72, encodedVMs[0].length-72)))))) == keccak256(message));

    }


    function testForward(GasParameters memory gasParams, VMParams memory batchParams, bytes memory message, address relayer, bool forward) public {
        
        standardAssume(gasParams, batchParams);

        vm.assume(gasParams.targetGasLimit >= 1000000);
        vm.assume(relayer != address(0x0));
        vm.assume(uint256(1) * gasParams.targetGasPrice * gasParams.targetNativePrice  > uint256(1) * gasParams.sourceGasPrice * gasParams.sourceNativePrice);
        uint16 SOURCE_CHAIN_ID = 3;
        uint16 TARGET_CHAIN_ID = 4;
        // initialize all contracts

        (Contracts memory source, Contracts memory target) = setUpTwoChains(SOURCE_CHAIN_ID, TARGET_CHAIN_ID, relayer);

        // set relayProvider prices
        source.relayProviderGovernance.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProviderGovernance.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);
        target.relayProviderGovernance.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        target.relayProviderGovernance.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        

        // estimate the cost based on the intialized values
        uint256 computeBudget = source.relayProvider.quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);

        // start listening to events
        vm.recordLogs();

        // send an arbitrary wormhole message to be relayed
        vm.prank(address(source.integration));
        source.wormhole.publishMessage{value: source.wormhole.messageFee()}(batchParams.nonce, abi.encodePacked(uint8(1), message), batchParams.consistencyLevel);

        // call the send function on the relayer contract

        ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest(TARGET_CHAIN_ID, bytes32(uint256(uint160(address(target.integration)))), bytes32(uint256(uint160(address(0x1)))), computeBudget, 0, bytes(""));

        source.coreRelayer.requestDelivery{value: source.wormhole.messageFee() + computeBudget}(request, batchParams.nonce, batchParams.consistencyLevel);

        // record the wormhole message emitted by the relayer contract
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes[] memory encodedVMs = new bytes[](2);
        encodedVMs[0] = source.wormholeSimulator.fetchSignedMessageFromLogs(entries[0], SOURCE_CHAIN_ID, address(source.integration));
        encodedVMs[1] = source.wormholeSimulator.fetchSignedMessageFromLogs(entries[1], SOURCE_CHAIN_ID, address(source.coreRelayer));
        genericRelayOne(encodedVMs, relayer, target.coreRelayer, target.wormhole);
        assertTrue(keccak256(target.integration.getPayload(keccak256(abi.encodePacked(keccak256(encodedVMs[0].slice(72, encodedVMs[0].length-72)))))) == keccak256(message));

        entries = vm.getRecordedLogs();
        encodedVMs[0] = target.wormholeSimulator.fetchSignedMessageFromLogs(entries[0], TARGET_CHAIN_ID, address(target.coreRelayer));
        encodedVMs[1] = target.wormholeSimulator.fetchSignedMessageFromLogs(entries[1], TARGET_CHAIN_ID, address(target.coreRelayer));
        genericRelayOne(encodedVMs, relayer, source.coreRelayer, source.wormhole);
        assertTrue(keccak256(source.integration.getPayload(keccak256(abi.encodePacked(keccak256(encodedVMs[0].slice(72, encodedVMs[0].length-72)))))) == keccak256(bytes("received!")));


    }


    function genericRelayOne(bytes[] memory encodedVMs, address relayer, ICoreRelayer coreRelayer, IWormhole wormhole) internal {
        CoreRelayer dummyRelayer = new CoreRelayer();
        bytes memory payload = wormhole.parseVM(encodedVMs[encodedVMs.length - 1]).payload;
        CoreRelayerStructs.DeliveryInstructionsContainer memory container = dummyRelayer.decodeDeliveryInstructionsContainer(payload);
        
        uint256 budget = 0;
        for(uint8 i=0; i<encodedVMs.length-1; i++) {
            budget += container.instructions[i].computeBudgetTarget + container.instructions[i].applicationBudgetTarget;
        }

        vm.deal(relayer, budget);
        vm.prank(relayer);
        coreRelayer.deliverSingle{value: budget}(ICoreRelayer.TargetDeliveryParametersSingle(encodedVMs, uint8(encodedVMs.length-1), 0));
    }

    /**
    FORWARDING TESTS

    */
    //This test confirms that forwarding a request produces the proper delivery instructions

    //This test confirms that forwarding cannot occur when the contract is locked

    //This test confirms that forwarding cannot occur if there are insufficient refunds after the request

}
