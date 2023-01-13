#! /usr/bin/sh

kubectl create secret generic private-keys \
    --from-literal=PRIVATE_KEYS_CHAIN_14=${PRIVATE_KEYS_CHAIN_14} \
    --from-literal=PRIVATE_KEYS_CHAIN_6=${PRIVATE_KEYS_CHAIN_6}