// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../contracts/interfaces/IWormhole.sol";
import "../contracts/interfaces/IWormholeReceiver.sol";
import "../contracts/interfaces/IWormholeRelayer.sol";
import "../contracts/interfaces/IRelayProvider.sol";
import "../contracts/libraries/external/BytesLib.sol";

contract ForwardTester is IWormholeReceiver {
    using BytesLib for bytes;

    IWormhole wormhole;
    IWormholeRelayer wormholeRelayer;

    constructor(address _wormhole, address _wormholeRelayer) {
        wormhole = IWormhole(_wormhole);
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    enum Action {
        MultipleForwardsRequested,
        NonceIsZero,
        MultichainSendEmpty,
        MaxTransactionFeeNotEnough,
        FundsTooMuch,
        WorksCorrectly
    }

    function receiveWormholeMessages(bytes[] memory vaas, bytes[] memory additionalData) public payable override {
        (IWormhole.VM memory vaa, bool valid, string memory reason) = wormhole.parseAndVerifyVM(vaas[0]);
        require(valid, reason);

        bytes memory payload = vaa.payload;
        Action action = Action(payload.toUint8(0));

        if (action == Action.MultipleForwardsRequested) {
            uint256 maxTransactionFee =
                wormholeRelayer.quoteGas(vaa.emitterChainId, 10000, wormholeRelayer.getDefaultRelayProvider());
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 1);
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 1);
        } else if (action == Action.NonceIsZero) {
            uint256 maxTransactionFee =
                wormholeRelayer.quoteGas(vaa.emitterChainId, 10000, wormholeRelayer.getDefaultRelayProvider());
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 0);
        } else if (action == Action.MultichainSendEmpty) {
            wormholeRelayer.multichainForward(
                IWormholeRelayer.MultichainSend(
                    wormholeRelayer.getDefaultRelayProvider(), new IWormholeRelayer.Send[](0)
                ),
                1
            );
        } else if (action == Action.MaxTransactionFeeNotEnough) {
            uint256 maxTransactionFee =
                wormholeRelayer.quoteGas(vaa.emitterChainId, 1, wormholeRelayer.getDefaultRelayProvider()) - 1;
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 1);
        } else if (action == Action.FundsTooMuch) {
            // set maximum budget to less than this
            uint256 maxTransactionFee =
                wormholeRelayer.quoteGas(vaa.emitterChainId, 10000, wormholeRelayer.getDefaultRelayProvider());
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 1);
        } else {
            uint256 maxTransactionFee =
                wormholeRelayer.quoteGas(vaa.emitterChainId, 10000, wormholeRelayer.getDefaultRelayProvider());
            wormholeRelayer.forward(vaa.emitterChainId, vaa.emitterAddress, vaa.emitterAddress, maxTransactionFee, 0, 1);
        }
    }
}
