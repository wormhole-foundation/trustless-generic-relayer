// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import "../contracts/coreRelayer/CoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayerState.sol";
import "../contracts/interfaces/IGasOracle.sol";
import {Setup as WormholeSetup} from "../wormhole/ethereum/contracts/Setup.sol";
import {Implementation as WormholeImplementation} from "../wormhole/ethereum/contracts/Implementation.sol";
import {Wormhole} from "../wormhole/ethereum/contracts/Wormhole.sol";
import {IWormholeReceiver} from "../contracts/interfaces/IWormholeReceiver.sol";
import {MockRelayerIntegration} from "../contracts/mock/MockRelayerIntegration.sol";
import {MockForwardingIntegration} from "../contracts/mock/MockForwardingIntegration.sol";
import "../contracts/libraries/external/BytesLib.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract TestCoreRelayer is CoreRelayer, Test {
    using BytesLib for bytes;

    uint16 constant SOURCE_CHAIN_ID = 2;
    uint16 constant TARGET_CHAIN_ID = 4;
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
        uint8 batchCount;
        address VMEmitterAddress;
        address targetAddress;
        address refundAddress;
    }

    function setUpCoreRelayer(uint32 evmGasOverhead) internal returns (Wormhole wormhole, GasOracle gasOracle) {
        // deploy Setup
        WormholeSetup setup = new WormholeSetup();

        // deploy Implementation
        WormholeImplementation implementation = new WormholeImplementation();

        // set guardian set
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
                block.chainid
            )
        );

        // deploy the gasOracle and set price
        gasOracle = new GasOracle(address(wormhole));

        // set up the relayer contracts
        setOwner(address(this));
        setConsistencyLevel(uint8(15));
        setChainId(SOURCE_CHAIN_ID);
        setWormhole(address(wormhole));
        setGasOracle(address(gasOracle));
        setEvmDeliverGasOverhead(evmGasOverhead);
    }

    function setUpForward(Wormhole wormhole, CoreRelayer coreRelayer) internal returns (IWormholeReceiver forwardingContract) {
        forwardingContract = new MockForwardingIntegration(address(wormhole), address(coreRelayer));
    }

    function setUpDelivery(Wormhole wormhole, CoreRelayer coreRelayer) internal returns (IWormholeReceiver deliveryContract) {
        deliveryContract = new MockRelayerIntegration(address(wormhole), address(coreRelayer));
    }

    function testSetupInitialState(
        address owner_,
        uint8 consistencyLevel_,
        address gasOracle_,
        address wormhole_,
        uint16 chainId_,
        uint32 evmGasOverhead_
    ) public {
        vm.assume(chainId_ > 0);
        vm.assume(gasOracle_ != address(0));
        vm.assume(wormhole_ != address(0));
        vm.assume(owner_ != address(0));
        vm.assume(consistencyLevel_ > 0);

        // This should be done during the deployment of the proxy contract.
        setOwner(owner_);
        setConsistencyLevel(consistencyLevel_);
        setChainId(chainId_);
        setWormhole(wormhole_);
        setGasOracle(gasOracle_);
        setEvmDeliverGasOverhead(evmGasOverhead_);

        require(owner() == owner_, "owner() != expected");
        require(consistencyLevel() == consistencyLevel_, "consistencyLevel() != expected");
        require(gasOracleAddress() == gasOracle_, "gasOracleAddress() != expected");
        require(wormhole() == IWormhole(wormhole_), "wormhole() != expected");
        require(chainId() == chainId_, "chainId() != expected");
        require(evmDeliverGasOverhead(chainId_) == evmGasOverhead_, "evmDeliverGasOverhead() != expected");
    }

    function parseWormholeEventLogs(Vm.Log memory log) public pure returns (IWormhole.VM memory vm) {
        uint256 index = 0;

        // emitterAddress
        vm.emitterAddress = bytes32(log.topics[1]);

        // sequence
        vm.sequence = log.data.toUint64(index + 32 - 8);
        index += 32;

        // nonce
        vm.nonce = log.data.toUint32(index + 32 - 4);
        index += 32;

        // skip random bytes
        index += 32;

        // consistency level
        vm.consistencyLevel = log.data.toUint8(index + 32 - 1);
        index += 32;

        // length of payload
        uint256 payloadLen = log.data.toUint256(index);
        index += 32;

        vm.payload = log.data.slice(index, payloadLen);
        index += payloadLen;

        // trailing bytes (due to 32 byte slot overlap)
        index += log.data.length - index;

        require(index == log.data.length, "failed to parse wormhole message");
    }

    function verifyRelayerMessagePayload(bytes memory payload, DeliveryInstructionsContainer memory container) public {
        // confirm emitted payload
        uint256 index = 0;

        assertEq(container.payloadID, payload.toUint8(index));
        index+=1;
        assertEq(container.instructions.length, payload.toUint8(index));
        index+=1;

        for(uint256 i = 0; i < container.instructions.length; i++) {
            // target address
            assertEq(container.instructions[i].targetAddress, payload.toBytes32(index));
            index += 32;

            // refund address
            assertEq(container.instructions[i].refundAddress, payload.toBytes32(index));
            index += 32;

            // target chain
            assertEq(TARGET_CHAIN_ID, payload.toUint16(index));
            index += 2;

            // relayParameters length
            assertEq(container.instructions[i].relayParameters.length, payload.toUint16(index));
            index += 2;

            // relayParameters
            assertEq(container.instructions[i].relayParameters, payload.slice(index, container.instructions[i].relayParameters.length));
            index += container.instructions[i].relayParameters.length;

        }

        require(index == payload.length, "failed to parse DeliveryInstructions payload");
    }

    function standardAssume(GasParameters memory gasParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
    }

    function standardAssume(GasParameters memory gasParams, VMParams memory batchParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(batchParams.targetAddress != address(0));
        vm.assume(batchParams.nonce > 0);
        vm.assume(batchParams.consistencyLevel > 0);
        vm.assume(batchParams.VMEmitterAddress != address(0));
    }


    /**
    SERIALIZATION TESTS
    */
    // This tests confirms that the DeliveryInstructions are deserialized correctly
    // when calling `deliver` on the target chain.
    function testDeliveryInstructionDeserialization(GasParameters memory gasParams, VMParams memory batchParams)
        public
    {
        standardAssume(gasParams, batchParams);

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory relayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            gasEstimate
        );

        // create delivery parameters struct
        DeliveryInstructions memory deliveryParams = DeliveryInstructions({
            targetChain: TARGET_CHAIN_ID,
            targetAddress: bytes32(uint256(uint160(batchParams.targetAddress))),
            refundAddress: bytes32(uint256(uint160(batchParams.refundAddress))),
            relayParameters: relayParameters
        });

        // serialize the payload by calling `encodeDeliveryInstructions`
        DeliveryInstructions[] memory array = new DeliveryInstructions[](1);
        array[0] = deliveryParams;
        DeliveryInstructionsContainer memory container =  DeliveryInstructionsContainer(1, array);
        bytes memory encodedDeliveryInstructions = encodeDeliveryInstructionsContainer(container);

        // deserialize the payload by parsing into the DliveryInstructions struct
        DeliveryInstructionsContainer memory instructions = decodeDeliveryInstructionsContainer(encodedDeliveryInstructions);

        // confirm that the values were parsed correctly
        assertEq(uint8(1), instructions.payloadID);
        //assertEq(SOURCE_CHAIN_ID, instructions.fromChain);
        assertEq(deliveryParams.targetAddress, instructions.instructions[0].targetAddress);
        assertEq(TARGET_CHAIN_ID, instructions.instructions[0].targetChain);
        assertEq(deliveryParams.relayParameters, instructions.instructions[0].relayParameters);
    }

    // This tests confirms that the DeliveryInstructions are deserialized correctly
    // when calling `deliver` on the target chain.
    function testRelayParametersDeserialization(GasParameters memory gasParams, VMParams memory batchParams) public {
        standardAssume(gasParams, batchParams);

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory encodedRelayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            gasEstimate
        );

        // deserialize the relayParameters
        RelayParameters memory decodedRelayParams = decodeRelayParameters(encodedRelayParameters);

        // confirm the values were parsed correctly
        assertEq(uint8(1), decodedRelayParams.version);
        assertEq(gasParams.targetGasLimit, decodedRelayParams.deliveryGasLimit);
        assertEq(gasEstimate, decodedRelayParams.nativePayment);
    }

    function testRelayParametersDeserializationFail(GasParameters memory gasParams, VMParams memory batchParams)
        public
    {
        standardAssume(gasParams, batchParams);

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters (add random bytes to the relayerParams)
        bytes memory encodedRelayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            gasEstimate,
            gasEstimate
        );

        vm.expectRevert("invalid relay parameters");
        // deserialize the relayParameters
        decodeRelayParameters(encodedRelayParameters);
    }

    /**
    SENDING TESTS

    */
    //This test confirms that the amount of gas required when querying or requesting delivery
    //is the expected amount
    function testEstimateCost(GasParameters memory gasParams) public {
        standardAssume(gasParams);

        // initialize all contract
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);

        // compute the expected output
        uint256 expectedGasEstimate = (
            gasOracle.computeGasCost(
                TARGET_CHAIN_ID, uint256(gasParams.targetGasLimit) + uint256(gasParams.evmGasOverhead)
            ) + IWormhole(address(wormhole)).messageFee()
        );

        // confirm gas estimate
        assertEq(gasEstimate, expectedGasEstimate);
    }

    // This test confirms that the `send` method generates the correct delivery Instructions payload
    // to be delivered on the target chain.
    function testSend(GasParameters memory gasParams, VMParams memory batchParams) public {
        standardAssume(gasParams, batchParams);

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = quoteEvmDeliveryPrice(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory relayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            gasEstimate
        );

        // create delivery parameters struct
        DeliveryInstructions memory deliveryParams = DeliveryInstructions({
            targetChain: TARGET_CHAIN_ID,
            targetAddress: bytes32(uint256(uint160(batchParams.targetAddress))),
            refundAddress: bytes32(uint256(uint160(batchParams.refundAddress))),
            relayParameters: relayParameters
        });

        DeliveryInstructions[] memory array = new DeliveryInstructions[](1);
        array[0] = deliveryParams;
        DeliveryInstructionsContainer memory container =  DeliveryInstructionsContainer(1, array);

        // start listening to events
        vm.recordLogs();

        // call the send function on the relayer contract
        uint64 sequence = 0; //this.send{value: gasEstimate + wormholeFee}(container, batchParams.nonce, batchParams.consistencyLevel);

        // record the wormhole message emitted by the relayer contract
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // parse the event logs into a VM struct and confirm the data emitted by the contract
        IWormhole.VM memory deliveryVM = parseWormholeEventLogs(entries[0]);

        // confirm the values emitted by the contract
        assertEq(deliveryVM.emitterAddress, bytes32(uint256(uint160(address(this)))));
        assertEq(deliveryVM.sequence, sequence);
        assertEq(deliveryVM.nonce, batchParams.nonce);

        // verify the payload in separate function to avoid stack-too-deep error
        verifyRelayerMessagePayload(deliveryVM.payload, container);
    }

    /**
    FORWARDING TESTS

    */
    //This test confirms that forwarding a request produces the proper delivery instructions

    //This test confirms that forwarding cannot occur when the contract is locked

    //This test confirms that forwarding cannot occur if there are insufficient refunds after the request

}
