## Objective

Define a common standard for cross-chain relaying systems built on Wormhole and a framework xDapps can follow to be composable with each other.

## Background

The Wormhole VAA model only handles attestation of cross-chain messages, but does not provide a system for generalized delivery. This requires users to do delivery on the target chain or dApps to operate independent relaying infrastructure.

Currently, composing between different cross-chain applications often is leading to design patterns where developers are nesting all actions into a common VAA that contains all instructions to save gas and ensure atomic execution.

This pattern is sub-optimal as it often requires multiple composing xDapps to integrate each other and extend their functionality for new use-cases and delivery methods.
This is undesirable as it adds more and more code-complexity over time and slows down integration efforts.

## **Goals**

Define common standards for relaying systems on Wormhole. This should lead to good documentation, low switching costs between systems and make it easier to build indexing services across competing solutions.

Define the primitives that xDapps need to follow to be compatible with these systems and allow them to compose with each other.

## Non-**Goals**

This doc does not define economics on how relayers should be incentivised in systems. We want to endorse a multitude of solutions to compete for the best solutions here.

## Overview

Wormhole xDapps as well as relaying systems should be designed to allow for maximal composability.

Thats why we propose a solution leveraging [Batch VAAs](https://github.com/wormhole-foundation/wormhole/blob/whitepaper/batch_vaa/whitepapers/0008_batch_messaging.md). They allow the integrator to perform multiple actions in different xDapps and then append delivery instructions. These delivery instructions are encoded in another VAA, emitted by the relayer contract, with the same nonce.

This delivery VAA caries a payload which can provide context for the receiving contract on what to do with the other VAAs within the batch.

To allow for atomic batch-interactions with different xDapps, xDapps need allow whitelisting of addresses that can trigger the intended actions on the target chain.
This address can then be set to the receiving contract that processes the whole batch that can ensure no VAAs are picked out of the batch and processes individually.

## Detailed Design: Composable xDapp

The integration path for xDapps to be compatible with the Wormhole Relaying blueprint and cross-chain atomic batch transactions boils down to three points to follow:

1. Accept the Wormhole `nonce` as a parameter that the caller can specify.
2. Return `sequence` number returned by the Wormhole contract back to the caller.
   If the contract address that is emitting the VAA is different from the callers entry-point, xDapps also need to return the address that is emitting the VAA.
3. Allow the caller to specify which `address` can trigger the intended action on the target chain.

_( E.g. for Portal bridge this means specifying the (contract) address that is the only one allowed to redeem a transfer. )_

## Detailed Design: Relaying system

**Structs:**

```solidity
struct DeliveryInstructions {
	// DeliveryInstructions
	PayloadID uint8 = 1

	// Address of the sender. Left-zero-padded if shorter than 32 bytes
	FromAddress bytes32
	// Chain ID of the sender
	FromChain uint16
	// Address of the receiver. Left-zero-padded if shorter than 32 bytes
	ToAddress bytes32
	// Chain ID of the receiver
	ToChain uint16

	// Length of user Payload
	PayloadLen uint16
	// Payload
	Payload bytes

	// Length of chain-specific payload
	ChainPayloadLen uint16
	// chain-specific delivery payload (accounts, storage slots...)
	ChainPayload bytes

	// Length of VAA whitelist
	WhitelistLen uint16
	// VAA whitelist
	Whitelist []VAAId

	// Length of Relayer Parameters
	RelayerParamsLen uint16
	// Relayer-Specific Parameters
	RelayerParams bytes
}

struct VAAId {
	// VAA emitter
	EmitterAddress bytes32
  // VAA sequence
	Sequence uint64
}

struct DeliveryStatus {
	// DeliveryStatus
	PayloadID uint8 = 2

	// Hash of the relayed batch
	BatchHash bytes32
	// Delivery
	Delivery VAAId

	// Delivery try
	DeliveryCount uint16

	// Delivery success
	DeliverySuccess bool (byte1)
}

struct ReDeliveryInstructions {
	// ReDeliveryInstructions
	PayloadID uint8 = 3

	// Hash of the batch to re-deliver
	BatchHash bytes32
	// Point to the original delivery instruction
  OriginalDelivery VAAId

	// Current deliverycount
	DeliveryCount uint16

	// Length of new Relayer Parameters
	RelayerParamsLen uint16
	// New Relayer-Specific Parameters
	RelayerParams bytes
}
```

### Relayer Parameters

The `relayerParams` payload can be freely designed by the relaying system and should contain all data internally required by the relaying system to handle economics and safely deliver.

This could be the amount of gas to call the target contract on deliver, data related to the payment of the relayer on the target chain et cetera.

A relaying system that handles payment on the source chain could have minimal Relaying parameters containing just the target gas amount, lets look at two examples:

```solidity
struct MinimalRelayerParamsExample {
  // All payloads should be versioned
	Version uint8
  // Limit the gas amount forwarded to wormholeReceiver()
	DeliveryGasAmount uint32
}

struct RelayerParamsExample {
  // All payloads should be versioned
	Version uint8
  // Limit the gas amount forwarded to wormholeReceiver()
	DeliveryGasAmount uint32
  // Limit the max batch size that was paid for -> fail delivery if batch is too big
	MaxVAAsInBatch bytes32
	// Payment on target chain:
	PaymentToken bytes32
	PaymentAmount uint32
	PaymentReceiver bytes32
}
```

### Relaying Contract Endpoints

`send(uint16 targetChain, bytes32 targetAddress, bytes payload, VAAWhitelist VAAId[], bytes relayerParams, bytes[] chainPayload, uint32 nonce, uint8 consistencyLevel) payable`

- Optionally: handle payment
- Emit `DeliveryInstructions` VAA with specified `targetChain, targetAddress, payload, relayerParams, nonce, VAAWhitelist` and `msg.sender`, the entry-point’s `chainId`

`reSend(VAAv1 DeliveryStatus, bytes[] newRelayerParams) payable`

- Optionally: handle payment
- Emit `RedeliveryInstructions` VAA with the batch hash & delivery reference and new `relayerParams`

`estimateCost(uint16 targetChainId, bytes[] relayerParams) view`

- provide a quote for given relayerParams
- Gas Price, Limit should be encoded in `relayerParams`

`deliver(VAAv2 batchVAA, VAAId delivery, uint targetCallGasOverwrite)`

- Check the delivery hash (`hash(batchHash, VAAId)`) against already successfully delivered ones and revert if it was successfully delivered before
- Parse and verify VAAv2 at Wormhole contract with caching enabled
- Check if the emitter of the `DeliveryInstructions` VAA is a known and trusted relaying contract
- Check if the `DeliveryInstructions.ToChain` is the right chain
- If a whitelist is specified, check if all specified VAAs are in the delivered VAAv2, if no whitelist is specified check that the full batch was delivered
- Call `wormholeReceiver` on the `DeliveryInstructions.ToAddress`
  - If the length of the VAA whitelist is > 0, just forward the whitelist of VAAs, otherwise the full batch
  - If `targetCallGasOverwrite` is higher than what might be specified in `DeliveryInstructions.RelayerParams` take the overwrite value
- Emit `DeliveryStatus` depending on success or failure of the `receive` call
  - If delivery was successful: mark the delivery hash as successfully delivered
  - If delivery failed: save the delivery attempt, to be able to accept a redelivery with the correct delivery count
- Call `wipeVAACache` on the Wormhole contract
- Optionally: payout relayer (make sure there is no double payout even if delivery continuously fails)

`reDeliver(VAAv2 batchVAA, VAA resubmissionVAA, uint targetCallGasOverwrite)`

- Check if the hash &deliveryID of `batchVAA` and `resubmissionVAA` match
- Check if `DeliveryCount` is the correct, expected one
- follow flow of `deliver` but take `RelayerParams` from the `resubmissionVAA` instead of the batch

### Receiver Contract Endpoints

`wormholeReceiver(VAAv4[] vaas, uint16 sourceChain, bytes32 sourceAddress, bytes payload)`

- verify `msg.sender == relayer contract`
- verify `sourceAddress` and `sourceChain`
- parse `payload` and process `vaas`
  - verify `vaas` at Wormhole Core if needed (relayer contract not trusted && final receiver does not verify)
