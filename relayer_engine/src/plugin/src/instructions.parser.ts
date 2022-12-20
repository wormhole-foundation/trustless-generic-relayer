export interface DeliveryInstructionsContainer {
    payloadId: number;
    instructions: DeliveryInstruction[];
}

export interface DeliveryInstruction {
    targetAddress: Buffer;
    refundAddress: Buffer;
    targetChain: number;
    relayParameters: RelayParameters;
}

export interface RelayParameters {
    version: number;
    deliveryGasLimit: number;
    nativePayment: Buffer;
}


export function parseDeliveryInstructions(payload: Buffer): DeliveryInstructionsContainer {
    const payloadId = payload[0];
    const instructionsLength = payload[1];
    let offset = 2;
    const instructions = [];
    for (let i = 0; i < instructionsLength; i++) {
        const targetAddress =  payload.subarray(offset, offset + 32)
        offset +=  32;
        const refundAddress =  payload.subarray(offset, offset + 32)
        offset +=  32;
        const targetChain = payload.readUInt16BE(offset);
        offset += 2;
        const relayParametersLength = payload.readUInt16BE(offset)
        offset += 2;
        const relayParameters = parseRelayParameters(payload.subarray(offset, relayParametersLength));
        instructions.push({
            targetChain,
            targetAddress,
            refundAddress,
            relayParameters
        });
    }
    return {
        payloadId,
        instructions
    };
}

function parseRelayParameters(params: Buffer): RelayParameters {
    const version = params[0];
    const deliveryGasLimit =  params.readUInt32BE(1);
    const nativePayment = params.subarray(2, 2 + 256);
    return {
        version,
        deliveryGasLimit,
        nativePayment
    };
}
