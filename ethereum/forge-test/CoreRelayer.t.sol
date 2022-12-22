// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import {ICoreRelayer} from "../contracts/interfaces/ICoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayerState.sol";
import {CoreRelayerSetup} from "../contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "../contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "../contracts/coreRelayer/CoreRelayerProxy.sol";
import {IGasOracle} from "../contracts/interfaces/IGasOracle.sol";
import {Setup as WormholeSetup} from "../wormhole/ethereum/contracts/Setup.sol";
import {Implementation as WormholeImplementation} from "../wormhole/ethereum/contracts/Implementation.sol";
import {Wormhole} from "../wormhole/ethereum/contracts/Wormhole.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";
import {IWormholeReceiver} from "../contracts/interfaces/IWormholeReceiver.sol";
import {MockRelayerIntegration} from "../contracts/mock/MockRelayerIntegration.sol";
import {MockForwardingIntegration} from "../contracts/mock/MockForwardingIntegration.sol";
import "../contracts/libraries/external/BytesLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract TestCoreRelayer is Test {
    using BytesLib for bytes;

    uint16 constant SOURCE_CHAIN_ID = 3;
    uint16 constant TARGET_CHAIN_ID = 3;
    uint16 MAX_UINT16_VALUE = 65535;
    uint96 MAX_UINT96_VALUE = 79228162514264337593543950335;

    struct GasParameters {
        uint32 evmGasOverhead;
        uint32 targetGasLimit;
        uint128 targetGasPrice;
        uint128 targetNativePrice;
        uint128 sourceGasPrice;
        uint128 sourceNativePrice;
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

    function setUpGasOracle(uint16 chainId, address relayer) internal returns (IGasOracle gasOracle) {
        gasOracle = IGasOracle(address(new GasOracle(chainId)));
        gasOracle.setRelayerAddress(chainId, bytes32(uint256(uint160(relayer))));
    }
 
    function setUpCoreRelayer(uint16 chainId, address wormhole, address defaultGasOracle) internal returns (ICoreRelayer coreRelayer) {
        
        CoreRelayerSetup coreRelayerSetup = new CoreRelayerSetup();
        CoreRelayerImplementation coreRelayerImplementation = new CoreRelayerImplementation();
        CoreRelayerProxy myCoreRelayer = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,address)")),
                address(coreRelayerImplementation),
                chainId,
                wormhole,
                defaultGasOracle
            )
        );

        coreRelayer = ICoreRelayer(address(myCoreRelayer));
        
        

    }

    function setUpForward(address wormhole, CoreRelayer coreRelayer) internal returns (IWormholeReceiver forwardingContract) {
        forwardingContract = new MockForwardingIntegration(wormhole, address(coreRelayer));
    }


    function standardAssume(GasParameters memory gasParams, VMParams memory batchParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(batchParams.nonce > 0);
        vm.assume(batchParams.consistencyLevel > 0);
    }


    /**
    SENDING TESTS

    */


    // This test confirms that the `send` method generates the correct delivery Instructions payload
    // to be delivered on the target chain.
    function testSend(GasParameters memory gasParams, VMParams memory batchParams, bytes memory message, address relayer) public {
        
        standardAssume(gasParams, batchParams);
        vm.assume(gasParams.targetGasLimit >= 500000);
        vm.assume(relayer != address(0x0));
        
        // initialize all contracts
        (IWormhole wormhole, WormholeSimulator wormholeSimulator) = setUpWormhole(3);
        IGasOracle gasOracle = setUpGasOracle(3, relayer);
        ICoreRelayer coreRelayer = setUpCoreRelayer(3, address(wormhole), address(gasOracle));

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        MockRelayerIntegration deliveryContract = new MockRelayerIntegration(address(wormhole), address(this));

        // estimate the cost based on the intialized values
        uint256 computeBudget = gasOracle.quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);


        // start listening to events
        vm.recordLogs();

        // send an arbitrary wormhole message to be relayed
        wormhole.publishMessage{value: wormhole.messageFee()}(batchParams.nonce, message, batchParams.consistencyLevel);

        // call the send function on the relayer contract

        ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest(TARGET_CHAIN_ID, bytes32(uint256(uint160(address(deliveryContract)))), bytes32(uint256(uint160(address(0x1)))), computeBudget, 0, bytes(""));

       console.log("EMITTER");
       console.log(address(coreRelayer));
        coreRelayer.requestDelivery{value: wormhole.messageFee() + computeBudget}(request, batchParams.nonce, batchParams.consistencyLevel);

        // record the wormhole message emitted by the relayer contract
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes[] memory encodedVMs = new bytes[](2);
        encodedVMs[0] = wormholeSimulator.fetchSignedMessageFromLogs(entries[0], SOURCE_CHAIN_ID, address(coreRelayer));
        encodedVMs[1] = wormholeSimulator.fetchSignedMessageFromLogs(entries[1], SOURCE_CHAIN_ID, address(coreRelayer));

        vm.deal(relayer, computeBudget);
        vm.prank(relayer);
        coreRelayer.deliverSingle{value: computeBudget}(ICoreRelayer.TargetDeliveryParametersSingle(encodedVMs, 1, 0));

        assertTrue(keccak256(deliveryContract.getPayload(keccak256(abi.encodePacked(keccak256(encodedVMs[0].slice(72, encodedVMs[0].length-72)))))) == keccak256(message));
        
    }

    /**
    FORWARDING TESTS

    */
    //This test confirms that forwarding a request produces the proper delivery instructions

    //This test confirms that forwarding cannot occur when the contract is locked

    //This test confirms that forwarding cannot occur if there are insufficient refunds after the request

}
