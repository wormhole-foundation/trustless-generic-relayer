// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

library CoreRelayerLibrary {
    using BytesLib for bytes;

    function parseUpgrade(bytes memory encodedUpgrade, bytes32 module)
        public
        pure
        returns (ContractUpgrade memory cu)
    {
        uint256 index = 0;

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

    function parseRegisterChain(bytes memory encodedRegistration, bytes32 module)
        public
        pure
        returns (RegisterChain memory registerChain)
    {
        uint256 index = 0;

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

    function parseUpdateDefaultProvider(bytes memory encodedDefaultProvider, bytes32 module)
        public
        pure
        returns (UpdateDefaultProvider memory defaultProvider)
    {
        uint256 index = 0;

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
}
