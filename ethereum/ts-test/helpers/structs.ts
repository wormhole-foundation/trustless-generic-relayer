import { ethers } from "ethers";
import { MockRelayerIntegration } from "../../../sdk/src/ethers-contracts/MockRelayerIntegration";

export interface RelayerArgs {
  nonce: number;
  targetChainId: number;
  targetAddress: string;
  targetGasLimit: number;
  consistencyLevel: number;
}

export interface TestResults {
  relayerArgs: MockRelayerIntegration.RelayerArgsStruct;
  signedBatchVM: ethers.BytesLike;
  targetChainGasEstimate: ethers.BigNumber;
  deliveryStatusVM: ethers.BytesLike;
}
