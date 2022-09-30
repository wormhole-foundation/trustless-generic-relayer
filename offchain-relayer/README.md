## prereqs

- tilt up and running with the Spy relayer enabled (`--spy_relayer=True`).
- the CoreRelayer deployed to tilt.
- Golang >= 1.17
- `jq` installed and available in your path

## relayer config

Config like contract addresses and RPC endpoints gets read from the `.relayer.yaml` file. any of the args can also be passed at runtime to override the values from the yaml file.

## start the relayer

```bash
./start-relayer.sh
```

## creating Go clients from ABIs

CoreRelayer

```bash
jq '.abi' ./ethereum/build/CoreRelayer.sol/CoreRelayer.json | docker run -i --rm  -v $(pwd):/root -u $(id -u):$(id -g)  ethereum/client-go:alltools-stable abigen --abi - --pkg core_relayer --type CoreRelayer --out /root/offchain-relayer/relay/ethereum/core_relayer/abi.go
```

## get the deployed replayer contract address

```bash
CHAINID=1337 && jq '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' ethereum/broadcast/deploy_contracts.sol/$CHAINID/run-latest.json
```

## wormhole ChainID to network ID

```solidity

        // Wormhole chain ids explicitly enumerated
        if        (chain == 2)  { evmChainId = 1;          // ethereum
        } else if (chain == 4)  { evmChainId = 56;         // bsc
        } else if (chain == 5)  { evmChainId = 137;        // polygon
        } else if (chain == 6)  { evmChainId = 43114;      // avalanche
        } else if (chain == 7)  { evmChainId = 42262;      // oasis
        } else if (chain == 9)  { evmChainId = 1313161554; // aurora
        } else if (chain == 10) { evmChainId = 250;        // fantom
        } else if (chain == 11) { evmChainId = 686;        // karura
        } else if (chain == 12) { evmChainId = 787;        // acala
        } else if (chain == 13) { evmChainId = 8217;       // klaytn
        } else if (chain == 14) { evmChainId = 42220;      // celo
        } else if (chain == 16) { evmChainId = 1284;       // moonbeam
        } else if (chain == 17) { evmChainId = 245022934;  // neon
        } else if (chain == 23) { evmChainId = 42161;      // arbitrum
        } else if (chain == 24) { evmChainId = 10;         // optimism
        } else if (chain == 25) { evmChainId = 100;        // gnosis
        } else {
            revert("Unknown chain id.");
        }

```
