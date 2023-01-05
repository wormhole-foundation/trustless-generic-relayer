import { ethers } from "ethers";
import fs from "fs";
import { MockRelayerIntegration, MockRelayerIntegration__factory } from "../../../sdk/src";

export function makeContract(
  signerOrProvider: ethers.Signer | ethers.providers.Provider,
  contractAddress: string,
  abiPath: string
): MockRelayerIntegration {
  return MockRelayerIntegration__factory.connect(contractAddress, signerOrProvider)
}