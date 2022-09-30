#!/usr/bin/env bash
set -exuo pipefail

./get-addresses.sh

go run main.go relay
