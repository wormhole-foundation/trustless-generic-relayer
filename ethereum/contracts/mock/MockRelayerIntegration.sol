// contracts/mock/MockBatchedVAASender.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/ICoreRelayer.sol";

contract MockRelayerIntegration {
    using BytesLib for bytes;

    // wormhole instance on this chain
    IWormhole immutable wormhole;

    // trusted relayer contract on this chain
    ICoreRelayer immutable relayer;

    // deployer of this contract
    address immutable owner;

    // map that stores payloads from received VAAs
    mapping(bytes32 => bytes) verifiedPayloads;

    constructor(address _wormholeCore, address _coreRelayer) {
        wormhole = IWormhole(_wormholeCore);
        relayer = ICoreRelayer(_coreRelayer);
        owner = msg.sender;
    }

    function estimateRelayCosts(uint16 targetChainId, uint256 targetGasLimit) public view returns (uint256) {
        return relayer.estimateEvmCost(targetChainId, targetGasLimit);
    }

    struct RelayerArgs {
        uint32 nonce;
        uint16 targetChainId;
        address targetAddress;
        uint32 targetGasLimit;
        uint8 consistencyLevel;
    }

    function doStuff(uint32 batchNonce, bytes[] calldata payload, uint8[] calldata consistencyLevel)
        public
        payable
        returns (uint64[] memory sequences)
    {
        // cache the payload count to save on gas
        uint256 numInputPayloads = payload.length;
        require(numInputPayloads == consistencyLevel.length, "invalid input parameters");

        // Cache the wormhole fee to save on gas costs. Then make sure the user sent
        // enough native asset to cover the cost of delivery (plus the cost of generating wormhole messages).
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= wormholeFee * (numInputPayloads + 1));

        // Create an array to store the wormhole message sequences. Add
        // a slot for the relay message sequence.
        sequences = new uint64[](numInputPayloads + 1);

        // send each wormhole message and save the message sequence
        uint256 messageIdx = 0;
        bytes memory verifyingPayload = abi.encodePacked(wormhole.chainId(), uint8(numInputPayloads));
        for (; messageIdx < numInputPayloads;) {
            sequences[messageIdx] = wormhole.publishMessage{value: wormholeFee}(
                batchNonce, payload[messageIdx], consistencyLevel[messageIdx]
            );

            verifyingPayload = abi.encodePacked(verifyingPayload, emitterAddress(), sequences[messageIdx]);
            unchecked {
                messageIdx += 1;
            }
        }

        // Encode app-relevant info regarding the input payloads.
        // All we care about is source chain id and number of input payloads.
        sequences[messageIdx] = wormhole.publishMessage{value: wormholeFee}(
            batchNonce,
            verifyingPayload,
            1 // consistencyLevel
        );
    }

    function sendBatchToTargetChain(
        bytes[] calldata payload,
        uint8[] calldata consistencyLevel,
        RelayerArgs memory relayerArgs
    ) public payable returns (uint64 relayerMessageSequence) {
        uint64[] memory doStuffSequences = doStuff(relayerArgs.nonce, payload, consistencyLevel);
        uint256 numMessageSequences = doStuffSequences.length;

        // estimate the cost of sending the batch based on the user specified gas limit
        uint256 gasEstimate = estimateRelayCosts(relayerArgs.targetChainId, relayerArgs.targetGasLimit);

        // Cache the wormhole fee to save on gas costs. Then make sure the user sent
        // enough native asset to cover the cost of delivery (plus the cost of generating wormhole messages).
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= gasEstimate + wormholeFee * (numMessageSequences + 1));

        // encode the relay parameters
        bytes memory relayParameters = abi.encodePacked(uint8(1), relayerArgs.targetGasLimit, gasEstimate);

        // create the relayer params to call the relayer with
        ICoreRelayer.DeliveryParameters memory deliveryParams = ICoreRelayer.DeliveryParameters({
            targetChain: relayerArgs.targetChainId,
            targetAddress: bytes32(uint256(uint160(relayerArgs.targetAddress))),
            relayParameters: relayParameters, // REVIEW: rename to encodedRelayParameters?
            nonce: relayerArgs.nonce,
            consistencyLevel: relayerArgs.consistencyLevel
        });

        // call the relayer contract and save the sequence.
        relayerMessageSequence = relayer.send{value: gasEstimate}(deliveryParams);
    }

    struct EmitterSequence {
        bytes32 emitter;
        uint64 sequence;
    }

    function parseVerifyingMessage(bytes memory verifyingObservation, uint256 numObservations)
        public
        returns (EmitterSequence[] memory emitterSequences)
    {
        (IWormhole.VM memory parsed, bool valid, string memory reason) = wormhole.parseAndVerifyVM(verifyingObservation);
        require(valid, reason);

        bytes memory payload = parsed.payload;
        require(payload.toUint16(0) == parsed.emitterChainId, "source chain != emitterChainId");
        require(uint256(payload.toUint8(2)) == numObservations, "incorrect number of observations");

        verifiedPayloads[parsed.hash] = payload;

        // TODO: instead of returning VM, return a struct that has info to verify observations
        emitterSequences = new EmitterSequence[](numObservations);
        uint256 index = 3;
        for (uint256 i = 0; i < numObservations;) {
            emitterSequences[i].emitter = payload.toBytes32(index);
            unchecked {
                index += 32;
            }
            emitterSequences[i].sequence = payload.toUint64(index);
            unchecked {
                index += 8;
            }
            unchecked {
                i += 1;
            }
        }
        require(payload.length == index, "payload.length != index");
    }

    function receiveWormholeMessages(bytes[] memory wormholeObservations) public {
        // loop through the array of wormhole observations from the batch and store each payload
        uint256 numObservations = wormholeObservations.length - 1;

        EmitterSequence[] memory emitterSequences =
            parseVerifyingMessage(wormholeObservations[numObservations], numObservations);

        for (uint256 i = 0; i < numObservations;) {
            (IWormhole.VM memory parsed, bool valid, string memory reason) =
                wormhole.parseAndVerifyVM(wormholeObservations[i]);
            require(valid, reason);

            require(emitterSequences[i].emitter == parsed.emitterAddress, "verifying emitter != emitterAddress");
            require(emitterSequences[i].sequence == parsed.sequence, "verifying sequence != sequence");

            // save the payload from each wormhole message
            verifiedPayloads[parsed.hash] = parsed.payload;

            unchecked {
                i += 1;
            }
        }
    }

    function getPayload(bytes32 hash) public view returns (bytes memory) {
        return verifiedPayloads[hash];
    }

    function clearPayload(bytes32 hash) public {
        delete verifiedPayloads[hash];
    }

    function parseWormholeBatch(bytes memory encoded) public view returns (IWormhole.VM2 memory) {
        return wormhole.parseBatchVM(encoded);
    }

    function parseWormholeObservation(bytes memory encoded) public view returns (IWormhole.VM memory) {
        return wormhole.parseVM(encoded);
    }

    function emitterAddress() public view returns (bytes32) {
        return bytes32(uint256(uint160(address(this))));
    }
}
