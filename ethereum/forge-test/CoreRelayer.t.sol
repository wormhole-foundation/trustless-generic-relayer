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
import {MockGenericRelayer} from "./MockGenericRelayer.sol";
import {MockWormhole} from "../contracts/mock/MockWormhole.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";
import {WormholeSimulator, FakeWormholeSimulator} from "./WormholeSimulator.sol";
import {IWormholeReceiver} from "../contracts/interfaces/IWormholeReceiver.sol";
import {AttackForwardIntegration} from "../contracts/mock/AttackForwardIntegration.sol";
import {MockRelayerIntegration, Structs} from "../contracts/mock/MockRelayerIntegration.sol";
import "../contracts/libraries/external/BytesLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract TestCoreRelayer is Test {
    using BytesLib for bytes;

    uint16 MAX_UINT16_VALUE = 65535;
    uint96 MAX_UINT96_VALUE = 79228162514264337593543950335;

    struct GasParameters {
        uint32 evmGasOverhead;
        uint32 targetGasLimit;
        uint128 targetGasPrice;
        uint128 sourceGasPrice;
    }

    struct FeeParameters {
        uint128 targetNativePrice;
        uint128 sourceNativePrice;
        uint128 wormholeFeeOnSource;
        uint128 wormholeFeeOnTarget;
        uint256 receiverValueTarget;
    }

    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;
    MockGenericRelayer genericRelayer;

    function setUp() public {
        // deploy Wormhole
        MockWormhole wormhole = new MockWormhole({
            initChainId: 2,
            initEvmChainId: block.chainid
        });

        relayerWormhole = wormhole;
        relayerWormholeSimulator = new FakeWormholeSimulator(
            wormhole
        );

        genericRelayer =
        new MockGenericRelayer(address(wormhole), address(relayerWormholeSimulator), address(setUpCoreRelayer(2, wormhole, address(0x1))));

        setUpChains(5);
    }

    function setUpWormhole(uint16 chainId)
        internal
        returns (IWormhole wormholeContract, WormholeSimulator wormholeSimulator)
    {
        // deploy Wormhole
        MockWormhole wormhole = new MockWormhole({
            initChainId: chainId,
            initEvmChainId: block.chainid
        });

        // replace Wormhole with the Wormhole Simulator contract (giving access to some nice helper methods for signing)
        wormholeSimulator = new FakeWormholeSimulator(
            wormhole
        );

        wormholeContract = wormhole;
    }

    function setUpRelayProvider(uint16 chainId) internal returns (RelayProvider relayProvider) {
        RelayProviderSetup relayProviderSetup = new RelayProviderSetup();
        RelayProviderImplementation relayProviderImplementation = new RelayProviderImplementation();
        RelayProviderProxy myRelayProvider = new RelayProviderProxy(
            address(relayProviderSetup),
            abi.encodeCall(
                RelayProviderSetup.setup,
                (
                    address(relayProviderImplementation),
                    chainId
                )
            )
        );

        relayProvider = RelayProvider(address(myRelayProvider));
    }

    function setUpCoreRelayer(uint16 chainId, IWormhole wormhole, address defaultRelayProvider)
        internal
        returns (IWormholeRelayer coreRelayer)
    {
        CoreRelayerSetup coreRelayerSetup = new CoreRelayerSetup();
        CoreRelayerImplementation coreRelayerImplementation = new CoreRelayerImplementation();
        CoreRelayerProxy myCoreRelayer = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeCall(
                CoreRelayerSetup.setup,
                (
                    address(coreRelayerImplementation),
                    chainId,
                    address(wormhole),
                    defaultRelayProvider,
                    wormhole.governanceChainId(),
                    wormhole.governanceContract(),
                    block.chainid
                )
            )
        );
        coreRelayer = IWormholeRelayer(address(myCoreRelayer));
    }

    struct StandardSetupTwoChains {
        uint16 sourceChainId;
        uint16 targetChainId;
        uint16 differentChainId;
        Contracts source;
        Contracts target;
    }

    function standardAssumeAndSetupTwoChains(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        uint32 minTargetGasLimit
    ) public returns (StandardSetupTwoChains memory s) {
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(feeParams.targetNativePrice > 0);
        vm.assume(gasParams.targetGasPrice > 0);
        vm.assume(gasParams.sourceGasPrice > 0);
        vm.assume(feeParams.sourceNativePrice > 0);
        vm.assume(
            feeParams.targetNativePrice
                < (uint256(2) ** 255)
                    / (
                        uint256(1) * gasParams.targetGasPrice
                            * (uint256(0) + gasParams.targetGasLimit + gasParams.evmGasOverhead) + feeParams.wormholeFeeOnTarget
                    )
        );
        vm.assume(
            feeParams.sourceNativePrice
                < (uint256(2) ** 255)
                    / (
                        uint256(1) * gasParams.sourceGasPrice
                            * (uint256(0) + gasParams.targetGasLimit + gasParams.evmGasOverhead) + feeParams.wormholeFeeOnSource
                    )
        );
        vm.assume(gasParams.sourceGasPrice < (uint256(2) ** 255) / feeParams.sourceNativePrice);
        vm.assume(gasParams.targetGasLimit >= minTargetGasLimit);
        vm.assume(
            1
                < (uint256(2) ** 255) / gasParams.targetGasLimit / gasParams.targetGasPrice
                    / (uint256(0) + feeParams.sourceNativePrice / feeParams.targetNativePrice + 2) / gasParams.targetGasLimit
        );
        vm.assume(
            1
                < (uint256(2) ** 255) / gasParams.targetGasLimit / gasParams.sourceGasPrice
                    / (uint256(0) + feeParams.targetNativePrice / feeParams.sourceNativePrice + 2) / gasParams.targetGasLimit
        );
        vm.assume(feeParams.receiverValueTarget < uint256(1) * (uint256(2) ** 239) / feeParams.targetNativePrice);

        s.sourceChainId = 1;
        s.targetChainId = 2;
        s.differentChainId = 3;
        s.source = map[s.sourceChainId];
        s.target = map[s.targetChainId];

        vm.deal(s.source.relayer, type(uint256).max / 2);
        vm.deal(s.target.relayer, type(uint256).max / 2);
        vm.deal(address(this), type(uint256).max / 2);
        vm.deal(address(s.target.integration), type(uint256).max / 2);
        vm.deal(address(s.source.integration), type(uint256).max / 2);

        // set relayProvider prices
        s.source.relayProvider.updatePrice(s.targetChainId, gasParams.targetGasPrice, feeParams.targetNativePrice);
        s.source.relayProvider.updatePrice(s.sourceChainId, gasParams.sourceGasPrice, feeParams.sourceNativePrice);
        s.target.relayProvider.updatePrice(s.targetChainId, gasParams.targetGasPrice, feeParams.targetNativePrice);
        s.target.relayProvider.updatePrice(s.sourceChainId, gasParams.sourceGasPrice, feeParams.sourceNativePrice);

        s.source.relayProvider.updateDeliverGasOverhead(s.targetChainId, gasParams.evmGasOverhead);
        s.target.relayProvider.updateDeliverGasOverhead(s.sourceChainId, gasParams.evmGasOverhead);

        s.source.wormholeSimulator.setMessageFee(feeParams.wormholeFeeOnSource);
        s.target.wormholeSimulator.setMessageFee(feeParams.wormholeFeeOnTarget);

        genericRelayer.setWormholeFee(s.sourceChainId, feeParams.wormholeFeeOnSource);
        genericRelayer.setWormholeFee(s.targetChainId, feeParams.wormholeFeeOnTarget);

        uint32 wormholeFeeOnTargetInSourceCurrency = uint32(
            feeParams.wormholeFeeOnTarget * s.source.relayProvider.quoteAssetPrice(s.targetChainId)
                / s.source.relayProvider.quoteAssetPrice(s.sourceChainId) + 1
        );
        s.source.relayProvider.updateWormholeFee(s.targetChainId, wormholeFeeOnTargetInSourceCurrency);
        uint32 wormholeFeeOnSourceInTargetCurrency = uint32(
            feeParams.wormholeFeeOnSource * s.target.relayProvider.quoteAssetPrice(s.sourceChainId)
                / s.target.relayProvider.quoteAssetPrice(s.targetChainId) + 1
        );
        s.target.relayProvider.updateWormholeFee(s.sourceChainId, wormholeFeeOnSourceInTargetCurrency);
    }

    struct Contracts {
        IWormhole wormhole;
        WormholeSimulator wormholeSimulator;
        RelayProvider relayProvider;
        IWormholeRelayer coreRelayer;
        CoreRelayer coreRelayerFull;
        MockRelayerIntegration integration;
        address relayer;
        address payable rewardAddress;
        address payable refundAddress;
        uint16 chainId;
    }

    mapping(uint16 => Contracts) map;

    function setUpChains(uint16 numChains) internal {
        for (uint16 i = 1; i <= numChains; i++) {
            Contracts memory mapEntry;
            (mapEntry.wormhole, mapEntry.wormholeSimulator) = setUpWormhole(i);
            mapEntry.relayProvider = setUpRelayProvider(i);
            mapEntry.coreRelayer = setUpCoreRelayer(i, mapEntry.wormhole, address(mapEntry.relayProvider));
            mapEntry.coreRelayerFull = CoreRelayer(address(mapEntry.coreRelayer));
            genericRelayer.setWormholeRelayerContract(i, address(mapEntry.coreRelayer));
            mapEntry.integration = new MockRelayerIntegration(address(mapEntry.wormhole), address(mapEntry.coreRelayer));
            mapEntry.relayer = address(uint160(uint256(keccak256(abi.encodePacked(bytes("relayer"), i)))));
            genericRelayer.setProviderDeliveryAddress(i, mapEntry.relayer);
            mapEntry.refundAddress =
                payable(address(uint160(uint256(keccak256(abi.encodePacked(bytes("refundAddress"), i))))));
            mapEntry.rewardAddress =
                payable(address(uint160(uint256(keccak256(abi.encodePacked(bytes("rewardAddress"), i))))));
            mapEntry.chainId = i;
            map[i] = mapEntry;
        }
        uint256 maxBudget = type(uint256).max;
        for (uint16 i = 1; i <= numChains; i++) {
            for (uint16 j = 1; j <= numChains; j++) {
                map[i].relayProvider.updateDeliveryAddress(j, bytes32(uint256(uint160(map[j].relayer))));
                map[i].relayProvider.updateAssetConversionBuffer(j, 500, 10000);
                map[i].relayProvider.updateRewardAddress(map[i].rewardAddress);
                registerCoreRelayerContract(
                    map[i].coreRelayerFull, i, j, bytes32(uint256(uint160(address(map[j].coreRelayer))))
                );
                map[i].relayProvider.updateMaximumBudget(j, maxBudget);
                map[i].integration.registerEmitter(j, bytes32(uint256(uint160(address(map[j].integration)))));
                Structs.XAddress[] memory addresses = new Structs.XAddress[](1);
                addresses[0] = Structs.XAddress(j, bytes32(uint256(uint160(address(map[j].integration)))));
                map[i].integration.registerEmitters(addresses);
            }
        }
    }

    function registerCoreRelayerContract(
        CoreRelayer governance,
        uint16 currentChainId,
        uint16 chainId,
        bytes32 coreRelayerContractAddress
    ) internal {
        bytes32 coreRelayerModule = 0x000000000000000000000000000000000000000000436f726552656c61796572;
        bytes memory message =
            abi.encodePacked(coreRelayerModule, uint8(2), currentChainId, chainId, coreRelayerContractAddress);
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

    function getDeliveryVAAHash() internal returns (bytes32 vaaHash) {
        vaaHash = vm.getRecordedLogs()[0].data.toBytes32(0);
    }

    function testSend(GasParameters memory gasParams, FeeParameters memory feeParams, bytes memory message) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 maxTransactionFee = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        );

        setup.source.integration.sendMessageWithRefundAddress{
            value: maxTransactionFee + uint256(3) * setup.source.wormhole.messageFee()
        }(message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress));

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));
    }

    function testFundsCorrectForASend(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        uint256 refundAddressBalance = setup.target.refundAddress.balance;
        uint256 relayerBalance = setup.target.relayer.balance;
        uint256 rewardAddressBalance = setup.source.rewardAddress.balance;
        uint256 receiverValueSource = setup.source.coreRelayer.quoteReceiverValue(
            setup.targetChainId, feeParams.receiverValueTarget, address(setup.source.relayProvider)
        );
        uint256 payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + uint256(3) * setup.source.wormhole.messageFee() + receiverValueSource;

        setup.source.integration.sendMessageGeneral{value: payment}(
            message,
            setup.targetChainId,
            address(setup.target.integration),
            address(setup.target.refundAddress),
            receiverValueSource,
            1
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        uint256 USDcost = (uint256(payment) - uint256(3) * map[setup.sourceChainId].wormhole.messageFee())
            * feeParams.sourceNativePrice
            - (setup.target.refundAddress.balance - refundAddressBalance) * feeParams.targetNativePrice;
        uint256 relayerProfit = uint256(feeParams.sourceNativePrice)
            * (setup.source.rewardAddress.balance - rewardAddressBalance)
            - feeParams.targetNativePrice * (relayerBalance - setup.target.relayer.balance);

        uint256 howMuchGasRelayerCouldHavePaidForAndStillProfited =
            relayerProfit / gasParams.targetGasPrice / feeParams.targetNativePrice;
        assertTrue(howMuchGasRelayerCouldHavePaidForAndStillProfited >= 30000); // takes around this much gas (seems to go from 36k-200k?!?)
        assertTrue(
            USDcost - (relayerProfit + (uint256(1) * feeParams.receiverValueTarget * feeParams.targetNativePrice)) >= 0,
            "We paid enough"
        );
        assertTrue(
            USDcost - (relayerProfit + (uint256(1) * feeParams.receiverValueTarget * feeParams.targetNativePrice))
                < feeParams.sourceNativePrice,
            "We paid the least amount necessary"
        );
    }

    function testFundsCorrectForASendIfReceiveWormholeMessagesReverts(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        uint256 refundAddressBalance = setup.target.refundAddress.balance;
        uint256 relayerBalance = setup.target.relayer.balance;
        uint256 rewardAddressBalance = setup.source.rewardAddress.balance;
        uint256 receiverValueSource = setup.source.coreRelayer.quoteReceiverValue(
            setup.targetChainId, feeParams.receiverValueTarget, address(setup.source.relayProvider)
        );

        uint256 payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, 21000, address(setup.source.relayProvider)
        ) + uint256(3) * setup.source.wormhole.messageFee() + receiverValueSource;

        setup.source.integration.sendMessageGeneral{value: payment}(
            message,
            setup.targetChainId,
            address(setup.target.integration),
            address(setup.target.refundAddress),
            receiverValueSource,
            1
        );

        genericRelayer.relay(setup.sourceChainId);

        uint256 USDcost = uint256(payment - uint256(3) * map[setup.sourceChainId].wormhole.messageFee())
            * feeParams.sourceNativePrice
            - (setup.target.refundAddress.balance - refundAddressBalance) * feeParams.targetNativePrice;
        uint256 relayerProfit = uint256(feeParams.sourceNativePrice)
            * (setup.source.rewardAddress.balance - rewardAddressBalance)
            - feeParams.targetNativePrice * (relayerBalance - setup.target.relayer.balance);
        console.log(USDcost);
        console.log(relayerProfit);
        console.log((USDcost - relayerProfit));
        assertTrue(USDcost == relayerProfit, "We paid the exact amount");
    }

    function testForward(GasParameters memory gasParams, FeeParameters memory feeParams, bytes memory message) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.assume(
            uint256(1) * gasParams.targetGasPrice * feeParams.targetNativePrice
                > uint256(1) * gasParams.sourceGasPrice * feeParams.sourceNativePrice
        );

        vm.recordLogs();
        vm.assume(
            setup.source.coreRelayer.quoteGas(
                setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
            ) < uint256(2) ** 221
        );
        vm.assume(
            setup.target.coreRelayer.quoteGas(setup.sourceChainId, 500000, address(setup.target.relayProvider))
                < uint256(2) ** 221 / feeParams.targetNativePrice
        );
        // estimate the cost based on the intialized values
        uint256 payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + uint256(3) * setup.source.wormhole.messageFee();

        uint256 payment2 = (
            setup.target.coreRelayer.quoteGas(setup.sourceChainId, 500000, address(setup.target.relayProvider))
                + uint256(2) * setup.target.wormhole.messageFee()
        ) * feeParams.targetNativePrice / feeParams.sourceNativePrice + 1;

        vm.assume((payment + payment2) < (uint256(2) ** 222));

        setup.source.integration.sendMessageWithForwardedResponse{value: payment + payment2}(
            message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        genericRelayer.relay(setup.targetChainId);

        assertTrue(keccak256(setup.source.integration.getMessage()) == keccak256(bytes("received!")));
    }

    function testAttackForwardRequestCache(GasParameters memory gasParams, FeeParameters memory feeParams) public {
        // General idea:
        // 1. Attacker sets up a malicious integration contract in the target chain.
        // 2. Attacker requests a message send to `target` chain.
        //   The message destination and the refund address are both the malicious integration contract in the target chain.
        // 3. The delivery of the message triggers a refund to the malicious integration contract.
        // 4. During the refund, the integration contract activates the forwarding mechanism.
        //   This is allowed due to the integration contract also being the target of the delivery.
        // 5. The forward request is left as is in the `CoreRelayer` state.
        // 6. The next message (i.e. the victim's message) delivery on `target` chain, from any relayer, using any `RelayProvider` and any integration contract,
        //   will see the forward request placed by the malicious integration contract and act on it.
        // Caveat: the delivery of the victim's message must not invoke the forwarding mechanism for the attack test to be meaningful.
        //
        // In essence, this tries to attack the shared forwarding request cache present in the contract state.
        // This attack doesn't work thanks to the check inside the `requestForward` function that only allows requesting a forward when there is a delivery being processed.

        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        // Collected funds from the attack are meant to be sent here.
        address attackerSourceAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes("attackerAddress"), setup.sourceChainId)))));
        assertTrue(attackerSourceAddress.balance == 0);

        // Borrowed assumes from testForward. They should help since this test is similar.
        vm.assume(
            uint256(1) * gasParams.targetGasPrice * feeParams.targetNativePrice
                > uint256(1) * gasParams.sourceGasPrice * feeParams.sourceNativePrice
        );

        vm.assume(
            setup.source.coreRelayer.quoteGas(
                setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
            ) < uint256(2) ** 222
        );
        vm.assume(
            setup.target.coreRelayer.quoteGas(setup.sourceChainId, 500000, address(setup.target.relayProvider))
                < uint256(2) ** 222 / feeParams.targetNativePrice
        );

        // Estimate the cost based on the initialized values
        uint256 computeBudget = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        );

        {
            AttackForwardIntegration attackerContract =
            new AttackForwardIntegration(setup.target.wormhole, setup.target.coreRelayer, setup.targetChainId, attackerSourceAddress);
            bytes memory attackMsg = "attack";

            vm.recordLogs();

            // The attacker requests the message to be sent to the malicious contract.
            // It is critical that the refund and destination (aka integrator) addresses are the same.
            setup.source.integration.sendMessage{value: computeBudget + uint256(3) * setup.source.wormhole.messageFee()}(
                attackMsg, setup.targetChainId, address(attackerContract)
            );

            // The relayer triggers the call to the malicious contract.
            genericRelayer.relay(setup.sourceChainId);

            // The message delivery should fail
            assertTrue(keccak256(setup.target.integration.getMessage()) != keccak256(attackMsg));
        }

        {
            // Now one victim sends their message. It doesn't need to be from the same source chain.
            // What's necessary is that a message is delivered to the chain targeted by the attacker.
            bytes memory victimMsg = "relay my message";

            uint256 victimBalancePreDelivery = setup.target.refundAddress.balance;

            // We will reutilize the compute budget estimated for the attacker to simplify the code here.
            // The victim requests their message to be sent.
            setup.source.integration.sendMessageWithRefundAddress{
                value: computeBudget + uint256(3) * setup.source.wormhole.messageFee()
            }(victimMsg, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress));

            // The relayer delivers the victim's message.
            // During the delivery process, the forward request injected by the malicious contract is acknowledged.
            // The victim's refund address is not called due to this.
            genericRelayer.relay(setup.sourceChainId);

            // Ensures the message was received.
            assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(victimMsg));
            // Here we assert that the victim's refund is safe.
            assertTrue(victimBalancePreDelivery < setup.target.refundAddress.balance);
        }

        genericRelayer.relay(setup.targetChainId);

        // Assert that the attack wasn't successful.
        assertTrue(attackerSourceAddress.balance == 0);
    }

    function sendWithoutEnoughMaxTransactionFee(bytes memory message, StandardSetupTwoChains memory setup)
        internal
        returns (bytes32 deliveryVaaHash)
    {
        uint256 paymentNotEnough = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, 10, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee() * 3;

        vm.deal(address(this), paymentNotEnough);
        setup.source.integration.sendMessageWithRefundAddress{value: paymentNotEnough}(
            message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(
            (keccak256(setup.target.integration.getMessage()) != keccak256(message))
                || (keccak256(message) == keccak256(bytes("")))
        );

        return getDeliveryVAAHash();
    }

    function testResend(GasParameters memory gasParams, FeeParameters memory feeParams, bytes memory message) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        bytes32 deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        uint256 newMaxTransactionFeeFee = setup.source.coreRelayer.quoteReceiverValue(
            setup.targetChainId, feeParams.receiverValueTarget, address(setup.source.relayProvider)
        );

        IWormholeRelayer.ResendByTx memory redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: uint8(2),
            multisendIndex: uint8(0),
            newMaxTransactionFee: payment - setup.source.wormhole.messageFee(),
            newReceiverValue: newMaxTransactionFeeFee,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), payment + newMaxTransactionFeeFee);

        setup.source.coreRelayer.resend{value: payment + newMaxTransactionFeeFee}(
            redeliveryRequest, address(setup.source.relayProvider)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));
    }

    function testQuoteReceiverValueIsEnough(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);
        vm.assume(feeParams.receiverValueTarget > 0);
        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        uint256 oldBalance = address(setup.target.integration).balance;

        bytes32 deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        uint256 newMaxTransactionFeeFee = setup.source.coreRelayer.quoteReceiverValue(
            setup.targetChainId, feeParams.receiverValueTarget, address(setup.source.relayProvider)
        );

        IWormholeRelayer.ResendByTx memory redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: payment - setup.source.wormhole.messageFee(),
            newReceiverValue: newMaxTransactionFeeFee,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), payment + newMaxTransactionFeeFee);

        setup.source.coreRelayer.resend{value: payment + newMaxTransactionFeeFee}(
            redeliveryRequest, address(setup.source.relayProvider)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        assertTrue(address(setup.target.integration).balance >= oldBalance + feeParams.receiverValueTarget);
    }

    function testQuoteReceiverValueIsNotMoreThanNecessary(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);
        vm.assume(feeParams.receiverValueTarget > 0);
        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        bytes32 deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        uint256 oldBalance = address(setup.target.integration).balance;

        uint256 newMaxTransactionFeeFee = setup.source.coreRelayer.quoteReceiverValue(
            setup.targetChainId, feeParams.receiverValueTarget, address(setup.source.relayProvider)
        );

        IWormholeRelayer.ResendByTx memory redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: payment - setup.source.wormhole.messageFee(),
            newReceiverValue: newMaxTransactionFeeFee - 1,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), payment + newMaxTransactionFeeFee - 1);

        setup.source.coreRelayer.resend{value: payment + newMaxTransactionFeeFee - 1}(
            redeliveryRequest, address(setup.source.relayProvider)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        assertTrue(address(setup.target.integration).balance < oldBalance + feeParams.receiverValueTarget);
    }

    function testTwoSends(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message,
        bytes memory secondMessage
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        // estimate the cost based on the intialized values
        uint256 payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + uint256(3) * setup.source.wormhole.messageFee();

        // This avoids payment overflow in the target.
        vm.assume(payment <= type(uint256).max >> 1);

        // start listening to events
        vm.recordLogs();

        setup.source.integration.sendMessageWithRefundAddress{value: payment}(
            message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        vm.getRecordedLogs();

        vm.deal(address(this), payment);

        setup.source.integration.sendMessageWithRefundAddress{value: payment}(
            secondMessage, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress)
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(secondMessage));
    }

    function testRevertNonceZero(GasParameters memory gasParams, FeeParameters memory feeParams, bytes memory message)
        public
    {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        uint256 wormholeFee = setup.source.wormhole.messageFee();
        // estimate the cost based on the intialized values
        uint256 maxTransactionFee = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        );

        vm.expectRevert(abi.encodeWithSignature("NonceIsZero()"));

        setup.source.integration.sendMessageGeneral{value: maxTransactionFee + 3 * wormholeFee}(
            message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress), 0, 0
        );
    }

    /**
     * Redelivery  9-17
     */
    struct RedeliveryStack {
        bytes32 deliveryVaaHash;
        uint256 payment;
        Vm.Log[] entries;
        bytes redeliveryVM;
        IWormhole.VM parsed;
        uint256 budget;
        IWormholeRelayer.ResendByTx redeliveryRequest;
        bytes[] originalEncodedVMs;
        IDelivery.TargetRedeliveryByTxHashParamsSingle package;
        CoreRelayer.RedeliveryByTxHashInstruction instruction;
    }

    function invalidateVM(bytes memory message, WormholeSimulator simulator) internal {
        change(message, message.length - 1);
        simulator.invalidateVM(message);
    }

    function change(bytes memory message, uint256 index) internal pure {
        if (message[index] == 0x02) {
            message[index] = 0x04;
        } else {
            message[index] = 0x02;
        }
    }

    function prepareRedeliveryStack(
        RedeliveryStack memory stack,
        bytes memory message,
        StandardSetupTwoChains memory setup,
        GasParameters memory gasParams
    ) internal {
        stack.deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), stack.payment);

        setup.source.coreRelayer.resend{value: stack.payment}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );

        stack.entries = vm.getRecordedLogs();

        stack.redeliveryVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], setup.sourceChainId, address(setup.source.coreRelayer)
        );

        stack.originalEncodedVMs = genericRelayer.getPastEncodedVMs(stack.deliveryVaaHash);

        stack.package = IDelivery.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM, stack.originalEncodedVMs, payable(setup.target.relayer)
        );

        stack.parsed = relayerWormhole.parseVM(stack.redeliveryVM);
        stack.instruction = setup.target.coreRelayerFull.decodeRedeliveryInstruction(stack.parsed.payload);

        stack.budget = stack.instruction.newMaximumRefundTarget + stack.instruction.newReceiverValueTarget
            + setup.target.wormhole.messageFee();
    }

    event Delivery(
        address indexed recipientContract,
        uint16 indexed sourceChain,
        uint64 indexed sequence,
        bytes32 deliveryVaaHash,
        DeliveryStatus status
    );

    enum DeliveryStatus {
        SUCCESS,
        RECEIVER_FAILURE,
        FORWARD_REQUEST_FAILURE,
        FORWARD_REQUEST_SUCCESS,
        INVALID_REDELIVERY
    }

    function testRevertResendMsgValueTooLow(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        stack.deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });
        vm.deal(address(this), stack.payment);
        vm.expectRevert(abi.encodeWithSignature("MsgValueTooLow()"));
        setup.source.coreRelayer.resend{value: stack.payment - 1}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );
    }

    function testRevertRedeliveryInvalidOriginalDeliveryVaa(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        bytes memory fakeVM = abi.encodePacked(stack.originalEncodedVMs[2]);
        invalidateVM(fakeVM, setup.target.wormholeSimulator);
        stack.originalEncodedVMs[2] = fakeVM;

        stack.package = IDelivery.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM, stack.originalEncodedVMs, payable(setup.target.relayer)
        );

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidVaa(uint8,string)", 2, ""));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryInvalidEmitterInOriginalDeliveryVaa(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        stack.originalEncodedVMs[2] = stack.originalEncodedVMs[0];

        stack.package = IDelivery.TargetRedeliveryByTxHashParamsSingle(
            stack.redeliveryVM, stack.originalEncodedVMs, payable(setup.target.relayer)
        );

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidEmitterInOriginalDeliveryVM(uint8)", 2));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryInvalidRedeliveryVaa(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        bytes memory fakeVM = abi.encodePacked(stack.redeliveryVM);
        invalidateVM(fakeVM, setup.target.wormholeSimulator);

        stack.package = IDelivery.TargetRedeliveryByTxHashParamsSingle(
            fakeVM, stack.originalEncodedVMs, payable(setup.target.relayer)
        );

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidRedeliveryVM(string)", ""));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryInvalidEmitterInRedeliveryVM(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        bytes memory fakeVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], setup.sourceChainId, address(setup.source.integration)
        );

        stack.package = IDelivery.TargetRedeliveryByTxHashParamsSingle(
            fakeVM, stack.originalEncodedVMs, payable(setup.target.relayer)
        );

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidEmitterInRedeliveryVM()"));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryUnexpectedRelayer(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        vm.deal(address(this), stack.budget);
        vm.expectRevert(abi.encodeWithSignature("UnexpectedRelayer()"));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryTargetChainIsNotThisChain(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("TargetChainIsNotThisChain(uint16)", setup.targetChainId));
        map[setup.differentChainId].coreRelayerFull.redeliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertRedeliveryInsufficientRelayerFunds(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        prepareRedeliveryStack(stack, message, setup, gasParams);

        vm.deal(setup.target.relayer, stack.budget);
        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InsufficientRelayerFunds()"));
        setup.target.coreRelayerFull.redeliverSingle{value: stack.budget - 1}(stack.package);
    }

    function testEmitInvalidRedeliveryOriginalAndNewProviderDeliveryAddressesDiffer(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        setup.source.relayProvider.updateDeliveryAddress(
            setup.targetChainId, setup.source.coreRelayer.toWormholeFormat(address(0x1))
        );
        address originalTargetRelayer = setup.target.relayer;
        setup.target.relayer = address(0x1);
        genericRelayer.setProviderDeliveryAddress(setup.targetChainId, address(0x1));
        vm.deal(setup.target.relayer, type(uint256).max / 2);

        stack.deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        setup.target.relayer = originalTargetRelayer;
        setup.source.relayProvider.updateDeliveryAddress(
            setup.targetChainId, setup.source.coreRelayer.toWormholeFormat(setup.target.relayer)
        );
        genericRelayer.setProviderDeliveryAddress(setup.targetChainId, setup.target.relayer);

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), stack.payment);
        setup.source.coreRelayer.resend{value: stack.payment}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );

        vm.expectEmit(true, true, true, true, address(setup.target.coreRelayer));
        emit Delivery({
            recipientContract: address(setup.target.integration),
            sourceChain: setup.sourceChainId,
            sequence: 0,
            deliveryVaaHash: stack.deliveryVaaHash,
            status: DeliveryStatus.INVALID_REDELIVERY
        });
        genericRelayer.relay(setup.sourceChainId);
    }

    function testEmitInvalidRedeliveryOriginalTargetChainIsThisChain(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        stack.deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.sourceChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        vm.assume(setup.sourceChainId != setup.targetChainId);

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.sourceChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), stack.payment);
        setup.source.coreRelayer.resend{value: stack.payment}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );

        vm.expectEmit(true, true, true, true, address(setup.source.coreRelayer));
        emit Delivery({
            recipientContract: address(setup.target.integration),
            sourceChain: setup.sourceChainId,
            sequence: 0,
            deliveryVaaHash: stack.deliveryVaaHash,
            status: DeliveryStatus.INVALID_REDELIVERY
        });
        genericRelayer.relay(setup.sourceChainId);
    }

    function testEmitInvalidRedeliveryReceiverValueTargetLessThanOriginal(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        uint256 paymentNotEnough = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, 10, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee() * 3;

        uint256 receiverValue =
            setup.source.coreRelayer.quoteReceiverValue(setup.targetChainId, 100, address(setup.source.relayProvider));

        vm.deal(address(this), paymentNotEnough + receiverValue);
        setup.source.integration.sendMessageGeneral{value: paymentNotEnough + receiverValue}(
            message,
            setup.targetChainId,
            address(setup.target.integration),
            address(setup.target.refundAddress),
            receiverValue,
            1
        );

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(
            (keccak256(setup.target.integration.getMessage()) != keccak256(message))
                || (keccak256(message) == keccak256(bytes("")))
        );

        stack.deliveryVaaHash = getDeliveryVAAHash();

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, 200000, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), stack.payment);
        setup.source.coreRelayer.resend{value: stack.payment}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );

        vm.expectEmit(true, true, true, true, address(setup.target.coreRelayer));
        emit Delivery({
            recipientContract: address(setup.target.integration),
            sourceChain: setup.sourceChainId,
            sequence: 0,
            deliveryVaaHash: stack.deliveryVaaHash,
            status: DeliveryStatus.INVALID_REDELIVERY
        });
        genericRelayer.relay(setup.sourceChainId);
    }

    function testEmitInvalidRedeliveryGasLimitTargetLessThanOriginal(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        RedeliveryStack memory stack;

        stack.deliveryVaaHash = sendWithoutEnoughMaxTransactionFee(message, setup);

        stack.payment = setup.source.coreRelayer.quoteGasResend(
            setup.targetChainId, 9, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        stack.redeliveryRequest = IWormholeRelayer.ResendByTx({
            sourceChain: setup.sourceChainId,
            sourceTxHash: stack.deliveryVaaHash,
            sourceNonce: 1,
            targetChain: setup.targetChainId,
            deliveryIndex: 2,
            multisendIndex: 0,
            newMaxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            newReceiverValue: 0,
            newRelayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.deal(address(this), stack.payment);
        setup.source.coreRelayer.resend{value: stack.payment}(
            stack.redeliveryRequest, address(setup.source.relayProvider)
        );

        vm.expectEmit(true, true, true, true, address(setup.target.coreRelayer));
        emit Delivery({
            recipientContract: address(setup.target.integration),
            sourceChain: setup.sourceChainId,
            sequence: 0,
            deliveryVaaHash: stack.deliveryVaaHash,
            status: DeliveryStatus.INVALID_REDELIVERY
        });
        genericRelayer.relay(setup.sourceChainId);
    }

    struct DeliveryStack {
        bytes32 deliveryVaaHash;
        uint256 payment;
        uint256 paymentNotEnough;
        Vm.Log[] entries;
        bytes actualVM1;
        bytes actualVM2;
        bytes deliveryVM;
        bytes[] encodedVMs;
        IWormhole.VM parsed;
        uint256 budget;
        IDelivery.TargetDeliveryParametersSingle package;
        CoreRelayer.DeliveryInstruction instruction;
    }

    function prepareDeliveryStack(DeliveryStack memory stack, StandardSetupTwoChains memory setup) internal {
        stack.entries = vm.getRecordedLogs();

        stack.actualVM1 = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[0], setup.sourceChainId, address(setup.source.integration)
        );

        stack.actualVM2 = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[1], setup.sourceChainId, address(setup.source.integration)
        );

        stack.deliveryVM = relayerWormholeSimulator.fetchSignedMessageFromLogs(
            stack.entries[2], setup.sourceChainId, address(setup.source.coreRelayer)
        );

        stack.encodedVMs = new bytes[](3);
        stack.encodedVMs[0] = stack.actualVM1;
        stack.encodedVMs[1] = stack.actualVM2;
        stack.encodedVMs[2] = stack.deliveryVM;

        stack.package = IDelivery.TargetDeliveryParametersSingle({
            encodedVMs: stack.encodedVMs,
            deliveryIndex: 2,
            multisendIndex: 0,
            relayerRefundAddress: payable(setup.target.relayer)
        });

        stack.parsed = relayerWormhole.parseVM(stack.deliveryVM);
        stack.instruction =
            setup.target.coreRelayerFull.decodeDeliveryInstructionsContainer(stack.parsed.payload).instructions[0];

        stack.budget = stack.instruction.maximumRefundTarget + stack.instruction.receiverValueTarget
            + setup.target.wormhole.messageFee();
    }

    function testRevertDeliverySendNotSufficientlyFunded(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        vm.assume(
            uint256(1) * feeParams.targetNativePrice * gasParams.targetGasPrice * 10
                < uint256(1) * feeParams.sourceNativePrice * gasParams.sourceGasPrice
        );
        stack.paymentNotEnough =
            setup.source.coreRelayer.quoteGas(setup.targetChainId, 600000, address(setup.source.relayProvider));

        setup.source.integration.sendMessageWithForwardedResponse{
            value: stack.paymentNotEnough + 3 * setup.source.wormhole.messageFee()
        }(message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress));

        genericRelayer.relay(setup.sourceChainId);

        assertTrue(keccak256(setup.target.integration.getMessage()) == keccak256(message));

        prepareDeliveryStack(stack, setup);

        vm.deal(setup.source.relayer, stack.budget);
        vm.prank(setup.source.relayer);
        vm.expectRevert(abi.encodeWithSignature("SendNotSufficientlyFunded()"));
        setup.source.coreRelayerFull.deliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertDeliveryInvalidDeliveryVAA(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + 3 * setup.source.wormhole.messageFee();

        setup.source.integration.sendMessageWithRefundAddress{value: stack.payment}(
            message, setup.targetChainId, address(setup.target.integration), setup.target.refundAddress
        );

        prepareDeliveryStack(stack, setup);

        bytes memory fakeVM = abi.encodePacked(stack.deliveryVM);

        invalidateVM(fakeVM, setup.target.wormholeSimulator);

        stack.encodedVMs[2] = fakeVM;

        stack.package = IDelivery.TargetDeliveryParametersSingle({
            encodedVMs: stack.encodedVMs,
            deliveryIndex: 2,
            multisendIndex: 0,
            relayerRefundAddress: payable(setup.target.relayer)
        });

        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidVaa(uint8,string)", 2, ""));
        setup.target.coreRelayerFull.deliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertDeliveryInvalidEmitter(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + 3 * setup.source.wormhole.messageFee();

        setup.source.integration.sendMessageWithRefundAddress{value: stack.payment}(
            message, setup.targetChainId, address(setup.target.integration), setup.target.refundAddress
        );

        prepareDeliveryStack(stack, setup);

        stack.encodedVMs[2] = stack.encodedVMs[0];

        stack.package = IDelivery.TargetDeliveryParametersSingle({
            encodedVMs: stack.encodedVMs,
            deliveryIndex: 2,
            multisendIndex: 0,
            relayerRefundAddress: payable(setup.target.relayer)
        });

        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidEmitter()"));
        setup.target.coreRelayerFull.deliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertDeliveryUnexpectedRelayer(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + 3 * setup.source.wormhole.messageFee();

        setup.source.integration.sendMessageWithRefundAddress{value: stack.payment}(
            message, setup.targetChainId, address(setup.target.integration), setup.target.refundAddress
        );

        prepareDeliveryStack(stack, setup);

        vm.expectRevert(abi.encodeWithSignature("UnexpectedRelayer()"));
        setup.target.coreRelayerFull.deliverSingle{value: stack.budget}(stack.package);
    }

    function testRevertDeliveryInsufficientRelayerFunds(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + 3 * setup.source.wormhole.messageFee();

        setup.source.integration.sendMessageWithRefundAddress{value: stack.payment}(
            message, setup.targetChainId, address(setup.target.integration), setup.target.refundAddress
        );

        prepareDeliveryStack(stack, setup);

        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("InsufficientRelayerFunds()"));
        setup.target.coreRelayerFull.deliverSingle{value: stack.budget - 1}(stack.package);
    }

    function testRevertDeliveryTargetChainIsNotThisChain(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        DeliveryStack memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + 3 * setup.source.wormhole.messageFee();

        setup.source.integration.sendMessageWithRefundAddress{value: stack.payment}(
            message, setup.targetChainId, address(setup.target.integration), setup.target.refundAddress
        );

        prepareDeliveryStack(stack, setup);

        vm.prank(setup.target.relayer);
        vm.expectRevert(abi.encodeWithSignature("TargetChainIsNotThisChain(uint16)", 2));
        map[setup.differentChainId].coreRelayerFull.deliverSingle{value: stack.budget}(stack.package);
    }

    struct SendStackTooDeep {
        uint256 payment;
        IWormholeRelayer.Send deliveryRequest;
        uint256 deliveryOverhead;
        IWormholeRelayer.Send badSend;
    }
    /**
     * Request delivery 25-27
     */

    function testRevertSendErrors(GasParameters memory gasParams, FeeParameters memory feeParams) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        SendStackTooDeep memory stack;

        stack.payment = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        ) + setup.source.wormhole.messageFee();

        setup.source.wormhole.publishMessage{value: setup.source.wormhole.messageFee()}(
            1, abi.encodePacked(uint8(0), bytes("hi!")), 200
        );

        stack.deliveryRequest = IWormholeRelayer.Send({
            targetChain: setup.targetChainId,
            targetAddress: setup.source.coreRelayer.toWormholeFormat(address(setup.target.integration)),
            refundAddress: setup.source.coreRelayer.toWormholeFormat(address(setup.target.refundAddress)),
            maxTransactionFee: stack.payment - setup.source.wormhole.messageFee(),
            receiverValue: 0,
            relayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        vm.expectRevert(abi.encodeWithSignature("MsgValueTooLow()"));
        setup.source.coreRelayer.send{value: stack.payment - 1}(
            stack.deliveryRequest, 1, address(setup.source.relayProvider)
        );

        setup.source.relayProvider.updateDeliverGasOverhead(setup.targetChainId, gasParams.evmGasOverhead);

        stack.deliveryOverhead = setup.source.relayProvider.quoteDeliveryOverhead(setup.targetChainId);
        vm.assume(stack.deliveryOverhead > 0);

        stack.badSend = IWormholeRelayer.Send({
            targetChain: setup.targetChainId,
            targetAddress: setup.source.coreRelayer.toWormholeFormat(address(setup.target.integration)),
            refundAddress: setup.source.coreRelayer.toWormholeFormat(address(setup.target.refundAddress)),
            maxTransactionFee: stack.deliveryOverhead - 1,
            receiverValue: 0,
            relayParameters: setup.source.coreRelayer.getDefaultRelayParams()
        });

        uint256 wormholeFee = setup.source.wormhole.messageFee();

        vm.expectRevert(abi.encodeWithSignature("MaxTransactionFeeNotEnough(uint8)", 0));
        setup.source.coreRelayer.send{value: stack.deliveryOverhead - 1 + wormholeFee}(
            stack.badSend, 1, address(setup.source.relayProvider)
        );

        //setup.source.relayProvider.updateDeliverGasOverhead(setup.targetChainId, 0);

        setup.source.relayProvider.updateMaximumBudget(
            setup.targetChainId, uint256(gasParams.targetGasLimit - 1) * gasParams.targetGasPrice
        );

        vm.expectRevert(abi.encodeWithSignature("FundsTooMuch(uint8)", 0));
        setup.source.coreRelayer.send{value: stack.payment}(
            stack.deliveryRequest, 1, address(setup.source.relayProvider)
        );
    }

    function testRevertTargetNotSupported(
        GasParameters memory gasParams,
        FeeParameters memory feeParams,
        bytes memory message
    ) public {
        StandardSetupTwoChains memory setup = standardAssumeAndSetupTwoChains(gasParams, feeParams, 1000000);

        vm.recordLogs();

        // estimate the cost based on the intialized values
        uint256 maxTransactionFee = setup.source.coreRelayer.quoteGas(
            setup.targetChainId, gasParams.targetGasLimit, address(setup.source.relayProvider)
        );

        uint256 wormholeFee = setup.source.wormhole.messageFee();

        vm.expectRevert(abi.encodeWithSignature("RelayProviderDoesNotSupportTargetChain()"));
        setup.source.integration.sendMessageWithRefundAddress{value: maxTransactionFee + uint256(3) * wormholeFee}(
            message, 32, address(setup.target.integration), address(setup.target.refundAddress)
        );

        setup.source.relayProvider.updateDeliveryAddress(
            setup.targetChainId, setup.source.relayProvider.getDeliveryAddress(32)
        );
        vm.expectRevert(abi.encodeWithSignature("RelayProviderDoesNotSupportTargetChain()"));
        setup.source.integration.sendMessageWithRefundAddress{value: maxTransactionFee + uint256(3) * wormholeFee}(
            message, setup.targetChainId, address(setup.target.integration), address(setup.target.refundAddress)
        );
    }
}
