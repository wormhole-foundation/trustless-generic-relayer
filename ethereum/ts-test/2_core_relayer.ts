import { expect } from "chai"
import { ethers } from "ethers"
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk"
import { ChainInfo, RELAYER_DEPLOYER_PRIVATE_KEY } from "./helpers/consts"
import { generateRandomString } from "./helpers/utils"
import {
  WormholeRelayer__factory,
  IWormhole__factory,
  MockRelayerIntegration__factory,
} from "../../sdk/src"
import {
  init,
  loadChains,
  loadWormholeRelayers,
  loadMockIntegrations,
} from "../ts-scripts/helpers/env"
import { MockRelayerIntegration, IWormholeRelayer } from "../../sdk/src"
const ETHEREUM_ROOT = `${__dirname}/..`

init()
const chains = loadChains()
const coreRelayers = loadWormholeRelayers()
const mockIntegrations = loadMockIntegrations()

describe("Core Relayer Integration Test - Two Chains", () => {
  // signers

  const sourceChain = chains.find((c) => c.chainId == 2) as ChainInfo
  const targetChain = chains.find((c) => c.chainId == 4) as ChainInfo

  const providerSource = new ethers.providers.StaticJsonRpcProvider(sourceChain.rpc)
  const providerTarget = new ethers.providers.StaticJsonRpcProvider(targetChain.rpc)

  const walletSource = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerSource)
  const walletTarget = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerTarget)

  const sourceWormholeRelayerAddress = coreRelayers.find(
    (p) => p.chainId == sourceChain.chainId
  )?.address as string
  const sourceMockIntegrationAddress = mockIntegrations.find(
    (p) => p.chainId == sourceChain.chainId
  )?.address as string
  const targetWormholeRelayerAddress = coreRelayers.find(
    (p) => p.chainId == targetChain.chainId
  )?.address as string
  const targetMockIntegrationAddress = mockIntegrations.find(
    (p) => p.chainId == targetChain.chainId
  )?.address as string

  const sourceWormholeRelayer = WormholeRelayer__factory.connect(
    sourceWormholeRelayerAddress,
    walletSource
  )
  const sourceMockIntegration = MockRelayerIntegration__factory.connect(
    sourceMockIntegrationAddress,
    walletSource
  )
  const targetWormholeRelayer = WormholeRelayer__factory.connect(
    targetWormholeRelayerAddress,
    walletTarget
  )
  const targetMockIntegration = MockRelayerIntegration__factory.connect(
    targetMockIntegrationAddress,
    walletTarget
  )

  it("Executes a delivery", async () => {
    const arbitraryPayload = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload}`)
    const value = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee: ${value}`)
    const tx = await sourceMockIntegration.sendMessage(
      arbitraryPayload,
      targetChain.chainId,
      targetMockIntegrationAddress,
      { value, gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 2000)
    })

    console.log("Checking if message was relayed")
    const message = await targetMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload}`)
    console.log(`Received message: ${message}`)
    expect(message).to.equal(arbitraryPayload)
  })

  it("Executes a forward", async () => {
    const arbitraryPayload1 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    const arbitraryPayload2 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload1}`)
    const value = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    const extraForwardingValue = await targetWormholeRelayer.quoteGas(
      sourceChain.chainId,
      500000,
      await targetWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee: ${value.add(extraForwardingValue)}`)

    const furtherInstructions: MockRelayerIntegration.FurtherInstructionsStruct = {
      keepSending: true,
      newMessages: [arbitraryPayload2, "0x00"],
      chains: [sourceChain.chainId],
      gasLimits: [500000],
    }
    const tx = await sourceMockIntegration.sendMessagesWithFurtherInstructions(
      [arbitraryPayload1],
      furtherInstructions,
      [targetChain.chainId],
      [value.add(extraForwardingValue)],
      { value: value.add(extraForwardingValue), gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if message was relayed")
    const message1 = await targetMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload1} (expecting ${arbitraryPayload2} from forward)`
    )
    console.log(`Received message on target: ${message1}`)
    expect(message1).to.equal(arbitraryPayload1)

    console.log("Checking if forward message was relayed back")
    const message2 = await sourceMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload2}`)
    console.log(`Received message on source: ${message2}`)
    expect(message2).to.equal(arbitraryPayload2)
  })

  it("Executes a multidelivery", async () => {
    const arbitraryPayload1 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload1}`)
    const value1 = await sourceWormholeRelayer.quoteGas(
      sourceChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    const value2 = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee: ${value1.add(value2)}`)

    const furtherInstructions: MockRelayerIntegration.FurtherInstructionsStruct = {
      keepSending: false,
      newMessages: [],
      chains: [],
      gasLimits: [],
    }
    const tx = await sourceMockIntegration.sendMessagesWithFurtherInstructions(
      [arbitraryPayload1],
      furtherInstructions,
      [sourceChain.chainId, targetChain.chainId],
      [value1, value2],
      { value: value1.add(value2), gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if first message was relayed")
    const message1 = await sourceMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload1}`
    )
    console.log(`Received message: ${message1}`)
    expect(message1).to.equal(arbitraryPayload1)

    console.log("Checking if second message was relayed")
    const message2 = await targetMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload1}`)
    console.log(`Received message: ${message2}`)
    expect(message2).to.equal(arbitraryPayload1)
  })
  it("Executes a multiforward", async () => {
    const arbitraryPayload1 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    const arbitraryPayload2 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload1}`)
    const value1 = await sourceWormholeRelayer.quoteGas(
      sourceChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    const value2 = await targetWormholeRelayer.quoteGas(
      sourceChain.chainId,
      500000,
      await targetWormholeRelayer.getDefaultRelayProvider()
    )
    const value3 = await targetWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await targetWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee: ${value1.add(value2).add(value3)}`)

    const furtherInstructions: MockRelayerIntegration.FurtherInstructionsStruct = {
      keepSending: true,
      newMessages: [arbitraryPayload2, "0x00"],
      chains: [sourceChain.chainId, targetChain.chainId],
      gasLimits: [500000, 500000],
    }
    const tx = await sourceMockIntegration.sendMessagesWithFurtherInstructions(
      [arbitraryPayload1],
      furtherInstructions,
      [targetChain.chainId],
      [value1.add(value2).add(value3)],
      { value: value1.add(value2).add(value3), gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if first forward was relayed")
    const message1 = await sourceMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload2}`
    )
    console.log(`Received message: ${message1}`)
    expect(message1).to.equal(arbitraryPayload2)

    console.log("Checking if second forward was relayed")
    const message2 = await targetMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload2}`
    )
    console.log(`Received message: ${message2}`)
    expect(message2).to.equal(arbitraryPayload2)
  })

  it("Executes a redelivery", async () => {
    const arbitraryPayload = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload}`)
    const valueNotEnough = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      10000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    const value = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee (not enough): ${valueNotEnough}`)
    const tx = await sourceMockIntegration.sendMessage(
      arbitraryPayload,
      targetChain.chainId,
      targetMockIntegrationAddress,
      { value: valueNotEnough, gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 2000)
    })

    console.log("Checking if message was relayed (it shouldn't have been!)")
    const message = await targetMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload}`)
    console.log(`Received message: ${message}`)
    expect(message).to.not.equal(arbitraryPayload)

    console.log("Resending the message");
    const request: IWormholeRelayer.ResendByTxStruct = {
      sourceChain: sourceChain.chainId,
      sourceTxHash: tx.hash,
      sourceNonce: 1,
      targetChain: targetChain.chainId, 
      deliveryIndex: 2,
      multisendIndex: 0,
      newMaxTransactionFee: value, 
      newReceiverValue: 0,
      newRelayParameters: sourceWormholeRelayer.getDefaultRelayParams()
    };
    await sourceWormholeRelayer.resend(request, 1, sourceWormholeRelayer.getDefaultRelayProvider(), {value: value, gasLimit: 500000}).then((t)=>t.wait);
    console.log("Message resent");

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if message was relayed")
    const messageNew = await targetMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload}`)
    console.log(`Received message: ${messageNew}`)
    expect(messageNew).to.equal(arbitraryPayload)

  })

  it("Executes a redelivery when delivery succeeds but forward fails", async () => {
    const arbitraryPayload1 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    const arbitraryPayload2 = ethers.utils.hexlify(
      ethers.utils.toUtf8Bytes(generateRandomString(32))
    )
    console.log(`Sent message: ${arbitraryPayload1}`)
    const value = await sourceWormholeRelayer.quoteGas(
      targetChain.chainId,
      500000,
      await sourceWormholeRelayer.getDefaultRelayProvider()
    )
    const extraForwardingValue = await targetWormholeRelayer.quoteGas(
      sourceChain.chainId,
      10000,
      await targetWormholeRelayer.getDefaultRelayProvider()
    )
    console.log(`Quoted gas delivery fee: ${value.add(extraForwardingValue)}`)

    const furtherInstructions: MockRelayerIntegration.FurtherInstructionsStruct = {
      keepSending: true,
      newMessages: [arbitraryPayload2, "0x00"],
      chains: [sourceChain.chainId],
      gasLimits: [500000],
    }
    const tx = await sourceMockIntegration.sendMessagesWithFurtherInstructions(
      [arbitraryPayload1],
      furtherInstructions,
      [targetChain.chainId],
      [value.add(extraForwardingValue)],
      { value: value.add(extraForwardingValue), gasLimit: 500000 }
    )
    console.log("Sent delivery request!")
    const rx = await tx.wait()
    console.log("Message confirmed!")

    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if message was relayed")
    const message1 = await targetMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload1} (expecting ${arbitraryPayload2} from forward)`
    )
    console.log(`Received message on target: ${message1}`)
    expect(message1).to.equal(arbitraryPayload1)

    console.log("Checking if forward message was relayed back (it shouldn't have been!)")
    const message2 = await sourceMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload2}`)
    console.log(`Received message on source: ${message2}`)
    expect(message2).to.not.equal(arbitraryPayload2)

    // RESEND THE MESSAGE SOMEHOW!

    /*console.log("Resending the message");
    const request: IWormholeRelayer.ResendByTxStruct = {
      sourceChain: sourceChain.chainId,
      sourceTxHash: tx.hash,
      sourceNonce: 1,
      targetChain: targetChain.chainId, 
      deliveryIndex: 2,
      multisendIndex: 0,
      newMaxTransactionFee: value, 
      newReceiverValue: 0,
      newRelayParameters: sourceWormholeRelayer.getDefaultRelayParams()
    };
    await sourceWormholeRelayer.resend(request, 1, sourceWormholeRelayer.getDefaultRelayProvider(), {value: value, gasLimit: 500000}).then((t)=>t.wait);
    console.log("Message resent");*/

    /*
    await new Promise((resolve) => {
      setTimeout(() => {
        resolve(0)
      }, 4000)
    })

    console.log("Checking if message was relayed")
    const message3 = await targetMockIntegration.getMessage()
    console.log(
      `Sent message: ${arbitraryPayload1} (expecting ${arbitraryPayload2} from forward)`
    )
    console.log(`Received message on target: ${message3}`)
    expect(message3).to.equal(arbitraryPayload1)

    console.log("Checking if forward message was relayed back (it shouldn't have been!)")
    const message4 = await sourceMockIntegration.getMessage()
    console.log(`Sent message: ${arbitraryPayload2}`)
    console.log(`Received message on source: ${message4}`)
    expect(message4).to.equal(arbitraryPayload2)
    */

  })
})
