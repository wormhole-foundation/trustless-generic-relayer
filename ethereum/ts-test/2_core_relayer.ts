import { expect } from "chai";
import { ethers } from "ethers";
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  ChainInfo,
  RELAYER_DEPLOYER_PRIVATE_KEY,
} from "./helpers/consts";
import { generateRandomString } from "./helpers/utils";
import { CoreRelayer__factory, IWormhole__factory, MockRelayerIntegration__factory } from "../../sdk/src";
import { init, loadChains, loadCoreRelayers, loadMockIntegrations } from "../ts-scripts/helpers/env";

const ETHEREUM_ROOT = `${__dirname}/..`;

init()
const chains = loadChains();
const coreRelayers = loadCoreRelayers();
const mockIntegrations = loadMockIntegrations();



describe("Core Relayer Integration Test - Two Chains", () => {
 
  // signers
  

  const sourceChain = chains.find((c)=>(c.chainId == 2)) as ChainInfo;
  const targetChain = chains.find((c)=>(c.chainId == 4)) as ChainInfo;

  const providerSource = new ethers.providers.StaticJsonRpcProvider(sourceChain.rpc);
  const providerTarget = new ethers.providers.StaticJsonRpcProvider(targetChain.rpc);

  const walletSource = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerSource);
  const walletTarget = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerTarget);

  const sourceCoreRelayerAddress = coreRelayers.find((p)=>(p.chainId==sourceChain.chainId))?.address as string
  const sourceMockIntegrationAddress = mockIntegrations.find((p)=>(p.chainId==sourceChain.chainId))?.address as string
  const targetCoreRelayerAddress = coreRelayers.find((p)=>(p.chainId==targetChain.chainId))?.address as string
  const targetMockIntegrationAddress = mockIntegrations.find((p)=>(p.chainId==targetChain.chainId))?.address as string

  const sourceCoreRelayer = CoreRelayer__factory.connect(sourceCoreRelayerAddress, walletSource);
  const sourceMockIntegration = MockRelayerIntegration__factory.connect(sourceMockIntegrationAddress, walletSource);
  const targetCoreRelayer = CoreRelayer__factory.connect(targetCoreRelayerAddress, walletTarget);
  const targetMockIntegration = MockRelayerIntegration__factory.connect(targetMockIntegrationAddress, walletTarget);

  it("Executes a delivery", async () => {

      const arbitraryPayload = ethers.utils.hexlify(ethers.utils.toUtf8Bytes(generateRandomString(32)))
      console.log(`Sent message: ${arbitraryPayload}`);
      const value = await sourceCoreRelayer.quoteGasDeliveryFee(targetChain.chainId, 1000000, await sourceCoreRelayer.getDefaultRelayProvider());
      console.log(`Quoted gas delivery fee: ${value}`)
      const tx = await sourceMockIntegration.sendMessage(arbitraryPayload, targetChain.chainId, targetMockIntegrationAddress, targetMockIntegrationAddress, {value, gasLimit: 500000});
      console.log("Sent delivery request!");
      const rx = await tx.wait();
      console.log("Message confirmed!");

      await new Promise((resolve) => {
        setTimeout(() => {
          resolve(0);
        }, 5000)
      })

      console.log("Checking if message was relayed")
      const message = await targetMockIntegration.getMessage();
      console.log(`Sent message: ${arbitraryPayload}`);
      console.log(`Received message: ${message}`)
      expect(message).to.equal(arbitraryPayload);
    
    
  });
  it("Executes a forward", async () => {

    const arbitraryPayload = ethers.utils.hexlify(ethers.utils.toUtf8Bytes(generateRandomString(32)))
    console.log(`Sent message: ${arbitraryPayload}`);
    const value = await sourceCoreRelayer.quoteGasDeliveryFee(targetChain.chainId, 1000000, await sourceCoreRelayer.getDefaultRelayProvider());
    console.log(`Quoted gas delivery fee: ${value}`)
    const tx = await sourceMockIntegration.sendMessage(arbitraryPayload, targetChain.chainId, targetMockIntegrationAddress, targetMockIntegrationAddress, {value, gasLimit: 500000});
    console.log("Sent delivery request!");
    const rx = await tx.wait();
    console.log("Message confirmed!");

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0);
      }, 5000)
    })

    console.log("Checking if message was relayed")
    const message = await targetMockIntegration.getMessage();
    console.log(`Sent message: ${arbitraryPayload}`);
    console.log(`Received message: ${message}`)
    expect(message).to.equal(arbitraryPayload);
  
  
});
});

