import { expect } from "chai"
import { ethers } from "ethers"
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk"
import { ChainInfo, RELAYER_DEPLOYER_PRIVATE_KEY } from "./helpers/consts"
import { generateRandomString } from "./helpers/utils"
import {
  CoreRelayer__factory,
  IWormhole__factory,
  MockRelayerIntegration__factory,
} from "../../sdk/src"
import {
  init,
  loadChains,
  loadCoreRelayers,
  loadMockIntegrations,
} from "../ts-scripts/helpers/env"
import { MockRelayerIntegration } from "../../sdk/src"
const ETHEREUM_ROOT = `${__dirname}/..`

init()
const chains = loadChains()
const coreRelayers = loadCoreRelayers()
const mockIntegrations = loadMockIntegrations()

describe("Core Relayer Integration Test - Two Chains", () => {
  // signers

  const sourceChain = chains.find((c) => c.chainId == 2) as ChainInfo
  const targetChain = chains.find((c) => c.chainId == 4) as ChainInfo

  const providerSource = new ethers.providers.StaticJsonRpcProvider(sourceChain.rpc)
  const providerTarget = new ethers.providers.StaticJsonRpcProvider(targetChain.rpc)

  const walletSource = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerSource)
  const walletTarget = new ethers.Wallet(RELAYER_DEPLOYER_PRIVATE_KEY, providerTarget)

  const sourceCoreRelayerAddress = coreRelayers.find(
    (p) => p.chainId == sourceChain.chainId
  )?.address as string
  const sourceMockIntegrationAddress = mockIntegrations.find(
    (p) => p.chainId == sourceChain.chainId
  )?.address as string
  const targetCoreRelayerAddress = coreRelayers.find(
    (p) => p.chainId == targetChain.chainId
  )?.address as string
  const targetMockIntegrationAddress = mockIntegrations.find(
    (p) => p.chainId == targetChain.chainId
  )?.address as string

  const sourceCoreRelayer = CoreRelayer__factory.connect(
    sourceCoreRelayerAddress,
    walletSource
  )
  const sourceMockIntegration = MockRelayerIntegration__factory.connect(
    sourceMockIntegrationAddress,
    walletSource
  )
  const targetCoreRelayer = CoreRelayer__factory.connect(
    targetCoreRelayerAddress,
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
    const value = await sourceCoreRelayer.quoteGasDeliveryFee(
      targetChain.chainId,
      500000,
      await sourceCoreRelayer.getDefaultRelayProvider()
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
    const value = await sourceCoreRelayer.quoteGasDeliveryFee(
      targetChain.chainId,
      500000,
      await sourceCoreRelayer.getDefaultRelayProvider()
    )
    const extraForwardingValue = await targetCoreRelayer.quoteGasDeliveryFee(
      sourceChain.chainId,
      500000,
      await targetCoreRelayer.getDefaultRelayProvider()
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
    const value1 = await sourceCoreRelayer.quoteGasDeliveryFee(
      sourceChain.chainId,
      500000,
      await sourceCoreRelayer.getDefaultRelayProvider()
    )
    const value2 = await sourceCoreRelayer.quoteGasDeliveryFee(
      targetChain.chainId,
      500000,
      await sourceCoreRelayer.getDefaultRelayProvider()
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
})
