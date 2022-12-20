// contracts/Relayer.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "../libraries/external/BytesLib.sol";

import "./GasOracleGetters.sol";
import "./GasOracleSetters.sol";


abstract contract GasOracleGovernance is
    GasOracleGetters,
    GasOracleSetters,
    ERC1967Upgrade
{
    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);
    event PermissionedRelayerAddressUpdated(uint16 chainId, bytes32 indexed oldAddress, bytes32 indexed newAddress);
    event DeliverGasOverheadUpdated(uint32 indexed oldGasOverhead, uint32 indexed newGasOverhead);

    function setPermissionedRelayerAddress(uint16 chainId, bytes32 newRelayerAddress) public onlyOwner {
        bytes32 oldAddress = relayerAddress(chainId);
        setRelayerAddress(chainId, newRelayerAddress);
        emit PermissionedRelayerAddressUpdated(chainId, oldAddress, newRelayerAddress);
    }

    function updateDeliverGasOverhead(uint16 chainId, uint32 newGasOverhead) public onlyOwner {
        uint32 currentGasOverhead = deliverGasOverhead(chainId);
        setDeliverGasOverhead(chainId, newGasOverhead);
        emit DeliverGasOverheadUpdated(currentGasOverhead, newGasOverhead);
    }

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 gasOracleChainId, address newImplementation) public onlyOwner {
        require(gasOracleChainId == chainId(), "wrong chain id");

        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
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
        require(owner() == _msgSender(), "owner() != _msgSender()");
        _;
    }
}
