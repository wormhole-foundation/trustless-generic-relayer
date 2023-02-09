import { expect } from "chai";
import { ethers } from "ethers";
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  ChainInfo,
  RELAYER_DEPLOYER_PRIVATE_KEY,
} from "./helpers/consts";
import {
  getSignedBatchVaaFromReceiptOnEth,
  getSignedVaaFromReceiptOnEth,
  verifyDeliveryStatusPayload,
} from "./helpers/utils";
import { CoreRelayer__factory, IWormhole__factory, MockRelayerIntegration__factory } from "../../sdk/src";
import { CoreRelayerStructs } from "../../sdk/src/ethers-contracts/CoreRelayer";
import { init, loadChains, loadCoreRelayers, loadMockIntegrations } from "../ts-scripts/helpers/env";

const ETHEREUM_ROOT = `${__dirname}/..`;

init()
const chains = loadChains();
const coreRelayers = loadCoreRelayers();
const mockIntegrations = loadMockIntegrations();

describe("Core Relayer Integration Test - Two Chains", () => {
  const provider = new ethers.providers.StaticJsonRpcProvider(chains[0].rpc);

  // signers
  const wallet = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, provider);

  const sourceChain = chains.find((c)=>(c.chainId == 2)) as ChainInfo;
  const targetChain = chains.find((c)=>(c.chainId == 4)) as ChainInfo;
  const sourceCoreRelayerAddress = coreRelayers.find((p)=>(p.chainId==sourceChain.chainId))?.address as string
  const sourceMockIntegrationAddress = mockIntegrations.find((p)=>(p.chainId==sourceChain.chainId))?.address as string
  const targetCoreRelayerAddress = coreRelayers.find((p)=>(p.chainId==targetChain.chainId))?.address as string
  const targetMockIntegrationAddress = mockIntegrations.find((p)=>(p.chainId==targetChain.chainId))?.address as string

  const sourceCoreRelayer = CoreRelayer__factory.connect(sourceCoreRelayerAddress, wallet);
  const sourceMockIntegration = MockRelayerIntegration__factory.connect(sourceMockIntegrationAddress, wallet);
  const targetCoreRelayer = CoreRelayer__factory.connect(targetCoreRelayerAddress, wallet);
  const targetMockIntegration = MockRelayerIntegration__factory.connect(targetMockIntegrationAddress, wallet);
  
  const sourceWormhole = IWormhole__factory.connect(sourceChain.wormholeAddress, wallet);
  

  it("Executes a delivery", async (done) => {

    try {
      const arbitraryPayload = ethers.utils.hexlify(ethers.utils.toUtf8Bytes((Math.random()*1e32).toString(36)))
      const value = await sourceCoreRelayer.quoteGasDeliveryFee(targetChain.chainId, 1000000, await sourceCoreRelayer.getDefaultRelayProvider());
      console.log(`Quoted gas delivery fee: ${value}`)
      const tx = await targetMockIntegration.sendMessage(arbitraryPayload, targetChain.chainId, targetMockIntegrationAddress, targetMockIntegrationAddress, {value, gasLimit: 500000});
      console.log("Sent delivery request!");
      const rx = await tx.wait();
      console.log("Message confirmed!");

      setTimeout(async () => {
        try {
          console.log("Checking if message was relayed")
          const message = await targetMockIntegration.getMessage();
          console.log(`Original message: ${arbitraryPayload}`);
          console.log(`Received message: ${message}`)
          expect(message).to.equal(arbitraryPayload);
          done()
        } catch (e) {
          done(e)
        }
      }, 1000 * 30)
    } catch (e) {
      done(e);
    }
    
  });
});

