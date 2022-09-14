#/bin/bash

pgrep anvil
if [ $? -eq 0 ]; then
    echo "anvil already running"
    exit 1;
fi

anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --timestamp 0 \
    --chain-id 1 > anvil.log &

sleep 2

## anvil's rpc
RPC="http://localhost:8545"

## first key from mnemonic above
PRIVATE_KEY="0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"

## deploy to anvil
forge script forge-scripts/deploy_dependencies.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow

## now deploy contracts
forge script forge-scripts/deploy_contracts.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow

## run tests here

# nuke
pkill anvil