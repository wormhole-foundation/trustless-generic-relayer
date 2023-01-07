import {
  getCoreRelayer,
  getCoreRelayerAddress,
  getMockIntegration,
  getMockIntegrationAddress,
  getRelayProviderAddress,
  init,
  loadChains,
} from "../helpers/env"

init()
const chains = loadChains()

async function run() {
  const sourceChain = chains[0]
  const targetChain = chains[1]

  const sourceRelayer = getCoreRelayer(sourceChain)

  // todo: remove
  const registeredChain = await sourceRelayer.registeredCoreRelayerContract(
    sourceChain.chainId
  )
  console.log("The source chain should be registered to itself")
  console.log(registeredChain)
  console.log(getCoreRelayerAddress(sourceChain))
  console.log("")

  const defaultRelayerProvider = await sourceRelayer.getDefaultRelayProvider()
  console.log("Default relay provider should be this chains relayProvider ")
  console.log(defaultRelayerProvider)
  console.log(getRelayProviderAddress(sourceChain))
  console.log("")

  const relayQuote = await (
    await sourceRelayer.quoteGasDeliveryFee(
      targetChain.chainId,
      2000000,
      sourceRelayer.getDefaultRelayProvider()
    )
  ).add(10000000000)
  console.log("relay quote: " + relayQuote)

  const mockIntegration = getMockIntegration(sourceChain)
  const targetAddress = getMockIntegrationAddress(targetChain)

  const tx = await mockIntegration.sendMessageWithForwardedResponse(
    Buffer.from("Hello World 3"),
    targetChain.chainId,
    targetAddress,
    targetAddress,
    {
      gasLimit: 1000000,
      value: relayQuote,
    }
  )
  const rx = await tx.wait()
  console.log(rx, "da receipt")
}

run().then(() => console.log("Done!"))

console.log("Start!")
