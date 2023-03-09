import { ethers } from "ethers";
import {CoreRelayer__factory, getCoreRelayer} from "../sdk/src"
import { ChainInfo, RELAYER_DEPLOYER_PRIVATE_KEY } from "./ts-test/helpers/consts"
import {
    init,
    loadChains,
    loadCoreRelayers,
    loadMockIntegrations,
  } from "./ts-scripts/helpers/env"

init()
const chains = loadChains()
const coreRelayers = loadCoreRelayers()

const coreRelayerAddress = coreRelayers.find(
    (p) => p.chainId == 4
  )?.address as string

const wallet = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, new ethers.providers.StaticJsonRpcProvider("http://localhost:8546")) 
const coreRelayer = CoreRelayer__factory.connect(coreRelayerAddress, wallet);
const run = async () => {
  console.log("Core relayer address")
  console.log(coreRelayerAddress);

  //0x010000000301007716b4804bf3e918819a37efa2aadcfdceb66263e5e84bb4215983b2b2cea9825e165406296fb0dbd5274b64d8b59d5f9b3ba99f0a5499d9b026b89fa20c2136000000000083f28822000100000000000000000000000000000000000000000000000000000000000000049016127c9d4b7d6e2000000000000000000000000000000000000000436f726552656c617965720d0a010004000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f
    const tx = await coreRelayer.setDefaultRelayProvider(ethers.utils.arrayify("0x01000000000100a943d1df9ac14e7b8a7ac908f8f5e3e37a4e8bb18e81276832b8cfe3b7676c6104cf7ae7a4e3d9f0e787d12b312433fb09e55b0be384b43ea2522e344410bcfb01000000005230e00900010000000000000000000000000000000000000000000000000000000000000004ae3178acb6b528c720000000000000000000000000000000000000000000436f726552656c617965720300040000000000000000000000000000000000000000000000000000000000000004"), {gasLimit: 500000});
    await tx.wait();
    console.log("The default relay provider...")
    console.log((await coreRelayer.getDefaultRelayProvider()))
}


run();