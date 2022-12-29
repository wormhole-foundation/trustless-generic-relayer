// contracts/mock/MockBatchedVAASender.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/ICoreRelayer.sol";
import "../interfaces/IWormholeReceiver.sol";

import "forge-std/Test.sol";
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

    function sendMessage() public payable{
        wormhole.publishMessage(1, abi.encode(uint8(1)), 200);

        //Calc which should be done off-chain
        //uint256 computeBudget = relayer.quoteGasDeliveryFee(wormhole.chainId(), 1000000, relayer.getDefaultRelayProvider());
        uint256 applicationBudget = 0;

        ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest(
            wormhole.chainId(), //target chain
            relayer.toWormholeFormat(address(this)), //target address
            relayer.toWormholeFormat(address(this)),  //refund address, This will be ignored on the target chain because the intent is to perform a forward
            msg.value, //compute budget
            applicationBudget, //application budget, not needed in this case. 
            relayer.getDefaultRelayParams() //no overrides
        );

        relayer.requestDelivery{value: msg.value}(request, 1, relayer.getDefaultRelayProvider());
    }


    function receiveWormholeMessages(bytes[] memory wormholeObservations, bytes[] memory additionalData) public payable override {
        // loop through the array of wormhole observations from the batch and store each payload
        uint256 numObservations = wormholeObservations.length;
        for (uint256 i = 0; i < numObservations - 1;) {

            (IWormhole.VM memory parsed, bool valid, string memory reason) =
                wormhole.parseAndVerifyVM(wormholeObservations[i]);
            require(valid, reason);

            bool forward = (parsed.payload.toUint8(0) == 1);
            verifiedPayloads[parsed.hash] = parsed.payload.slice(1, parsed.payload.length - 1);
            message = parsed.payload.slice(1, parsed.payload.length - 1);
            
            if(forward) {
                uint256 computeBudget = relayer.quoteGasDeliveryFee(parsed.emitterChainId, 500000, relayer.getDefaultRelayProvider());

                wormhole.publishMessage(1, abi.encodePacked(uint8(0), bytes("received!")), 200);

                ICoreRelayer.DeliveryRequest memory request = ICoreRelayer.DeliveryRequest(parsed.emitterChainId, parsed.emitterAddress, parsed.emitterAddress, computeBudget, 0, relayer.getDefaultRelayParams());

                relayer.requestForward(request, parsed.emitterChainId, 1, relayer.getDefaultRelayProvider());

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
