import {ethers} from "ethers";

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

export interface TestResults {
  relayerArgs: RelayerArgs;
  signedBatchVM: ethers.BytesLike;
  targetChainGasEstimate: ethers.BigNumber;
  deliveryStatusVM: ethers.BytesLike;
}
