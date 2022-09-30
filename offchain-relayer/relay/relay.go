package relay

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	_ "net/http/pprof" // #nosec G108 we are using a custom router (`router := mux.NewRouter()`) and thus not automatically expose pprof.
	"os"
	"strconv"
	"strings"

	"go.uber.org/zap/zapcore"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	spyv1 "github.com/certusone/generic-relayer/offchain-relayer/relay/proto/spy/v1"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	eth_common "github.com/ethereum/go-ethereum/common"
	ethcrypto "github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"

	ipfslog "github.com/ipfs/go-log/v2"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"

	"github.com/certusone/wormhole/node/pkg/common"
	"github.com/certusone/wormhole/node/pkg/devnet"

	"github.com/certusone/wormhole/node/pkg/readiness"
	"github.com/certusone/wormhole/node/pkg/supervisor"
	"github.com/wormhole-foundation/wormhole/sdk/vaa"

	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/certusone/generic-relayer/offchain-relayer/relay/ethereum/core_relayer"
)

const TARGET_GAS_LIMIT = 500000

// keep the data for each chain together in a struct
type ChainDef struct {
	RPCAddr         *string
	ContractAddr    eth_common.Address
	WormholeChainID vaa.ChainID
	NetworkID       *string
}

// a map of chains supplied as args, so we can lookup an iterate through
type Chains map[vaa.ChainID]*ChainDef

var (
	dataDir *string

	statusAddr *string

	senderKeyPath *string
	// senderKeyMnemonic *string
	senderKeyHex *string

	evmRPC             *string
	evmContract        *string
	evmWormholeChainID *uint16
	evmNetworkID       *string

	evm2RPC             *string
	evm2Contract        *string
	evm2WormholeChainID *uint16
	evm2NetworkID       *string

	logLevel *string

	unsafeDevMode *bool
	testnetMode   *bool
	nodeName      *string

	spyRPC      *string
	guardianRPC *string
)

func init() {
	statusAddr = RelayCmd.Flags().String("statusAddr", viper.GetString("statusAddr"), "Listen address for status server (disabled if blank)")

	dataDir = RelayCmd.Flags().String("dataDir", viper.GetString("dataDir"), "Data directory")

	senderKeyPath = RelayCmd.Flags().String("senderKeyPath", viper.GetString("senderKeyPath"), "Path to sender key (required)")
	// senderKeyMnemonic = RelayCmd.Flags().String("senderKeyMnemonic", "", "Path to sender key (required)")
	senderKeyHex = RelayCmd.Flags().String("senderKeyHex", viper.GetString("senderKeyHex"), "Sender private key hex (required)")

	evmRPC = RelayCmd.Flags().String("evmRPC", viper.GetString("evmRPC"), "EVM RPC URL")
	evmContract = RelayCmd.Flags().String("evmContract", viper.GetString("evmContract"), "EVM contract address")
	evmWormholeChainID = RelayCmd.Flags().Uint16("evmWormholeChainID", viper.GetUint16("evmWormholeChainID"), "Wormhole ChainID")
	evmNetworkID = RelayCmd.Flags().String("evmNetworkID", viper.GetString("evmNetworkID"), "The network's ChainID")

	evm2RPC = RelayCmd.Flags().String("evm2RPC", viper.GetString("evm2RPC"), "EVM RPC URL")
	evm2Contract = RelayCmd.Flags().String("evm2Contract", viper.GetString("evm2Contract"), "EVM contract address")
	evm2WormholeChainID = RelayCmd.Flags().Uint16("evm2WormholeChainID", viper.GetUint16("evm2WormholeChainID"), "Wormhole ChainID")
	evm2NetworkID = RelayCmd.Flags().String("evm2NetworkID", viper.GetString("evm2NetworkID"), "The network's ChainID")

	logLevel = RelayCmd.Flags().String("logLevel", viper.GetString("logLevel"), "Logging level (debug, info, warn, error, dpanic, panic, fatal)")

	unsafeDevMode = RelayCmd.Flags().Bool("unsafeDevMode", viper.GetBool("unsafeDevMode"), "Launch node in unsafe, deterministic devnet mode")
	testnetMode = RelayCmd.Flags().Bool("testnetMode", viper.GetBool("testnetMode"), "Launch node in testnet mode (enables testnet-only features like Ropsten)")

	nodeName = RelayCmd.Flags().String("nodeName", viper.GetString("nodeName"), "Node name to announce in gossip heartbeats")

	spyRPC = RelayCmd.Flags().String("spyRPC", viper.GetString("spyRPC"), "Listen address of public spy gRPC interface")

	guardianRPC = RelayCmd.Flags().String("guardianRPC", viper.GetString("guardianRPC"), "Adress of public guardian gRPC interface")

}

var (
	rootCtx       context.Context
	rootCtxCancel context.CancelFunc
)

const (
	spyReadiness readiness.Component = "spyReadiness"
)

const devwarning = `
        +++++++++++++++++++++++++++++++++++++++++++++++++++
        |   NODE IS RUNNING IN INSECURE DEVELOPMENT MODE  |
        |                                                 |
        |      Do not use --unsafeDevMode in prod.        |
        +++++++++++++++++++++++++++++++++++++++++++++++++++

`

var RelayCmd = &cobra.Command{
	Use:   "relay",
	Short: "Run the relayer",
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		// You can bind cobra and viper in a few locations, but PersistencePreRunE on the root command works well
		bindFlags(cmd, viper.GetViper())
		return nil
	},
	Run: runRelay,
}

// Take the values read by viper from the config file ".relay.yaml" and apply them to cmd.
// Bind each cobra flag to its associated viper configuration (config file and environment variable).
func bindFlags(cmd *cobra.Command, v *viper.Viper) {
	envPrefix := "RELAY"
	cmd.Flags().VisitAll(func(f *pflag.Flag) {
		// Environment variables can't have dashes in them, so bind them to their equivalent
		// keys with underscores, e.g. --favorite-color to STING_FAVORITE_COLOR
		if strings.Contains(f.Name, "-") {
			envVarSuffix := strings.ToUpper(strings.ReplaceAll(f.Name, "-", "_"))
			v.BindEnv(f.Name, fmt.Sprintf("%s_%s", envPrefix, envVarSuffix))
		}

		// Apply the viper config value to the flag when the flag is not set and viper has a value
		if !f.Changed && v.IsSet(f.Name) {
			val := v.Get(f.Name)
			cmd.Flags().Set(f.Name, fmt.Sprintf("%v", val))
		}
	})
}

// This variable may be overridden by the -X linker flag to "dev" in which case
// we enforce the --unsafeDevMode flag. Only development binaries/docker images
// are distributed. Production binaries are required to be built from source by
// guardians to reduce risk from a compromised builder.
var Build = "prod"

func runRelay(cmd *cobra.Command, args []string) {
	if Build == "dev" && !*unsafeDevMode {
		fmt.Println("This is a development build. --unsafeDevMode must be enabled.")
		os.Exit(1)
	}

	if *unsafeDevMode {
		fmt.Print(devwarning)
	}

	if *testnetMode {
		common.LockMemory()
		common.SetRestrictiveUmask()
	}

	// Refuse to run as root in production mode.
	if !*unsafeDevMode && os.Geteuid() == 0 {
		fmt.Println("can't run as uid 0")
		os.Exit(1)
	}

	// Set up logging. The go-log zap wrapper that libp2p uses is compatible with our
	// usage of zap in supervisor, which is nice.
	lvl, err := ipfslog.LevelFromString(*logLevel)
	if err != nil {
		fmt.Println("Invalid log level")
		os.Exit(1)
	}

	logger := zap.New(zapcore.NewCore(
		consoleEncoder{zapcore.NewConsoleEncoder(
			zap.NewDevelopmentEncoderConfig())},
		zapcore.AddSync(zapcore.Lock(os.Stderr)),
		zap.NewAtomicLevelAt(zapcore.Level(lvl))))

	if *unsafeDevMode {
		// Use the hostname as nodeName. For production, we don't want to do this to
		// prevent accidentally leaking sensitive hostnames.
		hostname, err := os.Hostname()
		if err != nil {
			panic(err)
		}
		*nodeName = hostname

		// Put node name into the log for development.
		logger = logger.Named(*nodeName)
	}

	// Override the default go-log config, which uses a magic environment variable.
	ipfslog.SetAllLoggers(lvl)

	// Register components for readiness checks.
	readiness.RegisterComponent(spyReadiness)

	if *statusAddr != "" {
		// Use a custom routing instead of using http.DefaultServeMux directly to avoid accidentally exposing packages
		// that register themselves with it by default (like pprof).
		router := mux.NewRouter()

		// pprof server. NOT necessarily safe to expose publicly - only enable it in dev mode to avoid exposing it by
		// accident. There's benefit to having pprof enabled on production nodes, but we would likely want to expose it
		// via a dedicated port listening on localhost, or via the admin UNIX socket.
		if *unsafeDevMode {
			// Pass requests to http.DefaultServeMux, which pprof automatically registers with as an import side-effect.
			router.PathPrefix("/debug/pprof/").Handler(http.DefaultServeMux)
		}

		// Simple endpoint exposing node readiness (safe to expose to untrusted clients)
		router.HandleFunc("/readyz", readiness.Handler)

		// Prometheus metrics (safe to expose to untrusted clients)
		router.Handle("/metrics", promhttp.Handler())

		go func() {
			logger.Info(fmt.Sprintf("status server listening on [::]:%s", *statusAddr))
			// SECURITY: If making changes, ensure that we always do `router := mux.NewRouter()` before this to avoid accidentally exposing pprof
			logger.Error("status server crashed", zap.Error(http.ListenAndServe(*statusAddr, router)))
		}()
	}

	if *senderKeyPath == "" && !*unsafeDevMode {
		logger.Fatal("Please specify --senderKeyPath")
	}

	if *dataDir == "" && !*unsafeDevMode {
		logger.Fatal("Please specify --dataDir")
	}

	// first chain
	if *evmRPC == "" {
		logger.Fatal("Please specify --evmRPC")
	}
	if *evmContract == "" {
		logger.Fatal("Please specify --evmContract")
	}
	if evmWormholeChainID == nil || *evm2WormholeChainID == 0 {
		logger.Fatal("Please specify --evmWormholeChainID")
	}
	if *evmNetworkID == "" {
		logger.Fatal("Please specify --evmNetworkID")
	}

	// second
	if *evm2RPC == "" {
		logger.Fatal("Please specify --evm2RPC")
	}
	if *evm2Contract == "" {
		logger.Fatal("Please specify --evm2Contract")
	}
	if evm2WormholeChainID == nil || *evm2WormholeChainID == 0 {
		logger.Fatal("Please specify --evm2WormholeChainID")
	}
	if *evm2NetworkID == "" {
		logger.Fatal("Please specify --evm2NetworkID")
	}

	if *nodeName == "" {
		logger.Fatal("Please specify --nodeName")
	}
	if *spyRPC == "" {
		logger.Fatal("Please specify --spyRPC")
	}
	if *guardianRPC == "" {
		logger.Fatal("Please specify --guardianRPC")
	}

	// collect the networks into a map indexed by chainID.

	// make a map of the chains that we can relay to.
	// key by the ChainID so we can check this map with values from VAAs.
	var connectedChains Chains = Chains{}

	// could do this better by making the Cobra args accept an iterable with this info.

	// first chain
	var evmChainID vaa.ChainID = vaa.ChainID(*evmWormholeChainID)
	connectedChains[evmChainID] = &ChainDef{
		RPCAddr:         evmRPC,
		ContractAddr:    eth_common.HexToAddress(strings.TrimPrefix(*evmContract, "0x")),
		WormholeChainID: evmChainID,
		NetworkID:       evmNetworkID,
	}

	// second chain
	var evm2ChainID vaa.ChainID = vaa.ChainID(*evm2WormholeChainID)
	connectedChains[evm2ChainID] = &ChainDef{
		RPCAddr:         evm2RPC,
		ContractAddr:    eth_common.HexToAddress(strings.TrimPrefix(*evm2Contract, "0x")),
		WormholeChainID: evm2ChainID,
		NetworkID:       evm2NetworkID,
	}

	// read the private key passed in.
	// start with the deterministic devent key, override it if the user passes one in.
	var sk *ecdsa.PrivateKey

	if *unsafeDevMode {
		acct := devnet.DeriveAccount(uint(2))
		sk, err = devnet.Wallet().PrivateKey(acct)
		if err != nil {
			logger.Fatal("failed to derive devnet sender key", zap.Error(err))
		}
	}
	if *senderKeyHex != "" {
		sk, err = ethcrypto.HexToECDSA(*senderKeyHex)
		if err != nil {
			logger.Fatal("failed transform senderKeyHex to ECDSA", zap.Error(err))
		}
	}
	if *senderKeyPath != "" {
		sk, err = ethcrypto.LoadECDSA(*senderKeyPath)
		if err != nil {
			logger.Fatal("failed load senderKeyPath.",
				zap.String("senderKeyPath", *senderKeyPath),
				zap.Error(err))
		}
	}

	if sk == nil {
		logger.Fatal("no sender key supplied, exiting.")
	}

	guardianAddr := ethcrypto.PubkeyToAddress(sk.PublicKey).String()
	logger.Info("Loaded guardian key", zap.String(
		"address", guardianAddr))

	// Relay's main lifecycle context.
	rootCtx, rootCtxCancel = context.WithCancel(context.Background())
	defer rootCtxCancel()

	// setup channels for passing VAAs around

	// Inbound VAA observations
	obsvC := make(chan []byte, 50)

	// Outbound VAA queue
	sendC := make(chan []byte)

	// Redirect ipfs logs to plain zap
	ipfslog.SetPrimaryCore(logger.Core())

	// setup the supervisor that will start/watch/reboot the individual parts of the application.
	supervisor.New(rootCtx, logger, func(ctx context.Context) error {

		if err := supervisor.Run(ctx, "spywatch",
			spyWatcherRunnable(spyRPC, spyReadiness, obsvC)); err != nil {
			return err
		}

		if err := supervisor.Run(ctx, "inspectVAA",
			inspectVAA(obsvC, sendC, connectedChains)); err != nil {
			return err
		}

		if err := supervisor.Run(ctx, "relayVAA",
			relayVAA(sendC, connectedChains, sk)); err != nil {
			return err
		}

		logger.Info("Started internal services")

		<-ctx.Done()
		return nil
	},
		// It's safer to crash and restart the process in case we encounter a panic,
		// rather than attempting to reschedule the runnable.
		supervisor.WithPropagatePanic)

	<-rootCtx.Done()

	logger.Info("root context cancelled, exiting...")
}

// relayVAA sends the batchVAAs it recieves to the deliver function of the target chain
func relayVAA(sendC chan []byte, networks Chains, senderKey *ecdsa.PrivateKey) supervisor.Runnable {
	return func(ctx context.Context) error {
		logger := supervisor.Logger(ctx)

		logger.Debug("inspectVAA going to fire off the supervisor.SignalHealthy")
		supervisor.Signal(ctx, supervisor.SignalHealthy)
		for {
			select {
			case <-ctx.Done():
				logger.Debug(("inspectVAA recieved cts.Done(), going to return nil"))
				return nil
			case b := <-sendC:

				// ultimatly calls deliver on the relayer contract

				batchVAA, err := UnmarshalBatch(b)
				if err != nil {
					// not a batchVAA, continue, break?
					logger.Info("failed to UnmarshalBatch, must not be a batchVAA.", zap.Error(err))
					continue
				}

				src := batchVAA.Observations[0].Observation.EmitterChain
				srcChain := vaa.ChainID(src)

				if _, ok := networks[srcChain]; !ok {
					logger.Info("no network config for this source.", zap.String("src_chain", src.String()))
					continue
				}
				srcNetwork := networks[srcChain]
				relayerAddr := srcNetwork.ContractAddr
				logger.Info("relayerAddr", zap.String("relayer_addr_hex", relayerAddr.String()))

				// find the deliveryVAA among the observations in the batch
				var deliveryVAAIndex int = -1
				for i, o := range batchVAA.Observations {
					logger.Info("observation ",
						zap.Int("index", i),
						zap.String("emitter_address_hex", eth_common.BytesToAddress(o.Observation.EmitterAddress[:]).Hex()))
					if eth_common.BytesToAddress(o.Observation.EmitterAddress[:]) == relayerAddr {
						// this is a batch with a relay VAA
						deliveryVAAIndex = i
					}
				}
				logger.Info("deliveryVAAIndex", zap.Int("deliveryVAAIndex", deliveryVAAIndex))

				if deliveryVAAIndex < 0 {
					logger.Info("could not find the deliveryVAAIndex, continuing.")
					continue
				} else {
					logger.Info("found deliveryVAA among the observations", zap.Int("deliveryVAAIndex", deliveryVAAIndex))
				}

				// construct the delivery params
				deliveryParams := core_relayer.CoreRelayerStructsTargetDeliveryParameters{
					EncodedVM:             b,
					DeliveryIndex:         uint8(deliveryVAAIndex),
					TargetCallGasOverride: uint32(TARGET_GAS_LIMIT),
				}

				relayRequestVAA := batchVAA.Observations[deliveryVAAIndex]

				// create the client of the source chain
				conn, err := ethclient.Dial(*srcNetwork.RPCAddr)
				if err != nil {
					logger.Fatal("Failed to connect to the srcNetwork with ethclient: %", zap.Error(err))
				}

				// instantiate the CoreRelayer of the source chain
				srcRelayer, err := core_relayer.NewCoreRelayer(srcNetwork.ContractAddr, conn)
				if err != nil {
					logger.Error("failed getting NewCoreRelayer for source", zap.Error(err))
					continue
				}

				// create delivery instructions from the source chain's contract
				deliveryInstructions, err := srcRelayer.DecodeDeliveryInstructions(nil, relayRequestVAA.Observation.Payload)
				if err != nil {
					logger.Error("failed to decode delivery instructions", zap.Error(err))
				}
				logger.Debug("Decoded DeliveryInstructions!",
					zap.String("from_chain", vaa.ChainID(deliveryInstructions.FromChain).String()),
					zap.String("from_address", eth_common.BytesToHash(deliveryInstructions.FromAddress[:]).Hex()),
					zap.String("target_chain", vaa.ChainID(deliveryInstructions.TargetChain).String()),
					zap.String("target_address", eth_common.BytesToHash(deliveryInstructions.TargetAddress[:]).Hex()),
				)

				destChain := vaa.ChainID(deliveryInstructions.TargetChain)
				if _, ok := networks[destChain]; !ok {
					// we do not have the network to relay this message
					logger.Info("recieved relay request for unsuppported chain, doing nothing",
						zap.String("dest_chain", destChain.String()))
					continue
				}

				// create the client connection to the target chain
				destNetwork := networks[destChain]
				destConn, err := ethclient.Dial(*destNetwork.RPCAddr)
				if err != nil {
					logger.Error("failed to connect to target RPC",
						zap.String("target_chain", destNetwork.WormholeChainID.String()),
						zap.Error(err))
				}

				networkID, err := strconv.Atoi(*destNetwork.NetworkID)
				if err != nil {
					logger.Fatal("failed to convert destNetwork.NetworkID to int.", zap.Error(err))
				}
				networkID64 := int64(networkID)
				// create a transactor for the target chain
				auth, err := bind.NewKeyedTransactorWithChainID(senderKey, big.NewInt(networkID64))
				if err != nil {
					logger.Fatal("failed to create NewKeyedTransactorWithChainID", zap.Error(err))
				}

				// create the contract instance of the target chain
				destRelayer, err := core_relayer.NewCoreRelayerTransactor(destNetwork.ContractAddr, destConn)
				if err != nil {
					logger.Error("failed getting NewCoreRelayer for target",
						zap.String("contract_addr", destNetwork.ContractAddr.Hex()),
						zap.Error(err))
					continue
				}

				// send the transaction to the target chain
				tx, err := destRelayer.Deliver(auth, deliveryParams)
				if err != nil {
					logger.Error("failed delivering to destination",
						zap.Error(err))
					continue
				}

				logger.Info("successfully relayed VAA!", zap.String("tx_hash", tx.Hash().String()))

			}
		}
	}
}

// inpects SignedVAAs and determines if they should be relayed.
func inspectVAA(obsvC chan []byte, sendC chan []byte, networks Chains) supervisor.Runnable {
	return func(ctx context.Context) error {
		logger := supervisor.Logger(ctx)

		logger.Debug("inspectVAA going to fire off the supervisor.SignalHealthy")
		supervisor.Signal(ctx, supervisor.SignalHealthy)

		for {
			select {
			case <-ctx.Done():
				logger.Debug(("inspectVAA recieved cts.Done(), going to return nil"))
				return nil
			case b := <-obsvC:
				batchVAA, err := UnmarshalBatch(b)
				if err != nil {
					// this log is too noisy.
					// logger.Debug("failed to UnmarshalBatch, must not be a batchVAA.", zap.Error(err))
					continue
				}
				logger.Info("successfully unmarshaled BatchVAA!")

				src := batchVAA.Observations[0].Observation.EmitterChain
				srcChain := vaa.ChainID(src)

				if _, ok := networks[srcChain]; !ok {
					logger.Info("no network config for this source.", zap.String("src_chain", src.String()))
					continue
				} else {
					logger.Info("found network config for source", zap.String("src_chain", src.String()))
				}

				srcNetwork := networks[srcChain]
				relayerAddr := srcNetwork.ContractAddr
				logger.Info("relayerAddr", zap.String("relayer_addr_hex", relayerAddr.String()))

				// find the deliveryVAA among the observations in the batch
				var deliveryVAAIndex int = -1
				for i, o := range batchVAA.Observations {
					logger.Info("observation ",
						zap.Int("index", i),
						zap.String("emitter_address_hex", eth_common.BytesToAddress(o.Observation.EmitterAddress[:]).Hex()))
					if eth_common.BytesToAddress(o.Observation.EmitterAddress[:]) == relayerAddr {
						// this is a batch with a relay VAA
						deliveryVAAIndex = i
					}
				}
				logger.Info("deliveryVAAIndex", zap.Int("deliveryVAAIndex", deliveryVAAIndex))

				if deliveryVAAIndex < 0 {
					logger.Info("could not find the deliveryVAAIndex, continuing.")
					continue
				} else {
					logger.Info("found deliveryVAA among the observations", zap.Int("deliveryVAAIndex", deliveryVAAIndex))
				}

				relayRequestVAA := batchVAA.Observations[deliveryVAAIndex]

				// create the network client for the source chain
				conn, err := ethclient.Dial(*srcNetwork.RPCAddr)
				if err != nil {
					logger.Fatal("Failed to connect to the srcNetwork with ethclient: %", zap.Error(err))
				}
				// instantiate the CoreRelayer contract that produced the VAA
				srcRelayer, err := core_relayer.NewCoreRelayer(srcNetwork.ContractAddr, conn)
				if err != nil {
					logger.Error("failed getting NewCoreRelayer for source", zap.Error(err))
					continue
				}

				// create the delivery instructions from the source chain contract
				deliveryInstructions, err := srcRelayer.DecodeDeliveryInstructions(nil, relayRequestVAA.Observation.Payload)
				if err != nil {
					logger.Error("failed to decode delivery instructions", zap.Error(err))
				}
				logger.Debug("Decoded DeliveryInstructions!",
					zap.String("from_chain", vaa.ChainID(deliveryInstructions.FromChain).String()),
					zap.String("from_address", eth_common.BytesToHash(deliveryInstructions.FromAddress[:]).Hex()),
					zap.String("target_chain", vaa.ChainID(deliveryInstructions.TargetChain).String()),
					zap.String("target_address", eth_common.BytesToHash(deliveryInstructions.TargetAddress[:]).Hex()),
				)

				// check that we have the network connection info for the target chain of this relay request
				destChain := vaa.ChainID(deliveryInstructions.TargetChain)
				if _, ok := networks[destChain]; !ok {
					// we do not have the network to relay this message
					logger.Info("recieved relay request for unsuppported chain, doing nothing",
						zap.String("dest_chain", destChain.String()))
					continue
				}

				// the relay VAA looks good, and we verified we have everything we need to relay this VAA,
				// send it!
				sendC <- b
				logger.Info("sent the VAA to sendC.")

			}
		}
	}
}

// connects to the guardian's spy and recieves a stream of SignedVAAs, pass them
// along to the obsvC channel.
func spyWatcherRunnable(
	spyAddr *string,
	readyHandle readiness.Component,
	obsvC chan []byte,
) supervisor.Runnable {
	return func(ctx context.Context) error {
		logger := supervisor.Logger(ctx)

		_, client, err := getSpyRPCServiceClient(ctx, *spyAddr)
		if err != nil {
			logger.Fatal("failed to getSpyRPCServiceClient", zap.Error(err))
		}

		req := &spyv1.SubscribeSignedVAARequest{Filters: []*spyv1.FilterEntry{}}
		stream, err := client.SubscribeSignedVAA(ctx, req)
		if err != nil {
			logger.Fatal("failed subscribing to SpyRPCClient", zap.Error(err))
		}

		logger.Debug("spyWatcherRunnable going to fire off the supervisor.SignalHealthy")
		supervisor.Signal(ctx, supervisor.SignalHealthy)

		logger.Debug("spyWatchRunnable going to fire off 'ready' to the readiness component")
		readiness.SetReady(readyHandle)

		for {
			// recieve is a blocking call, it will keep recieving/looping until the pipe breaks.
			signedVAA, err := stream.Recv()
			if err == io.EOF {
				// connection has closed.
				// probably want to kill the thread so the supervisor will start a new one?
				// or does this break do enough (exits the for loop, so nil is returned?)
				logger.Info("the SignedVAA stream has closed, err == io.EOF. going to break.")
				break
			}
			if err != nil {
				logger.Fatal("SubscribeSignedVAA returned an error", zap.Error(err))
			}
			logger.Debug("going to push signedVaa bytes onto the obsvC")
			b := signedVAA.VaaBytes
			obsvC <- b
		}
		logger.Debug("spyWatcherRunnable is going to return a value to the supervisor")
		return nil
	}
}

func getSpyRPCServiceClient(ctx context.Context, addr string) (*grpc.ClientConn, spyv1.SpyRPCServiceClient, error) {
	conn, err := grpc.DialContext(ctx, addr, grpc.WithTransportCredentials(insecure.NewCredentials()))

	if err != nil {
		log.Fatalf("failed to connect to %s: %v", addr, err)
	}

	c := spyv1.NewSpyRPCServiceClient(conn)
	return conn, c, err
}
