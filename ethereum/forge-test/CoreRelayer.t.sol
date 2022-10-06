// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import "../contracts/coreRelayer/CoreRelayer.sol";
import "../contracts/coreRelayer/CoreRelayerState.sol";
import "../contracts/interfaces/IGasOracle.sol";
import {Setup as WormholeSetup} from "../wormhole/ethereum/contracts/Setup.sol";
import {Implementation as WormholeImplementation} from "../wormhole/ethereum/contracts/Implementation.sol";
import {Wormhole} from "../wormhole/ethereum/contracts/Wormhole.sol";
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
        require(evmDeliverGasOverhead() == evmGasOverhead_, "evmDeliverGasOverhead() != expected");
    }

    function testEstimateCost(GasParameters memory gasParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);

        // initialize all contract
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = estimateEvmCost(TARGET_CHAIN_ID, gasParams.targetGasLimit);

        // compute the expected output
        uint256 expectedGasEstimate = (
            gasOracle.computeGasCost(
                TARGET_CHAIN_ID, uint256(gasParams.targetGasLimit) + uint256(gasParams.evmGasOverhead)
            ) + IWormhole(address(wormhole)).messageFee()
        );

        // confirm gas estimate
        assertEq(gasEstimate, expectedGasEstimate);
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

    function verifyRelayerMessagePayload(bytes memory payload, DeliveryParameters memory deliveryParams) public {
        // confirm emitted payload
        uint256 index = 0;

        // DeliveryInstructions payload
        assertEq(uint8(1), payload.toUint8(index));
        index += 1;

        // `send` caller
        assertEq(bytes32(uint256(uint160(address(this)))), payload.toBytes32(index));
        index += 32;

        // source chainId
        assertEq(SOURCE_CHAIN_ID, payload.toUint16(index));
        index += 2;

        // target address
        assertEq(deliveryParams.targetAddress, payload.toBytes32(index));
        index += 32;

        // target chain
        assertEq(TARGET_CHAIN_ID, payload.toUint16(index));
        index += 2;

        // relayParameters length
        assertEq(deliveryParams.relayParameters.length, payload.toUint16(index));
        index += 2;

        // relayParameters
        assertEq(deliveryParams.relayParameters, payload.slice(index, deliveryParams.relayParameters.length));
        index += deliveryParams.relayParameters.length;

        require(index == payload.length, "failed to parse DeliveryInstructions payload");
    }

    // This test confirms that the `send` method generates the correct delivery Instructions payload
    // to be delivered on the target chain.
    function testSend(GasParameters memory gasParams, VMParams memory batchParams) public {
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

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = estimateEvmCost(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory relayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            uint8(batchParams.batchCount), // no other VAAs for this test
            gasEstimate
        );

        // create delivery parameters struct
        DeliveryParameters memory deliveryParams = DeliveryParameters({
            targetChain: TARGET_CHAIN_ID,
            targetAddress: bytes32(uint256(uint160(batchParams.targetAddress))),
            relayParameters: relayParameters,
            nonce: batchParams.nonce,
            consistencyLevel: batchParams.consistencyLevel
        });

        // start listening to events
        vm.recordLogs();

        // call the send function on the relayer contract
        uint64 sequence = this.send{value: gasEstimate + wormholeFee}(deliveryParams);

        // record the wormhole message emitted by the relayer contract
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // parse the event logs into a VM struct and confirm the data emitted by the contract
        IWormhole.VM memory deliveryVM = parseWormholeEventLogs(entries[0]);

        // confirm the values emitted by the contract
        assertEq(deliveryVM.emitterAddress, bytes32(uint256(uint160(address(this)))));
        assertEq(deliveryVM.sequence, sequence);
        assertEq(deliveryVM.nonce, batchParams.nonce);

        // verify the payload in separate function to avoid stack-too-deep error
        verifyRelayerMessagePayload(deliveryVM.payload, deliveryParams);
    }

    // This tests confirms that the DeliveryInstructions are deserialized correctly
    // when calling `deliver` on the target chain.
    function testDeliveryInstructionDeserialization(GasParameters memory gasParams, VMParams memory batchParams)
        public
    {
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

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = estimateEvmCost(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory relayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            uint8(batchParams.batchCount), // no other VAAs for this test
            gasEstimate
        );

        // create delivery parameters struct
        DeliveryParameters memory deliveryParams = DeliveryParameters({
            targetChain: TARGET_CHAIN_ID,
            targetAddress: bytes32(uint256(uint160(batchParams.targetAddress))),
            relayParameters: relayParameters,
            nonce: batchParams.nonce,
            consistencyLevel: batchParams.consistencyLevel
        });

        // serialize the payload by calling `encodeDeliveryInstructions`
        bytes memory encodedDeliveryInstructions = encodeDeliveryInstructions(deliveryParams);

        // deserialize the payload by parsing into the DliveryInstructions struct
        DeliveryInstructions memory instructions = decodeDeliveryInstructions(encodedDeliveryInstructions);

        // confirm that the values were parsed correctly
        assertEq(uint8(1), instructions.payloadID);
        assertEq(bytes32(uint256(uint160(msg.sender))), instructions.fromAddress);
        assertEq(SOURCE_CHAIN_ID, instructions.fromChain);
        assertEq(deliveryParams.targetAddress, instructions.targetAddress);
        assertEq(TARGET_CHAIN_ID, instructions.targetChain);
        assertEq(deliveryParams.relayParameters, instructions.relayParameters);
    }

    // This tests confirms that the DeliveryInstructions are deserialized correctly
    // when calling `deliver` on the target chain.
    function testRelayParametersDeserialization(GasParameters memory gasParams, VMParams memory batchParams) public {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(batchParams.VMEmitterAddress != address(0));

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = estimateEvmCost(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters
        bytes memory encodedRelayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            uint8(batchParams.batchCount), // no other VAAs for this test
            gasEstimate
        );

        // deserialize the relayParameters
        RelayParameters memory decodedRelayParams = decodeRelayParameters(encodedRelayParameters);

        // confirm the values were parsed correctly
        assertEq(uint8(1), decodedRelayParams.version);
        assertEq(gasParams.targetGasLimit, decodedRelayParams.deliveryGasLimit);
        assertEq(uint8(batchParams.batchCount), decodedRelayParams.maximumBatchSize);
        assertEq(gasEstimate, decodedRelayParams.nativePayment);
    }

    function testRelayParametersDeserializationFail(GasParameters memory gasParams, VMParams memory batchParams)
        public
    {
        uint128 halfMaxUint128 = 2 ** (128 / 2) - 1;
        vm.assume(gasParams.evmGasOverhead > 0);
        vm.assume(gasParams.targetGasLimit > 0);
        vm.assume(gasParams.targetGasPrice > 0 && gasParams.targetGasPrice < halfMaxUint128);
        vm.assume(gasParams.targetNativePrice > 0 && gasParams.targetNativePrice < halfMaxUint128);
        vm.assume(gasParams.sourceGasPrice > 0 && gasParams.sourceGasPrice < halfMaxUint128);
        vm.assume(gasParams.sourceNativePrice > 0 && gasParams.sourceNativePrice < halfMaxUint128);
        vm.assume(batchParams.VMEmitterAddress != address(0));

        // initialize all contracts
        (Wormhole wormhole, GasOracle gasOracle) = setUpCoreRelayer(gasParams.evmGasOverhead);

        // set gasOracle prices
        gasOracle.updatePrice(TARGET_CHAIN_ID, gasParams.targetGasPrice, gasParams.targetNativePrice);
        gasOracle.updatePrice(SOURCE_CHAIN_ID, gasParams.sourceGasPrice, gasParams.sourceNativePrice);

        // estimate the cost based on the intialized values
        uint256 gasEstimate = estimateEvmCost(TARGET_CHAIN_ID, gasParams.targetGasLimit);
        uint256 wormholeFee = IWormhole(address(wormhole)).messageFee();

        // the balance of this contract is the max Uint96
        vm.assume(gasEstimate < MAX_UINT96_VALUE - wormholeFee);

        // format the relayParameters (add random bytes to the relayerParams)
        bytes memory encodedRelayParameters = abi.encodePacked(
            uint8(1), // version
            gasParams.targetGasLimit,
            uint8(batchParams.batchCount), // no other VAAs for this test
            gasEstimate,
            gasEstimate
        );

        vm.expectRevert("invalid relay parameters");
        // deserialize the relayParameters
        decodeRelayParameters(encodedRelayParameters);
    }
}
