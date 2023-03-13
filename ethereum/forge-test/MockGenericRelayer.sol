// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {IWormholeRelayer} from "../contracts/interfaces/IWormholeRelayer.sol";
import {IDelivery} from "../contracts/interfaces/IDelivery.sol";
import {IWormholeRelayerInstructionParser} from "./IWormholeRelayerInstructionParser.sol";
import {IWormhole} from "../contracts/interfaces/IWormhole.sol";
import {WormholeSimulator} from "./WormholeSimulator.sol";
import "../contracts/libraries/external/BytesLib.sol";
import "forge-std/Vm.sol";


contract MockGenericRelayer {
    using BytesLib for bytes;

    IWormhole relayerWormhole;
    WormholeSimulator relayerWormholeSimulator;
    IWormholeRelayerInstructionParser parser;

    address constant private VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256('hevm cheat code')))));

    Vm public constant vm = Vm(VM_ADDRESS);

    mapping(uint16 => address) wormholeRelayerContracts;

    mapping(uint16 => address) relayers;

    mapping(uint16 => uint256) wormholeFees;
    
    mapping(uint256 => bool) nonceCompleted;

    mapping(bytes32 => bytes[]) pastEncodedVMs;

    constructor(address _wormhole, address _wormholeSimulator, address wormholeRelayer) {
        // deploy Wormhole

        relayerWormhole = IWormhole(_wormhole);
        relayerWormholeSimulator = WormholeSimulator(_wormholeSimulator);
        parser = IWormholeRelayerInstructionParser(wormholeRelayer);
    }

    function getPastEncodedVMs(bytes32 vaaHash) public view returns (bytes[] memory) {
        return pastEncodedVMs[vaaHash];
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
        Vm.Log[] memory entries = relayerWormholeSimulator.fetchWormholeMessageFromLog(vm.getRecordedLogs());
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
            if (!nonceCompleted[parsed[i].nonce]) {
                nonceCompleted[parsed[i].nonce] = true;
                uint8 length = 1;
                for (uint16 j = i + 1; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        length++;
                    }
                }
                bytes[] memory encodedVMsToBeDelivered = new bytes[](length);
                uint8 counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        encodedVMsToBeDelivered[counter] = encodedVMs[j];
                        counter++;
                    }
                }
                counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        if (
                            parsed[j].emitterAddress == parser.toWormholeFormat(wormholeRelayerContracts[chainId])
                                && (parsed[j].emitterChainId == chainId)
                        ) {
                            genericRelay(counter, encodedVMs[j], encodedVMsToBeDelivered, parsed[j]);
                        }
                        counter += 1;
                    }
                }
            }
        }
        for (uint8 i = 0; i < encodedVMs.length; i++) {
            nonceCompleted[parsed[i].nonce] = false;
        }
    }

    function genericRelay(
        uint8 counter,
        bytes memory encodedDeliveryInstructionsContainer,
        bytes[] memory encodedVMsToBeDelivered,
        IWormhole.VM memory parsedInstruction
    ) internal {
        uint8 payloadId = parsedInstruction.payload.toUint8(0);
        if (payloadId == 1) {
            IWormholeRelayerInstructionParser.DeliveryInstructionsContainer memory container =
                parser.decodeDeliveryInstructionsContainer(parsedInstruction.payload);
            for (uint8 k = 0; k < container.instructions.length; k++) {
                uint256 budget =
                    container.instructions[k].maximumRefundTarget + container.instructions[k].receiverValueTarget;
                uint16 targetChain = container.instructions[k].targetChain;
                IDelivery.TargetDeliveryParametersSingle memory package = IDelivery.TargetDeliveryParametersSingle({
                    encodedVMs: encodedVMsToBeDelivered,
                    deliveryIndex: counter,
                    multisendIndex: k,
                    relayerRefundAddress: payable(relayers[targetChain])
                });
                if(container.sufficientlyFunded) {
                    vm.prank(relayers[targetChain]);
                    IDelivery(wormholeRelayerContracts[targetChain]).deliverSingle{value: (budget + wormholeFees[targetChain])}(package);
                } 
            }
            pastEncodedVMs[parsedInstruction.hash] = encodedVMsToBeDelivered;
        } else if (payloadId == 2) {
            IWormholeRelayerInstructionParser.RedeliveryByTxHashInstruction memory instruction =
                parser.decodeRedeliveryInstruction(parsedInstruction.payload);
            bytes[] memory originalEncodedVMs =
                pastEncodedVMs[instruction.sourceTxHash];
            uint16 targetChain = instruction.targetChain;
            uint256 budget = instruction.newMaximumRefundTarget + instruction.newReceiverValueTarget
                + wormholeFees[targetChain];
            IDelivery.TargetRedeliveryByTxHashParamsSingle memory package = IDelivery
                .TargetRedeliveryByTxHashParamsSingle({
                redeliveryVM: encodedDeliveryInstructionsContainer,
                sourceEncodedVMs: originalEncodedVMs,
                relayerRefundAddress: payable(relayers[targetChain])
            });
            vm.prank(relayers[targetChain]);
            IDelivery(wormholeRelayerContracts[targetChain]).redeliverSingle{value: budget}(package);
        }
    }
}
