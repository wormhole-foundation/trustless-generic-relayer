// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Migrations} from "wormhole/ethereum/contracts/Migrations.sol";
import {IWormhole} from "contracts/interfaces/IWormhole.sol";
import {RelayProvider} from "contracts/relayProvider/RelayProvider.sol";
import {RelayProviderSetup} from "contracts/relayProvider/RelayProviderSetup.sol";
import {RelayProviderImplementation} from "contracts/relayProvider/RelayProviderImplementation.sol";
import {RelayProviderProxy} from "contracts/relayProvider/RelayProviderProxy.sol";
import {CoreRelayer} from "contracts/coreRelayer/CoreRelayer.sol";
import {CoreRelayerSetup} from "contracts/coreRelayer/CoreRelayerSetup.sol";
import {CoreRelayerImplementation} from "contracts/coreRelayer/CoreRelayerImplementation.sol";
import {CoreRelayerProxy} from "contracts/coreRelayer/CoreRelayerProxy.sol";
import {MockRelayerIntegration} from "contracts/mock/MockRelayerIntegration.sol";

import "forge-std/console.sol";

//Goal deploy all necessary contracts to one chain

//Initialize our wallet & RPC provider
//Initialize our Wormhole object

//Step 1: Deploy RelayProvider
// Deploy Contracts
// Call setup
// Set Reward Address, set delivery address, set delivergasoverhead, set price table, set maximum budget

//Step 2: Deploy CoreRelayer
// Deploy Contracts
// Call setup
// later: register all core relayers with eachother

//Step 3: Deploy xMint
// Deploy Hub if hubchain, deploy spoke if spoke chain
// call setup

contract ContractScript is Script {
    Migrations migrations;
    IWormhole wormhole;

    // GasOracle
    RelayProviderSetup relayProviderSetup;
    RelayProviderImplementation relayProviderImplementation;
    RelayProviderProxy relayProviderProxy;

    // CoreRelayer
    CoreRelayerSetup coreRelayerSetup;
    CoreRelayerImplementation coreRelayerImplementation;
    CoreRelayerProxy coreRelayerProxy;
    CoreRelayer coreRelayer;

    // MockRelayerIntegration
    MockRelayerIntegration mockRelayerIntegration;

    address TILT_WORMHOLE_ADDRESS = 0xC89Ce4735882C9F0f0FE26686c53074E09B0D550;
    address TILT_MIGRATION_ADDRESS = 0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab;
    bool isTilt = false;
    uint16 chainId;
    address wormholeAddress;

    function setUp() public {}

    function deployRelayProvider() public {
        // first Setup
        relayProviderSetup = new RelayProviderSetup();

        // next Implementation
        relayProviderImplementation = new RelayProviderImplementation();

        // setup Proxy using Implementation
        relayProviderProxy = new RelayProviderProxy(
            address(relayProviderSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16)")),
                address(relayProviderImplementation),
                wormhole.chainId()
            )
        );

        // following is used just to roll to the next block
        if (isTilt) {
            migrations.setCompleted(69);
        }
    }

    function deployCoreRelayer() public {
        // first Setup
        coreRelayerSetup = new CoreRelayerSetup();

        // next Implementation
        coreRelayerImplementation = new CoreRelayerImplementation();

        // setup Proxy using Implementation
        coreRelayerProxy = new CoreRelayerProxy(
            address(coreRelayerSetup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,address)")),
                address(coreRelayerImplementation),
                wormhole.chainId(),
                address(wormhole),
                address(relayProviderProxy)
            )
        );

        // following is used just to roll to the next block
        if (isTilt) {
            migrations.setCompleted(69);
        }

        coreRelayer = CoreRelayer(address(coreRelayerProxy));
    }

    function configureRelayProvider() public {
        address currentAddress = address(this);
        RelayProvider provider = RelayProvider(address(relayProviderProxy));
        CoreRelayer core_relayer = CoreRelayer(address(coreRelayerProxy));

        //Set Reward Address,
        provider.updateRewardAddress(currentAddress);

        uint16[] memory chains;

        //set delivery address,
        if (isTilt) {
            chains = new uint16[](2);
            chains[0] = 2;
            chains[1] = 4;
        } else {
            chains = new uint16[](2);
            chains[0] = 6;
            chains[1] = 14;
        }

        bytes32 thing = core_relayer.toWormholeFormat(currentAddress);
        console.log("got current address wh");

        for (uint16 i = 0; i < chains.length; i++) {
            console.log("about to set delivery address");
            provider.updateDeliveryAddress(chains[i], core_relayer.toWormholeFormat(currentAddress));
            provider.updateAssetConversionBuffer(chains[i], 5, 100);
            provider.updateDeliverGasOverhead(chains[i], 350000);
            provider.updatePrice(chains[i], uint128(300000000000), uint128(100000));
            provider.updateMaximumBudget(chains[i], uint256(1000000000000000000));

            console.log("max budget for chain %s", i);
            console.log(provider.quoteMaximumBudget(i));
        }
    }

    function configureCoreRelayer() public {
        //Only thing to do here is register all the chains together
        // contract already registers itself in the setup
        // CoreRelayer core_relayer = CoreRelayer(address(coreRelayerProxy));
        // core_relayer.registerCoreRelayerContract(chainId, core_relayer.toWormholeFormat(address(core_relayer)));
    }

    // function deployMockRelayerIntegration() public {
    //     // deploy the mock integration contract
    //     mockRelayerIntegration = new MockRelayerIntegration(
    //         address(wormhole),
    //         address(coreRelayerProxy)
    //     );
    // }

    function deployRelayerIntegrationContract() public {
        // if(chainId == 2 || chainId == 6) {
        //     //deploy hub
        // } else {
        //     //deploy spoke
        // }

        mockRelayerIntegration = new MockRelayerIntegration(address(wormhole), 
            address(coreRelayerProxy));
    }

    function run(address _wormholeAddress) public {
        //actual setup
        wormhole = IWormhole(_wormholeAddress);
        wormholeAddress = _wormholeAddress;
        chainId = wormhole.chainId();
        isTilt = (wormholeAddress == TILT_WORMHOLE_ADDRESS);
        if (isTilt) {
            console.log("running in tilt");
            migrations = Migrations(TILT_MIGRATION_ADDRESS);
        }

        // begin sending transactions
        vm.startBroadcast();

        deployRelayProvider();
        deployCoreRelayer();

        configureRelayProvider();
        configureCoreRelayer();

        vm.roll(block.number + 1);

        deployRelayerIntegrationContract();

        mockRelayerIntegration.sendMessage{
            gas: 1000000,
            value: coreRelayer.quoteGasDeliveryFee(chainId, 1000000, coreRelayer.getDefaultRelayProvider()) + 10000000000
        }(abi.encode("Hello World"), chainId, address(mockRelayerIntegration));

        // finished
        vm.stopBroadcast();
    }
}
