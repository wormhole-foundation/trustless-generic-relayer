import { ethers } from "ethers";
import { ChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import { WORMHOLE_MESSAGE_EVENT_ABI, GUARDIAN_PRIVATE_KEY } from "./consts";
const elliptic = require("elliptic");

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

export function doubleKeccak256(body: ethers.BytesLike) {
  return ethers.utils.keccak256(ethers.utils.keccak256(body));
}

function zeroPadBytes(value: string, length: number): string {
  while (value.length < 2 * length) {
    value = "0" + value;
  }
  return value;
}

export async function getSignedBatchVaaFromReceiptOnEth(
  receipt: ethers.ContractReceipt,
  emitterChainId: ChainId,
  guardianSetIndex: number
): Promise<ethers.BytesLike> {
  // grab each message from the transaction logs
  const messageEvents = await parseWormholeEventsFromReceipt(receipt);

  // create a timestamp for the
  const timestamp = Math.floor(+new Date() / 1000);

  let observationHashes = "";
  let encodedObservationsWithLengthPrefix = "";
  for (let i = 0; i < messageEvents.length; i++) {
    const event = messageEvents[i];

    const emitterAddress: ethers.utils.BytesLike = ethers.utils.hexlify(
      "0x" + tryNativeToHexString(event.args.sender, emitterChainId)
    );

    // encode the observation
    const encodedObservation = ethers.utils.solidityPack(
      ["uint32", "uint32", "uint16", "bytes32", "uint64", "uint8", "bytes"],
      [
        timestamp,
        event.args.nonce,
        emitterChainId,
        emitterAddress,
        event.args.sequence,
        event.args.consistencyLevel,
        event.args.payload,
      ]
    );

    // compute the hash of the observation
    const hash = doubleKeccak256(encodedObservation);
    observationHashes += hash.substring(2);

    // grab the index, and length of the observation and add them to the observation bytestring
    // divide observationBytes by two to convert string representation length to bytes
    const observationElements = [
      ethers.utils.solidityPack(["uint8"], [i]).substring(2),
      ethers.utils.solidityPack(["uint32"], [encodedObservation.substring(2).length / 2]).substring(2),
      encodedObservation.substring(2),
    ];
    encodedObservationsWithLengthPrefix += observationElements.join("");
  }

  // compute the has of batch hashes - hash(hash(VAA1), hash(VAA2), ...)
  const batchHash = doubleKeccak256("0x" + observationHashes);

  // sign the batchHash
  const ec = new elliptic.ec("secp256k1");
  const key = ec.keyFromPrivate(GUARDIAN_PRIVATE_KEY);
  const signature = key.sign(batchHash.substring(2), { canonical: true });

  // create the signature
  const packSig = [
    ethers.utils.solidityPack(["uint8"], [0]).substring(2),
    zeroPadBytes(signature.r.toString(16), 32),
    zeroPadBytes(signature.s.toString(16), 32),
    ethers.utils.solidityPack(["uint8"], [signature.recoveryParam]).substring(2),
  ];
  const signatures = packSig.join("");

  const vm = [
    // this is a type 2 VAA since it's a batch
    ethers.utils.solidityPack(["uint8"], [2]).substring(2),
    ethers.utils.solidityPack(["uint32"], [guardianSetIndex]).substring(2), // guardianSetIndex
    ethers.utils.solidityPack(["uint8"], [1]).substring(2), // number of signers
    signatures,
    ethers.utils.solidityPack(["uint8"], [messageEvents.length]).substring(2),
    observationHashes,
    ethers.utils.solidityPack(["uint8"], [messageEvents.length]).substring(2),
    encodedObservationsWithLengthPrefix,
  ].join("");

  return "0x" + vm;
}

export async function getSignedVaaFromReceiptOnEth(
  receipt: ethers.ContractReceipt,
  emitterChainId: ChainId,
  guardianSetIndex: number
) {
  //: Promise<ethers.BytesLike> {
  // parse the wormhole message logs
  const messageEvents = await parseWormholeEventsFromReceipt(receipt);

  // find the VAA event
  let event;
  if (messageEvents.length == 1) {
    event = messageEvents[0];
  } else {
    throw new Error("More than one message emitted!");
  }

  // create a timestamp and find the emitter address
  const timestamp = Math.floor(+new Date() / 1000);
  const emitterAddress: ethers.utils.BytesLike = ethers.utils.hexlify(
    "0x" + tryNativeToHexString(event.args.sender, emitterChainId)
  );

  // encode the observation
  const encodedObservation = ethers.utils.solidityPack(
    ["uint32", "uint32", "uint16", "bytes32", "uint64", "uint8", "bytes"],
    [
      timestamp,
      event.args.nonce,
      emitterChainId,
      emitterAddress,
      event.args.sequence,
      event.args.consistencyLevel,
      event.args.payload,
    ]
  );

  // compute the hash of the observation
  const hash = doubleKeccak256(encodedObservation);

  // sign the batchHash
  const ec = new elliptic.ec("secp256k1");
  const key = ec.keyFromPrivate(GUARDIAN_PRIVATE_KEY);
  const signature = key.sign(hash.substring(2), { canonical: true });

  // create the signature
  const packSig = [
    ethers.utils.solidityPack(["uint8"], [0]).substring(2),
    zeroPadBytes(signature.r.toString(16), 32),
    zeroPadBytes(signature.s.toString(16), 32),
    ethers.utils.solidityPack(["uint8"], [signature.recoveryParam]).substring(2),
  ];
  const signatures = packSig.join("");

  const vm = [
    // this is a type 1 VAA
    ethers.utils.solidityPack(["uint8"], [1]).substring(2),
    ethers.utils.solidityPack(["uint32"], [guardianSetIndex]).substring(2), // guardianSetIndex
    ethers.utils.solidityPack(["uint8"], [1]).substring(2), // number of signers
    signatures,
    encodedObservation.substring(2),
  ].join("");

  return "0x" + vm;
}

export function removeObservationFromBatch(indexToRemove: number, encodedVM: ethers.BytesLike): ethers.BytesLike {
  // index of the signature count (number of signers for the VM)
  let index: number = 5;

  // grab the signature count
  const sigCount: number = parseInt(ethers.utils.hexDataSlice(encodedVM, index, index + 1));
  index += 1;

  // skip the signatures
  index += 66 * sigCount;

  // hash count
  const hashCount: number = parseInt(ethers.utils.hexDataSlice(encodedVM, index, index + 1));
  index += 1;

  // skip the hashes
  index += 32 * hashCount;

  // observation count
  const observationCount: number = parseInt(ethers.utils.hexDataSlice(encodedVM, index, index + 1));
  const observationCountIndex: number = index; // save the index
  index += 1;

  // find the index of the observation that will be removed
  let bytesRangeToRemove: number[] = [0, 0];
  for (let i = 0; i < observationCount; i++) {
    const observationStartIndex = index;

    // parse the observation index and the observation length
    const observationIndex: number = parseInt(ethers.utils.hexDataSlice(encodedVM, index, index + 1));
    index += 1;

    const observationLen: number = parseInt(ethers.utils.hexDataSlice(encodedVM, index, index + 4));
    index += 4;

    // save the index of the observation we want to remove
    if (observationIndex == indexToRemove) {
      bytesRangeToRemove[0] = observationStartIndex;
      bytesRangeToRemove[1] = observationStartIndex + 5 + observationLen;
    }
    index += observationLen;
  }

  // remove the observation by slicing the original byte array
  const newEncodedVMByteArray: ethers.BytesLike[] = [
    ethers.utils.hexDataSlice(encodedVM, 0, observationCountIndex),
    ethers.utils.hexlify([observationCount - 1]),
    ethers.utils.hexDataSlice(encodedVM, observationCountIndex + 1, bytesRangeToRemove[0]),
    ethers.utils.hexDataSlice(encodedVM, bytesRangeToRemove[1], encodedVM.length),
  ];
  return ethers.utils.hexConcat(newEncodedVMByteArray);
}

export function verifyDeliveryStatusPayload(
  payload: ethers.BytesLike,
  batchHash: ethers.BytesLike,
  relayerAddress: ethers.BytesLike,
  deliverySequence: number,
  deliveryAttempts: number,
  successBoolean: number
): boolean {
  // confirm that the payload is formatted correctly
  let index: number = 0;

  // grab the payloadID = 2
  const payloadId: number = parseInt(ethers.utils.hexDataSlice(payload, index, index + 1));
  index += 1;

  // delivery batch hash
  const deliveryBatchHash: ethers.BytesLike = ethers.utils.hexDataSlice(payload, index, index + 32);
  index += 32;

  // deliveryId emitter address
  const emitterAddress: ethers.BytesLike = ethers.utils.hexDataSlice(payload, index, index + 32);
  index += 32;

  // deliveryId sequence
  const sequence: number = parseInt(ethers.utils.hexDataSlice(payload, index, index + 8));
  index += 8;

  // delivery count
  const deliveryCount: number = parseInt(ethers.utils.hexDataSlice(payload, index, index + 2));
  index += 2;

  // grab the success boolean
  const isDelivered: number = parseInt(ethers.utils.hexDataSlice(payload, index, index + 1));
  index += 1;

  // define the expected DeliveryStatus values
  const expectedPayloadId = 2;

  // finally, compare the expected values with the actual values
  if (payloadId != expectedPayloadId) {
    console.log("Invalid payloadId");
    return false;
  } else if (deliveryBatchHash != batchHash) {
    console.log("Invalid batch hash");
    return false;
  } else if (emitterAddress != relayerAddress) {
    console.log("Invalid emitter address in delivery AllowedEmitterSequenceedEmitterSequence");
    return false;
  } else if (sequence != deliverySequence) {
    console.log("Invalid emitter address in delivery AllowedEmitterSequenceedEmitterSequence");
    return false;
  } else if (deliveryCount != deliveryAttempts) {
    console.log("Invalid number of delivery attempts");
    return false;
  } else if (isDelivered != successBoolean) {
    console.log("Invalid success boolean");
    return false;
  }

  // everything looks good
  return true;
}
