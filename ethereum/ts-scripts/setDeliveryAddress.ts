import { RelayProvider__factory } from "../../sdk/src"
import { ethers } from "ethers"
import fs from "fs"
import { tryNativeToHexString } from "@certusone/wormhole-sdk"

const CHAIN_INFOS = [
  {
    id: 44787,
    wormholeId: 14,
    rpc: "https://alfajores-forno.celo-testnet.org",
    mockIntegrationAddress: "celo",
    relayerAddress: "",
    relayProvider: "",
  },
  {
    id: 43113,
    wormholeId: 6,
    rpc: "https://api.avax-test.network/ext/bc/C/rpc",
    mockIntegrationAddress: "fuji",
    relayerAddress: "",
    relayProvider: "",
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
  await Promise.all(
    CHAIN_INFOS.map(async (info) => {
      const file = await fs.readFileSync(
        `./broadcast/deploy_contracts.sol/${info.id}/run-latest.json`
      )
      const content = JSON.parse(file.toString())
      const createTransaction = content.transactions.find((x: any, index: any) => {
        return x.contractName == "MockRelayerIntegration"
      })
      const relayProviderTx = content.transactions.find((x: any, index: any) => {
        return x.contractName == "RelayProviderProxy" && index <= 4
      })
      const createTransaction2 = content.transactions.find((x: any, index: any) => {
        return x.contractName == "RelayProviderProxy" && index > 4
      })
      info.mockIntegrationAddress = createTransaction.contractAddress
      info.relayerAddress = createTransaction2.contractAddress
      info.relayProvider = relayProviderTx.contractAddress
    })
  )

  for (const info of CHAIN_INFOS) {
    const rpc = new ethers.providers.StaticJsonRpcProvider(info.rpc)
    const wallet = new ethers.Wallet(pk, rpc)
    const relayerProvider = RelayProvider__factory.connect(info.relayProvider, wallet)

    for (const { wormholeId } of CHAIN_INFOS) {
      await relayerProvider
        .updateDeliveryAddress(
          wormholeId,
          "0x" + tryNativeToHexString(wallet.address, "ethereum")
        )
        .then((tx) => tx.wait())
      await relayerProvider
        .updateRewardAddress(wallet.address)
        .then((tx) => tx.wait())

      console.log(
        `Delivery address for chain ${wormholeId} on chain ${
          info.wormholeId
        }: ${await relayerProvider.getDeliveryAddress(wormholeId)}`
      )
    }
  }
}

run().then(() => console.log("Done!"))

console.log("Start!")
