#/bin/bash

## tilt's rpc
RPC="http://localhost:8545"

## first account's private key
PRIVATE_KEY="0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"

## deploy to tilt (need --legacy because ganache in Tilt does not use eip-1559)
forge script forge-scripts/deploy_contracts.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow --legacy
