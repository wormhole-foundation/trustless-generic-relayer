import { readFileSync, writeFileSync } from "fs"
import {
  getCoreRelayer,
  getMockIntegration,
  getRelayProvider,
  init,
  loadChains,
} from "../helpers/env"

const env = init({ lastRunOverride: true })
const chains = loadChains()

interface Address {
  chainId: number
  address: string
}
interface ContractsJson {
  relayProviders: Address[]
  coreRelayers: Address[]
  mockIntegrations: Address[]
}

async function main() {
  const path = `./ts-scripts/config/${env}/contracts.json`
  const blob = readFileSync(path)
  const contracts: ContractsJson = JSON.parse(String(blob))
  console.log("Old:")
  console.log(`${String(blob)}`)
  for (const chain of chains) {
    update(contracts.relayProviders, {
      chainId: chain.chainId,
      address: getRelayProvider(chain).address,
    })
    update(contracts.coreRelayers, {
      chainId: chain.chainId,
      address: getCoreRelayer(chain).address,
    })
    update(contracts.mockIntegrations, {
      chainId: chain.chainId,
      address: getMockIntegration(chain).address,
    })
  }
  const newStr = JSON.stringify(contracts, undefined, 2)
  console.log("New:")
  console.log(`${String(newStr)}`)
  writeFileSync(path, newStr)
}

function update(arr: Address[], newAddress: Address) {
  const idx = arr.findIndex((a) => a.chainId === newAddress.chainId)
  if (idx === -1) {
    arr.push(newAddress)
  } else {
    arr[idx] = newAddress
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
