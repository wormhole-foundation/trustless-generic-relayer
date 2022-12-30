import { ChainId, RefundEscrow, tryNativeToHexString } from "@certusone/wormhole-sdk"
import { CoreRelayer__factory, MockRelayerIntegration__factory } from "../../sdk/src"
import { CoreRelayerStructs } from "../../sdk/src/ethers-contracts/CoreRelayer"
import { ethers } from "ethers"
import fs from "fs"

// tilt
// const CHAIN_INFOS = [
//   {
//     id: 1337,
//     wormholeId: 2,
//     rpc: "http://localhost:8545",
//     contractAddress: "foo",
//   },
//   {
//     id: 1397,
//     wormholeId: 4,
//     rpc: "http://localhost:8546",
//     contractAddress: "foo",
//   },
// ]

const CHAIN_INFOS = [
  {
    id: 44787,
    wormholeId: 14,
    rpc: "https://alfajores-forno.celo-testnet.org",
    mockIntegrationAddress: "celo",
    relayerAddress: "",
  },
  {
    id: 43113,
    wormholeId: 6,
    rpc: "https://api.avax-test.network/ext/bc/C/rpc",
    mockIntegrationAddress: "fuji",
    relayerAddress: "",
  },
]

async function run() {
  if (!process.env["PRIVATE_KEY"]) {
    console.log("Missing private key env var, falling back to tilt private key")
  }
  const pk =
    process.env["PRIVATE_KEY"] ||
    "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"

  //first collect all contract addresses
  const promises = CHAIN_INFOS.map(async (info) => {
    const file = await fs.readFileSync(
      `./broadcast/deploy_contracts.sol/${info.id}/run-latest.json`
    )
    const content = JSON.parse(file.toString())
    const createTransaction = content.transactions.find((x: any, index: any) => {
      return x.contractName == "MockRelayerIntegration"
    })
    const createTransaction2 = content.transactions.find((x: any, index: any) => {
      return x.contractName == "RelayProviderProxy" && index > 4
    })
    info.mockIntegrationAddress = createTransaction.contractAddress
    info.relayerAddress = createTransaction2.contractAddress
  })

  await Promise.all(promises)
  const sourceChain = CHAIN_INFOS[1]
  const targetChain = CHAIN_INFOS[1]

  const sourceProvider = new ethers.providers.StaticJsonRpcProvider(sourceChain.rpc)
  const targetProvider = new ethers.providers.StaticJsonRpcProvider(targetChain.rpc)

  // signers
  const sourceWallet = new ethers.Wallet(pk, sourceProvider)
  const targetWallet = new ethers.Wallet(pk, targetProvider)

  const mockIntegration = MockRelayerIntegration__factory.connect(
    sourceChain.mockIntegrationAddress,
    sourceWallet
  )

  const coreRelayer = CoreRelayer__factory.connect(
    sourceChain.relayerAddress,
    sourceWallet
  )

  const relayQuote = await (
    await coreRelayer.quoteGasDeliveryFee(
      targetChain.wormholeId,
      1000000,
      coreRelayer.getDefaultRelayProvider()
    )
  ).add(10000000000)

  const tx = await mockIntegration.sendMessage(
    Buffer.from("Hello World"),
    targetChain.wormholeId,
    targetChain.mockIntegrationAddress,
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
