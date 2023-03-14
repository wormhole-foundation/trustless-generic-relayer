import {
  ChainId,
  EVMChainId,
  isEVMChain,
  tryNativeToHexString,
  tryUint8ArrayToNative,
} from "@certusone/wormhole-sdk"

export class PluginError extends Error {
  constructor(msg: string, public args?: Record<any, any>) {
    super(msg)
  }
}

export function convertAddressBytesToHex(bytes: Uint8Array | Buffer): string {
  return tryNativeToHexString(tryUint8ArrayToNative(bytes, "ethereum"), "ethereum")
}
