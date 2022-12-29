import { ChainId, RefundEscrow, tryNativeToHexString } from "@certusone/wormhole-sdk"
import { CoreRelayer__factory, MockRelayerIntegration__factory } from "../../sdk/src"
import { CoreRelayerStructs } from "../../sdk/src/ethers-contracts/CoreRelayer"
import { ethers } from "ethers"
import fs from "fs"

const CHAIN_INFOS = [
  {
    id: 1337,
    wormholeId: 2,
    rpc: "http://localhost:8545",
    contractAddress: "foo",
    relayerAddress: "foo",
    pk: "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d",
  },
  {
    id: 1397,
    wormholeId: 4,
    rpc: "http://localhost:8546",
    contractAddress: "foo",
    relayerAddress: "foo",
    pk: "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d",
  },
]

async function run() {
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
    info.contractAddress = createTransaction.contractAddress
    info.relayerAddress = createTransaction2.contractAddress
  })

  await Promise.all(promises)
  const sourceChain = CHAIN_INFOS[0]
  const targetChain = CHAIN_INFOS[0]

  const sourceProvider = new ethers.providers.StaticJsonRpcProvider(sourceChain.rpc)
  const targetProvider = new ethers.providers.StaticJsonRpcProvider(targetChain.rpc)

  // signers
  const sourceWallet = new ethers.Wallet(sourceChain.pk, sourceProvider)
  const targetWallet = new ethers.Wallet(targetChain.pk, targetProvider)

  const mockIntegration = MockRelayerIntegration__factory.connect(
    sourceChain.contractAddress,
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

  await mockIntegration.sendMessage(
    Buffer.from("Hello World"),
    targetChain.wormholeId,
    targetChain.contractAddress,
    {
      gasLimit: 1000000,
      value: relayQuote,
    }
  )
}

run()

console.log("Done!")
