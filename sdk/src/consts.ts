import { ChainId, Network } from "@certusone/wormhole-sdk"
import { ethers } from "ethers"
import {
  CoreRelayer,
  CoreRelayerGetters__factory,
  CoreRelayer__factory,
} from "./ethers-contracts"

const TESTNET = [
  { chainId: 4, coreRelayerAddress: "0xaC9EF19ab4F9a3a265809df0C4eB1E821f43391A" },
  { chainId: 5, coreRelayerAddress: "0xEf06AE191B42ac59883815c4cFaCC9164f1d50eE" },
  { chainId: 6, coreRelayerAddress: "0x9Dfd308e2450b26290d926Beea2Bb4F0B8553729" },
  { chainId: 14, coreRelayerAddress: "0x49181C4fE76E0F28DB04084935d81DaBb26ac26d" },
  { chainId: 16, coreRelayerAddress: "0x414De856795ecA8F0207D83d69C372Df799Ee377" },
]

const MAINNET: any[] = []

type ENV = "mainnet" | "testnet"

export function getCoreRelayerAddressNative(chainId: ChainId, env: Network): string {
  if (env == "TESTNET") {
    const address = TESTNET.find((x) => x.chainId == chainId)?.coreRelayerAddress
    if (!address) {
      throw Error("Invalid chain ID")
    }
    return address
  } else if (env == "MAINNET") {
    const address = MAINNET.find((x) => x.chainId == chainId)?.coreRelayerAddress
    if (!address) {
      throw Error("Invalid chain ID")
    }
    return address
  } else {
    throw Error("Invalid environment")
  }
}

export function getCoreRelayer(
  chainId: ChainId,
  env: Network,
  provider: ethers.providers.Provider
): CoreRelayer {
  const thisChainsRelayer = getCoreRelayerAddressNative(chainId, env)
  const contract = CoreRelayer__factory.connect(thisChainsRelayer, provider)
  return contract
}
