import { ChainInfo, init, loadChains } from "../helpers/env"
import { sendMessage, sleep } from "./messageUtils"

init()
const chains = loadChains()

async function run() {
  const chainIntervalIdx = process.argv.findIndex((arg) => arg === "--chainInterval")
  const salvoIntervalIdx = process.argv.findIndex((arg) => arg === "--salvoInterval")
  const chainInterval =
    chainIntervalIdx !== -1 ? Number(process.argv[chainIntervalIdx + 1]) : 5_000
  const salvoInterval =
    salvoIntervalIdx !== -1 ? Number(process.argv[salvoIntervalIdx + 1]) : 60_000

  console.log(`chainInterval: ${chainInterval}`)
  console.log(`salvoInterval: ${salvoInterval}`)

  if (process.argv.find((arg) => arg === "--per-chain")) {
    await perChain(chainInterval, salvoInterval)
  } else {
    await matrix(chainInterval, salvoInterval)
  }
}

async function perChain(chainInterval: number, salvoInterval: number) {
  console.log(`Sending test messages to and from each chain...`)
  for (let salvo = 0; true; salvo++) {
    console.log("")
    console.log(`Sending salvo ${salvo}`)
    for (let i = 0; i < chains.length; ++i) {
      const j = i === 0 ? chains.length - 1 : 0
      try {
        await sendMessage(chains[i], chains[j], false, true)
      } catch (e) {
        console.error(e)
      }
      await sleep(chainInterval)
    }
    await sleep(salvoInterval)
  }
}

async function matrix(chainInterval: number, salvoInterval: number) {
  console.log(`Sending test messages to and from every combination of chains...`)
  for (let salvo = 0; true; salvo++) {
    console.log("")
    console.log(`Sending salvo ${salvo}`)

    for (let i = 0; i < chains.length; ++i) {
      for (let j = 0; i < chains.length; ++i) {
        try {
          await sendMessage(chains[i], chains[j], false, true)
        } catch (e) {
          console.error(e)
        }
        await sleep(chainInterval)
      }
    }
    await sleep(salvoInterval)
  }
}

console.log("Start!")
run().then(() => console.log("Done!"))
