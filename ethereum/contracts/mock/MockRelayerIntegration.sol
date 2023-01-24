// contracts/mock/MockBatchedVAASender.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/ICoreRelayer.sol";
import "../interfaces/IWormholeReceiver.sol";

import "forge-std/console.sol";

contract MockRelayerIntegration is IWormholeReceiver {
    using BytesLib for bytes;

    // wormhole instance on this chain
    IWormhole immutable wormhole;

    // trusted relayer contract on this chain
    ICoreRelayer immutable relayer;

    // deployer of this contract
    address immutable owner;

    // map that stores payloads from received VAAs
    mapping(bytes32 => bytes) verifiedPayloads;

    bytes message;

    constructor(address _wormholeCore, address _coreRelayer) {
        wormhole = IWormhole(_wormholeCore);
        relayer = ICoreRelayer(_coreRelayer);
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
        uint256 applicationBudget,
        uint32 nonce
    ) public payable {
        executeSend(fullMessage, targetChainId, destination, refundAddress, applicationBudget, nonce);
    }

    function executeSend(
        bytes memory fullMessage,
        uint16 targetChainId,
        address destination,
        address refundAddress,
        uint256 applicationBudget,
        uint32 nonce
    ) internal {
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, fullMessage, 200);

        ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest({
            targetChain: targetChainId,
            targetAddress: relayer.toWormholeFormat(address(destination)),
            refundAddress: relayer.toWormholeFormat(address(refundAddress)), // This will be ignored on the target chain if the intent is to perform a forward
            computeBudget: msg.value - 2 * wormhole.messageFee() - applicationBudget,
            applicationBudget: applicationBudget, // not needed in this case.
            relayParameters: relayer.getDefaultRelayParams() //no overrides
        });

        relayer.requestDelivery{value: msg.value - wormhole.messageFee()}(
            request, nonce, relayer.getDefaultRelayProvider()
        );
        console.log("CURRENT BALANCE");
        console.log(wormhole.chainId());
        console.log(address(this).balance);
    }

    function receiveWormholeMessages(bytes[] memory wormholeObservations, bytes[] memory) public payable override {
        // loop through the array of wormhole observations from the batch and store each payload
        uint256 numObservations = wormholeObservations.length;
        console.log("CURRENT BALANCE");
        console.log(wormhole.chainId());
        console.log(address(this).balance);
        for (uint256 i = 0; i < numObservations - 1;) {
            (IWormhole.VM memory parsed, bool valid, string memory reason) =
                wormhole.parseAndVerifyVM(wormholeObservations[i]);
            require(valid, reason);

            bool forward = (parsed.payload.toUint8(0) == 1);
            verifiedPayloads[parsed.hash] = parsed.payload.slice(1, parsed.payload.length - 1);
            message = parsed.payload.slice(1, parsed.payload.length - 1);
            console.log("CURRENT BALANCE");
            console.log(wormhole.chainId());
            console.log(address(this).balance);
            if (forward) {
                wormhole.publishMessage{value: wormhole.messageFee()}(
                    parsed.nonce, abi.encodePacked(uint8(0), bytes("received!")), 200
                );

                uint256 computeBudget =
                    relayer.quoteGasDeliveryFee(parsed.emitterChainId, 500000, relayer.getDefaultRelayProvider());

                ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest({
                    targetChain: parsed.emitterChainId,
                    targetAddress: parsed.emitterAddress,
                    refundAddress: parsed.emitterAddress,
                    computeBudget: computeBudget,
                    applicationBudget: 0,
                    relayParameters: relayer.getDefaultRelayParams()
                });

                relayer.requestForward(request, parsed.emitterChainId, parsed.nonce, relayer.getDefaultRelayProvider());
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
}
