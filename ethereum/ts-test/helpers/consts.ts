// rpc
export const LOCALHOST = "http://localhost:8545";

// wormhole
export const CORE_BRIDGE_ADDRESS = "0xC89Ce4735882C9F0f0FE26686c53074E09B0D550";

// signer
export const ORACLE_DEPLOYER_PRIVATE_KEY = "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d";
export const RELAYER_DEPLOYER_PRIVATE_KEY = "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d";
export const GUARDIAN_PRIVATE_KEY = "cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0";

// contract address
export const GAS_ORACLE_ADDRESS = "0x9561C133DD8580860B6b7E504bC5Aa500f0f06a7";
export const CORE_RELAYER_ADDRESS = "0x9b1f7F645351AF3631a656421eD2e40f2802E6c0";
export const MOCK_RELAYER_INTEGRATION_ADDRESS = "0x2612Af3A521c2df9EAF28422Ca335b04AdF3ac66";

// misc
export const CHAIN_ID_ETH = 2;
export const CHAIN_ID_AVAX = 6;

// wormhole event ABIs
export const WORMHOLE_MESSAGE_EVENT_ABI = [
  "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)",
];
