import { BigNumber, ethers } from "ethers"
import { arrayify } from "ethers/lib/utils"

export enum RelayerPayloadId {
  Delivery = 1,
  Redelivery = 2,
  // DeliveryStatus = 3,
}

export interface DeliveryInstructionsContainer {
  payloadId: number // 1
  sufficientlyFunded: boolean
  messages: MessageInfo[]
  instructions: DeliveryInstruction[]
  messages: MessageInfo[]
}

export enum MessageInfoType {
  EmitterSequence = 0,
  VaaHash = 1,
}

export interface MessageInfo {
  payloadType: MessageInfoType
  emitterAddress?: Buffer
  sequence?: BigNumber
  vaaHash?: Buffer
}

export interface DeliveryInstruction {
  targetChain: number
  targetAddress: Buffer
  refundAddress: Buffer
  maximumRefundTarget: BigNumber
  receiverValueTarget: BigNumber
  executionParameters: ExecutionParameters
}

export interface ExecutionParameters {
  version: number
  gasLimit: number
  providerDeliveryAddress: Buffer
}

export interface RedeliveryByTxHashInstruction {
  payloadId: number //2
  sourceChain: number
  sourceTxHash: Buffer
  deliveryVaaSequence: BigNumber
  targetChain: number
  multisendIndex: number
  newMaximumRefundTarget: BigNumber
  newReceiverValueTarget: BigNumber
  executionParameters: ExecutionParameters
}

export enum MessageInfoType {EMITTER_SEQUENCE, VAAHASH}

export interface MessageInfo {
  infoType: MessageInfoType,
  emitterAddress: Buffer,
  sequence: number,
  vaaHash: Buffer
}

export function parsePayloadType(
  stringPayload: string | Buffer | Uint8Array
): RelayerPayloadId {
  const payload =
    typeof stringPayload === "string" ? arrayify(stringPayload) : stringPayload
  if (payload[0] == 0 || payload[0] >= 3) {
    throw new Error("Unrecogned payload type " + payload[0])
  }
  return payload[0]
}

export function parseDeliveryInstructionsContainer(
  bytes: Buffer
): DeliveryInstructionsContainer {
  let idx = 0
  const payloadId = bytes.readUInt8(idx)
  if (payloadId !== RelayerPayloadId.Delivery) {
    throw new Error(
      `Expected Delivery payload type (${RelayerPayloadId.Delivery}), found: ${payloadId}`
    )
  }
  idx += 1

  const sufficientlyFunded = Boolean(bytes.readUInt8(idx))
  idx += 1

  const numMessages = bytes.readUInt8(idx)
  idx += 1

  const numInstructions = bytes.readUInt8(idx)
  idx += 1

  let messages = [] as MessageInfo[]
  for(let i=0; i < numMessages; ++i) {
    const payloadId = bytes.readUint8(idx);
    idx += 1;
    const infoType = bytes.readUint8(idx) as MessageInfoType;
    idx += 1;
    let emitterAddress = Buffer.from([]);
    let sequence = 0;
    let vaaHash = Buffer.from([]);
    if(infoType == MessageInfoType.EMITTER_SEQUENCE) {
      emitterAddress = bytes.slice(idx, idx+32);
      idx += 32;
      sequence = ethers.BigNumber.from(Uint8Array.prototype.subarray.call(bytes, idx, idx+8)).toNumber();
      idx += 8;
    } else if(infoType == MessageInfoType.VAAHASH) {
      vaaHash = bytes.slice(idx, idx + 32);
      idx += 32;
    }
    messages.push({
      infoType,
      emitterAddress,
      sequence,
      vaaHash
    })
  }

  let instructions = [] as DeliveryInstruction[]
  for (let i = 0; i < numInstructions; ++i) {
    const targetChain = bytes.readUInt16BE(idx)
    idx += 2
    const targetAddress = bytes.slice(idx, idx + 32)
    idx += 32
    const refundAddress = bytes.slice(idx, idx + 32)
    idx += 32
    const maximumRefundTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    idx += 32
    const receiverValueTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    idx += 32
    const executionParameters = parseExecutionParameters(bytes, [idx])
    idx += 37
    instructions.push(
      // dumb typechain format
      {
        targetChain,
        targetAddress,
        refundAddress,
        maximumRefundTarget,
        receiverValueTarget,
        executionParameters,
      }
    )
  }

  // parse the manifest
  const numMessages = bytes.readUInt8(idx)
  idx += 1

  const idxPtr: [number] = [idx]
  const messages = [] as MessageInfo[]
  for (let i = 0; i < numMessages; ++i) {
    messages.push(parseMessageInfo(bytes, idxPtr))
  }
  return {
    payloadId,
    sufficientlyFunded,
    messages,
    instructions,
    messages,
  }
}

function parseMessageInfo(bytes: Buffer, idxPtr: [number]): MessageInfo {
  let idx = idxPtr[0]
  const payloadType = bytes.readUInt8(idx) as MessageInfoType
  switch (payloadType) {
    case MessageInfoType.EmitterSequence:
      const emitterAddress = bytes.slice(idx, idx + 32)
      idx += 32
      const sequence = ethers.BigNumber.from(
        Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
      )
      idx += 8
      idxPtr[0] = idx
      return { emitterAddress, sequence, payloadType }
    case MessageInfoType.VaaHash:
      const vaaHash = bytes.slice(idx, idx + 32)
      idx += 32
      idxPtr[0] = idx
      return { vaaHash, payloadType }
  }
}

export function parseRedeliveryByTxHashInstruction(
  bytes: Buffer
): RedeliveryByTxHashInstruction {
  let idx = 0
  const payloadId = bytes.readUInt8(idx)
  if (payloadId !== RelayerPayloadId.Redelivery) {
    throw new Error(
      `Expected Delivery payload type (${RelayerPayloadId.Redelivery}), found: ${payloadId}`
    )
  }
  idx += 1

  const sourceChain = bytes.readUInt16BE(idx)
  idx += 2

  const sourceTxHash = bytes.slice(idx, idx + 32)
  idx += 32

  const deliveryVaaSequence = BigNumber.from(bytes.slice(idx, idx + 8))
  idx += 8

  const targetChain = bytes.readUInt16BE(idx)
  idx += 2

  const multisendIndex = bytes.readUint8(idx)
  idx += 1

  // note: confirmed that BigNumber.from(<Buffer>) assumes big endian
  const newMaximumRefundTarget = BigNumber.from(bytes.slice(idx, idx + 32))
  idx += 32

  const newReceiverValueTarget = BigNumber.from(bytes.slice(idx, idx + 32))
  idx += 32

  const executionParameters = parseExecutionParameters(bytes, [idx])
  idx += 37
  return {
    payloadId,
    sourceChain,
    sourceTxHash,
    deliveryVaaSequence,
    targetChain,
    multisendIndex,
    newMaximumRefundTarget,
    newReceiverValueTarget,
    executionParameters,
  }
}

function parseExecutionParameters(
  bytes: Buffer,
  idxPtr: [number] = [0]
): ExecutionParameters {
  let idx = idxPtr[0]
  const version = bytes.readUInt8(idx)
  idx += 1
  const gasLimit = bytes.readUint32BE(idx)
  idx += 4
  const providerDeliveryAddress = bytes.slice(idx, idx + 32)
  idx += 32
  idxPtr[0] = idx
  return { version, gasLimit, providerDeliveryAddress }
}

/*
 * Helpers
 */

export function dbg<T>(x: T, msg?: string): T {
  if (msg) {
    console.log("[DEBUG] " + msg)
  }
  console.log(x)
  return x
}
