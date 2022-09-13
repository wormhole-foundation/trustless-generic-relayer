// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import "../contracts/gasOracle/GasOracleState.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

contract TestGasOracle is Test {
    uint16 constant TEST_ORACLE_CHAIN_ID = 2;

    GasOracle internal gasOracle;

    function initializeGasOracle(uint16 oracleChainId) internal {
        gasOracle = new GasOracle(
            0xC89Ce4735882C9F0f0FE26686c53074E09B0D550, // wormhole
            oracleChainId // chainId
        );
    }

    function testSetupInitialState(address wormhole, uint16 srcChainId) public {
        vm.assume(wormhole != address(0));
        vm.assume(srcChainId > 0);

        gasOracle = new GasOracle(
            wormhole, // wormhole
            srcChainId // srcChainId
        );

        require(gasOracle.owner() == address(this), "owner() != expected");
        require(gasOracle.chainId() == srcChainId, "chainId() != expected");

        // TODO: check slots?
    }

    function testCannotInitializeWithChainIdZero(address oracleOwner) public {
        vm.assume(oracleOwner != address(0));

        // you shall not pass
        vm.expectRevert("srcChainId == 0");
        initializeGasOracle(
            0 // srcChainId
        );
    }

    function testCannotUpdatePriceWithChainIdZero(uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) public {
        vm.assume(updateGasPrice > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateChainId == 0");
        gasOracle.updatePrice(
            0, // updateChainId
            updateGasPrice,
            updateNativeCurrencyPrice
        );
    }

    function testCannotUpdatePriceWithGasPriceZero(uint16 updateChainId, uint128 updateNativeCurrencyPrice) public {
        vm.assume(updateChainId > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateGasPrice == 0");
        gasOracle.updatePrice(
            updateChainId,
            0, // updateGasPrice == 0
            updateNativeCurrencyPrice
        );
    }

    function testCannotUpdatePriceWithNativeCurrencyPriceZero(uint16 updateChainId, uint128 updateGasPrice) public {
        vm.assume(updateChainId > 0);
        vm.assume(updateGasPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.expectRevert("updateNativeCurrencyPrice == 0");
        gasOracle.updatePrice(
            updateChainId,
            updateGasPrice,
            0 // updateNativeCurrencyPrice == 0
        );
    }

    function testCanUpdatePriceOnlyAsOwner(
        address oracleOwner,
        uint16 updateChainId,
        uint128 updateGasPrice,
        uint128 updateNativeCurrencyPrice
    )
        public
    {
        vm.assume(oracleOwner != address(0));
        vm.assume(oracleOwner != address(this));
        vm.assume(updateChainId > 0);
        vm.assume(updateGasPrice > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // you shall not pass
        vm.prank(oracleOwner);
        vm.expectRevert("owner() != _msgSender()");
        gasOracle.updatePrice(updateChainId, updateGasPrice, updateNativeCurrencyPrice);
    }

    function testCannotGetPriceBeforeUpdateSrcPrice(
        uint16 dstChainId,
        uint128 dstGasPrice,
        uint128 dstNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // update the price with reasonable values
        gasOracle.updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("srcNativeCurrencyPrice == 0");
        gasOracle.getPrice(dstChainId);
    }

    function testCannotGetPriceBeforeUpdateDstPrice(
        uint16 dstChainId,
        uint128 srcGasPrice,
        uint128 srcNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );
        console.log("address(this)", address(this));
        console.log("msg.sender", msg.sender);
        console.log("msg.sender", msg.sender);
        console.log("gasOracle.owner()", gasOracle.owner());

        // update the price with reasonable values
        //vm.prank(gasOracle.owner());
        gasOracle.updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("dstNativeCurrencyPrice == 0");
        gasOracle.getPrice(dstChainId);
    }

    function testUpdatePrice(
        uint16 dstChainId,
        uint128 dstGasPrice,
        uint128 dstNativeCurrencyPrice,
        uint128 srcGasPrice,
        uint128 srcNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        // update the prices with reasonable values
        gasOracle.updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);
        gasOracle.updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        // verify price
        uint256 expected = (uint256(dstGasPrice) * dstNativeCurrencyPrice) / srcNativeCurrencyPrice;
        require(gasOracle.getPrice(dstChainId) == expected, "gasOracle.getPrice(updateChainId) != expected");
    }

    function testUpdatePrices(
        uint16 dstChainId,
        uint128 dstGasPrice,
        uint128 dstNativeCurrencyPrice,
        uint128 srcGasPrice,
        uint128 srcNativeCurrencyPrice
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);

        initializeGasOracle(
            TEST_ORACLE_CHAIN_ID // chainId
        );

        GasOracle.UpdatePrice[] memory updates = new GasOracle.UpdatePrice[](2);
        updates[0] = GasOracle.UpdatePrice({
            chainId: TEST_ORACLE_CHAIN_ID,
            gasPrice: srcGasPrice,
            nativeCurrencyPrice: srcNativeCurrencyPrice
        });
        updates[1] = GasOracle.UpdatePrice({
            chainId: dstChainId,
            gasPrice: dstGasPrice,
            nativeCurrencyPrice: dstNativeCurrencyPrice
        });

        // update the prices with reasonable values
        gasOracle.updatePrices(updates);

        // verify price
        uint256 expected = (uint256(dstGasPrice) * dstNativeCurrencyPrice) / srcNativeCurrencyPrice;
        require(gasOracle.getPrice(dstChainId) == expected, "gasOracle.getPrice(updateChainId) != expected");
    }
}
