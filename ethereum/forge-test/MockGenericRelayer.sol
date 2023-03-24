// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {IWormholeRelayer} from "../contracts/interfaces/IWormholeRelayer.sol";
import {IDelivery} from "../contracts/interfaces/IDelivery.sol";
import {IWormholeRelayerInstructionParser} from "./IWormholeRelayerInstructionParser.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";
import {WormholeSimulator} from "./WormholeSimulator.sol";
import "../contracts/libraries/external/BytesLib.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

contract MockGenericRelayer {
    using BytesLib for bytes;

    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;
    IWormholeRelayerInstructionParser parser;

    address private constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    Vm public constant vm = Vm(VM_ADDRESS);

    mapping(uint16 => address) wormholeRelayerContracts;

    mapping(uint16 => address) relayers;

    mapping(uint16 => uint256) wormholeFees;

    mapping(bytes32 => bytes[]) pastEncodedVMs;

    mapping(bytes32 => bytes) pastEncodedDeliveryVAA;

    constructor(address _wormhole, address _wormholeSimulator, address wormholeRelayer) {
        // deploy Wormhole

        relayerWormhole = IWormhole(_wormhole);
        relayerWormholeSimulator = WormholeSimulator(_wormholeSimulator);
        parser = IWormholeRelayerInstructionParser(wormholeRelayer);
    }

    function getPastEncodedVMs(bytes32 vaaHash) public view returns (bytes[] memory) {
        return pastEncodedVMs[vaaHash];
    }

    function getPastDeliveryVAA(bytes32 vaaHash) public view returns (bytes memory) {
        return pastEncodedDeliveryVAA[vaaHash];
    }

    function setWormholeRelayerContract(uint16 chainId, address contractAddress) public {
        wormholeRelayerContracts[chainId] = contractAddress;
    }

    function setProviderDeliveryAddress(uint16 chainId, address deliveryAddress) public {
        relayers[chainId] = deliveryAddress;
    }

    function setWormholeFee(uint16 chainId, uint256 fee) public {
        wormholeFees[chainId] = fee;
    }

    function relay(uint16 chainId) public {
        relay(vm.getRecordedLogs(), chainId);
    }

    function messageInfoMatchesVAA(IWormholeRelayer.MessageInfo memory messageInfo, bytes memory vaa)
        internal
        view
        returns (bool)
    {
        IWormhole.VM memory parsedVaa = relayerWormhole.parseVM(vaa);
        bool emitterAddressMatch = messageInfo.emitterAddress == parsedVaa.emitterAddress;
        bool sequenceMatch = (messageInfo.sequence == parsedVaa.sequence);
        bool emitterAddressAndSequenceEmpty =
            (messageInfo.emitterAddress == bytes32(0x0)) && (messageInfo.sequence == 0);
        bool vaaHashMatch = (messageInfo.vaaHash == parsedVaa.hash);
        bool vaaHashEmpty = messageInfo.vaaHash == bytes32(0x0);
        return (emitterAddressMatch && sequenceMatch && (vaaHashEmpty || vaaHashMatch))
            || (emitterAddressAndSequenceEmpty && vaaHashMatch);
    }

    function relay(Vm.Log[] memory logs, uint16 chainId) public {
        Vm.Log[] memory entries = relayerWormholeSimulator.fetchWormholeMessageFromLog(logs);
        bytes[] memory encodedVMs = new bytes[](entries.length);
        for (uint256 i = 0; i < encodedVMs.length; i++) {
            encodedVMs[i] = relayerWormholeSimulator.fetchSignedMessageFromLogs(
                entries[i], chainId, address(uint160(uint256(bytes32(entries[i].topics[1]))))
            );
        }
        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedVMs.length);
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            parsed[i] = relayerWormhole.parseVM(encodedVMs[i]);
        }
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            if (
                parsed[i].emitterAddress == parser.toWormholeFormat(wormholeRelayerContracts[chainId])
                    && (parsed[i].emitterChainId == chainId)
            ) {
                genericRelay(encodedVMs[i], encodedVMs, parsed[i]);
            }
        }
    }

    // TODO: Make the key 'txHash + sequence' instead of 'VAAHASH'

    function genericRelay(
        bytes memory encodedDeliveryVAA,
        bytes[] memory encodedVMs,
        IWormhole.VM memory parsedDeliveryVAA
    ) internal {
        uint8 payloadId = parsedDeliveryVAA.payload.toUint8(0);
        if (payloadId == 1) {
            IWormholeRelayerInstructionParser.DeliveryInstructionsContainer memory container =
                parser.decodeDeliveryInstructionsContainer(parsedDeliveryVAA.payload);

            bytes[] memory encodedVMsToBeDelivered = new bytes[](container.messages.length);

            for (uint8 i = 0; i < container.messages.length; i++) {
                for (uint8 j = 0; j < encodedVMs.length; j++) {
                    if (messageInfoMatchesVAA(container.messages[i], encodedVMs[j])) {
                        encodedVMsToBeDelivered[i] = encodedVMs[j];
                        break;
                    }
                }
            }

            for (uint8 k = 0; k < container.instructions.length; k++) {
                uint256 budget =
                    container.instructions[k].maximumRefundTarget + container.instructions[k].receiverValueTarget;
                uint16 targetChain = container.instructions[k].targetChain;
                IDelivery.TargetDeliveryParametersSingle memory package = IDelivery.TargetDeliveryParametersSingle({
                    encodedVMs: encodedVMsToBeDelivered,
                    encodedDeliveryVAA: encodedDeliveryVAA,
                    multisendIndex: k,
                    relayerRefundAddress: payable(relayers[targetChain])
                });
                if (container.sufficientlyFunded) {
                    vm.prank(relayers[targetChain]);
                    IDelivery(wormholeRelayerContracts[targetChain]).deliverSingle{
                        value: (budget + wormholeFees[targetChain])
                    }(package);
                }
            }
            pastEncodedVMs[parsedDeliveryVAA.hash] = encodedVMsToBeDelivered;
            pastEncodedDeliveryVAA[parsedDeliveryVAA.hash] = encodedDeliveryVAA;
        } else if (payloadId == 2) {
            IWormholeRelayerInstructionParser.RedeliveryByTxHashInstruction memory instruction =
                parser.decodeRedeliveryInstruction(parsedDeliveryVAA.payload);
            bytes[] memory originalEncodedVMs = pastEncodedVMs[instruction.sourceTxHash];
            uint16 targetChain = instruction.targetChain;
            uint256 budget =
                instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget + wormholeFees[targetChain];
            IDelivery.TargetRedeliveryByTxHashParamsSingle memory package = IDelivery
                .TargetRedeliveryByTxHashParamsSingle({
                redeliveryVM: encodedDeliveryVAA,
                sourceEncodedVMs: originalEncodedVMs,
                originalEncodedDeliveryVAA: pastEncodedDeliveryVAA[instruction.sourceTxHash],
                relayerRefundAddress: payable(relayers[targetChain])
            });
            vm.prank(relayers[targetChain]);
            IDelivery(wormholeRelayerContracts[targetChain]).redeliverSingle{value: budget}(package);
        }
    }
}