#! /usr/bin/sh

# typically source ../../pkeys.sh in project root first

# kubectl delete secret private-keys --ignore-not-found

kubectl create secret generic private-keys \
    --from-literal=PRIVATE_KEYS_CHAIN_14=${PRIVATE_KEYS_CHAIN_14} \
    --from-literal=PRIVATE_KEYS_CHAIN_6=${PRIVATE_KEYS_CHAIN_6}