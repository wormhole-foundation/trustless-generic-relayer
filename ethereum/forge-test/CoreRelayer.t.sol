// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {IRelayProvider} from "../contracts/interfaces/IRelayProvider.sol";
import {RelayProvider} from "../contracts/relayProvider/RelayProvider.sol";
import {RelayProviderSetup} from "../contracts/relayProvider/RelayProviderSetup.sol";
import {RelayProviderImplementation} from "../contracts/relayProvider/RelayProviderImplementation.sol";
import {RelayProviderProxy} from "../contracts/relayProvider/RelayProviderProxy.sol";
import {RelayProviderMessages} from "../contracts/relayProvider/RelayProviderMessages.sol";
import {RelayProviderStructs} from "../contracts/relayProvider/RelayProviderStructs.sol";
import {ICoreRelayer} from "../contracts/interfaces/ICoreRelayer.sol";
import {ICoreRelayerGovernance} from "../contracts/interfaces/ICoreRelayerGovernance.sol";
import {CoreRelayerSetup} from "../contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "../contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "../contracts/coreRelayer/CoreRelayerProxy.sol";
import {CoreRelayerMessages} from "../contracts/coreRelayer/CoreRelayerMessages.sol";
import {CoreRelayerStructs} from "../contracts/coreRelayer/CoreRelayerStructs.sol";
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

    /**
    *   FORGE TESTING PLAN!! Read this on Tuesday
    *   Step 1: Set up 'usd fund for a relayer'. before and after the test, check how much 'usd fund' the relayer earned, and assert its positive (and at least gasPrice * some minimum amount of gas the transaction takes)
    *   Step 2: make sure the user balance loses how ever much the relayer gains (minus whatever fees) 
    *  
    *   Step 3: Change the MockRelayerIntegration to take messages with arbitrary length forwarding specifications (A->B->C->D etc), write a helper to figure out how much gas to pay for these, and implement that
    *   Step 4: Make tests for each of the error messages
    * 3<->4 interchangeable
    *
     */

    struct GasParameters {
        uint32 evmGasOverhead;
        uint32 targetGasLimit;
        uint64 targetGasPrice;
        uint64 targetNativePrice;
        uint64 sourceGasPrice;
        uint64 sourceNativePrice;
    }

    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;

    function setUp() public {
        WormholeSetup setup = new WormholeSetup();

        // deploy Implementation
        WormholeImplementation implementation = new WormholeImplementation();

        // set guardian set
        address[] memory guardians = new address[](1);
        guardians[0] = 0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe;

        // deploy Wormhole
        relayerWormhole = IWormhole(address(new Wormhole(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address[],uint16,uint16,bytes32,uint256)")),
                address(implementation),
                guardians,
                2, // wormhole chain id
                uint16(1), // governance chain id
                0x0000000000000000000000000000000000000000000000000000000000000004, // governance contract
                block.chainid
            )
        )));

        relayerWormholeSimulator = new WormholeSimulator(
            address(relayerWormhole),
            uint256(0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0)
        );

        setUpChains(5);

    }

    function setUpWormhole(uint16 chainId) internal returns (IWormhole wormholeContract) {
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
        WormholeSimulator wormholeSimulator = new WormholeSimulator(
            address(wormhole),
            uint256(0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0)
        );

        wormholeContract = IWormhole(wormholeSimulator.wormhole());
    }

    function setUpRelayProvider(uint16 chainId) internal returns (RelayProvider relayProvider) {
        RelayProviderSetup relayProviderSetup = new RelayProviderSetup();
        RelayProviderImplementation relayProviderImplementation = new RelayProviderImplementation();
        RelayProviderProxy myRelayProvider = new RelayProviderProxy(
            address(relayProviderSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16)")),
                address(relayProviderImplementation),
                chainId
            )
        );

        relayProvider = RelayProvider(address(myRelayProvider));
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


    function standardAssumeAndSetupTwoChains(GasParameters memory gasParams, uint256 minTargetGasLimit) public returns (uint16 sourceId, uint16 targetId, Contracts memory source, Contracts memory target) {
        uint128 halfMaxUint128 = 2 ** (62) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice  < halfMaxUint128 / gasParams.sourceGasPrice );
        vm.assume(gasParams.targetNativePrice < halfMaxUint128 / gasParams.targetGasPrice );
        vm.assume(gasParams.targetGasLimit >= minTargetGasLimit);

        sourceId = 1;
        targetId = 2;
        source = map[sourceId];
        target = map[targetId];

        vm.deal(source.relayer, address(this).balance);
        vm.deal(target.relayer, address(this).balance);

        // set relayProvider prices
        source.relayProvider.updatePrice(targetId, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProvider.updatePrice(sourceId, gasParams.sourceGasPrice, gasParams.sourceNativePrice);
        target.relayProvider.updatePrice(targetId, gasParams.targetGasPrice, gasParams.targetNativePrice);
        target.relayProvider.updatePrice(sourceId, gasParams.sourceGasPrice, gasParams.sourceNativePrice);
    }


    /**
    SENDING TESTS

    */

    struct Contracts {
        IWormhole wormhole;
        RelayProvider relayProvider;
        ICoreRelayer coreRelayer;     
        ICoreRelayerGovernance coreRelayerGovernance;
        MockRelayerIntegration integration; 
        address relayer;
        address rewardAddress;
        address refundAddress;
        uint16 chainId;
    }

    mapping(uint16 => Contracts) map;


    function setUpChains(uint16 numChains) internal {
        for(uint16 i=1; i<=numChains; i++) {
            Contracts memory mapEntry;
            mapEntry.wormhole = setUpWormhole(i);
            mapEntry.relayProvider = setUpRelayProvider(i);
            mapEntry.coreRelayer = setUpCoreRelayer(i, address(mapEntry.wormhole), address(mapEntry.relayProvider));
            mapEntry.coreRelayerGovernance = ICoreRelayerGovernance(address(mapEntry.coreRelayer));
            mapEntry.integration = new MockRelayerIntegration(address(mapEntry.wormhole), address(mapEntry.coreRelayer));
            mapEntry.relayer = address(uint160(uint256(keccak256(abi.encodePacked(bytes("relayer"), i)))));
            mapEntry.refundAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes("refundAddress"), i)))));
            mapEntry.rewardAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes("rewardAddress"), i)))));
            mapEntry.chainId = i;
            map[i] = mapEntry;
        }
        uint256 maxBudget = 2**128-1;
        for(uint16 i=1; i<=numChains; i++) {
            for(uint16 j=1; j<=numChains; j++) {
                map[i].relayProvider.updateDeliveryAddress(j, bytes32(uint256(uint160(map[j].relayer))));
                map[i].relayProvider.updateRewardAddress(map[i].rewardAddress);
                map[i].coreRelayerGovernance.registerCoreRelayerContract(j, bytes32(uint256(uint160(address(map[j].coreRelayer)))));
                map[i].relayProvider.updateMaximumBudget(j, maxBudget);
            }
        }

    }

    function within(uint256 a, uint256 b, uint256 c) internal view returns (bool) {
        return (a/b <= c && b/a <= c);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns(address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function testSend(GasParameters memory gasParams, bytes memory message) public {
        
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) = standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 computeBudget = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        source.integration.sendMessage{value: computeBudget + source.wormhole.messageFee()}(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

    }

    function testFundsCorrect(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) = standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        uint256 refundAddressBalance = target.refundAddress.balance;
        uint256 relayerBalance = target.relayer.balance;
        uint256 rewardAddressBalance = source.rewardAddress.balance;

        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider) + source.wormhole.messageFee();

        source.integration.sendMessage{value: payment}(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        uint256 USDcost = uint256(payment)*gasParams.sourceNativePrice - (target.refundAddress.balance - refundAddressBalance)*gasParams.targetNativePrice;
        uint256 relayerProfit = uint256(gasParams.sourceNativePrice) * (source.rewardAddress.balance - rewardAddressBalance) - gasParams.targetNativePrice*( relayerBalance - target.relayer.balance);

        uint256 howMuchGasRelayerCouldHavePaidForAndStillProfited = relayerProfit/gasParams.targetGasPrice/gasParams.targetNativePrice;
        assertTrue(howMuchGasRelayerCouldHavePaidForAndStillProfited >= 30000); // takes around this much gas (seems to go from 36k-200k?!?)
        assertTrue(USDcost == relayerProfit, "We paid the exact amount");
    }


    function testForward(GasParameters memory gasParams, bytes memory message) public {
        
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) = standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.assume(uint256(1) * gasParams.targetGasPrice * gasParams.targetNativePrice  > uint256(1) * gasParams.sourceGasPrice * gasParams.sourceNativePrice);


        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider) + source.wormhole.messageFee();

        source.integration.sendMessageWithForwardedResponse{value: payment}(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));
     
        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        genericRelayer(signMessages(senderArray(address(target.integration), address(target.coreRelayer)), TARGET_CHAIN_ID));

        assertTrue(keccak256(source.integration.getMessage()) == keccak256(bytes("received!")));


    }

    function testRedelivery(GasParameters memory gasParams, bytes memory message) public {
        
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) = standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();
        
        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasRedeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider) + source.wormhole.messageFee();
        uint256 paymentNotEnough = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, 10, source.relayProvider) + source.wormhole.messageFee();


        source.integration.sendMessage{value: paymentNotEnough}(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue((keccak256(target.integration.getMessage()) != keccak256(message)) || (keccak256(message) == keccak256(bytes(""))));

        bytes32 deliveryVaaHash = vm.getRecordedLogs()[0].data.toBytes32(0);

        ICoreRelayer.RedeliveryByTxHashRequest memory redeliveryRequest = ICoreRelayer.RedeliveryByTxHashRequest(SOURCE_CHAIN_ID, deliveryVaaHash, 1, TARGET_CHAIN_ID, payment - source.wormhole.messageFee(), 0, source.coreRelayer.getDefaultRelayParams());

        source.coreRelayer.requestRedelivery{value: payment}(redeliveryRequest, 1, source.relayProvider);

        genericRelayer(signMessages(senderArray(address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

    }

    function testTwoSends(GasParameters memory gasParams, bytes memory message, bytes memory secondMessage) public {
        
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) = standardAssumeAndSetupTwoChains(gasParams, 1000000); 

        
        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider) + source.wormhole.messageFee();

        // start listening to events
        vm.recordLogs();
        

        source.integration.sendMessage{value: payment}(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        vm.getRecordedLogs();

        source.integration.sendMessage{value: payment}(secondMessage, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(signMessages(senderArray(address(source.integration), address(source.coreRelayer)), SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(secondMessage));

    }

    function signMessages(address[] memory senders, uint16 chainId) internal returns (bytes[] memory encodedVMs) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        require(senders.length <= entries.length, "Wrong length of senders array");
        encodedVMs = new bytes[](senders.length);
        for(uint256 i=0; i<senders.length; i++) {
            encodedVMs[i] = relayerWormholeSimulator.fetchSignedMessageFromLogs(entries[i], chainId, senders[i]);
        }
    }

    mapping(uint256 => bool) nonceCompleted; 

    mapping(bytes32 => ICoreRelayer.TargetDeliveryParametersSingle) pastDeliveries;

    function genericRelayer(bytes[] memory encodedVMs) internal {
        
        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedVMs.length);
        for(uint16 i=0; i<encodedVMs.length; i++) {
            parsed[i] = relayerWormhole.parseVM(encodedVMs[i]);
        }
        uint16 chainId = parsed[parsed.length - 1].emitterChainId;
        Contracts memory contracts = map[chainId];

        for(uint16 i=0; i<encodedVMs.length; i++) {
            if(!nonceCompleted[parsed[i].nonce]) {
                nonceCompleted[parsed[i].nonce] = true;
                uint8 length = 1;
                for(uint16 j=i+1; j<encodedVMs.length; j++) {
                    if(parsed[i].nonce == parsed[j].nonce) {
                        length++;
                    }
                }
                bytes[] memory deliveryInstructions = new bytes[](length);
                uint8 counter = 0;
                for(uint16 j=i; j<encodedVMs.length; j++) {
                    if(parsed[i].nonce == parsed[j].nonce) {
                        deliveryInstructions[counter] = encodedVMs[j];
                        counter++;
                    }
                }
                counter = 0;
                for(uint16 j=i; j<encodedVMs.length; j++) {
                    if(parsed[i].nonce == parsed[j].nonce) {
                        if(parsed[j].emitterAddress == toWormholeFormat(address(contracts.coreRelayer)) && (parsed[j].emitterChainId == chainId)) {
                             genericRelay(contracts, counter, encodedVMs[j], deliveryInstructions, parsed[j]);
                        }
                        counter += 1;
                    }
                }


            }
        }
        for(uint8 i=0; i<encodedVMs.length; i++) {
            nonceCompleted[parsed[i].nonce] = false;
        }
    }

    function genericRelay(Contracts memory contracts, uint8 counter, bytes memory encodedVM, bytes[] memory deliveryInstructions, IWormhole.VM memory parsed) internal {
        uint8 payloadId = parsed.payload.toUint8(0);
        if(payloadId == 1) {
            ICoreRelayer.DeliveryInstructionsContainer memory container = contracts.coreRelayer.getDeliveryInstructionsContainer(parsed.payload);
            for(uint8 k=0; k<container.instructions.length; k++) {
                uint256 budget = container.instructions[k].maximumRefundTarget + container.instructions[k].applicationBudgetTarget;
                ICoreRelayer.TargetDeliveryParametersSingle memory package = ICoreRelayer.TargetDeliveryParametersSingle(deliveryInstructions, counter, k);
                uint16 targetChain = container.instructions[k].targetChain;
                
                vm.prank(map[targetChain].relayer);
                map[targetChain].coreRelayer.deliverSingle{value: budget}(package);
                pastDeliveries[parsed.hash] = package;
            }
        } else if(payloadId == 2) {
            ICoreRelayer.RedeliveryByTxHashInstruction memory instruction = contracts.coreRelayer.getRedeliveryByTxHashInstruction(parsed.payload);
            ICoreRelayer.TargetDeliveryParametersSingle memory originalDelivery = pastDeliveries[instruction.sourceTxHash];
            uint256 budget = instruction.newMaximumRefundTarget + instruction.newApplicationBudgetTarget;
            uint16 targetChain = instruction.targetChain;
            ICoreRelayer.TargetRedeliveryByTxHashParamsSingle memory package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(encodedVM, originalDelivery.encodedVMs, originalDelivery.deliveryIndex, originalDelivery.multisendIndex);
            
            vm.prank(map[targetChain].relayer);
            map[targetChain].coreRelayer.redeliverSingle{value: budget}(package);
        }
    }

    function senderArray(address a, address b) internal returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function senderArray(address a) internal returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    /**
    FORWARDING TESTS

    */
    //This test confirms that forwarding a request produces the proper delivery instructions

    //This test confirms that forwarding cannot occur when the contract is locked

    //This test confirms that forwarding cannot occur if there are insufficient refunds after the request

}
