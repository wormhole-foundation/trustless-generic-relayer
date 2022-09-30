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

    // trusted mock integration contracts
    mapping(uint16 => bytes32) trustedSenders;

    // map that stores payloads from received VAAs
    mapping(bytes32 => bytes) verifiedPayloads;

    constructor(address _wormholeCore, address _coreRelayer) {
        wormhole = IWormhole(_wormholeCore);
        relayer = ICoreRelayer(_coreRelayer);
        owner = msg.sender;
    }

    function estimateRelayCosts(uint16 targetChainId, uint256 targetGasLimit) public view returns (uint256) {
        return relayer.estimateCost(targetChainId, targetGasLimit);
    }

    struct RelayerArgs {
        uint32 nonce;
        uint16 targetChainId;
        address targetAddress;
        uint32 targetGasLimit;
        uint8 consistencyLevel;
        uint8[] deliveryListIndices;
    }

    function sendBatchToTargetChain(
        bytes[] calldata payload,
        uint8[] calldata consistencyLevel,
        RelayerArgs memory relayerArgs
    )
        public
        payable
        returns (uint64[] memory messageSequences)
    {
        // cache the payload count to save on gas
        uint256 numPayloads = payload.length;

        require(numPayloads == consistencyLevel.length, "invalid input parameters");

        // estimate the cost of sending the batch based on the user specified gas limit
        uint256 gasEstimate = estimateRelayCosts(relayerArgs.targetChainId, relayerArgs.targetGasLimit);

        // Cache the wormhole fee to save on gas costs. Then make sure the user sent
        // enough native asset to cover the cost of delivery (plus the cost of generating wormhole messages).
        uint256 wormholeFee = wormhole.messageFee();
        require(msg.value >= gasEstimate + wormholeFee * numPayloads);

        // Create an array to store the wormhole message sequences. Add
        // a slot for the relay message sequence.
        messageSequences = new uint64[](numPayloads+1);

        // create the deliveryList
        uint256 deliveryListLength = relayerArgs.deliveryListIndices.length;
        ICoreRelayer.VAAId[] memory deliveryList = new ICoreRelayer.VAAId[](deliveryListLength);

        // send each wormhole message and save the message sequence
        for (uint256 i = 0; i < numPayloads; i++) {
            messageSequences[i] =
                wormhole.publishMessage{value: wormholeFee}(relayerArgs.nonce, payload[i], consistencyLevel[i]);

            // add to delivery list based on the index (if indices are specified)
            for (uint256 j = 0; j < deliveryListLength; j++) {
                if (i == relayerArgs.deliveryListIndices[j]) {
                    deliveryList[j] = ICoreRelayer.VAAId({
                        emitterAddress: bytes32(uint256(uint160(address(this)))),
                        sequence: messageSequences[i]
                    });
                }
            }
        }

        // encode the relay parameters
        bytes memory relayParameters =
            abi.encodePacked(uint8(1), relayerArgs.targetGasLimit, uint8(numPayloads), gasEstimate);

        // create the relayer params to call the relayer with
        ICoreRelayer.DeliveryParameters memory deliveryParams = ICoreRelayer.DeliveryParameters({
            targetChain: relayerArgs.targetChainId,
            targetAddress: bytes32(uint256(uint160(relayerArgs.targetAddress))),
            payload: new bytes(0),
            deliveryList: deliveryList,
            relayParameters: relayParameters,
            chainPayload: new bytes(0),
            nonce: relayerArgs.nonce,
            consistencyLevel: relayerArgs.consistencyLevel
        });

        // call the relayer contract and save the sequence.
        messageSequences[numPayloads] = relayer.send{value: gasEstimate}(deliveryParams);

        return messageSequences;
    }

    function wormholeReceiver(
        IWormhole.VM[] memory vmList,
        uint16 sourceChain,
        bytes32 sourceAddress,
        bytes memory payload
    )
        public
    {
        // make sure the caller is a trusted relayer contract
        require(msg.sender == address(relayer), "caller not trusted");

        // make sure the sender of the batch is a trusted contract
        require(sourceAddress == trustedSender(sourceChain), "batch sender not trusted");

        // loop through the array of VMs and store each payload
        uint256 vmCount = vmList.length;
        for (uint256 i = 0; i < vmCount;) {
            (bool valid, string memory reason) = wormhole.verifyVM(vmList[i]);
            require(valid, reason);

            // save the payload from each VAA
            verifiedPayloads[vmList[i].hash] = vmList[i].payload;

            unchecked {
                i += 1;
            }
        }
    }

    // setters
    function registerTrustedSender(uint16 chainId, bytes32 senderAddress) public {
        require(msg.sender == owner, "caller must be the owner");
        trustedSenders[chainId] = senderAddress;
    }

    // getters
    function trustedSender(uint16 chainId) public view returns (bytes32) {
        return trustedSenders[chainId];
    }

    function getPayload(bytes32 hash) public view returns (bytes memory) {
        return verifiedPayloads[hash];
    }

    function clearPayload(bytes32 hash) public {
        delete verifiedPayloads[hash];
    }

    function parseBatchVM(bytes memory encoded) public view returns (IWormhole.VM2 memory) {
        return wormhole.parseBatchVM(encoded);
    }

    function parseVM(bytes memory encoded) public view returns (IWormhole.VM memory) {
        return wormhole.parseVM(encoded);
    }
}
