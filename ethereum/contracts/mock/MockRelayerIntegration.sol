// contracts/mock/MockBatchedVAASender.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/IWormholeRelayer.sol";
import "../interfaces/IWormholeReceiver.sol";

import "forge-std/console.sol";

contract MockRelayerIntegration is IWormholeReceiver {
    using BytesLib for bytes;

    // wormhole instance on this chain
    IWormhole immutable wormhole;

    // trusted relayer contract on this chain
    IWormholeRelayer immutable relayer;

    // deployer of this contract
    address immutable owner;

    // map that stores payloads from received VAAs
    mapping(bytes32 => bytes) verifiedPayloads;

    bytes message;

    struct FurtherInstructions {
        bool keepSending;
        bytes newMessage;
        uint16[] chains;
        uint32[] gasLimits;
    }

    struct Message {
        bytes text;
        FurtherInstructions furtherInstructions;
    }

    constructor(address _wormholeCore, address _coreRelayer) {
        wormhole = IWormhole(_wormholeCore);
        relayer = IWormholeRelayer(_coreRelayer);
        owner = msg.sender;
    }

    function sendMessage(bytes memory _message, uint16 targetChainId, address destination, address refundAddress)
        public
        payable
    {
        executeSend(abi.encodePacked(uint8(0), _message), targetChainId, destination, refundAddress, 0, 1);
    }

    function sendMessageWithForwardedResponse(
        bytes memory _message,
        uint16 targetChainId,
        address destination,
        address refundAddress
    ) public payable {
        executeSend(abi.encodePacked(uint8(1), _message), targetChainId, destination, refundAddress, 0, 1);
    }

    function sendMessageGeneral(
        bytes memory fullMessage,
        uint16 targetChainId,
        address destination,
        address refundAddress,
        uint256 receiverValue,
        uint32 nonce
    ) public payable {
        executeSend(fullMessage, targetChainId, destination, refundAddress, receiverValue, nonce);
    }

    function executeSend(
        bytes memory fullMessage,
        uint16 targetChainId,
        address destination,
        address refundAddress,
        uint256 receiverValue,
        uint32 nonce
    ) internal {
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, fullMessage, 200);

        IWormholeRelayer.Send memory request = IWormholeRelayer.Send({
            targetChain: targetChainId,
            targetAddress: relayer.toWormholeFormat(address(destination)),
            refundAddress: relayer.toWormholeFormat(address(refundAddress)), // This will be ignored on the target chain if the intent is to perform a forward
            maxTransactionFee: msg.value - 2 * wormhole.messageFee() - receiverValue,
            receiverValue: receiverValue, // not needed in this case.
            relayParameters: relayer.getDefaultRelayParams() //no overrides
        });

        relayer.send{value: msg.value - wormhole.messageFee()}(request, nonce, relayer.getDefaultRelayProvider());
    }

    function receiveWormholeMessages(bytes[] memory wormholeObservations, bytes[] memory) public payable override {
        // loop through the array of wormhole observations from the batch and store each payload
        uint256 numObservations = wormholeObservations.length;
        for (uint256 i = 0; i < numObservations - 1;) {
            (IWormhole.VM memory parsed, bool valid, string memory reason) =
                wormhole.parseAndVerifyVM(wormholeObservations[i]);
            require(valid, reason);

            bool forward = (parsed.payload.toUint8(0) == 1);
            verifiedPayloads[parsed.hash] = parsed.payload.slice(1, parsed.payload.length - 1);
            message = parsed.payload.slice(1, parsed.payload.length - 1);
            if (forward) {
                wormhole.publishMessage{value: wormhole.messageFee()}(
                    parsed.nonce, abi.encodePacked(uint8(0), bytes("received!")), 200
                );

                uint256 maxTransactionFee =
                    relayer.quoteGas(parsed.emitterChainId, 500000, relayer.getDefaultRelayProvider());

                IWormholeRelayer.Send memory request = IWormholeRelayer.Send({
                    targetChain: parsed.emitterChainId,
                    targetAddress: parsed.emitterAddress,
                    refundAddress: parsed.emitterAddress,
                    maxTransactionFee: maxTransactionFee,
                    receiverValue: 0,
                    relayParameters: relayer.getDefaultRelayParams()
                });

                relayer.forward(request, parsed.nonce, relayer.getDefaultRelayProvider());
            }

            unchecked {
                i += 1;
            }
        }
    }

    function getPayload(bytes32 hash) public view returns (bytes memory) {
        return verifiedPayloads[hash];
    }

    function getMessage() public view returns (bytes memory) {
        return message;
    }

    function clearPayload(bytes32 hash) public {
        delete verifiedPayloads[hash];
    }

    function parseWormholeObservation(bytes memory encoded) public view returns (IWormhole.VM memory) {
        return wormhole.parseVM(encoded);
    }

    function emitterAddress() public view returns (bytes32) {
        return bytes32(uint256(uint160(address(this))));
    }

    function encodeMessage(Message message) public view returns (bytes encodedMessage) {
        encodedMessage = abi.encodePacked(uint16(message.text.length), message.text, uint8(0));
    }

    function encodeMessage(Message message, ForwardingInstructions forwardingInstructions) public view returns (bytes encodedMessage) {
        encodedMessage = abi.encodePacked(encodeMessage(message), uint8(forwardingInstructions.keepSending), uint16(forwardingInstructions.newMessage.length), uint16(forwardingInstuctions.chains.length));
        for(uint16 i=0; i<forwardingInstructions.chains.length; i++) {
             encodedMessage = abi.encodePacked(encodedMessage, forwardingInstructions.chains[i], forwardingInstructions.gasLimits[i]);
        }
    }

    function decodeMessage(bytes encodedMessage) public view returns (Message message) {
        uint256 index = 0;
        uint16 length = encodedMessage.toUint16(index);
        index += 2;
        message.text = encodedMessage.slice(index, length);
        index += length;
        message.forwardingInstructions.keepSending = encodedMessage.toUint8(index) == 1;
        index += 1;
        length = encodedMessage.toUint16(index);
        index += 2;
        uint16[] chains = new uint16[](length);
        uint32[] gasLimits = new uint32[](length);
        message.forwardingInstructions.
    }

    
}
