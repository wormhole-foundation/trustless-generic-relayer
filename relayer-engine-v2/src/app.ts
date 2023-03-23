import * as fs from "fs/promises"
import yargs from "yargs"
import * as Koa from "koa"
import {
  Environment,
  Next,
  StandardRelayerApp,
} from "wormhole-relayer"

import {
  EVMChainId,
} from "@certusone/wormhole-sdk"
import { rootLogger } from "./log"
import { GRContext, processGenericRelayerVaa } from "./processor"
import { Logger } from "winston"
import { sourceTx } from "wormhole-relayer/lib/middleware/source-tx.middleware"

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

  // Config
  const contracts = JSON.parse(
    await fs.readFile(`../ethereum/ts-scripts/config/testnet/contracts.json`, {
      encoding: "utf-8",
    })
  ) as ContractsJson
  const chainIds = new Set(contracts.coreRelayers.map((r) => r.chainId))

  const privateKey = process.env["PRIVATE_KEY"]! as string
  const privateKeys = {} as Record<EVMChainId, [string]>
  for (const chainId of chainIds) {
    privateKeys[chainId] = [privateKey]
  }

  const app = new StandardRelayerApp<GRContext>(flagToEnvironment(opts.flag), {
    name: "GenericRelayer",
    privateKeys,
    // redis: {},
    // redisCluster: {},
    // redisClusterEndpoints: [],
    fetchSourceTxhash: true,
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
    ctx.relayProviders = relayProviders
    ctx.wormholeRelayer = wormholeRelayers
    next()
  })
  app.use(sourceTx())

  // Set up routes
  app.multiple(wormholeRelayers, processGenericRelayerVaa)

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

main().catch((e) => {
  console.error("Encountered unrecoverable error:")
  console.error(e)
  process.exit(1)
})

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
