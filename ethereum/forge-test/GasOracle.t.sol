// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import "../contracts/gasOracle/GasOracleSetup.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

contract TestGasOracle is GasOracle, GasOracleSetup, Test {
    uint16 constant TEST_ORACLE_CHAIN_ID = 2;
    //uint256 constant TEST_SRC_GAS_PRICE = 10;
    //uint256 constant TEST_SRC_NATIVE_CURRENCY_PRICE = 250;

    function initializeGasOracle(address oracleOwner, uint16 oracleChainId) internal {
        setupInitialState(
            oracleOwner, // owner
            0xC89Ce4735882C9F0f0FE26686c53074E09B0D550, // wormhole
            oracleChainId // chainId
        );
    }

    function testSetupInitialState(address oracleOwner, address wormhole, uint16 srcChainId) public {
        vm.assume(oracleOwner != address(0));
        vm.assume(wormhole != address(0));
        vm.assume(srcChainId > 0);

        setupInitialState(
            oracleOwner, // owner
            wormhole, // wormhole
            srcChainId // srcChainId
        );

        require(owner() == oracleOwner, "owner() != expected");
        require(chainId() == srcChainId, "chainId() != expected");
        require(_state.provider.wormhole == wormhole, "_state.provider.wormhole != expected");

        // TODO: check slots?
    }

    function testCannotInitializeWithOwnerZeroAddress(uint16 srcChainId) public {
        vm.assume(srcChainId > 0);

        // you shall not pass
        vm.expectRevert("owner == address(0)");
        initializeGasOracle(
            address(0), // owner
            srcChainId // srcChainId
        );
    }

    function testCannotInitializeWithChainIdZero(address oracleOwner) public {
        vm.assume(oracleOwner != address(0));

        // you shall not pass
        vm.expectRevert("srcChainId == 0");
        initializeGasOracle(
            oracleOwner, // owner
            0 // srcChainId
        );
    }

    function testCannotUpdatePriceWithChainIdZero(uint256 updateGasPrice, uint256 updateNativeCurrencyPrice) public {
        vm.assume(updateGasPrice > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            _msgSender(), // owner
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateChainId == 0");
        updatePrice(
            0, // updateChainId
            updateGasPrice,
            updateNativeCurrencyPrice
        );
    }

    function testCannotUpdatePriceWithGasPriceZero(uint16 updateChainId, uint256 updateNativeCurrencyPrice) public {
        vm.assume(updateChainId > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            _msgSender(), // owner
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateGasPrice == 0");
        updatePrice(
            updateChainId,
            0, // updateGasPrice == 0
            updateNativeCurrencyPrice
        );
    }

    function testCannotUpdatePriceWithNativeCurrencyPriceZero(uint16 updateChainId, uint256 updateGasPrice) public {
        vm.assume(updateChainId > 0);
        vm.assume(updateGasPrice > 0);

        initializeGasOracle(
            _msgSender(), // owner
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateNativeCurrencyPrice == 0");
        updatePrice(
            updateChainId,
            updateGasPrice,
            0 // updateNativeCurrencyPrice == 0
        );
    }

    function testCanUpdatePriceOnlyAsOwner(
        address oracleOwner,
        uint16 updateChainId,
        uint256 updateGasPrice,
        uint256 updateNativeCurrencyPrice
    )
        public
    {
        vm.assume(oracleOwner != address(0));
        vm.assume(oracleOwner != _msgSender());
        vm.assume(updateChainId > 0);
        vm.assume(updateGasPrice > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            oracleOwner,
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("owner() != _msgSender()");
        updatePrice(
            updateChainId, // chainId
            updateGasPrice, // gasPrice
            updateNativeCurrencyPrice // nativeCurrencyPrice
        );
    }

    function testCannotGetPriceBeforeUpdateSrcPrice(
        uint16 dstChainId,
        uint256 dstGasPrice,
        uint256 dstNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        // we will also assume reasonable values for gasPrice and nativeCurrencyPrice
        vm.assume(dstGasPrice < 2 ** 128);
        vm.assume(dstNativeCurrencyPrice < 2 ** 128);

        initializeGasOracle(
            _msgSender(),
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // update the price with reasonable values
        updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("srcNativeCurrencyPrice == 0");
        getPrice(dstChainId);
    }

    function testCannotGetPriceBeforeUpdateDstPrice(
        uint16 dstChainId,
        uint256 srcGasPrice,
        uint256 srcNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);
        // we will also assume reasonable values for gasPrice and nativeCurrencyPrice
        vm.assume(srcGasPrice < 2 ** 128);
        vm.assume(srcNativeCurrencyPrice < 2 ** 128);

        initializeGasOracle(
            _msgSender(),
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // update the price with reasonable values
        updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("dstNativeCurrencyPrice == 0");
        getPrice(dstChainId);
    }

    function testUpdatePrice(
        uint16 dstChainId,
        uint256 dstGasPrice,
        uint256 dstNativeCurrencyPrice,
        uint256 srcGasPrice,
        uint256 srcNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);
        // we will also assume reasonable values for gasPrice and nativeCurrencyPrice
        vm.assume(dstGasPrice < 2 ** 128);
        vm.assume(dstNativeCurrencyPrice < 2 ** 128);
        vm.assume(srcGasPrice < 2 ** 128);
        vm.assume(srcNativeCurrencyPrice < 2 ** 128);

        initializeGasOracle(
            _msgSender(),
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // update the prices with reasonable values
        updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);
        updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        // verify price
        uint256 expected = dstGasPrice * dstNativeCurrencyPrice / srcNativeCurrencyPrice;
        require(getPrice(dstChainId) == expected, "getPrice(updateChainId) != expected");
    }
}
