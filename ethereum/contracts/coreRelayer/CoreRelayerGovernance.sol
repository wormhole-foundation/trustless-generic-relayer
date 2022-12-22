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
    //TODO set default relay provider function, managed by VAAs

    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);
    event RelayProviderUpdated(address indexed oldDefaultRelayProvider, address indexed newDefaultRelayProvider);
    
    /// @dev registerChain registers other trusted contracts with this contract
    function registerChain(uint16 relayerChainId, bytes32 relayerAddress) public onlyOwner {
        require(relayerAddress != bytes32(0), "invalid relayer address");
        require(registeredRelayer(relayerChainId) == bytes32(0), "relayer already registered");
        require(relayerChainId != 0, "invalid chainId");

        setRegisteredRelayer(relayerChainId, relayerAddress);
    }

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 thisRelayerChainId, address newImplementation) public onlyOwner {
        require(thisRelayerChainId == chainId(), "wrong chain id");

        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }


    /// @dev updateRelayProviderContract changes the contract address for the RelayProvider
    function updateDefaultRelayProviderContract(uint16 thisChainId, address newRelayProviderAddress) public onlyOwner {
        require(thisChainId == chainId(), "wrong chain id");
        require(newRelayProviderAddress != address(0), "new RelayProvider address cannot be address(0)");

        // cache the current defaultRelayProvider address
        address currentRelayProvider = getDefaultRelayProviderAddress();

        setDefaultRelayProvider(newRelayProviderAddress);

        emit RelayProviderUpdated(currentRelayProvider, newRelayProviderAddress);
    }

    /**
     * @dev submitOwnershipTransferRequest serves to begin the ownership transfer process of the contracts
     * - it saves an address for the new owner in the pending state
     */
    function submitOwnershipTransferRequest(uint16 thisRelayerChainId, address newOwner) public onlyOwner {
        require(thisRelayerChainId == chainId(), "incorrect chainId");
        require(newOwner != address(0), "new owner cannot be address(0)");

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

        require(msg.sender == newOwner, "caller must be pending owner");

        // cache currentOwner for Event
        address currentOwner = owner();

        // update the owner in the contract state and reset the pending owner
        setOwner(newOwner);
        setPendingOwner(address(0));

        emit OwnershipTransfered(currentOwner, newOwner);
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "caller must be the owner");
        _;
    }
}
