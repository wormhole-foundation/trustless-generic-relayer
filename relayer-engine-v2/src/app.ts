import * as fs from "fs/promises"
import yargs from "yargs"
import * as Koa from "koa"
import {
  Environment,
  Next,
  StandardRelayerApp,
  StandardRelayerContext,
} from "wormhole-relayer"
import { EVMChainId } from "@certusone/wormhole-sdk"
import { rootLogger } from "./log"
import { processGenericRelayerVaa } from "./processor"
import { Logger } from "winston"
import * as deepCopy from "clone"

export type GRContext = StandardRelayerContext & {
  relayProviders: Record<EVMChainId, string>
  wormholeRelayer: Record<EVMChainId, string>
}

type Opts = {
  flag: Flag
}

enum Flag {
  Tilt = "tilt",
  Testnet = "testnet",
  K8sTestnet = "k8s-testnet",
  Mainnet = "mainnet",
}

type ContractConfigEntry = { chainId: EVMChainId; address: "string" }
type ContractsJson = {
  relayProviders: ContractConfigEntry[]
  coreRelayers: ContractConfigEntry[]
  mockIntegrations: ContractConfigEntry[]
}

async function main() {
  let opts = yargs(process.argv.slice(2)).argv as unknown as Opts
  const contracts = await loadContractsJson()

  const app = new StandardRelayerApp<GRContext>(flagToEnvironment(opts.flag), {
    name: "GenericRelayer",
    privateKeys: privateKeys(contracts),
    // redis: {},
    // redisCluster: {},
    // redisClusterEndpoints: [],
  })

  // Build contract address maps
  const relayProviders = {} as Record<EVMChainId, string>
  const wormholeRelayers = {} as Record<EVMChainId, string>
  contracts.relayProviders.forEach(
    ({ chainId, address }: ContractConfigEntry) => (relayProviders[chainId] = address)
  )
  contracts.coreRelayers.forEach(
    ({ chainId, address }: ContractConfigEntry) => (wormholeRelayers[chainId] = address)
  )

  // Set up middleware
  app.use(async (ctx: GRContext, next: Next) => {
    ctx.relayProviders = deepCopy(relayProviders)
    ctx.wormholeRelayer = deepCopy(wormholeRelayers)
    next()
  })

  // Set up routes
  app.multiple(deepCopy(wormholeRelayers), processGenericRelayerVaa)

  app.listen()
  runUI(app, opts, rootLogger)
}

function runUI(relayer: any, { port }: any, logger: Logger) {
  const app = new Koa()

  app.use(relayer.storageKoaUI("/ui"))

  port = Number(port) || 3000
  app.listen(port, () => {
    logger.info(`Running on ${port}...`)
    logger.info(`For the UI, open http://localhost:${port}/ui`)
    logger.info("Make sure Redis is running on port 6379 by default")
  })
}

function flagToEnvironment(flag: Flag): Environment {
  switch (flag) {
    case Flag.K8sTestnet:
      return Environment.TESTNET
    case Flag.Testnet:
      return Environment.TESTNET
    case Flag.Mainnet:
      return Environment.MAINNET
    case Flag.Tilt:
      return Environment.DEVNET
  }
}

async function loadContractsJson(): Promise<ContractsJson> {
  return JSON.parse(
    await fs.readFile(`../ethereum/ts-scripts/config/testnet/contracts.json`, {
      encoding: "utf-8",
    })
  ) as ContractsJson
}

function privateKeys(contracts: ContractsJson) {
  const chainIds = new Set(contracts.coreRelayers.map((r) => r.chainId))
  const privateKey = process.env["PRIVATE_KEY"]! as string
  const privateKeys = {} as Record<EVMChainId, [string]>
  for (const chainId of chainIds) {
    privateKeys[chainId] = [privateKey]
  }
  return privateKeys
}

main().catch((e) => {
  console.error("Encountered unrecoverable error:")
  console.error(e)
  process.exit(1)
})
