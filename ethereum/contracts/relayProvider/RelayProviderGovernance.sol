// contracts/Relayer.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "../libraries/external/BytesLib.sol";

import "./RelayProviderGetters.sol";
import "./RelayProviderSetters.sol";
import "./RelayProviderStructs.sol";



abstract contract RelayProviderGovernance is
    RelayProviderGetters,
    RelayProviderSetters,
    ERC1967Upgrade
{
    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);
    event RewardAddressUpdated(address indexed newAddress);
    event DeliveryAddressUpdated(uint16 indexed targetChainId, bytes32 indexed newAddress);
    event DeliverGasOverheadUpdated(uint32 indexed oldGasOverhead, uint32 indexed newGasOverhead);

    function updateRewardAddress(address newAddress) public onlyOwner {
        setRewardAddress(newAddress);
        emit RewardAddressUpdated(newAddress);
    }

    function updateDeliveryAddress(uint16 targetChain, bytes32 newAddress) public onlyOwner {
        setDeliveryAddress(targetChain, newAddress);
        emit DeliveryAddressUpdated(targetChain, newAddress);
    }

    function updateDeliverGasOverhead(uint16 chainId, uint32 newGasOverhead) public onlyOwner {
        uint32 currentGasOverhead = deliverGasOverhead(chainId);
        setDeliverGasOverhead(chainId, newGasOverhead);
        emit DeliverGasOverheadUpdated(currentGasOverhead, newGasOverhead);
    }

    function updateWormholeFee(uint16 chainId, uint32 newWormholeFee) public onlyOwner {
        setWormholeFee(chainId, newWormholeFee);
    }

    function updatePrice(uint16 updateChainId, uint128 updateGasPrice, uint128 updateNativeCurrencyPrice)
        public
        onlyOwner
    {
        require(updateChainId > 0, "updateChainId == 0");
        require(updateGasPrice > 0, "updateGasPrice == 0");
        require(updateNativeCurrencyPrice > 0, "updateNativeCurrencyPrice == 0");
        setPriceInfo(updateChainId, updateGasPrice, updateNativeCurrencyPrice);
    }

    function updatePrices(RelayProviderStructs.UpdatePrice[] memory updates) public onlyOwner {
        uint256 pricesLen = updates.length;
        for (uint256 i = 0; i < pricesLen;) {
            updatePrice(updates[i].chainId, updates[i].gasPrice, updates[i].nativeCurrencyPrice);
            unchecked {
                i += 1;
            }
        }
    }

    function updateMaximumBudget(uint16 targetChainId, uint256 maximumTotalBudget) public onlyOwner {
        setMaximumBudget(targetChainId, maximumTotalBudget);
    }

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 relayProviderChainId, address newImplementation) public onlyOwner {
        require(relayProviderChainId == chainId(), "wrong chain id");

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
