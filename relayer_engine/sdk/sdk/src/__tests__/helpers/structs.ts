import { ethers } from "ethers";

export interface RelayerArgs {
  nonce: number;
  targetChainId: number;
  targetAddress: string;
  targetGasLimit: number;
  consistencyLevel: number;
}

export interface TargetDeliveryParameters {
  encodedVM: ethers.utils.BytesLike;
  deliveryIndex: number;
  targetCallGasOverride: ethers.BigNumber;
}

export interface DeliveryStatus {
  payloadId: number;
  batchHash: ethers.utils.BytesLike;
  emitterAddress: ethers.utils.BytesLike;
  sequence: number;
  deliveryCount: number;
  deliverySuccess: number;
}
