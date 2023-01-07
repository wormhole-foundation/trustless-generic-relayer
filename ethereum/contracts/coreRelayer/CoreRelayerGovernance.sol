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
    using BytesLib for bytes;
    event ContractUpgraded(address indexed oldContract, address indexed newContract);

    // "CoreRelayer" (left padded)
    bytes32 constant module = 0x000000000000000000000000000000000000000000436f726552656c61796572;

    function submitContractUpgrade(bytes memory _vm) public {
        require(!isFork(), "invalid fork");

        (IWormhole.VM memory vm, bool valid, string memory reason) = verifyGovernanceVM(_vm);
        require(valid, reason);

        setConsumedGovernanceAction(vm.hash);

        ContractUpgrade memory contractUpgrade = parseUpgrade(vm.payload);

        require(contractUpgrade.chain == chainId(), "wrong chain id");

        upgradeImplementation(contractUpgrade.newContract);
    }

    function registerCoreRelayerContract(bytes memory vaa) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = verifyGovernanceVM(vaa);
        require(valid, reason);

        setConsumedGovernanceAction(vm.hash);

        RegisterChain memory rc = parseRegisterChain(vm.payload);

        require((rc.chain == chainId() && !isFork()) || rc.chain == 0, "invalid chain id");

        setRegisteredCoreRelayerContract(rc.emitterChain, rc.emitterAddress);
    }

    function setDefaultRelayProvider(bytes memory vaa) public {
        (IWormhole.VM memory vm, bool valid, string memory reason) = verifyGovernanceVM(vaa);
        require(valid, reason);

        setConsumedGovernanceAction(vm.hash);

        UpdateDefaultProvider memory provider = parseUpdateDefaultProvider(vm.payload);

        require((provider.chain == chainId() && !isFork()) || provider.chain == 0, "invalid chain id");

        setRelayProvider(provider.newProvider);
    }

    function parseUpgrade(bytes memory encodedUpgrade) public pure returns (ContractUpgrade memory cu) {
        uint index = 0;

        cu.module = encodedUpgrade.toBytes32(index);
        index += 32;

        require(cu.module == module, "wrong module");

        cu.action = encodedUpgrade.toUint8(index);
        index += 1;

        require(cu.action == 1, "invalid ContractUpgrade");

        cu.chain = encodedUpgrade.toUint16(index);
        index += 2;

        cu.newContract = address(uint160(uint256(encodedUpgrade.toBytes32(index))));
        index += 32;

        require(encodedUpgrade.length == index, "invalid ContractUpgrade");
    }

    function parseRegisterChain(bytes memory encodedRegistration) public pure returns (RegisterChain memory registerChain) {
        uint index = 0;

        registerChain.module = encodedRegistration.toBytes32(index);
        index += 32;

        require(registerChain.module == module, "wrong module");

        registerChain.action = encodedRegistration.toUint8(index);
        index += 1;

        registerChain.chain = encodedRegistration.toUint16(index);
        index += 2;

        require(registerChain.action == 2, "invalid RegisterChain");

        registerChain.emitterChain = encodedRegistration.toUint16(index);
        index += 2;

        registerChain.emitterAddress = encodedRegistration.toBytes32(index);
        index += 32;

        require(encodedRegistration.length == index, "invalid RegisterChain");
    }

    function parseUpdateDefaultProvider(bytes memory encodedDefaultProvider) public pure returns (UpdateDefaultProvider memory defaultProvider) {
        uint index = 0;

        defaultProvider.module = encodedDefaultProvider.toBytes32(index);
        index += 32;

        require(defaultProvider.module == module, "wrong module");

        defaultProvider.action = encodedDefaultProvider.toUint8(index);
        index += 1;

        require(defaultProvider.action == 3, "invalid DefaultProvider");
        
        defaultProvider.chain = encodedDefaultProvider.toUint16(index);
        index += 2;

        defaultProvider.newProvider = address(uint160(uint256(encodedDefaultProvider.toBytes32(index))));
        index += 32;

        require(encodedDefaultProvider.length == index, "invalid DefaultProvider");
    }

    struct ContractUpgrade {
        bytes32 module;
        uint8 action;
        uint16 chain;
        address newContract;
    }

    struct RegisterChain {
        bytes32 module;
        uint8 action;
        uint16 chain; //TODO Why is this on this object?

        uint16 emitterChain;
        bytes32 emitterAddress;
    }

    //This could potentially be combined with ContractUpgrade
    struct UpdateDefaultProvider {
        bytes32 module;
        uint8 action;
        uint16 chain;
        address newProvider;
    }

    function verifyGovernanceVM(bytes memory encodedVM) internal view returns (IWormhole.VM memory parsedVM, bool isValid, string memory invalidReason){
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedVM);

        if (!valid) {
            return (vm, valid, reason);
        }

        if (vm.emitterChainId != governanceChainId()) {
            return (vm, false, "wrong governance chain");
        }
        if (vm.emitterAddress != governanceContract()) {
            return (vm, false, "wrong governance contract");
        }

        if (governanceActionIsConsumed(vm.hash)) {
            return (vm, false, "governance action already consumed");
        }

        return (vm, true, "");
    }

    function upgradeImplementation(address newImplementation) internal {
        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // Call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }
}
