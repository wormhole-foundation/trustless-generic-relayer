import { redeemOnXpla, SignedVaa } from "@certusone/wormhole-sdk"
import {
  StagingAreaKeyLock,
  getScopedLogger,
  sleep,
  second,
} from "@wormhole-foundation/relayer-engine"
import { ScopedLogger } from "@wormhole-foundation/relayer-engine/relayer-engine/lib/helpers/logHelper"
import { logger } from "ethers"
import { retryAsyncUntilDefined } from "ts-retry/lib/cjs/retry"
import { Logger } from "winston"
import * as wh from "@certusone/wormhole-sdk"
import * as grpcWebNodeHttpTransport from "@improbable-eng/grpc-web-node-http-transport"

/*
 * DB types
 */

export const PENDING = "pending"
export interface Pending {
  startTime: string
  numTimesRetried: number
  hash: string
  nextRetryTime: string
}

export interface SyntheticBatchEntry {
  chainId: number
  deliveryVaaIdx: number
  vaas: { emitter: string; sequence: string; bytes: string }[]
  allFetched: boolean
  // only present for Redeliveries
  redeliveryVaa?: string
}

export async function fetchVaaWorker(
  eventSource: (event: SignedVaa) => Promise<void>,
  db: StagingAreaKeyLock,
  parentLogger: ScopedLogger,
  engineConfig: { wormholeRpc: string }
): Promise<void> {
  const logger = getScopedLogger(["fetchWorker"], parentLogger)
  logger.info(`Started fetchVaaWorker`)
  while (true) {
    await sleep(3_000) // todo: make configurable

    // track which delivery vaa hashes have all vaas ready this iteration
    let newlyResolved = new Map<string, SyntheticBatchEntry>()
    await db.withKey([PENDING], async (kv: { [PENDING]?: Pending[] }, tx) => {
      // if objects have not been created, initialize
      if (!kv.pending) {
        kv.pending = []
      }
      logger.debug(`Pending: ${JSON.stringify(kv.pending, undefined, 4)}`)

      // filter to the pending items that are due to be retried
      const entriesToFetch = kv.pending.filter(
        (delivery) => new Date(JSON.parse(delivery.nextRetryTime)).getTime() < Date.now()
      )
      if (entriesToFetch.length === 0) {
        return { newKV: kv, val: undefined }
      }

      logger.info(`Attempting to fetch ${entriesToFetch.length} entries`)
      await db.withKey(
        // get `SyntheticBatchEntry`s for each hash
        entriesToFetch.map((d) => d.hash),
        async (kv: Record<string, SyntheticBatchEntry>) => {
          const promises = Object.entries(kv).map(async ([hash, entry]) => {
            if (entry.allFetched) {
              // nothing to do
              logger.warn("Entry in pending but nothing to fetch " + hash)
              return [hash, entry]
            }
            const newEntry: SyntheticBatchEntry = await fetchEntry(
              hash,
              entry,
              logger,
              engineConfig
            )
            if (newEntry.allFetched) {
              newlyResolved.set(hash, newEntry)
            }
            return [hash, newEntry]
          })

          const newKV = Object.fromEntries(await Promise.all(promises))
          return { newKV, val: undefined }
        },
        tx
      )

      kv[PENDING] = kv[PENDING].filter((p) => !newlyResolved.has(p.hash)).map((x) => ({
        ...x,
        numTimesRetried: x.numTimesRetried + 1,
        nextRetryTime: new Date(Date.now() + second * x.numTimesRetried).toString(),
      }))
      return { newKV: kv, val: undefined }
    })
    // kick off an engine listener event for each resolved delivery vaa
    for (const entry of newlyResolved.values()) {
      logger.info("Kicking off engine listener event for resolved entry")
      if (entry.redeliveryVaa) {
        eventSource(Buffer.from(entry.redeliveryVaa, "base64"))
      } else {
        eventSource(Buffer.from(entry.vaas[entry.deliveryVaaIdx].bytes, "base64"))
      }
    }
  }
}

export async function fetchEntry(
  hash: string,
  value: SyntheticBatchEntry,
  logger: Logger,
  engineConfig: { wormholeRpc: string }
): Promise<SyntheticBatchEntry> {
  logger.info("Fetching SyntheticBatchEntry...", { hash })
  // track if there are missing vaas after trying to fetch
  let hasMissingVaas = false

  // for each entry, attempt to fetch vaas from wormhole rpc
  const vaas = await Promise.all(
    value.vaas.map(async ({ emitter, sequence, bytes }, idx) => {
      // skip if vaa has already been fetched
      if (bytes.length !== 0) {
        return { emitter, sequence, bytes }
      }
      try {
        // try to fetch vaa from rpc
        const resp = await wh.getSignedVAA(
          engineConfig.wormholeRpc,
          value.chainId as wh.EVMChainId,
          emitter,
          sequence,
          { transport: grpcWebNodeHttpTransport.NodeHttpTransport() }
        )
        logger.info(`Fetched vaa ${idx} for delivery ${hash}`)
        return {
          emitter,
          sequence,
          // base64 encode
          bytes: Buffer.from(resp.vaaBytes).toString("base64"),
        }
      } catch (e) {
        hasMissingVaas = true
        logger.debug(e)
        return { emitter, sequence, bytes: "" }
      }
    })
  )
  // if all vaas have been fetched, mark this hash as resolved
  return { ...value, vaas, allFetched: !hasMissingVaas }
}

export async function addEntryToPendingQueue(
  hash: string,
  newEntry: SyntheticBatchEntry,
  db: StagingAreaKeyLock
) {
  await retryAsyncUntilDefined(async () => {
    try {
      return db.withKey(
        [hash, PENDING],
        // note _hash is actually the value of the variable `hash`, but ts will not
        // let this be expressed
        async (kv: { [PENDING]: Pending[]; _hash: SyntheticBatchEntry }) => {
          // @ts-ignore
          let oldEntry: SyntheticBatchEntry | null = kv[hash]
          if (oldEntry?.allFetched) {
            return { newKV: kv, val: true }
          }
          if (kv[PENDING].findIndex((e) => e.hash === hash) !== -1) {
            return { newKV: kv, val: true }
          }

          const now = Date.now().toString()
          kv.pending.push({
            nextRetryTime: now,
            numTimesRetried: 0,
            startTime: now,
            hash,
          })
          // @ts-ignore
          kv[hash] = newEntry
          return { newKV: kv, val: true }
        }
      )
    } catch (e) {
      logger.warn(e)
    }
  })
}
