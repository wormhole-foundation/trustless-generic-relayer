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


    function standardAssume(GasParameters memory gasParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice  < halfMaxUint128 / gasParams.sourceGasPrice );
        vm.assume(gasParams.targetNativePrice < halfMaxUint128 / gasParams.targetGasPrice );

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
            mapEntry.chainId = i;
            map[i] = mapEntry;
        }
        uint256 maxBudget = 2**128-1;
        for(uint16 i=1; i<=numChains; i++) {
            for(uint16 j=1; j<=numChains; j++) {
                map[i].relayProvider.updateDeliveryAddress(j, bytes32(uint256(uint160(map[j].relayer))));
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
    // This test confirms that the `send` method generates the correct delivery Instructions payload
    // to be delivered on the target chain.
    function testSend(GasParameters memory gasParams, bytes memory message) public {
        
        standardAssume(gasParams);

        vm.assume(gasParams.targetGasLimit >= 1000000);
        //vm.assume(within(gasParams.targetGasPrice, gasParams.sourceGasPrice, 10**10));
        //vm.assume(within(gasParams.targetNativePrice, gasParams.sourceNativePrice, 10**10));
        
        uint16 SOURCE_CHAIN_ID = 1;
        uint16 TARGET_CHAIN_ID = 2;

        Contracts memory source = map[SOURCE_CHAIN_ID];
        Contracts memory target = map[TARGET_CHAIN_ID];

        // set relayProvider prices
        source.relayProvider.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProvider.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        
        // estimate the cost based on the intialized values
        uint256 computeBudget = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        // start listening to events
        vm.recordLogs();

        source.integration.sendMessage{value: computeBudget + source.wormhole.messageFee()}(message, TARGET_CHAIN_ID, address(target.integration));

        address[] memory senders = new address[](2);
        senders[0] = address(source.integration);
        senders[1] = address(source.coreRelayer);
        genericRelayer(signMessages(senders, SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

    }


    function testForward(GasParameters memory gasParams, bytes memory message) public {
        
        standardAssume(gasParams);

        uint16 SOURCE_CHAIN_ID = 1;
        uint16 TARGET_CHAIN_ID = 2;
        Contracts memory source = map[SOURCE_CHAIN_ID];
        Contracts memory target = map[TARGET_CHAIN_ID];

        vm.assume(gasParams.targetGasLimit >= 1000000);
        vm.assume(uint256(1) * gasParams.targetGasPrice * gasParams.targetNativePrice  > uint256(1) * gasParams.sourceGasPrice * gasParams.sourceNativePrice);

        // set relayProvider prices
        source.relayProvider.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProvider.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);
        target.relayProvider.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        target.relayProvider.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        

        // estimate the cost based on the intialized values
        uint256 computeBudget = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        // start listening to events
        vm.recordLogs();

        source.integration.sendMessageWithForwardedResponse{value: computeBudget + source.wormhole.messageFee()}(message, TARGET_CHAIN_ID, address(target.integration));
        
        address[] memory senders = new address[](2);
        senders[0] = address(source.integration);
        senders[1] = address(source.coreRelayer);

     
        genericRelayer(signMessages(senders, SOURCE_CHAIN_ID));

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        senders = new address[](2);
        senders[0] = address(target.integration);
        senders[1] = address(target.coreRelayer);
        genericRelayer(signMessages(senders, TARGET_CHAIN_ID));

        assertTrue(keccak256(source.integration.getMessage()) == keccak256(bytes("received!")));


    }

    function testRedelivery(GasParameters memory gasParams, bytes memory message) public {
        
        standardAssume(gasParams);

        vm.assume(gasParams.targetGasLimit >= 1000000);
        vm.assume(gasParams.targetNativePrice <= uint256(2)**63);
        //vm.assume(within(gasParams.targetGasPrice, gasParams.sourceGasPrice, 10**10));
        //vm.assume(within(gasParams.targetNativePrice, gasParams.sourceNativePrice, 10**10));
        
        uint16 SOURCE_CHAIN_ID = 1;
        uint16 TARGET_CHAIN_ID = 2;

        Contracts memory source = map[SOURCE_CHAIN_ID];
        Contracts memory target = map[TARGET_CHAIN_ID];

        // set relayProvider prices
        source.relayProvider.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProvider.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        
        // estimate the cost based on the intialized values
        uint256 computeBudget = source.coreRelayer.quoteGasRedeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);
        uint256 computeBudgetNotEnough = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, 10, source.relayProvider);

        // start listening to events
        vm.recordLogs();

        source.integration.sendMessage{value: computeBudgetNotEnough + source.wormhole.messageFee()}(message, TARGET_CHAIN_ID, address(target.integration));

        address[] memory senders = new address[](2);
        senders[0] = address(source.integration);
        senders[1] = address(source.coreRelayer);
        genericRelayer(signMessages(senders, SOURCE_CHAIN_ID));

        bytes32 deliveryVaaHash = vm.getRecordedLogs()[0].data.toBytes32(0);

        ICoreRelayer.RedeliveryByTxHashRequest memory redeliveryRequest = ICoreRelayer.RedeliveryByTxHashRequest(SOURCE_CHAIN_ID, deliveryVaaHash, 1, TARGET_CHAIN_ID, computeBudget, 0, source.coreRelayer.getDefaultRelayParams());

        source.coreRelayer.requestRedelivery{value: source.wormhole.messageFee() + computeBudget}(redeliveryRequest, 1, source.relayProvider);

        senders = new address[](1);
        senders[0] = address(source.coreRelayer);
        genericRelayer(signMessages(senders, SOURCE_CHAIN_ID));
        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

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
                vm.deal(map[targetChain].relayer, budget);
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
            vm.deal(map[targetChain].relayer, budget);
            vm.prank(map[targetChain].relayer);
            map[targetChain].coreRelayer.redeliverSingle{value: budget}(package);
        }
    }

    /**
    FORWARDING TESTS

    */
    //This test confirms that forwarding a request produces the proper delivery instructions

    //This test confirms that forwarding cannot occur when the contract is locked

    //This test confirms that forwarding cannot occur if there are insufficient refunds after the request

}
