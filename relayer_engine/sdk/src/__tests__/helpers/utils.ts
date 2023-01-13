import {ethers} from "ethers";
import fs from "fs";
import path from "path";
import {DeliveryStatus} from "./structs";
import {WORMHOLE_RPCS, WORMHOLE_MESSAGE_EVENT_ABI} from "./consts";
import {NodeHttpTransport} from "@improbable-eng/grpc-web-node-http-transport";
import {ChainId, getEmitterAddressEth, getSignedVAAWithRetry} from "@certusone/wormhole-sdk";
import {
  GasOracle,
  GasOracle__factory,
  MockRelayerIntegration,
  MockRelayerIntegration__factory,
  CoreRelayer,
  CoreRelayer__factory,
} from "../../";

export function makeGasOracleFromForgeBroadcast(
  broadcastPath: string,
  signerOrProvider: ethers.Signer | ethers.providers.Provider
): GasOracle {
  const address = getContractAddressFromForgeBroadcast(broadcastPath, "GasOracle");
  return GasOracle__factory.connect(address, signerOrProvider);
}

export function makeMockRelayerIntegrationFromForgeBroadcast(
  broadcastPath: string,
  signerOrProvider: ethers.Signer | ethers.providers.Provider
): MockRelayerIntegration {
  const address = getContractAddressFromForgeBroadcast(broadcastPath, "MockRelayerIntegration");
  return MockRelayerIntegration__factory.connect(address, signerOrProvider);
}

export function makeCoreRelayerFromForgeBroadcast(
  broadcastPath: string,
  signerOrProvider: ethers.Signer | ethers.providers.Provider
): CoreRelayer {
  const address = getContractAddressFromForgeBroadcast(broadcastPath, "ERC1967Proxy");
  return CoreRelayer__factory.connect(address, signerOrProvider);
}

function readForgeBroadcast(broadcastPath: string): any {
  if (!fs.existsSync(broadcastPath)) {
    throw new Error("broadcastPath does not exist");
  }

  return JSON.parse(fs.readFileSync(broadcastPath, "utf8"));
}

function getContractAddressFromForgeBroadcast(broadcastPath: string, contractName: string) {
  const transactions: any[] = readForgeBroadcast(broadcastPath).transactions;
  const result = transactions.find((tx) => tx.contractName == contractName && tx.transactionType == "CREATE");
  if (result == undefined) {
    throw new Error("transaction.find == undefined");
  }
  return result.contractAddress;
}

export function resolvePath(fp: string) {
  return path.resolve(fp);
}

export async function parseWormholeEventsFromReceipt(
  receipt: ethers.ContractReceipt
): Promise<ethers.utils.LogDescription[]> {
  // create the wormhole message interface
  const wormholeMessageInterface = new ethers.utils.Interface(WORMHOLE_MESSAGE_EVENT_ABI);

  // loop through the logs and parse the events that were emitted
  const logDescriptions: ethers.utils.LogDescription[] = await Promise.all(
    receipt.logs.map(async (log) => {
      return wormholeMessageInterface.parseLog(log);
    })
  );

  return logDescriptions;
}

export async function getSignedVaaFromReceiptOnEth(
  receipt: ethers.ContractReceipt,
  emitterChainId: ChainId,
  contractAddress: ethers.BytesLike
): Promise<Uint8Array> {
  const messageEvents = await parseWormholeEventsFromReceipt(receipt);

  // grab the sequence from the parsed message log
  if (messageEvents.length !== 1) {
    throw Error("more than one message found in log");
  }
  const sequence = messageEvents[0].args.sequence;

  // fetch the signed VAA
  const result = await getSignedVAAWithRetry(
    WORMHOLE_RPCS,
    emitterChainId,
    getEmitterAddressEth(contractAddress),
    sequence.toString(),
    {
      transport: NodeHttpTransport(),
    }
  );
  return result.vaaBytes;
}

export function parseDeliveryStatusVaa(payload: ethers.BytesLike): DeliveryStatus {
  // confirm that the payload is formatted correctly
  let index: number = 0;

  // interface that we will parse the bytes into
  let deliveryStatus: DeliveryStatus = {} as DeliveryStatus;

  // grab the payloadID = 2
  deliveryStatus.payloadId = parseInt(ethers.utils.hexDataSlice(payload, index, index + 1));
  index += 1;

  // delivery batch hash
  deliveryStatus.batchHash = ethers.utils.hexDataSlice(payload, index, index + 32);
  index += 32;

  // deliveryId emitter address
  deliveryStatus.emitterAddress = ethers.utils.hexDataSlice(payload, index, index + 32);
  index += 32;

  // deliveryId sequence
  deliveryStatus.sequence = parseInt(ethers.utils.hexDataSlice(payload, index, index + 8));
  index += 8;

  // delivery count
  deliveryStatus.deliveryCount = parseInt(ethers.utils.hexDataSlice(payload, index, index + 2));
  index += 2;

  // grab the success boolean
  deliveryStatus.deliverySuccess = parseInt(ethers.utils.hexDataSlice(payload, index, index + 1));
  index += 1;

  return deliveryStatus;
}
