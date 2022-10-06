#!/usr/bin/env bash
set -exuo pipefail

cat relayer.tilt.yaml > .relayer.yaml

# function for updating or inserting a KEY: value pair in a file.
function upsert_env_file {
    file=${1} # file will be created if it does not exist.
    key=${2}  # line must start with the key.
    new_value=${3}

    # replace the value if it exists, else, append it to the file
    if [[ -f $file ]] && grep -q "^$key:" $file; then
        # file has the key, update it:
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # on macOS's sed, the -i flag needs the '' argument to not create
            # backup files
            sed -i '' -e "/^$key:/s/:\ .*/:\ $new_value/" $file
        else
            sed -i -e "/^$key:/s/:\ .*/:\ $new_value/" $file
        fi
    else
        # file does not have the key, add it:
        echo "$key: $new_value" >> $file
    fi
}


ETH_EVM_CHAINID="1337"
BSC_EVM_CHAINID="1397"

ETHEREUM_ROOT="$(pwd)/../ethereum"

ETH_FORGE_BROADCAST="$ETHEREUM_ROOT/broadcast/deploy_contracts.sol/$ETH_EVM_CHAINID/run-latest.json"
BSC_FORGE_BROADCAST="$ETHEREUM_ROOT/broadcast/deploy_contracts.sol/$BSC_EVM_CHAINID/run-latest.json"


ethAddr=$(jq --raw-output -c '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' $ETH_FORGE_BROADCAST)
bscAddr=$(jq --raw-output -c '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' $BSC_FORGE_BROADCAST)

upsert_env_file "./.relayer.yaml" "evmContract" $ethAddr
upsert_env_file "./.relayer.yaml" "evm2Contract" $bscAddr
