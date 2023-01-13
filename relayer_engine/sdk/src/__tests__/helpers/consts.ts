// rpc
export const ETH_RPC = "http://localhost:8545";
export const BSC_RPC = "http://localhost:8546";
export const WORMHOLE_RPCS = ["http://localhost:7071"];

export const ETH_EVM_CHAINID = 1337;
export const BSC_EVM_CHAINID = 1397;

// evm wallets
export const DEPLOYER_PRIVATE_KEY = "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"; // account 0
export const EVM_PRIVATE_KEY = "0x6370fd033278c143179d81c5526140625662b8daa446c22ee2d73db3707e620c"; // account 2

// io
export const ETHEREUM_ROOT = `${__dirname}/../../../../ethereum`; // holy parent directories, batman
export const ETH_FORGE_BROADCAST = `${ETHEREUM_ROOT}/broadcast/deploy_contracts.sol/${ETH_EVM_CHAINID}/run-latest.json`;
export const BSC_FORGE_BROADCAST = `${ETHEREUM_ROOT}/broadcast/deploy_contracts.sol/${BSC_EVM_CHAINID}/run-latest.json`;

// misc
export const ZERO_ADDRESS_BYTES = "0x0000000000000000000000000000000000000000000000000000000000000000";

// the amount of gas that the target relayer contract will invoke the wormhole receiver with
export const TARGET_GAS_LIMIT = 500000; // evm gas units

// wormhole event ABIs
export const WORMHOLE_MESSAGE_EVENT_ABI = [
  "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)",
];
