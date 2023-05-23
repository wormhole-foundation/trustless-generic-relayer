# NOTICE: Development has been moved to the wormhole mono repo (wormhole-foundation/wormhole)

At the time of writing this, the develpment branch is `generic-relayer-merge` with contracts under /ethereum/contracts/relayer and offchain relayer under /relayer/generic-relayer/relayer-engine-v2. 
Eventually this will be merged down to main.

# Generic Relayers

## Objective

Develop a common standard for a cross-chain relaying system that any application can interface with on-chain to enable better composability.

## Background

In the current design of Wormhole, user applications have 2 options to relay messages across chains - (1) users manually redeem messages and (2) applications build and maintain a specialized relayer network.

Both of these paradigms present shortcomings for users and integrators respectively. For users, there is an added friction in the UX in the form of an additional interaction and requirement of owning assets on both the source and destination chain to pay for gas. For integrators, specialized relayers represent another piece of infrastructure that represents additional liveness and potential legal responsibility.

A decentralized network of generic relayers can address the shortcomings of both of the two current relaying methods by handling the cross-chain message redemption and submission on behalf of users and be a separate decentralized service that integrators can leverage.

Fundamentally, the relayer service should require no additional trust assumptions from the integrating contract's perspective. This service should merely serve as a third delivery mechanism option without changing any composing protocol's messaging. See the best practices for [protocol design](https://book.wormhole.com/dapps/architecture/3_protocolDesign.html).

## Goals

- Allow developers to send and receive cross-chain messages through on-chain entrypoints to Wormhole.
- Develop relayers that are capable of redeeming and submitting full or subset of Batch VAAs.
- Provide a composable, trustless relaying service in line with the Wormhole ecosystem.

## Non-Goals

- Design the economic incentives on how relayers should be incentivized in systems. We support a multitude of solutions to compete for the best solutions.
- Provide modularity that allows developers to specify additional off-chain computation on VAAs prior to submission on-chain.

## Overview

Generic relayers consist of three components:

1. `CoreRelayer` contract lives on all chains that integrators interact with to request for a generic relayer to deliver a cross-chain message.
2. `GasOracle` contract lives on all chains that provides an estimate to the gas costs associated with a particular cross-chain message. This is a critical function to ensure that users/applications are appropriately covering the costs that relayers face when submitting a transaction on the destination chain.
3. Off-chain Relayer that listens for VAAs that it is assigned to, redeems the VAA from the Guardian Network, and submits the VAA on the destination chain.

## Detailed Design

The interface to the Generic Relayer can be found [here](https://github.com/certusone/generic-relayer/blob/relayer/ethereum/contracts/interfaces/IWormholeRelayer.sol)

## Local Node Tests

In the [ethereum](ethereum) directory, run `make build` then `make test` to perform both Forge and local validator tests.

To run the Forge tests only, run `forge test`.

To run the local node (anvil) tests, run `make integration-test`.

## Tilt Integration Tests

To deploy everything to Tilt, run `make tilt-deploy`.

Bring up tilt from the `scratch/batch_vaa_integration` branch found [here](https://github.com/wormhole-foundation/wormhole/tree/scratch/batch_vaa_integration)

Run `make tilt-test` to start the off-chain relayer, and run the integration tests
