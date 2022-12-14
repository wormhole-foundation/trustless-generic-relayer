// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "solidity-bytes-utils/BytesLib.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IWormholeReceiver.sol";
import "../../interfaces/ICoreRelayer.sol";

contract Xmint is ERC20, IWormholeReceiver {
    // using BytesLib for bytes;

    address owner;

    IWormhole core_bridge;
    ITokenBridge token_bridge;
    ICoreRelayer core_relayer;
    bytes32 hubContract;
    uint16 hubContractChain;

    uint32 nonce = 1;

    //TODO capture in dollars?
    uint256 SAFE_DELIVERY_GAS_CAPTURE = 1000000000; //Capture 1 million gas for fees

    event Log(string indexed str);

    constructor(
        string memory name_,
        string memory symbol_, 
        address coreBridgeAddress,
        address tokenBridgeAddress,
        address coreRelayerAddress
    ) ERC20(name_, symbol_) {
        owner = msg.sender;
        core_bridge = IWormhole(coreBridgeAddress);
        token_bridge = ITokenBridge(tokenBridgeAddress);
        core_relayer = ICoreRelayer(coreRelayerAddress);
    }

    //This function captures native (ETH) tokens from the user, requests a token transfer to the hub contract,
    //And then requests delivery from relayer network.
    function purchaseTokens() public payable {
        //Calculate how many tokens will be required to cover transaction fees.
        uint256 deliveryFeeBuffer = core_relayer.quoteEvmDeliveryPrice(hubContractChain, SAFE_DELIVERY_GAS_CAPTURE);

        //require that enough funds were paid to cover the compute budget.
        require(msg.value > deliveryFeeBuffer);

        uint256 bridgeAmount = msg.value -deliveryFeeBuffer;

        (bool success, bytes memory data) = address(token_bridge).call{value: bridgeAmount}(
            //TODO why does this function not take a nonce?
            abi.encodeWithSignature("wrapAndTransferETHWithPayload(unit16,bytes32,uint32,bytes)", hubContractChain, hubContract, nonce, encodeRecipientPayload(toWormholeFormat(msg.sender)))
        );

        //Request delivery from the relayer network.
        requestDelivery();
    }

    //This function receives messages back from the Hub contract and distributes the tokens to the user.
    function receiveWormholeMessages(bytes[] memory vaas) public override {
        //Complete the token bridge transfer
        ITokenBridge.TransferWithPayload memory transferResult = token_bridge.parseTransferWithPayload(token_bridge.completeTransferWithPayload(vaas[0]));
        //TODO decode recipient, transfer the tokens to them
    }

    function requestDelivery() internal {
        //TODO
    }

    //TODO move these two function into common file
    function encodeRecipientPayload(bytes32 whFormatAddress) internal returns (bytes memory payload){

    }

    function decodeRecipientPayload(bytes memory payload) internal returns (bytes32 whFormatAddress){

    }

    //TODO move elsewhere
    function toWormholeFormat(address native) internal returns (bytes32 whFormatAddress){

    }
}