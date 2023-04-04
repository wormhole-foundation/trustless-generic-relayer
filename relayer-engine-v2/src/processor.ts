import * as wh from "@certusone/wormhole-sdk"
import { Next } from "wormhole-relayer"
import {
  IDelivery,
  MessageInfoType,
  RelayerPayloadId,
  CoreRelayer__factory,
  parseWormholeRelayerPayloadType,
  parseWormholeRelayerSend,
} from "../pkgs/sdk/src"
import { EVMChainId } from "@certusone/wormhole-sdk"
import { GRContext } from "./app"

export async function processGenericRelayerVaa(ctx: GRContext, next: Next) {
  const payloadId = parseWormholeRelayerPayloadType(ctx.vaa!.payload)
  // route payload types
  if (payloadId != RelayerPayloadId.Delivery) {
    ctx.logger.error(`Expected GR Delivery payload type, found ${payloadId}`)
    throw new Error("Expected GR Delivery payload type")
  }
  await processDelivery(ctx)
  await next()
}

async function processDelivery(ctx: GRContext) {
  const chainId = ctx.vaa!.emitterChain as wh.EVMChainId
  const payload = parseWormholeRelayerSend(ctx.vaa!.payload)

  if (
    payload.messages.findIndex((m) => m.payloadType !== MessageInfoType.EMITTER_SEQUENCE)
  ) {
    throw new Error(`Only supports EmitterSequence MessageInfoType`)
  }
  const fetchedVaas = await ctx.fetchVaas({
    ids: payload.messages.map((m) => ({
      emitterAddress: m.emitterAddress!,
      emitterChain: chainId,
      sequence: m.sequence!.toBigInt(),
    })),
    txHash: ctx.sourceTxHash,
  })
  for (let i = 0; i < payload.instructions.length; i++) {
    const ix = payload.instructions[i]
    // const chainId = assertEvmChainId(ix.targetChain)
    const chainId = ix.targetChain as EVMChainId
    const budget = ix.receiverValueTarget.add(ix.maximumRefundTarget).add(100)

    await ctx.wallets.onEVM(chainId, async ({ wallet }) => {
      const coreRelayer = CoreRelayer__factory.connect(
        ctx.wormholeRelayers[chainId],
        wallet
      )

      const input: IDelivery.TargetDeliveryParametersStruct = {
        encodedVMs: fetchedVaas.map((v) => v.bytes),
        encodedDeliveryVAA: ctx.vaaBytes!,
        multisendIndex: i,
        relayerRefundAddress: wallet.address,
      }

      await coreRelayer
        // @ts-ignore
        .deliver(input, { value: budget, gasLimit: 3000000 })
        .then((x) => x.wait())

      ctx.logger.info(
        `Relayed instruction ${i + 1} of ${
          payload.instructions.length
        } to chain ${chainId}`
      )
    })
  }
}
