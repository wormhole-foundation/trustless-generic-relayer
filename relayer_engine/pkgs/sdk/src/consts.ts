import { ChainId, Network, ChainName } from "@certusone/wormhole-sdk"
import { ethers } from "ethers"
import { CoreRelayer__factory } from "../src/ethers-contracts/factories/CoreRelayer__factory"
import { CoreRelayer } from "../src"

const TESTNET = [
  { chainId: 4, coreRelayerAddress: "0xaC9EF19ab4F9a3a265809df0C4eB1E821f43391A" },
  { chainId: 5, coreRelayerAddress: "0xEf06AE191B42ac59883815c4cFaCC9164f1d50eE" },
  { chainId: 6, coreRelayerAddress: "0x9Dfd308e2450b26290d926Beea2Bb4F0B8553729" },
  { chainId: 14, coreRelayerAddress: "0x49181C4fE76E0F28DB04084935d81DaBb26ac26d" },
  { chainId: 16, coreRelayerAddress: "0x414De856795ecA8F0207D83d69C372Df799Ee377" },
]

const DEVNET = [
  { chainId: 2, coreRelayerAddress: "0x42D4BA5e542d9FeD87EA657f0295F1968A61c00A" },
  { chainId: 4, coreRelayerAddress: "0xFF5181e2210AB92a5c9db93729Bc47332555B9E9" },
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
  } else if (env == "DEVNET") {
    const address = DEVNET.find((x) => x.chainId == chainId)?.coreRelayerAddress
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

export const RPCS_BY_CHAIN: { [key in ChainName]?: string } = {
  ethereum: process.env.ETH_RPC,
  bsc: process.env.BSC_RPC || 'https://bsc-dataseed2.defibit.io',
  polygon: 'https://rpc.ankr.com/polygon',
  avalanche: 'https://rpc.ankr.com/avalanche',
  oasis: 'https://emerald.oasis.dev',
  algorand: 'https://mainnet-api.algonode.cloud',
  fantom: 'https://rpc.ankr.com/fantom',
  karura: 'https://eth-rpc-karura.aca-api.network',
  acala: 'https://eth-rpc-acala.aca-api.network',
  klaytn: 'https://klaytn-mainnet-rpc.allthatnode.com:8551',
  celo: 'https://forno.celo.org',
  moonbeam: 'https://rpc.ankr.com/moonbeam',
  arbitrum: 'https://rpc.ankr.com/arbitrum',
  optimism: 'https://rpc.ankr.com/optimism',
  aptos: 'https://fullnode.mainnet.aptoslabs.com/',
  near: 'https://rpc.mainnet.near.org',
  xpla: 'https://dimension-lcd.xpla.dev',
  terra2: 'https://phoenix-lcd.terra.dev',
  terra: 'https://columbus-fcd.terra.dev',
  injective: 'https://k8s.mainnet.lcd.injective.network',
  solana: process.env.SOLANA_RPC ?? 'https://api.mainnet-beta.solana.com',
};

export const GUARDIAN_RPC_HOSTS = [
  'https://wormhole-v2-mainnet-api.certus.one',
  'https://wormhole.inotel.ro',
  'https://wormhole-v2-mainnet-api.mcf.rocks',
  'https://wormhole-v2-mainnet-api.chainlayer.network',
  'https://wormhole-v2-mainnet-api.staking.fund',
];
