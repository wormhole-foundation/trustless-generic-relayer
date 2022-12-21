// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../contracts/gasOracle/GasOracle.sol";
import "../contracts/interfaces/IGasOracle.sol";
import {Implementation} from "../wormhole/ethereum/contracts/Implementation.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

contract TestGasOracle is Test {
    uint16 constant TEST_ORACLE_CHAIN_ID = 2;

    IGasOracle internal gasOracle;

    function initializeGasOracle() internal {
   
        GasOracle gasOracleImplementation = new GasOracle(TEST_ORACLE_CHAIN_ID);

        require(gasOracleImplementation.owner() == address(this), "owner() != expected");
        require(gasOracleImplementation.chainId() == TEST_ORACLE_CHAIN_ID, "chainId() != expected");

        gasOracle = IGasOracle(address(gasOracleImplementation));
    }

    function testCannotUpdatePriceWithChainIdZero(uint128 updateGasPrice, uint128 updateNativeCurrencyPrice) public {
        vm.assume(updateGasPrice > 0);
        vm.assume(updateNativeCurrencyPrice > 0);

        initializeGasOracle();

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

        initializeGasOracle();

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

        initializeGasOracle();

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

        initializeGasOracle();

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

        initializeGasOracle();

        // update the price with reasonable values
        gasOracle.updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("srcNativeCurrencyPrice == 0");
        gasOracle.quoteEvmDeliveryPrice(dstChainId, 1);
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

        initializeGasOracle();

        // update the price with reasonable values
        //vm.prank(gasOracle.owner());
        gasOracle.updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        // you shall not pass
        vm.expectRevert("dstNativeCurrencyPrice == 0");
        gasOracle.quoteEvmDeliveryPrice(dstChainId, 1);
    }

    function testUpdatePrice(
        uint16 dstChainId,
        uint128 dstGasPrice,
        uint64 dstNativeCurrencyPrice,
        uint128 srcGasPrice,
        uint64 srcNativeCurrencyPrice,
        uint32 gasLimit,
        uint32 deliverGasOverhead,
        uint32 targetWormholeFee
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID);
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);

        initializeGasOracle();

        // update the prices with reasonable values
        gasOracle.updatePrice(dstChainId, dstGasPrice, dstNativeCurrencyPrice);
        gasOracle.updatePrice(TEST_ORACLE_CHAIN_ID, srcGasPrice, srcNativeCurrencyPrice);

        gasOracle.updateDeliverGasOverhead(dstChainId, deliverGasOverhead);
        gasOracle.updateWormholeFee(dstChainId, targetWormholeFee);

        // verify price
        uint256 expected = ( uint256(dstNativeCurrencyPrice) * (uint256(dstGasPrice) * (uint64(gasLimit) + deliverGasOverhead)) + (srcNativeCurrencyPrice - 1)) / srcNativeCurrencyPrice + targetWormholeFee ;
        require(gasOracle.quoteEvmDeliveryPrice(dstChainId, gasLimit) == expected, "gasOracle.quoteEvmDeliveryPrice(...) != expected");
    }

    struct UpdatePrice {
        uint16 chainId;
        uint128 gasPrice;
        uint128 nativeCurrencyPrice;
    }


    function testUpdatePrices(
        uint16 dstChainId,
        uint128 dstGasPrice,
        uint64 dstNativeCurrencyPrice,
        uint128 srcGasPrice,
        uint64 srcNativeCurrencyPrice,
        uint32 gasLimit,
        uint32 deliverGasOverhead,
        uint32 targetWormholeFee
    )
        public
    {
        vm.assume(dstChainId > 0);
        vm.assume(dstChainId != TEST_ORACLE_CHAIN_ID); // wormhole.chainId()
        vm.assume(dstGasPrice > 0);
        vm.assume(dstNativeCurrencyPrice > 0);
        vm.assume(srcGasPrice > 0);
        vm.assume(srcNativeCurrencyPrice > 0);

        initializeGasOracle();

        IGasOracle.UpdatePrice[] memory updates = new IGasOracle.UpdatePrice[](2);
        updates[0] = IGasOracle.UpdatePrice({
            chainId: TEST_ORACLE_CHAIN_ID,
            gasPrice: srcGasPrice,
            nativeCurrencyPrice: srcNativeCurrencyPrice
        });
        updates[1] = IGasOracle.UpdatePrice({
            chainId: dstChainId,
            gasPrice: dstGasPrice,
            nativeCurrencyPrice: dstNativeCurrencyPrice
        });

        // update the prices with reasonable values
        gasOracle.updatePrices(updates);

         gasOracle.updateDeliverGasOverhead(dstChainId, deliverGasOverhead);
        gasOracle.updateWormholeFee(dstChainId, targetWormholeFee);

        // verify price
        uint256 expected = ( uint256(dstNativeCurrencyPrice) * (uint256(dstGasPrice) * (uint64(gasLimit) + deliverGasOverhead)) + (srcNativeCurrencyPrice - 1)) / srcNativeCurrencyPrice + targetWormholeFee ;
        require(gasOracle.quoteEvmDeliveryPrice(dstChainId, gasLimit) == expected, "gasOracle.quoteEvmDeliveryPrice(...) != expected");
    }
}
