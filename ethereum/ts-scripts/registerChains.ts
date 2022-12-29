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
    pk: "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d",
  },
  {
    id: 1397,
    wormholeId: 4,
    rpc: "http://localhost:8546",
    contractAddress: "foo",
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
      return x.contractName == "RelayProviderProxy" && index > 4
    })
    info.contractAddress = createTransaction.contractAddress
  })
  await Promise.all(promises)

  const promises2 = CHAIN_INFOS.map(async (info) => {
    const provider = new ethers.providers.StaticJsonRpcProvider(info.rpc)

    // signers
    const wallet = new ethers.Wallet(info.pk, provider)

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

run()

console.log("Done!")
