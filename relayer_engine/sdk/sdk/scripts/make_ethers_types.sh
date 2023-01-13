#!/bin/bash

SRC=$(dirname $0)/../../ethereum/build
DST=$(dirname $0)/../src/ethers-contracts

typechain --target=ethers-v5 --out-dir=$DST $SRC/*/*.json
