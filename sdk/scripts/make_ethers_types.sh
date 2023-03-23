#!/bin/bash

SRC=$(dirname $0)/../../ethereum/build
SDK=$(dirname $0)/..
DST=$SDK/src/ethers-contracts

typechain --target=ethers-v5 --out-dir=$DST $SRC/*/*.json

mkdir $SDK/../relayer_engine/pkgs
mkdir $SDK/../relayer_engine/pkgs/sdk
cp -r $SDK/src $SDK/../relayer_engine/pkgs/sdk
cp $SDK/* $SDK/../relayer_engine/pkgs/sdk/
cp $SDK/.gitignore $SDK/../relayer_engine/pkgs/sdk/.gitignore

mkdir $SDK/../relayer-engine-v2/pkgs
mkdir $SDK/../relayer-engine-v2/pkgs/sdk
cp -r $SDK/src $SDK/../relayer-engine-v2/pkgs/sdk
cp $SDK/* $SDK/../relayer-engine-v2/pkgs/sdk/
cp $SDK/.gitignore $SDK/../relayer-engine-v2/pkgs/sdk/.gitignore
