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
    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);
    event GasOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event EVMDeliverGasOverheadUpdated(uint32 indexed oldGasOverhead, uint32 indexed newGasOverhead);

    /// @dev registerChain registers other relayer contracts with this relayer
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

    /// @dev updateEvmDeliverGasOverhead changes the EVMGasOverhead variable
    function updateEvmDeliverGasOverhead(uint32 newGasOverhead) public onlyOwner {
        // cache the current EVMDeliverGasOverhead
        uint32 currentGasOverhead = evmDeliverGasOverhead();

        setEvmDeliverGasOverhead(newGasOverhead);

        emit EVMDeliverGasOverheadUpdated(currentGasOverhead, newGasOverhead);
    }

    /// @dev updateGasOracleContract changes the contract address for the gasOracle
    function updateGasOracleContract(uint16 thisRelayerChainId, address newGasOracleAddress) public onlyOwner {
        require(thisRelayerChainId == chainId(), "wrong chain id");
        require(newGasOracleAddress != address(0), "new gasOracle address cannot be address(0)");

        // cache the current gas oracle address
        address currentGasOracle = gasOracleAddress();

        setGasOracle(newGasOracleAddress);

        emit GasOracleUpdated(currentGasOracle, newGasOracleAddress);
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
