ts-node ./ts-scripts/config/checkNetworks.ts \
  && ts-node ./ts-scripts/relayProvider/deployRelayProvider.ts \
  && ts-node ./ts-scripts/coreRelayer/deployWormholeRelayer.ts \
  && ts-node ./ts-scripts/relayProvider/registerChainsRelayProvider.ts \
  && ts-node ./ts-scripts/coreRelayer/registerChainsWormholeRelayerSelfSign.ts \
  && ts-node ./ts-scripts/relayProvider/configureRelayProvider.ts \
  && ts-node ./ts-scripts/mockIntegration/deployMockIntegration.ts \
  && ts-node ./ts-scripts/mockIntegration/messageTest.ts \
  && ts-node ./ts-scripts/config/syncContractsJson.ts