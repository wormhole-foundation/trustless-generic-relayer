#! /usr/bin/sh

# typically source ../../pkeys.sh in project root first

kubectl delete secret private-keys --ignore-not-found

kubectl create secret generic private-keys \
    --from-literal=PRIVATE_KEYS_CHAIN_4=${PRIVATE_KEYS_CHAIN_4} \
    --from-literal=PRIVATE_KEYS_CHAIN_5=${PRIVATE_KEYS_CHAIN_5} \
    --from-literal=PRIVATE_KEYS_CHAIN_6=${PRIVATE_KEYS_CHAIN_6} \
    --from-literal=PRIVATE_KEYS_CHAIN_16=${PRIVATE_KEYS_CHAIN_16} \
    --from-literal=PRIVATE_KEYS_CHAIN_14=${PRIVATE_KEYS_CHAIN_14} 