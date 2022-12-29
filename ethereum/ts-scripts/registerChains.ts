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
    contractAddress: "celo",
  },
  {
    id: 43113,
    wormholeId: 6,
    rpc: "https://api.avax-test.network/ext/bc/C/rpc",
    contractAddress: "fuji",
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
      return x.contractName == "RelayProviderProxy" && index > 4
    })
    info.contractAddress = createTransaction.contractAddress
  })
  await Promise.all(promises)

  const promises2 = CHAIN_INFOS.map(async (info) => {
    const provider = new ethers.providers.StaticJsonRpcProvider(info.rpc)

    // signers
    const wallet = new ethers.Wallet(pk, provider)

    const coreRelayer = CoreRelayer__factory.connect(info.contractAddress, wallet)

    for (const info2 of CHAIN_INFOS) {
      if (info.wormholeId != info2.wormholeId) {
        await coreRelayer.registerCoreRelayerContract(
          info2.wormholeId,
          "0x" + tryNativeToHexString(info.contractAddress, "ethereum")
        )
      }
    }
  })

  await Promise.all(promises2)
}

run().then(() => console.log("Done!"))

console.log("Start!")
