// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "solidity-bytes-utils/BytesLib.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IWormholeReceiver.sol";
import "../../interfaces/ICoreRelayer.sol";


contract Xmint is ERC20, IWormholeReceiver {
    //using BytesLib for bytes;

    mapping(uint16 => bytes32) trustedContracts;
    mapping(bytes32 => bool) consumedMessages;
    address owner;
    IWormhole core_bridge;
    ITokenBridge token_bridge;
    ICoreRelayer core_relayer;
    uint32 nonce = 1;

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

    /**
        This function is used to add spoke contract deployments into the trusted addresses of this
        contract.
    */
    function registerApplicationContracts(uint16 chainId, bytes32 emitterAddr) public {
        require(msg.sender == owner, "Only owner can register new chains!");
        trustedContracts[chainId] = emitterAddr;
    }

    //This is the function which receives all messages from the remote contracts.
    function receiveWormholeMessages(bytes[] memory vaas) public override {
        //The first message should be from the token bridge, so attempt to redeem it.
        ITokenBridge.TransferWithPayload memory transferResult = token_bridge.parseTransferWithPayload(token_bridge.completeTransferWithPayload(vaas[0]));

        // Ensure this transfer originated from a trusted address!
        // The token bridge enforces replay protection however, so no need to enforce it here.
        // The chain which this came from is a property of the core bridge, so the chain ID is read from the VAA.
        uint16 fromChain = core_bridge.parseVM(vaas[0]).emitterChainId;
        //Require that the address these tokens were sent from is the trusted remote contract for that chain.
        require(transferResult.fromAddress == trustedContracts[fromChain]);
        
        //Calculate how many tokens to mint for the user
        //TODO is transferResult already normalized, or does the normalization have to happen here?
        //TODO is token address the origin mint or the local mint?
        uint256 mintAmount = calculateMintAmount(transferResult.amount, toNativeAddress(transferResult.tokenAddress));

        //Mint tokens to this contract
        _mint(address(this), mintAmount);

        //Bridge the tokens back to the remote contract, noting intended recipient.
        bridgeTokens(fromChain, decodeRecipientPayload(transferResult.payload), mintAmount);

        //Request delivery from the relayer network.
        requestForward(fromChain, decodeRecipientPayload(transferResult.payload));
    }

    //This function allows you to purchase tokens from the Hub chain. Because this is all on the Hub chain, 
    // there's no need for relaying.
    function purchaseLocal() internal {

    }

    function mintLocal() internal {

    }

    function encodeRecipientPayload(bytes memory encoded) internal returns (bytes32 whFormatAddress){

    }

    function decodeRecipientPayload(bytes memory whFormatAddress) internal returns (bytes32 encoded){

    }

    function toNativeAddress(bytes32 whFormatAddress) internal returns (address) {

    } 

    function bridgeTokens(uint16 remoteChain, bytes32 intendedRecipient, uint256 amount) internal {

    }

    function requestForward(uint16 targetChain, bytes32 intendedRecipient) internal {
    }

    //This function calculates how many tokens should be minted to the end user based on how much
    //money they sent to this contract.
    function calculateMintAmount(uint256 inputAmount, address inputToken) internal returns (uint256 mintAmount) {
        //Because this is a toy example, we will mint them 1 token regardless of what token they paid with
        // or how much they paid.
        return 1 * 10^18;
    }
}