#!/usr/bin/env bash
set -exuo pipefail

cd $(dirname $0)/..
jq '.abi' ./ethereum/build/CoreRelayer.sol/CoreRelayer.json | docker run -i --rm  -v $(pwd):/root -u $(id -u):$(id -g)  ethereum/client-go:alltools-stable abigen --abi - --pkg core_relayer --type CoreRelayer --out /root/offchain-relayer/relay/ethereum/core_relayer/abi.go