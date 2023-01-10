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
        uint16 wormholeFeeOnSource;
        uint16 wormholeFeeOnTarget;
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
        relayerWormhole = IWormhole(
            address(
                new Wormhole(
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
                )
            )
        );

        relayerWormholeSimulator = new WormholeSimulator(
            address(relayerWormhole),
            uint256(0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0)
        );

        setUpChains(5);
    }

    function setUpWormhole(uint16 chainId)
        internal
        returns (IWormhole wormholeContract, WormholeSimulator wormholeSimulator)
    {
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

    function setUpCoreRelayer(uint16 chainId, address wormhole, address defaultRelayProvider)
        internal
        returns (ICoreRelayer coreRelayer)
    {

        CoreRelayerSetup coreRelayerSetup = new CoreRelayerSetup();
        CoreRelayerImplementation coreRelayerImplementation = new CoreRelayerImplementation();
        CoreRelayerProxy myCoreRelayer = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,address,uint16,bytes32,uint256)")),
                address(coreRelayerImplementation),
                chainId,
                wormhole,
                defaultRelayProvider,
                uint16(1), // governance chain id
                0x0000000000000000000000000000000000000000000000000000000000000004, // governance contract
                block.chainid
            )
        );
        coreRelayer = ICoreRelayer(address(myCoreRelayer));

    }

    function standardAssumeAndSetupTwoChains(GasParameters memory gasParams, uint256 minTargetGasLimit)
        public
        returns (uint16 sourceId, uint16 targetId, Contracts memory source, Contracts memory target)
    {
        uint128 halfMaxUint128 = 2 ** (62) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice < halfMaxUint128 / gasParams.sourceGasPrice);
        vm.assume(gasParams.targetNativePrice < halfMaxUint128 / gasParams.targetGasPrice);
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
     * SENDING TESTS
     */

    struct Contracts {
        IWormhole wormhole;
        WormholeSimulator wormholeSimulator;
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
        for (uint16 i = 1; i <= numChains; i++) {
            Contracts memory mapEntry;
            (mapEntry.wormhole, mapEntry.wormholeSimulator) = setUpWormhole(i);
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
        uint256 maxBudget = 2 ** 128 - 1;
        for (uint16 i = 1; i <= numChains; i++) {
            for (uint16 j = 1; j <= numChains; j++) {
                map[i].relayProvider.updateDeliveryAddress(j, bytes32(uint256(uint160(map[j].relayer))));
                map[i].relayProvider.updateRewardAddress(map[i].rewardAddress);
                registerCoreRelayerContract(map[i].coreRelayerGovernance, i,
                    j, bytes32(uint256(uint160(address(map[j].coreRelayer))))
                );
                map[i].relayProvider.updateMaximumBudget(j, maxBudget);
            }
        }
    }

    function registerCoreRelayerContract(ICoreRelayerGovernance governance, uint16 currentChainId, uint16 chainId, bytes32 coreRelayerContractAddress) internal {
        bytes32 coreRelayerModule = 0x000000000000000000000000000000000000000000436f726552656c61796572;
        bytes memory message = abi.encodePacked(coreRelayerModule, uint8(2), uint16(currentChainId), chainId, coreRelayerContractAddress);
        IWormhole.VM memory preSignedMessage = IWormhole.VM({
            version: 1,
            timestamp: uint32(block.timestamp),
            nonce: 0,
            emitterChainId: relayerWormhole.governanceChainId(),
            emitterAddress: relayerWormhole.governanceContract(),
            sequence: 0,
            consistencyLevel: 200,
            payload: message,
            guardianSetIndex: 0,
            signatures: new IWormhole.Signature[](0),
            hash: bytes32("")
        });

        bytes memory signed = relayerWormholeSimulator.encodeAndSignMessage(preSignedMessage);
        governance.registerCoreRelayerContract(signed);
    }

    function within(uint256 a, uint256 b, uint256 c) internal view returns (bool) {
        return (a / b <= c && b / a <= c);
    }

    function toWormholeFormat(address addr) public pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) public pure returns (address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function testSend(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 computeBudget =
            source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        source.integration.sendMessage{value: computeBudget + source.wormhole.messageFee()}(
            message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));
    }

    function testFundsCorrect(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        uint256 refundAddressBalance = target.refundAddress.balance;
        uint256 relayerBalance = target.relayer.balance;
        uint256 rewardAddressBalance = source.rewardAddress.balance;

        map[SOURCE_CHAIN_ID].wormholeSimulator.setMessageFee(gasParams.wormholeFeeOnSource);
        map[TARGET_CHAIN_ID].wormholeSimulator.setMessageFee(gasParams.wormholeFeeOnTarget);
        uint32 wormholeFeeOnTargetInSourceCurrency = uint32(
            gasParams.wormholeFeeOnSource * map[SOURCE_CHAIN_ID].relayProvider.quoteAssetPrice(TARGET_CHAIN_ID)
                / map[SOURCE_CHAIN_ID].relayProvider.quoteAssetPrice(SOURCE_CHAIN_ID) + 1
        );
        map[SOURCE_CHAIN_ID].relayProvider.updateWormholeFee(TARGET_CHAIN_ID, wormholeFeeOnTargetInSourceCurrency);

        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(
            TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider
        ) + source.wormhole.messageFee();

        source.integration.sendMessage{value: payment}(
            message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        uint256 USDcost = uint256(payment) * gasParams.sourceNativePrice
            - (target.refundAddress.balance - refundAddressBalance) * gasParams.targetNativePrice;
        uint256 relayerProfit = uint256(gasParams.sourceNativePrice)
            * (source.rewardAddress.balance - rewardAddressBalance)
            - gasParams.targetNativePrice * (relayerBalance - target.relayer.balance);

        uint256 howMuchGasRelayerCouldHavePaidForAndStillProfited =
            relayerProfit / gasParams.targetGasPrice / gasParams.targetNativePrice;
        assertTrue(howMuchGasRelayerCouldHavePaidForAndStillProfited >= 30000); // takes around this much gas (seems to go from 36k-200k?!?)

        assertTrue(
            USDcost == relayerProfit + 2 * map[SOURCE_CHAIN_ID].wormhole.messageFee() * gasParams.sourceNativePrice,
            "We paid the exact amount"
        );
    }

    function testForward(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.assume(
            uint256(1) * gasParams.targetGasPrice * gasParams.targetNativePrice
                > uint256(1) * gasParams.sourceGasPrice * gasParams.sourceNativePrice
        );

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(
            TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider
        ) + source.wormhole.messageFee();

        source.integration.sendMessageWithForwardedResponse{value: payment}(
            message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        genericRelayer(TARGET_CHAIN_ID, 2);

        assertTrue(keccak256(source.integration.getMessage()) == keccak256(bytes("received!")));
    }

    function testRedelivery(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasRedeliveryFee(
            TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider
        ) + source.wormhole.messageFee();
        uint256 paymentNotEnough = source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, 10, source.relayProvider)
            + source.wormhole.messageFee();

        source.integration.sendMessage{value: paymentNotEnough}(
            message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(
            (keccak256(target.integration.getMessage()) != keccak256(message))
                || (keccak256(message) == keccak256(bytes("")))
        );

        bytes32 deliveryVaaHash = vm.getRecordedLogs()[0].data.toBytes32(0);

        ICoreRelayer.RedeliveryByTxHashRequest memory redeliveryRequest = ICoreRelayer.RedeliveryByTxHashRequest(
            SOURCE_CHAIN_ID,
            deliveryVaaHash,
            1,
            TARGET_CHAIN_ID,
            payment - source.wormhole.messageFee(),
            0,
            source.coreRelayer.getDefaultRelayParams()
        );

        source.coreRelayer.requestRedelivery{value: payment}(redeliveryRequest, 1, source.relayProvider);

        genericRelayer(SOURCE_CHAIN_ID, 1);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));
    }

    function testTwoSends(GasParameters memory gasParams, bytes memory message, bytes memory secondMessage) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        // estimate the cost based on the intialized values
        uint256 payment = source.coreRelayer.quoteGasDeliveryFee(
            TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider
        ) + source.wormhole.messageFee();

        // start listening to events
        vm.recordLogs();

        source.integration.sendMessage{value: payment}(
            message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));

        vm.getRecordedLogs();

        source.integration.sendMessage{value: payment}(
            secondMessage, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
        );

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(keccak256(target.integration.getMessage()) == keccak256(secondMessage));
    }

    function testRevertNonceZero(GasParameters memory gasParams, bytes memory message) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        uint256 wormholeFee = source.wormhole.messageFee();
        // estimate the cost based on the intialized values
        uint256 computeBudget =
            source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        vm.expectRevert(bytes("2"));
        source.integration.sendMessageGeneral{value: computeBudget + wormholeFee}(
            abi.encodePacked(uint8(0), message),
            TARGET_CHAIN_ID,
            address(target.integration),
            address(target.refundAddress),
            0,
            0
        );
    }

    /**
     * Forwarding tests 2, 3-7.. need to think about how to test this.. some sort of way to control the forwarding request? Or maybe make a different relayerintegration for testing?
     */

    /**
     * Reentrancy test for execute delivery 8
     */

    /**
     * Redelivery  9-17
     */
    struct RedeliveryStackTooDeep {
        bytes32 deliveryVaaHash;
        uint256 payment;
        Vm.Log[] entries;
        bytes redeliveryVM;
        IWormhole.VM parsed;
        uint256 budget;
        ICoreRelayer.RedeliveryByTxHashRequest redeliveryRequest;
        ICoreRelayer.TargetDeliveryParametersSingle originalDelivery;
        ICoreRelayer.TargetRedeliveryByTxHashParamsSingle package;
        ICoreRelayer.RedeliveryByTxHashInstruction instruction;
    }

    function change(bytes memory message, uint256 index) internal {
        if (message[index] == 0x02) {
            message[index] = 0x04;
        } else {
            message[index] = 0x02;
        }
    }

    function testRevertRedeliveryErrors_1_9_10_11_12_13_14_15_16_17(
        GasParameters memory gasParams,
        bytes memory message
    ) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        RedeliveryStackTooDeep memory stack;

        source.integration.sendMessage{
            value: source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, 21000, source.relayProvider)
                + source.wormhole.messageFee()
        }(message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress));

        genericRelayer(SOURCE_CHAIN_ID, 2);

        assertTrue(
            (keccak256(target.integration.getMessage()) != keccak256(message))
                || (keccak256(message) == keccak256(bytes("")))
        );

        stack.deliveryVaaHash = vm.getRecordedLogs()[0].data.toBytes32(0);

        stack.payment =
            source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);

        stack.redeliveryRequest = ICoreRelayer.RedeliveryByTxHashRequest(
            SOURCE_CHAIN_ID,
            stack.deliveryVaaHash,
            1,
            TARGET_CHAIN_ID,
            stack.payment - source.wormhole.messageFee(),
            0,
            source.coreRelayer.getDefaultRelayParams()
        );

        vm.expectRevert(bytes("1"));
        source.coreRelayer.requestRedelivery{value: stack.payment - 1}(stack.redeliveryRequest, 1, source.relayProvider);

        source.coreRelayer.requestRedelivery{value: stack.payment}(stack.redeliveryRequest, 1, source.relayProvider);

        stack.entries = vm.getRecordedLogs();

        stack.redeliveryVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], SOURCE_CHAIN_ID, address(source.coreRelayer)
        );

        stack.originalDelivery = pastDeliveries[stack.deliveryVaaHash];

        bytes memory fakeVM = abi.encodePacked(stack.originalDelivery.encodedVMs[1]);
        bytes memory correctVM = abi.encodePacked(stack.originalDelivery.encodedVMs[1]);
        change(fakeVM, fakeVM.length - 1);
        stack.originalDelivery.encodedVMs[1] = fakeVM;

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        stack.parsed = relayerWormhole.parseVM(stack.redeliveryVM);
        stack.instruction = target.coreRelayer.getRedeliveryByTxHashInstruction(stack.parsed.payload);

        stack.budget = stack.instruction.newMaximumRefundTarget + stack.instruction.newApplicationBudgetTarget;

        vm.prank(target.relayer);
        vm.expectRevert(bytes("9"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        stack.originalDelivery.encodedVMs[1] = stack.originalDelivery.encodedVMs[0];

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.prank(target.relayer);
        vm.expectRevert(bytes("10"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        stack.originalDelivery.encodedVMs[1] = correctVM;

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        correctVM = abi.encodePacked(stack.redeliveryVM);
        fakeVM = abi.encodePacked(correctVM);
        change(fakeVM, fakeVM.length - 1);

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            fakeVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.prank(target.relayer);
        vm.expectRevert(bytes("11"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        fakeVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], SOURCE_CHAIN_ID, address(source.integration)
        );
        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            fakeVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.prank(target.relayer);
        vm.expectRevert(bytes("12"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        source.relayProvider.updateDeliveryAddress(TARGET_CHAIN_ID, bytes32(uint256(uint160(address(this)))));
        vm.getRecordedLogs();
        source.coreRelayer.requestRedelivery{value: stack.payment}(stack.redeliveryRequest, 1, source.relayProvider);
        stack.entries = vm.getRecordedLogs();
        source.relayProvider.updateDeliveryAddress(TARGET_CHAIN_ID, bytes32(uint256(uint160(address(target.relayer)))));

        fakeVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], SOURCE_CHAIN_ID, address(source.coreRelayer)
        );
        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            fakeVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.prank(target.relayer);
        vm.expectRevert(bytes("13"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.expectRevert(bytes("14"));
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        uint16 differentChainId = 2;
        if (TARGET_CHAIN_ID == 2) {
            differentChainId = 3;
        }

        vm.deal(map[differentChainId].relayer, stack.budget);
        vm.expectRevert(bytes("15"));
        vm.prank(target.relayer);
        map[differentChainId].coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        stack.redeliveryRequest = ICoreRelayer.RedeliveryByTxHashRequest(
            SOURCE_CHAIN_ID,
            stack.deliveryVaaHash,
            1,
            differentChainId,
            stack.payment - source.wormhole.messageFee(),
            0,
            source.coreRelayer.getDefaultRelayParams()
        );
        source.relayProvider.updatePrice(differentChainId, gasParams.targetGasPrice, gasParams.targetNativePrice);
        source.relayProvider.updatePrice(differentChainId, gasParams.sourceGasPrice, gasParams.sourceNativePrice);
        source.relayProvider.updateDeliveryAddress(differentChainId, bytes32(uint256(uint160(address(target.relayer)))));
        vm.getRecordedLogs();
        source.coreRelayer.requestRedelivery{value: stack.payment}(stack.redeliveryRequest, 1, source.relayProvider);
        stack.entries = vm.getRecordedLogs();
        source.relayProvider.updateDeliveryAddress(
            differentChainId, bytes32(uint256(uint160(address(map[differentChainId].relayer))))
        );

        fakeVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], SOURCE_CHAIN_ID, address(source.coreRelayer)
        );
        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            fakeVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.expectRevert(bytes("16"));
        vm.prank(target.relayer);
        map[differentChainId].coreRelayer.redeliverSingle{value: stack.budget}(stack.package);

        stack.package = ICoreRelayer.TargetRedeliveryByTxHashParamsSingle(
            correctVM,
            stack.originalDelivery.encodedVMs,
            stack.originalDelivery.deliveryIndex,
            stack.originalDelivery.multisendIndex
        );

        vm.expectRevert(bytes("17"));
        vm.prank(target.relayer);
        target.coreRelayer.redeliverSingle{value: stack.budget - 1}(stack.package);

        assertTrue(
            (keccak256(target.integration.getMessage()) != keccak256(message))
                || (keccak256(message) == keccak256(bytes("")))
        );
        vm.prank(target.relayer);
        target.coreRelayer.redeliverSingle{value: stack.budget}(stack.package);
        assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));
    }

    /**
     * Delivery 18-24
     */
    struct DeliveryStackTooDeep {
        bytes32 deliveryVaaHash;
        uint256 payment;
        uint256 paymentNotEnough;
        Vm.Log[] entries;
        bytes actualVM;
        bytes deliveryVM;
        bytes[] encodedVMs;
        IWormhole.VM parsed;
        uint256 budget;
        ICoreRelayer.TargetDeliveryParametersSingle package;
        ICoreRelayer.DeliveryInstruction instruction;
    }

     function testRevertDeliveryErrors_18_19_20_21_22_23_24(
        GasParameters memory gasParams,
        bytes memory message
    ) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        DeliveryStackTooDeep memory stack;


        if(uint256(1)*gasParams.targetNativePrice*gasParams.targetGasPrice < uint256(1)*gasParams.sourceNativePrice*gasParams.sourceGasPrice) {
            stack.paymentNotEnough =  source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, 500000, source.relayProvider);

            source.integration.sendMessageWithForwardedResponse{value: stack.paymentNotEnough  + source.wormhole.messageFee()}(
                message, TARGET_CHAIN_ID, address(target.integration), address(target.refundAddress)
            );

            genericRelayer(SOURCE_CHAIN_ID, 2);

            assertTrue(keccak256(target.integration.getMessage()) == keccak256(message));
            stack.entries = vm.getRecordedLogs();



            stack.actualVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], TARGET_CHAIN_ID, address(target.integration)
            );

            stack.deliveryVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[1], TARGET_CHAIN_ID, address(target.coreRelayer)
            );
            
            stack.encodedVMs = new bytes[](2);
            stack.encodedVMs[0] = stack.actualVM;
            stack.encodedVMs[1] = stack.deliveryVM;

             stack.package = ICoreRelayer.TargetDeliveryParametersSingle(
            stack.encodedVMs,
            1,
            0
            );

            stack.parsed = relayerWormhole.parseVM(stack.deliveryVM);
            stack.instruction = target.coreRelayer.getDeliveryInstructionsContainer(stack.parsed.payload).instructions[0];

            stack.budget = stack.instruction.maximumRefundTarget + stack.instruction.applicationBudgetTarget;

            vm.prank(source.relayer);
            vm.expectRevert(bytes("20"));
            source.coreRelayer.deliverSingle{value: stack.budget}(stack.package);
        }


        stack.payment =  source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);


        source.wormhole.publishMessage{value: source.wormhole.messageFee()}(1, abi.encodePacked(uint8(0), bytes("hi!")), 200);

        ICoreRelayer.DeliveryRequest memory deliveryRequest = ICoreRelayer.DeliveryRequest(
            TARGET_CHAIN_ID, //target chain
            source.coreRelayer.toWormholeFormat(address(target.integration)), 
            source.coreRelayer.toWormholeFormat(address(target.refundAddress)), 
            stack.payment - source.wormhole.messageFee(),
            0,
            source.coreRelayer.getDefaultRelayParams() 
        );

        source.coreRelayer.requestDelivery{value: stack.payment}(deliveryRequest, 1, source.relayProvider);

        stack.entries = vm.getRecordedLogs();

        stack.actualVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], SOURCE_CHAIN_ID, address(this)
        );

        stack.deliveryVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[1], SOURCE_CHAIN_ID, address(source.coreRelayer)
        );

        bytes memory fakeVM = abi.encodePacked(stack.deliveryVM);

        change(fakeVM, fakeVM.length - 1);

        stack.encodedVMs = new bytes[](2);
        stack.encodedVMs[0] = stack.actualVM;
        stack.encodedVMs[1] = fakeVM;

        stack.package = ICoreRelayer.TargetDeliveryParametersSingle(
            stack.encodedVMs,
            1,
            0
        );

        stack.parsed = relayerWormhole.parseVM(stack.deliveryVM);
        stack.instruction = target.coreRelayer.getDeliveryInstructionsContainer(stack.parsed.payload).instructions[0];

        stack.budget = stack.instruction.maximumRefundTarget + stack.instruction.applicationBudgetTarget;

        vm.prank(target.relayer);
        vm.expectRevert(bytes("18"));
        target.coreRelayer.deliverSingle{value: stack.budget}(stack.package);

        stack.encodedVMs[1] = stack.encodedVMs[0];

        stack.package = ICoreRelayer.TargetDeliveryParametersSingle(
            stack.encodedVMs,
            1,
            0
        );

        vm.prank(target.relayer);
        vm.expectRevert(bytes("19"));
        target.coreRelayer.deliverSingle{value: stack.budget}(stack.package);

        stack.encodedVMs[1] = stack.deliveryVM;

        stack.package = ICoreRelayer.TargetDeliveryParametersSingle(
            stack.encodedVMs,
            1,
            0
        );

        
        vm.expectRevert(bytes("21"));
        target.coreRelayer.deliverSingle{value: stack.budget}(stack.package);

        vm.prank(target.relayer);
         vm.expectRevert(bytes("22"));
        target.coreRelayer.deliverSingle{value: stack.budget-1}(stack.package);

         uint16 differentChainId = 2;
        if (TARGET_CHAIN_ID == 2) {
            differentChainId = 3;
        }

        vm.prank(target.relayer);
        vm.expectRevert(bytes("24"));
        map[differentChainId].coreRelayer.deliverSingle{value: stack.budget}(stack.package);

         vm.prank(target.relayer);
        target.coreRelayer.deliverSingle{value: stack.budget}(stack.package);

         vm.prank(target.relayer);
         vm.expectRevert(bytes("23"));
        target.coreRelayer.deliverSingle{value: stack.budget}(stack.package);

    }

    struct RequestDeliveryStackTooDeep {
        uint256 payment;
        ICoreRelayer.DeliveryRequest deliveryRequest;
        uint256 deliveryOverhead;
        ICoreRelayer.DeliveryRequest badDeliveryRequest;
    }
    /**
     * Request delivery 25-27
     */
     function testRevertRequestDeliveryErrors_25_26_27(
        GasParameters memory gasParams,
        bytes memory message
    ) public {
        (uint16 SOURCE_CHAIN_ID, uint16 TARGET_CHAIN_ID, Contracts memory source, Contracts memory target) =
            standardAssumeAndSetupTwoChains(gasParams, 1000000);

        vm.recordLogs();

        RequestDeliveryStackTooDeep memory stack;

        stack.payment =  source.coreRelayer.quoteGasDeliveryFee(TARGET_CHAIN_ID, gasParams.targetGasLimit, source.relayProvider);


        source.wormhole.publishMessage{value: source.wormhole.messageFee()}(1, abi.encodePacked(uint8(0), bytes("hi!")), 200);

        stack.deliveryRequest = ICoreRelayer.DeliveryRequest(
            TARGET_CHAIN_ID, //target chain
            source.coreRelayer.toWormholeFormat(address(target.integration)), 
            source.coreRelayer.toWormholeFormat(address(target.refundAddress)), 
            stack.payment - source.wormhole.messageFee(),
            0,
            source.coreRelayer.getDefaultRelayParams() 
        );

        vm.expectRevert(bytes("25"));
        source.coreRelayer.requestDelivery{value: stack.payment - 1}(stack.deliveryRequest, 1, source.relayProvider);

        source.relayProvider.updateDeliverGasOverhead(TARGET_CHAIN_ID, gasParams.evmGasOverhead);

        stack.deliveryOverhead = source.relayProvider.quoteDeliveryOverhead(TARGET_CHAIN_ID);
        vm.assume(stack.deliveryOverhead > 0);

        stack.badDeliveryRequest = ICoreRelayer.DeliveryRequest(
            TARGET_CHAIN_ID, //target chain
            source.coreRelayer.toWormholeFormat(address(target.integration)), 
            source.coreRelayer.toWormholeFormat(address(target.refundAddress)), 
            stack.deliveryOverhead - 1,
            0,
            source.coreRelayer.getDefaultRelayParams() 
        );

        vm.expectRevert(bytes("26"));
        source.coreRelayer.requestDelivery{value: stack.deliveryOverhead - 1}(stack.badDeliveryRequest, 1, source.relayProvider);

        source.relayProvider.updateDeliverGasOverhead(TARGET_CHAIN_ID, 0);

        source.relayProvider.updateMaximumBudget(TARGET_CHAIN_ID, uint256(gasParams.targetGasLimit - 1) * gasParams.targetGasPrice);

        vm.expectRevert(bytes("27"));
        source.coreRelayer.requestDelivery{value: stack.payment}(stack.deliveryRequest, 1, source.relayProvider);

    }

    /**
     * asset conversoin 28-29
     */

    /**
     *
     *
     * GENERIC RELAYER CODE
     *
     *
     */

    mapping(uint256 => bool) nonceCompleted;

    mapping(bytes32 => ICoreRelayer.TargetDeliveryParametersSingle) pastDeliveries;

    function genericRelayer(uint16 chainId, uint8 num) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes[] memory encodedVMs = new bytes[](num);
        for (uint256 i = 0; i < num; i++) {
            encodedVMs[i] = relayerWormholeSimulator.fetchSignedMessageFromLogs(
                entries[i], chainId, address(uint160(uint256(bytes32(entries[i].topics[1]))))
            );
        }

        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedVMs.length);
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            parsed[i] = relayerWormhole.parseVM(encodedVMs[i]);
        }
        //uint16 chainId = parsed[parsed.length - 1].emitterChainId;
        Contracts memory contracts = map[chainId];

        for (uint16 i = 0; i < encodedVMs.length; i++) {
            if (!nonceCompleted[parsed[i].nonce]) {
                nonceCompleted[parsed[i].nonce] = true;
                uint8 length = 1;
                for (uint16 j = i + 1; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        length++;
                    }
                }
                bytes[] memory deliveryInstructions = new bytes[](length);
                uint8 counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        deliveryInstructions[counter] = encodedVMs[j];
                        counter++;
                    }
                }
                counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        if (
                            parsed[j].emitterAddress == toWormholeFormat(address(contracts.coreRelayer))
                                && (parsed[j].emitterChainId == chainId)
                        ) {
                            genericRelay(contracts, counter, encodedVMs[j], deliveryInstructions, parsed[j]);
                        }
                        counter += 1;
                    }
                }
            }
        }
        for (uint8 i = 0; i < encodedVMs.length; i++) {
            nonceCompleted[parsed[i].nonce] = false;
        }
    }

    function genericRelay(
        Contracts memory contracts,
        uint8 counter,
        bytes memory encodedVM,
        bytes[] memory deliveryInstructions,
        IWormhole.VM memory parsed
    ) internal {
        uint8 payloadId = parsed.payload.toUint8(0);
        if (payloadId == 1) {
            ICoreRelayer.DeliveryInstructionsContainer memory container =
                contracts.coreRelayer.getDeliveryInstructionsContainer(parsed.payload);
            for (uint8 k = 0; k < container.instructions.length; k++) {
                uint256 budget =
                    container.instructions[k].maximumRefundTarget + container.instructions[k].applicationBudgetTarget;
                ICoreRelayer.TargetDeliveryParametersSingle memory package =
                    ICoreRelayer.TargetDeliveryParametersSingle(deliveryInstructions, counter, k);
                uint16 targetChain = container.instructions[k].targetChain;
                uint256 wormholeFee = map[targetChain].wormhole.messageFee();
                vm.prank(map[targetChain].relayer);
                map[targetChain].coreRelayer.deliverSingle{value: (budget + wormholeFee)}(package);
                pastDeliveries[parsed.hash] = package;
            }
        } else if (payloadId == 2) {
            ICoreRelayer.RedeliveryByTxHashInstruction memory instruction =
                contracts.coreRelayer.getRedeliveryByTxHashInstruction(parsed.payload);
            ICoreRelayer.TargetDeliveryParametersSingle memory originalDelivery =
                pastDeliveries[instruction.sourceTxHash];
            uint256 budget = instruction.newMaximumRefundTarget + instruction.newApplicationBudgetTarget;
            uint16 targetChain = instruction.targetChain;
            ICoreRelayer.TargetRedeliveryByTxHashParamsSingle memory package = ICoreRelayer
                .TargetRedeliveryByTxHashParamsSingle(
                encodedVM, originalDelivery.encodedVMs, originalDelivery.deliveryIndex, originalDelivery.multisendIndex
            );

            vm.prank(map[targetChain].relayer);
            map[targetChain].coreRelayer.redeliverSingle{value: budget}(package);
        }
    }
}
