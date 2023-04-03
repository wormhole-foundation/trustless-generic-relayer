import * as wh from "@certusone/wormhole-sdk"
import { Next } from "wormhole-relayer"
import {
  IDelivery,
  MessageInfoType,
  parseDeliveryInstructionsContainer,
  parsePayloadType,
  parseRedeliveryByTxHashInstruction,
  RelayerPayloadId,
  RelayProvider__factory,
} from "../pkgs/sdk/src"
import { EVMChainId } from "@certusone/wormhole-sdk"
import { GRContext } from "./app"

export async function processGenericRelayerVaa(ctx: GRContext, next: Next) {
  const payloadId = parsePayloadType(ctx.vaa!.payload)
  // route payload types
  switch (payloadId) {
    case RelayerPayloadId.Delivery:
      await processDelivery(ctx)
      break
    case RelayerPayloadId.Redelivery:
      await processRedelivery(ctx)
      break
  }
  await next()
}

async function processDelivery(ctx: GRContext) {
  const chainId = ctx.vaa!.emitterChain as wh.EVMChainId
  const payload = parseDeliveryInstructionsContainer(ctx.vaa!.payload)
  if (payload.sufficientlyFunded) {
    ctx.logger.info("Insufficiently funded delivery request, skipping")
    return
  }

  if (
    payload.messages.findIndex((m) => m.payloadType !== MessageInfoType.EmitterSequence)
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
      const relayProvider = RelayProvider__factory.connect(
        ctx.relayProviders[chainId],
        wallet
      )

      const input: IDelivery.TargetDeliveryParametersSingleStruct = {
        encodedVMs: fetchedVaas.map((v) => v.bytes),
        encodedDeliveryVAA: ctx.vaaBytes!,
        multisendIndex: i,
        relayerRefundAddress: wallet.address,
      }

      if (!(await relayProvider.approvedSender(wallet.address))) {
        ctx.logger.warn(
          `Approved sender not set correctly for chain ${chainId}, should be ${wallet.address}`
        )
        return
      }

      await relayProvider
        // @ts-ignore
        .deliverSingle(input, { value: budget, gasLimit: 3000000 })
        .then((x) => x.wait())

      ctx.logger.info(
        `Relayed instruction ${i + 1} of ${
          payload.instructions.length
        } to chain ${chainId}`
      )
    })
  }
}

async function processRedelivery(ctx: GRContext) {
  const chainId = ctx.vaa!.emitterChain as wh.EVMChainId
  const redelivery = parseRedeliveryByTxHashInstruction(ctx.vaa!.payload)

  const deliveryVAA = await ctx.fetchVaa(
    chainId,
    ctx.wormholeRelayer[chainId],
    // @ts-ignore
    redelivery.sequence
  )
  const deliveryInstructionsContainer = parseDeliveryInstructionsContainer(
    deliveryVAA.payload
  )

  if (
    deliveryInstructionsContainer.messages.findIndex(
      (m) => m.payloadType !== MessageInfoType.EmitterSequence
    )
  ) {
    throw new Error(`Only supports EmitterSequence MessageInfoType`)
  }

  const fetchedVaas = await ctx.fetchVaas({
    ids: deliveryInstructionsContainer.messages.map((m) => ({
      emitterAddress: m.emitterAddress!,
      emitterChain: chainId,
      sequence: m.sequence!.toBigInt(),
    })),
    txHash: redelivery.sourceTxHash.toString("hex"), // todo: confirm this works
  })
  await ctx.wallets.onEVM(chainId, async ({ wallet }) => {
    const relayProvider = RelayProvider__factory.connect(
      ctx.relayProviders[chainId],
      wallet
    )

    if (!(await relayProvider.approvedSender(wallet.address))) {
      ctx.logger.warn(
        `Approved sender not set correctly for chain ${chainId}, should be ${wallet.address}`
      )
      return
    }

    const { newReceiverValueTarget, newMaximumRefundTarget } = redelivery
    const budget = newReceiverValueTarget.add(newMaximumRefundTarget).add(100)
    const input: IDelivery.TargetRedeliveryByTxHashParamsSingleStruct = {
      sourceEncodedVMs: [...fetchedVaas.map((v) => v.bytes), deliveryVAA.bytes],
      originalEncodedDeliveryVAA: deliveryVAA.bytes,
      redeliveryVM: ctx.vaaBytes!,
      relayerRefundAddress: wallet.address,
    }

    await relayProvider
      .redeliverSingle(input, { value: budget, gasLimit: 3000000 })
      .then((x) => x.wait())

    ctx.logger.info(`Redelivered instruction to chain ${chainId}`)
  })
}
