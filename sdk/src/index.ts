export type { GasOracle } from "./ethers-contracts/GasOracle"
export { GasOracle__factory } from "./ethers-contracts/factories/GasOracle__factory"
export type { CoreRelayer } from "./ethers-contracts/CoreRelayer"
export { CoreRelayer__factory } from "./ethers-contracts/factories/CoreRelayer__factory"
export type { MockRelayerIntegration } from "./ethers-contracts/MockRelayerIntegration"
export { MockRelayerIntegration__factory } from "./ethers-contracts/factories/MockRelayerIntegration__factory"
export type { IWormhole } from "./ethers-contracts/IWormhole"
export { IWormhole__factory } from "./ethers-contracts/factories/IWormhole__factory"

import { ethers } from "ethers"
import { CoreRelayerStructs } from "./ethers-contracts/CoreRelayer"

export enum RelayerPayloadType {
  Delivery = 1,
  Redelivery = 2,
  DeliveryStatus = 3,
}

export interface DeliveryInstructionsContainer {
  payloadId: number
  sufficientlyFunded: boolean
  instructions: DeliveryInstruction[]
}

export interface DeliveryInstruction {
  computeBudgetTarget: ethers.BigNumber
  targetChain: number
  targetAddress: Buffer
  refundAddress: Buffer
  maximumRefundTarget: ethers.BigNumber
  applicationBudgetTarget: ethers.BigNumber
  executionParameters: ExecutionParameters
}

export interface ExecutionParameters {
  version: number
  gasLimit: number
  providerDeliveryAddress: Buffer
}

export function parsePayloadType(payload: Buffer | Uint8Array): RelayerPayloadType {
  if (payload[0] == 0 || payload[0] > 3) {
    throw new Error("Unrecogned payload type")
  }
  return payload[0]
}

export function parseDeliveryInstructionsContainer(
  bytes: Buffer
): DeliveryInstructionsContainer {
  let idx = 0
  const payloadId = bytes.readUInt8(idx)
  if (payloadId !== RelayerPayloadType.Delivery) {
    throw new Error(
      `Expected Delivery payload type (${RelayerPayloadType.Delivery}), found: ${payloadId}`
    )
  }
  idx += 1

  const sufficientlyFunded = Boolean(bytes.readUInt8(idx))
  idx += 1

  const numInstructions = bytes.readUInt8(idx)
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
    const computeBudgetTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    idx += 32
    const applicationBudgetTarget = ethers.BigNumber.from(
      Uint8Array.prototype.subarray.call(bytes, idx, idx + 32)
    )
    idx += 32
    const version = bytes.readUInt8(idx)
    idx += 1
    const gasLimit = bytes.readUint32BE(idx)
    idx += 4
    const providerDeliveryAddress = bytes.slice(idx, idx + 32)
    idx += 32
    const executionParameters = { version, gasLimit, providerDeliveryAddress }
    instructions.push(
      // dumb typechain format
      {
        computeBudgetTarget,
        targetChain,
        targetAddress,
        refundAddress,
        maximumRefundTarget,
        applicationBudgetTarget,
        executionParameters,
      }
    )
  }
  return {
    payloadId,
    sufficientlyFunded,
    instructions,
  }
}
