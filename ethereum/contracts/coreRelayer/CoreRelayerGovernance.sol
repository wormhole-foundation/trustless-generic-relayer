// contracts/Relayer.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "../libraries/external/BytesLib.sol";

import "./CoreRelayerGetters.sol";
import "./CoreRelayerSetters.sol";
import "./CoreRelayerStructs.sol";
import "./CoreRelayerMessages.sol";

import "../interfaces/IWormhole.sol";

abstract contract CoreRelayerGovernance is
    CoreRelayerGetters,
    CoreRelayerSetters,
    CoreRelayerMessages,
    ERC1967Upgrade
{
    //TODO convert this upgrade to being managed by guardian VAAs

    // event ContractUpgraded(address indexed oldContract, address indexed newContract);
    // event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);
    // event RelayProviderUpdated(address indexed newDefaultRelayProvider);

    /// @dev registerCoreRelayerContract registers other relayer contracts with this relayer
    function registerCoreRelayerContract(uint16 chainId, bytes32 coreRelayerContractAddress) public onlyOwner {
        require(coreRelayerContractAddress != bytes32(0), "1"); //"invalid contract address");
        require(chainId != 0, "3"); //"invalid chainId");

        setRegisteredCoreRelayerContract(chainId, coreRelayerContractAddress);
    }

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 thisRelayerChainId, address newImplementation) public onlyOwner {
        require(thisRelayerChainId == chainId(), "3");

        // cache currentImplementation for event
        //address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        //emit ContractUpgraded(currentImplementation, newImplementation);
    }

    /**
     * @dev submitOwnershipTransferRequest serves to begin the ownership transfer process of the contracts
     * - it saves an address for the new owner in the pending state
     */
    function submitOwnershipTransferRequest(uint16 thisRelayerChainId, address newOwner) public onlyOwner {
        require(thisRelayerChainId == chainId(), "4");
        require(newOwner != address(0), "5");

        setPendingOwner(newOwner);
    }

    /**
     * @dev confirmOwnershipTransferRequest serves to finalize an ownership transfer
     * - it checks that the caller is the pendingOwner to validate the wallet address
     * - it updates the owner state variable with the pendingOwner state variable
     */
    function confirmOwnershipTransferRequest() public {
        // cache the new owner address
        address newOwner = pendingOwner();

        require(msg.sender == newOwner, "6");

        // cache currentOwner for event
        //address currentOwner = owner();

        // update the owner in the contract state and reset the pending owner
        setOwner(newOwner);
        setPendingOwner(address(0));

        //emit OwnershipTransfered(currentOwner, newOwner);
    }

    function setDefaultRelayProvider(address relayProvider) public onlyOwner {
        setRelayProvider(relayProvider);
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "7");
        _;
    }
}
