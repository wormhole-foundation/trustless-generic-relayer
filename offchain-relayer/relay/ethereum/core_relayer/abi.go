// Code generated - DO NOT EDIT.
// This file is a generated binding and any manual changes will be lost.

package core_relayer

import (
	"errors"
	"math/big"
	"strings"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/event"
)

// Reference imports to suppress errors if they are not otherwise used.
var (
	_ = errors.New
	_ = big.NewInt
	_ = strings.NewReader
	_ = ethereum.NotFound
	_ = bind.Bind
	_ = common.Big1
	_ = types.BloomLookup
	_ = event.NewSubscription
)

// CoreRelayerStructsDeliveryInstructions is an auto generated low-level Go binding around an user-defined struct.
type CoreRelayerStructsDeliveryInstructions struct {
	PayloadID       uint8
	FromAddress     [32]byte
	FromChain       uint16
	TargetAddress   [32]byte
	TargetChain     uint16
	Payload         []byte
	ChainPayload    []byte
	DeliveryList    []CoreRelayerStructsVAAId
	RelayParameters []byte
}

// CoreRelayerStructsDeliveryParameters is an auto generated low-level Go binding around an user-defined struct.
type CoreRelayerStructsDeliveryParameters struct {
	TargetChain      uint16
	TargetAddress    [32]byte
	Payload          []byte
	DeliveryList     []CoreRelayerStructsVAAId
	RelayParameters  []byte
	ChainPayload     []byte
	Nonce            uint32
	ConsistencyLevel uint8
}

// CoreRelayerStructsRelayParameters is an auto generated low-level Go binding around an user-defined struct.
type CoreRelayerStructsRelayParameters struct {
	Version          uint8
	DeliveryGasLimit uint32
	MaximumBatchSize uint8
	NativePayment    *big.Int
}

// CoreRelayerStructsTargetDeliveryParameters is an auto generated low-level Go binding around an user-defined struct.
type CoreRelayerStructsTargetDeliveryParameters struct {
	EncodedVM             []byte
	DeliveryIndex         uint8
	TargetCallGasOverride uint32
}

// CoreRelayerStructsVAAId is an auto generated low-level Go binding around an user-defined struct.
type CoreRelayerStructsVAAId struct {
	EmitterAddress [32]byte
	Sequence       uint64
}

// CoreRelayerMetaData contains all meta data concerning the CoreRelayer contract.
var CoreRelayerMetaData = &bind.MetaData{
	ABI: "[{\"anonymous\":false,\"inputs\":[{\"indexed\":false,\"internalType\":\"address\",\"name\":\"previousAdmin\",\"type\":\"address\"},{\"indexed\":false,\"internalType\":\"address\",\"name\":\"newAdmin\",\"type\":\"address\"}],\"name\":\"AdminChanged\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"address\",\"name\":\"beacon\",\"type\":\"address\"}],\"name\":\"BeaconUpgraded\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"address\",\"name\":\"oldContract\",\"type\":\"address\"},{\"indexed\":true,\"internalType\":\"address\",\"name\":\"newContract\",\"type\":\"address\"}],\"name\":\"ContractUpgraded\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"oldOverhead\",\"type\":\"uint32\"},{\"indexed\":true,\"internalType\":\"uint32\",\"name\":\"newOverhead\",\"type\":\"uint32\"}],\"name\":\"EVMGasOverheadUpdated\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"address\",\"name\":\"oldOracle\",\"type\":\"address\"},{\"indexed\":true,\"internalType\":\"address\",\"name\":\"newOracle\",\"type\":\"address\"}],\"name\":\"GasOracleUpdated\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"address\",\"name\":\"oldOwner\",\"type\":\"address\"},{\"indexed\":true,\"internalType\":\"address\",\"name\":\"newOwner\",\"type\":\"address\"}],\"name\":\"OwnershipTransfered\",\"type\":\"event\"},{\"anonymous\":false,\"inputs\":[{\"indexed\":true,\"internalType\":\"address\",\"name\":\"implementation\",\"type\":\"address\"}],\"name\":\"Upgraded\",\"type\":\"event\"},{\"inputs\":[{\"internalType\":\"bytes32\",\"name\":\"deliveryHash\",\"type\":\"bytes32\"}],\"name\":\"attemptedDeliveryCount\",\"outputs\":[{\"internalType\":\"uint16\",\"name\":\"\",\"type\":\"uint16\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"chainId\",\"outputs\":[{\"internalType\":\"uint16\",\"name\":\"\",\"type\":\"uint16\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"confirmOwnershipTransferRequest\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"consistencyLevel\",\"outputs\":[{\"internalType\":\"uint8\",\"name\":\"\",\"type\":\"uint8\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes\",\"name\":\"encoded\",\"type\":\"bytes\"}],\"name\":\"decodeDeliveryInstructions\",\"outputs\":[{\"components\":[{\"internalType\":\"uint8\",\"name\":\"payloadID\",\"type\":\"uint8\"},{\"internalType\":\"bytes32\",\"name\":\"fromAddress\",\"type\":\"bytes32\"},{\"internalType\":\"uint16\",\"name\":\"fromChain\",\"type\":\"uint16\"},{\"internalType\":\"bytes32\",\"name\":\"targetAddress\",\"type\":\"bytes32\"},{\"internalType\":\"uint16\",\"name\":\"targetChain\",\"type\":\"uint16\"},{\"internalType\":\"bytes\",\"name\":\"payload\",\"type\":\"bytes\"},{\"internalType\":\"bytes\",\"name\":\"chainPayload\",\"type\":\"bytes\"},{\"components\":[{\"internalType\":\"bytes32\",\"name\":\"emitterAddress\",\"type\":\"bytes32\"},{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"internalType\":\"structCoreRelayerStructs.VAAId[]\",\"name\":\"deliveryList\",\"type\":\"tuple[]\"},{\"internalType\":\"bytes\",\"name\":\"relayParameters\",\"type\":\"bytes\"}],\"internalType\":\"structCoreRelayerStructs.DeliveryInstructions\",\"name\":\"instructions\",\"type\":\"tuple\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes\",\"name\":\"encoded\",\"type\":\"bytes\"}],\"name\":\"decodeRelayParameters\",\"outputs\":[{\"components\":[{\"internalType\":\"uint8\",\"name\":\"version\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"deliveryGasLimit\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"maximumBatchSize\",\"type\":\"uint8\"},{\"internalType\":\"uint256\",\"name\":\"nativePayment\",\"type\":\"uint256\"}],\"internalType\":\"structCoreRelayerStructs.RelayParameters\",\"name\":\"relayParams\",\"type\":\"tuple\"}],\"stateMutability\":\"pure\",\"type\":\"function\"},{\"inputs\":[{\"components\":[{\"internalType\":\"bytes\",\"name\":\"encodedVM\",\"type\":\"bytes\"},{\"internalType\":\"uint8\",\"name\":\"deliveryIndex\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetCallGasOverride\",\"type\":\"uint32\"}],\"internalType\":\"structCoreRelayerStructs.TargetDeliveryParameters\",\"name\":\"targetParams\",\"type\":\"tuple\"}],\"name\":\"deliver\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"stateMutability\":\"payable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"chainId\",\"type\":\"uint16\"},{\"internalType\":\"uint32\",\"name\":\"gasLimit\",\"type\":\"uint32\"}],\"name\":\"estimateCost\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"gasEstimate\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes\",\"name\":\"encodedVm\",\"type\":\"bytes\"}],\"name\":\"finaliseRewardPayout\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"gasOracle\",\"outputs\":[{\"internalType\":\"contractIGasOracle\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"gasOracleAddress\",\"outputs\":[{\"internalType\":\"address\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"getEvmGasOverhead\",\"outputs\":[{\"internalType\":\"uint32\",\"name\":\"\",\"type\":\"uint32\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes32\",\"name\":\"deliveryHash\",\"type\":\"bytes32\"}],\"name\":\"isDeliveryCompleted\",\"outputs\":[{\"internalType\":\"bool\",\"name\":\"\",\"type\":\"bool\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"impl\",\"type\":\"address\"}],\"name\":\"isInitialized\",\"outputs\":[{\"internalType\":\"bool\",\"name\":\"\",\"type\":\"bool\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"owner\",\"outputs\":[{\"internalType\":\"address\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"pendingOwner\",\"outputs\":[{\"internalType\":\"address\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"components\":[{\"internalType\":\"bytes\",\"name\":\"encodedVM\",\"type\":\"bytes\"},{\"internalType\":\"uint8\",\"name\":\"deliveryIndex\",\"type\":\"uint8\"},{\"internalType\":\"uint32\",\"name\":\"targetCallGasOverride\",\"type\":\"uint32\"}],\"internalType\":\"structCoreRelayerStructs.TargetDeliveryParameters\",\"name\":\"targetParams\",\"type\":\"tuple\"},{\"internalType\":\"bytes\",\"name\":\"encodedRedeliveryVm\",\"type\":\"bytes\"}],\"name\":\"reDeliver\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"stateMutability\":\"payable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes\",\"name\":\"encodedVm\",\"type\":\"bytes\"},{\"internalType\":\"bytes\",\"name\":\"newRelayerParams\",\"type\":\"bytes\"}],\"name\":\"reSend\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"stateMutability\":\"payable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"bytes32\",\"name\":\"deliveryHash\",\"type\":\"bytes32\"}],\"name\":\"redeliveryAttemptCount\",\"outputs\":[{\"internalType\":\"uint16\",\"name\":\"\",\"type\":\"uint16\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"relayerChainId\",\"type\":\"uint16\"},{\"internalType\":\"bytes32\",\"name\":\"relayerAddress\",\"type\":\"bytes32\"}],\"name\":\"registerChain\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"chain\",\"type\":\"uint16\"}],\"name\":\"registeredRelayer\",\"outputs\":[{\"internalType\":\"bytes32\",\"name\":\"\",\"type\":\"bytes32\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"address\",\"name\":\"relayer\",\"type\":\"address\"},{\"internalType\":\"uint16\",\"name\":\"rewardChain\",\"type\":\"uint16\"}],\"name\":\"relayerRewards\",\"outputs\":[{\"internalType\":\"uint256\",\"name\":\"\",\"type\":\"uint256\"}],\"stateMutability\":\"view\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"rewardChain\",\"type\":\"uint16\"},{\"internalType\":\"bytes32\",\"name\":\"receiver\",\"type\":\"bytes32\"},{\"internalType\":\"uint32\",\"name\":\"nonce\",\"type\":\"uint32\"}],\"name\":\"rewardPayout\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"stateMutability\":\"payable\",\"type\":\"function\"},{\"inputs\":[{\"components\":[{\"internalType\":\"uint16\",\"name\":\"targetChain\",\"type\":\"uint16\"},{\"internalType\":\"bytes32\",\"name\":\"targetAddress\",\"type\":\"bytes32\"},{\"internalType\":\"bytes\",\"name\":\"payload\",\"type\":\"bytes\"},{\"components\":[{\"internalType\":\"bytes32\",\"name\":\"emitterAddress\",\"type\":\"bytes32\"},{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"internalType\":\"structCoreRelayerStructs.VAAId[]\",\"name\":\"deliveryList\",\"type\":\"tuple[]\"},{\"internalType\":\"bytes\",\"name\":\"relayParameters\",\"type\":\"bytes\"},{\"internalType\":\"bytes\",\"name\":\"chainPayload\",\"type\":\"bytes\"},{\"internalType\":\"uint32\",\"name\":\"nonce\",\"type\":\"uint32\"},{\"internalType\":\"uint8\",\"name\":\"consistencyLevel\",\"type\":\"uint8\"}],\"internalType\":\"structCoreRelayerStructs.DeliveryParameters\",\"name\":\"deliveryParams\",\"type\":\"tuple\"}],\"name\":\"send\",\"outputs\":[{\"internalType\":\"uint64\",\"name\":\"sequence\",\"type\":\"uint64\"}],\"stateMutability\":\"payable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"thisRelayerChainId\",\"type\":\"uint16\"},{\"internalType\":\"address\",\"name\":\"newOwner\",\"type\":\"address\"}],\"name\":\"submitOwnershipTransferRequest\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"thisRelayerChainId\",\"type\":\"uint16\"},{\"internalType\":\"uint32\",\"name\":\"newGasOverhead\",\"type\":\"uint32\"}],\"name\":\"updateEvmGasOverhead\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"thisRelayerChainId\",\"type\":\"uint16\"},{\"internalType\":\"address\",\"name\":\"newGasOracleAddress\",\"type\":\"address\"}],\"name\":\"updateGasOracleContract\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[{\"internalType\":\"uint16\",\"name\":\"thisRelayerChainId\",\"type\":\"uint16\"},{\"internalType\":\"address\",\"name\":\"newImplementation\",\"type\":\"address\"}],\"name\":\"upgrade\",\"outputs\":[],\"stateMutability\":\"nonpayable\",\"type\":\"function\"},{\"inputs\":[],\"name\":\"wormhole\",\"outputs\":[{\"internalType\":\"contractIWormhole\",\"name\":\"\",\"type\":\"address\"}],\"stateMutability\":\"view\",\"type\":\"function\"}]",
}

// CoreRelayerABI is the input ABI used to generate the binding from.
// Deprecated: Use CoreRelayerMetaData.ABI instead.
var CoreRelayerABI = CoreRelayerMetaData.ABI

// CoreRelayer is an auto generated Go binding around an Ethereum contract.
type CoreRelayer struct {
	CoreRelayerCaller     // Read-only binding to the contract
	CoreRelayerTransactor // Write-only binding to the contract
	CoreRelayerFilterer   // Log filterer for contract events
}

// CoreRelayerCaller is an auto generated read-only Go binding around an Ethereum contract.
type CoreRelayerCaller struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// CoreRelayerTransactor is an auto generated write-only Go binding around an Ethereum contract.
type CoreRelayerTransactor struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// CoreRelayerFilterer is an auto generated log filtering Go binding around an Ethereum contract events.
type CoreRelayerFilterer struct {
	contract *bind.BoundContract // Generic contract wrapper for the low level calls
}

// CoreRelayerSession is an auto generated Go binding around an Ethereum contract,
// with pre-set call and transact options.
type CoreRelayerSession struct {
	Contract     *CoreRelayer      // Generic contract binding to set the session for
	CallOpts     bind.CallOpts     // Call options to use throughout this session
	TransactOpts bind.TransactOpts // Transaction auth options to use throughout this session
}

// CoreRelayerCallerSession is an auto generated read-only Go binding around an Ethereum contract,
// with pre-set call options.
type CoreRelayerCallerSession struct {
	Contract *CoreRelayerCaller // Generic contract caller binding to set the session for
	CallOpts bind.CallOpts      // Call options to use throughout this session
}

// CoreRelayerTransactorSession is an auto generated write-only Go binding around an Ethereum contract,
// with pre-set transact options.
type CoreRelayerTransactorSession struct {
	Contract     *CoreRelayerTransactor // Generic contract transactor binding to set the session for
	TransactOpts bind.TransactOpts      // Transaction auth options to use throughout this session
}

// CoreRelayerRaw is an auto generated low-level Go binding around an Ethereum contract.
type CoreRelayerRaw struct {
	Contract *CoreRelayer // Generic contract binding to access the raw methods on
}

// CoreRelayerCallerRaw is an auto generated low-level read-only Go binding around an Ethereum contract.
type CoreRelayerCallerRaw struct {
	Contract *CoreRelayerCaller // Generic read-only contract binding to access the raw methods on
}

// CoreRelayerTransactorRaw is an auto generated low-level write-only Go binding around an Ethereum contract.
type CoreRelayerTransactorRaw struct {
	Contract *CoreRelayerTransactor // Generic write-only contract binding to access the raw methods on
}

// NewCoreRelayer creates a new instance of CoreRelayer, bound to a specific deployed contract.
func NewCoreRelayer(address common.Address, backend bind.ContractBackend) (*CoreRelayer, error) {
	contract, err := bindCoreRelayer(address, backend, backend, backend)
	if err != nil {
		return nil, err
	}
	return &CoreRelayer{CoreRelayerCaller: CoreRelayerCaller{contract: contract}, CoreRelayerTransactor: CoreRelayerTransactor{contract: contract}, CoreRelayerFilterer: CoreRelayerFilterer{contract: contract}}, nil
}

// NewCoreRelayerCaller creates a new read-only instance of CoreRelayer, bound to a specific deployed contract.
func NewCoreRelayerCaller(address common.Address, caller bind.ContractCaller) (*CoreRelayerCaller, error) {
	contract, err := bindCoreRelayer(address, caller, nil, nil)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerCaller{contract: contract}, nil
}

// NewCoreRelayerTransactor creates a new write-only instance of CoreRelayer, bound to a specific deployed contract.
func NewCoreRelayerTransactor(address common.Address, transactor bind.ContractTransactor) (*CoreRelayerTransactor, error) {
	contract, err := bindCoreRelayer(address, nil, transactor, nil)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerTransactor{contract: contract}, nil
}

// NewCoreRelayerFilterer creates a new log filterer instance of CoreRelayer, bound to a specific deployed contract.
func NewCoreRelayerFilterer(address common.Address, filterer bind.ContractFilterer) (*CoreRelayerFilterer, error) {
	contract, err := bindCoreRelayer(address, nil, nil, filterer)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerFilterer{contract: contract}, nil
}

// bindCoreRelayer binds a generic wrapper to an already deployed contract.
func bindCoreRelayer(address common.Address, caller bind.ContractCaller, transactor bind.ContractTransactor, filterer bind.ContractFilterer) (*bind.BoundContract, error) {
	parsed, err := abi.JSON(strings.NewReader(CoreRelayerABI))
	if err != nil {
		return nil, err
	}
	return bind.NewBoundContract(address, parsed, caller, transactor, filterer), nil
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_CoreRelayer *CoreRelayerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _CoreRelayer.Contract.CoreRelayerCaller.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_CoreRelayer *CoreRelayerRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _CoreRelayer.Contract.CoreRelayerTransactor.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_CoreRelayer *CoreRelayerRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _CoreRelayer.Contract.CoreRelayerTransactor.contract.Transact(opts, method, params...)
}

// Call invokes the (constant) contract method with params as input values and
// sets the output to result. The result type might be a single field for simple
// returns, a slice of interfaces for anonymous returns and a struct for named
// returns.
func (_CoreRelayer *CoreRelayerCallerRaw) Call(opts *bind.CallOpts, result *[]interface{}, method string, params ...interface{}) error {
	return _CoreRelayer.Contract.contract.Call(opts, result, method, params...)
}

// Transfer initiates a plain transaction to move funds to the contract, calling
// its default method if one is available.
func (_CoreRelayer *CoreRelayerTransactorRaw) Transfer(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _CoreRelayer.Contract.contract.Transfer(opts)
}

// Transact invokes the (paid) contract method with params as input values.
func (_CoreRelayer *CoreRelayerTransactorRaw) Transact(opts *bind.TransactOpts, method string, params ...interface{}) (*types.Transaction, error) {
	return _CoreRelayer.Contract.contract.Transact(opts, method, params...)
}

// AttemptedDeliveryCount is a free data retrieval call binding the contract method 0x696262fc.
//
// Solidity: function attemptedDeliveryCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerCaller) AttemptedDeliveryCount(opts *bind.CallOpts, deliveryHash [32]byte) (uint16, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "attemptedDeliveryCount", deliveryHash)

	if err != nil {
		return *new(uint16), err
	}

	out0 := *abi.ConvertType(out[0], new(uint16)).(*uint16)

	return out0, err

}

// AttemptedDeliveryCount is a free data retrieval call binding the contract method 0x696262fc.
//
// Solidity: function attemptedDeliveryCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerSession) AttemptedDeliveryCount(deliveryHash [32]byte) (uint16, error) {
	return _CoreRelayer.Contract.AttemptedDeliveryCount(&_CoreRelayer.CallOpts, deliveryHash)
}

// AttemptedDeliveryCount is a free data retrieval call binding the contract method 0x696262fc.
//
// Solidity: function attemptedDeliveryCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerCallerSession) AttemptedDeliveryCount(deliveryHash [32]byte) (uint16, error) {
	return _CoreRelayer.Contract.AttemptedDeliveryCount(&_CoreRelayer.CallOpts, deliveryHash)
}

// ChainId is a free data retrieval call binding the contract method 0x9a8a0592.
//
// Solidity: function chainId() view returns(uint16)
func (_CoreRelayer *CoreRelayerCaller) ChainId(opts *bind.CallOpts) (uint16, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "chainId")

	if err != nil {
		return *new(uint16), err
	}

	out0 := *abi.ConvertType(out[0], new(uint16)).(*uint16)

	return out0, err

}

// ChainId is a free data retrieval call binding the contract method 0x9a8a0592.
//
// Solidity: function chainId() view returns(uint16)
func (_CoreRelayer *CoreRelayerSession) ChainId() (uint16, error) {
	return _CoreRelayer.Contract.ChainId(&_CoreRelayer.CallOpts)
}

// ChainId is a free data retrieval call binding the contract method 0x9a8a0592.
//
// Solidity: function chainId() view returns(uint16)
func (_CoreRelayer *CoreRelayerCallerSession) ChainId() (uint16, error) {
	return _CoreRelayer.Contract.ChainId(&_CoreRelayer.CallOpts)
}

// ConsistencyLevel is a free data retrieval call binding the contract method 0xe8dfd508.
//
// Solidity: function consistencyLevel() view returns(uint8)
func (_CoreRelayer *CoreRelayerCaller) ConsistencyLevel(opts *bind.CallOpts) (uint8, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "consistencyLevel")

	if err != nil {
		return *new(uint8), err
	}

	out0 := *abi.ConvertType(out[0], new(uint8)).(*uint8)

	return out0, err

}

// ConsistencyLevel is a free data retrieval call binding the contract method 0xe8dfd508.
//
// Solidity: function consistencyLevel() view returns(uint8)
func (_CoreRelayer *CoreRelayerSession) ConsistencyLevel() (uint8, error) {
	return _CoreRelayer.Contract.ConsistencyLevel(&_CoreRelayer.CallOpts)
}

// ConsistencyLevel is a free data retrieval call binding the contract method 0xe8dfd508.
//
// Solidity: function consistencyLevel() view returns(uint8)
func (_CoreRelayer *CoreRelayerCallerSession) ConsistencyLevel() (uint8, error) {
	return _CoreRelayer.Contract.ConsistencyLevel(&_CoreRelayer.CallOpts)
}

// DecodeDeliveryInstructions is a free data retrieval call binding the contract method 0x4d92d3c9.
//
// Solidity: function decodeDeliveryInstructions(bytes encoded) pure returns((uint8,bytes32,uint16,bytes32,uint16,bytes,bytes,(bytes32,uint64)[],bytes) instructions)
func (_CoreRelayer *CoreRelayerCaller) DecodeDeliveryInstructions(opts *bind.CallOpts, encoded []byte) (CoreRelayerStructsDeliveryInstructions, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "decodeDeliveryInstructions", encoded)

	if err != nil {
		return *new(CoreRelayerStructsDeliveryInstructions), err
	}

	out0 := *abi.ConvertType(out[0], new(CoreRelayerStructsDeliveryInstructions)).(*CoreRelayerStructsDeliveryInstructions)

	return out0, err

}

// DecodeDeliveryInstructions is a free data retrieval call binding the contract method 0x4d92d3c9.
//
// Solidity: function decodeDeliveryInstructions(bytes encoded) pure returns((uint8,bytes32,uint16,bytes32,uint16,bytes,bytes,(bytes32,uint64)[],bytes) instructions)
func (_CoreRelayer *CoreRelayerSession) DecodeDeliveryInstructions(encoded []byte) (CoreRelayerStructsDeliveryInstructions, error) {
	return _CoreRelayer.Contract.DecodeDeliveryInstructions(&_CoreRelayer.CallOpts, encoded)
}

// DecodeDeliveryInstructions is a free data retrieval call binding the contract method 0x4d92d3c9.
//
// Solidity: function decodeDeliveryInstructions(bytes encoded) pure returns((uint8,bytes32,uint16,bytes32,uint16,bytes,bytes,(bytes32,uint64)[],bytes) instructions)
func (_CoreRelayer *CoreRelayerCallerSession) DecodeDeliveryInstructions(encoded []byte) (CoreRelayerStructsDeliveryInstructions, error) {
	return _CoreRelayer.Contract.DecodeDeliveryInstructions(&_CoreRelayer.CallOpts, encoded)
}

// DecodeRelayParameters is a free data retrieval call binding the contract method 0x18f6df06.
//
// Solidity: function decodeRelayParameters(bytes encoded) pure returns((uint8,uint32,uint8,uint256) relayParams)
func (_CoreRelayer *CoreRelayerCaller) DecodeRelayParameters(opts *bind.CallOpts, encoded []byte) (CoreRelayerStructsRelayParameters, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "decodeRelayParameters", encoded)

	if err != nil {
		return *new(CoreRelayerStructsRelayParameters), err
	}

	out0 := *abi.ConvertType(out[0], new(CoreRelayerStructsRelayParameters)).(*CoreRelayerStructsRelayParameters)

	return out0, err

}

// DecodeRelayParameters is a free data retrieval call binding the contract method 0x18f6df06.
//
// Solidity: function decodeRelayParameters(bytes encoded) pure returns((uint8,uint32,uint8,uint256) relayParams)
func (_CoreRelayer *CoreRelayerSession) DecodeRelayParameters(encoded []byte) (CoreRelayerStructsRelayParameters, error) {
	return _CoreRelayer.Contract.DecodeRelayParameters(&_CoreRelayer.CallOpts, encoded)
}

// DecodeRelayParameters is a free data retrieval call binding the contract method 0x18f6df06.
//
// Solidity: function decodeRelayParameters(bytes encoded) pure returns((uint8,uint32,uint8,uint256) relayParams)
func (_CoreRelayer *CoreRelayerCallerSession) DecodeRelayParameters(encoded []byte) (CoreRelayerStructsRelayParameters, error) {
	return _CoreRelayer.Contract.DecodeRelayParameters(&_CoreRelayer.CallOpts, encoded)
}

// EstimateCost is a free data retrieval call binding the contract method 0xc1f74e50.
//
// Solidity: function estimateCost(uint16 chainId, uint32 gasLimit) view returns(uint256 gasEstimate)
func (_CoreRelayer *CoreRelayerCaller) EstimateCost(opts *bind.CallOpts, chainId uint16, gasLimit uint32) (*big.Int, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "estimateCost", chainId, gasLimit)

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// EstimateCost is a free data retrieval call binding the contract method 0xc1f74e50.
//
// Solidity: function estimateCost(uint16 chainId, uint32 gasLimit) view returns(uint256 gasEstimate)
func (_CoreRelayer *CoreRelayerSession) EstimateCost(chainId uint16, gasLimit uint32) (*big.Int, error) {
	return _CoreRelayer.Contract.EstimateCost(&_CoreRelayer.CallOpts, chainId, gasLimit)
}

// EstimateCost is a free data retrieval call binding the contract method 0xc1f74e50.
//
// Solidity: function estimateCost(uint16 chainId, uint32 gasLimit) view returns(uint256 gasEstimate)
func (_CoreRelayer *CoreRelayerCallerSession) EstimateCost(chainId uint16, gasLimit uint32) (*big.Int, error) {
	return _CoreRelayer.Contract.EstimateCost(&_CoreRelayer.CallOpts, chainId, gasLimit)
}

// GasOracle is a free data retrieval call binding the contract method 0x5d62a8dd.
//
// Solidity: function gasOracle() view returns(address)
func (_CoreRelayer *CoreRelayerCaller) GasOracle(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "gasOracle")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// GasOracle is a free data retrieval call binding the contract method 0x5d62a8dd.
//
// Solidity: function gasOracle() view returns(address)
func (_CoreRelayer *CoreRelayerSession) GasOracle() (common.Address, error) {
	return _CoreRelayer.Contract.GasOracle(&_CoreRelayer.CallOpts)
}

// GasOracle is a free data retrieval call binding the contract method 0x5d62a8dd.
//
// Solidity: function gasOracle() view returns(address)
func (_CoreRelayer *CoreRelayerCallerSession) GasOracle() (common.Address, error) {
	return _CoreRelayer.Contract.GasOracle(&_CoreRelayer.CallOpts)
}

// GasOracleAddress is a free data retrieval call binding the contract method 0x786a8f58.
//
// Solidity: function gasOracleAddress() view returns(address)
func (_CoreRelayer *CoreRelayerCaller) GasOracleAddress(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "gasOracleAddress")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// GasOracleAddress is a free data retrieval call binding the contract method 0x786a8f58.
//
// Solidity: function gasOracleAddress() view returns(address)
func (_CoreRelayer *CoreRelayerSession) GasOracleAddress() (common.Address, error) {
	return _CoreRelayer.Contract.GasOracleAddress(&_CoreRelayer.CallOpts)
}

// GasOracleAddress is a free data retrieval call binding the contract method 0x786a8f58.
//
// Solidity: function gasOracleAddress() view returns(address)
func (_CoreRelayer *CoreRelayerCallerSession) GasOracleAddress() (common.Address, error) {
	return _CoreRelayer.Contract.GasOracleAddress(&_CoreRelayer.CallOpts)
}

// GetEvmGasOverhead is a free data retrieval call binding the contract method 0x11bca1f4.
//
// Solidity: function getEvmGasOverhead() view returns(uint32)
func (_CoreRelayer *CoreRelayerCaller) GetEvmGasOverhead(opts *bind.CallOpts) (uint32, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "getEvmGasOverhead")

	if err != nil {
		return *new(uint32), err
	}

	out0 := *abi.ConvertType(out[0], new(uint32)).(*uint32)

	return out0, err

}

// GetEvmGasOverhead is a free data retrieval call binding the contract method 0x11bca1f4.
//
// Solidity: function getEvmGasOverhead() view returns(uint32)
func (_CoreRelayer *CoreRelayerSession) GetEvmGasOverhead() (uint32, error) {
	return _CoreRelayer.Contract.GetEvmGasOverhead(&_CoreRelayer.CallOpts)
}

// GetEvmGasOverhead is a free data retrieval call binding the contract method 0x11bca1f4.
//
// Solidity: function getEvmGasOverhead() view returns(uint32)
func (_CoreRelayer *CoreRelayerCallerSession) GetEvmGasOverhead() (uint32, error) {
	return _CoreRelayer.Contract.GetEvmGasOverhead(&_CoreRelayer.CallOpts)
}

// IsDeliveryCompleted is a free data retrieval call binding the contract method 0x1dd5f138.
//
// Solidity: function isDeliveryCompleted(bytes32 deliveryHash) view returns(bool)
func (_CoreRelayer *CoreRelayerCaller) IsDeliveryCompleted(opts *bind.CallOpts, deliveryHash [32]byte) (bool, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "isDeliveryCompleted", deliveryHash)

	if err != nil {
		return *new(bool), err
	}

	out0 := *abi.ConvertType(out[0], new(bool)).(*bool)

	return out0, err

}

// IsDeliveryCompleted is a free data retrieval call binding the contract method 0x1dd5f138.
//
// Solidity: function isDeliveryCompleted(bytes32 deliveryHash) view returns(bool)
func (_CoreRelayer *CoreRelayerSession) IsDeliveryCompleted(deliveryHash [32]byte) (bool, error) {
	return _CoreRelayer.Contract.IsDeliveryCompleted(&_CoreRelayer.CallOpts, deliveryHash)
}

// IsDeliveryCompleted is a free data retrieval call binding the contract method 0x1dd5f138.
//
// Solidity: function isDeliveryCompleted(bytes32 deliveryHash) view returns(bool)
func (_CoreRelayer *CoreRelayerCallerSession) IsDeliveryCompleted(deliveryHash [32]byte) (bool, error) {
	return _CoreRelayer.Contract.IsDeliveryCompleted(&_CoreRelayer.CallOpts, deliveryHash)
}

// IsInitialized is a free data retrieval call binding the contract method 0xd60b347f.
//
// Solidity: function isInitialized(address impl) view returns(bool)
func (_CoreRelayer *CoreRelayerCaller) IsInitialized(opts *bind.CallOpts, impl common.Address) (bool, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "isInitialized", impl)

	if err != nil {
		return *new(bool), err
	}

	out0 := *abi.ConvertType(out[0], new(bool)).(*bool)

	return out0, err

}

// IsInitialized is a free data retrieval call binding the contract method 0xd60b347f.
//
// Solidity: function isInitialized(address impl) view returns(bool)
func (_CoreRelayer *CoreRelayerSession) IsInitialized(impl common.Address) (bool, error) {
	return _CoreRelayer.Contract.IsInitialized(&_CoreRelayer.CallOpts, impl)
}

// IsInitialized is a free data retrieval call binding the contract method 0xd60b347f.
//
// Solidity: function isInitialized(address impl) view returns(bool)
func (_CoreRelayer *CoreRelayerCallerSession) IsInitialized(impl common.Address) (bool, error) {
	return _CoreRelayer.Contract.IsInitialized(&_CoreRelayer.CallOpts, impl)
}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_CoreRelayer *CoreRelayerCaller) Owner(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "owner")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_CoreRelayer *CoreRelayerSession) Owner() (common.Address, error) {
	return _CoreRelayer.Contract.Owner(&_CoreRelayer.CallOpts)
}

// Owner is a free data retrieval call binding the contract method 0x8da5cb5b.
//
// Solidity: function owner() view returns(address)
func (_CoreRelayer *CoreRelayerCallerSession) Owner() (common.Address, error) {
	return _CoreRelayer.Contract.Owner(&_CoreRelayer.CallOpts)
}

// PendingOwner is a free data retrieval call binding the contract method 0xe30c3978.
//
// Solidity: function pendingOwner() view returns(address)
func (_CoreRelayer *CoreRelayerCaller) PendingOwner(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "pendingOwner")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// PendingOwner is a free data retrieval call binding the contract method 0xe30c3978.
//
// Solidity: function pendingOwner() view returns(address)
func (_CoreRelayer *CoreRelayerSession) PendingOwner() (common.Address, error) {
	return _CoreRelayer.Contract.PendingOwner(&_CoreRelayer.CallOpts)
}

// PendingOwner is a free data retrieval call binding the contract method 0xe30c3978.
//
// Solidity: function pendingOwner() view returns(address)
func (_CoreRelayer *CoreRelayerCallerSession) PendingOwner() (common.Address, error) {
	return _CoreRelayer.Contract.PendingOwner(&_CoreRelayer.CallOpts)
}

// RedeliveryAttemptCount is a free data retrieval call binding the contract method 0x59fbacbf.
//
// Solidity: function redeliveryAttemptCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerCaller) RedeliveryAttemptCount(opts *bind.CallOpts, deliveryHash [32]byte) (uint16, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "redeliveryAttemptCount", deliveryHash)

	if err != nil {
		return *new(uint16), err
	}

	out0 := *abi.ConvertType(out[0], new(uint16)).(*uint16)

	return out0, err

}

// RedeliveryAttemptCount is a free data retrieval call binding the contract method 0x59fbacbf.
//
// Solidity: function redeliveryAttemptCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerSession) RedeliveryAttemptCount(deliveryHash [32]byte) (uint16, error) {
	return _CoreRelayer.Contract.RedeliveryAttemptCount(&_CoreRelayer.CallOpts, deliveryHash)
}

// RedeliveryAttemptCount is a free data retrieval call binding the contract method 0x59fbacbf.
//
// Solidity: function redeliveryAttemptCount(bytes32 deliveryHash) view returns(uint16)
func (_CoreRelayer *CoreRelayerCallerSession) RedeliveryAttemptCount(deliveryHash [32]byte) (uint16, error) {
	return _CoreRelayer.Contract.RedeliveryAttemptCount(&_CoreRelayer.CallOpts, deliveryHash)
}

// RegisteredRelayer is a free data retrieval call binding the contract method 0x9d9dfdf7.
//
// Solidity: function registeredRelayer(uint16 chain) view returns(bytes32)
func (_CoreRelayer *CoreRelayerCaller) RegisteredRelayer(opts *bind.CallOpts, chain uint16) ([32]byte, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "registeredRelayer", chain)

	if err != nil {
		return *new([32]byte), err
	}

	out0 := *abi.ConvertType(out[0], new([32]byte)).(*[32]byte)

	return out0, err

}

// RegisteredRelayer is a free data retrieval call binding the contract method 0x9d9dfdf7.
//
// Solidity: function registeredRelayer(uint16 chain) view returns(bytes32)
func (_CoreRelayer *CoreRelayerSession) RegisteredRelayer(chain uint16) ([32]byte, error) {
	return _CoreRelayer.Contract.RegisteredRelayer(&_CoreRelayer.CallOpts, chain)
}

// RegisteredRelayer is a free data retrieval call binding the contract method 0x9d9dfdf7.
//
// Solidity: function registeredRelayer(uint16 chain) view returns(bytes32)
func (_CoreRelayer *CoreRelayerCallerSession) RegisteredRelayer(chain uint16) ([32]byte, error) {
	return _CoreRelayer.Contract.RegisteredRelayer(&_CoreRelayer.CallOpts, chain)
}

// RelayerRewards is a free data retrieval call binding the contract method 0xde142814.
//
// Solidity: function relayerRewards(address relayer, uint16 rewardChain) view returns(uint256)
func (_CoreRelayer *CoreRelayerCaller) RelayerRewards(opts *bind.CallOpts, relayer common.Address, rewardChain uint16) (*big.Int, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "relayerRewards", relayer, rewardChain)

	if err != nil {
		return *new(*big.Int), err
	}

	out0 := *abi.ConvertType(out[0], new(*big.Int)).(**big.Int)

	return out0, err

}

// RelayerRewards is a free data retrieval call binding the contract method 0xde142814.
//
// Solidity: function relayerRewards(address relayer, uint16 rewardChain) view returns(uint256)
func (_CoreRelayer *CoreRelayerSession) RelayerRewards(relayer common.Address, rewardChain uint16) (*big.Int, error) {
	return _CoreRelayer.Contract.RelayerRewards(&_CoreRelayer.CallOpts, relayer, rewardChain)
}

// RelayerRewards is a free data retrieval call binding the contract method 0xde142814.
//
// Solidity: function relayerRewards(address relayer, uint16 rewardChain) view returns(uint256)
func (_CoreRelayer *CoreRelayerCallerSession) RelayerRewards(relayer common.Address, rewardChain uint16) (*big.Int, error) {
	return _CoreRelayer.Contract.RelayerRewards(&_CoreRelayer.CallOpts, relayer, rewardChain)
}

// Wormhole is a free data retrieval call binding the contract method 0x84acd1bb.
//
// Solidity: function wormhole() view returns(address)
func (_CoreRelayer *CoreRelayerCaller) Wormhole(opts *bind.CallOpts) (common.Address, error) {
	var out []interface{}
	err := _CoreRelayer.contract.Call(opts, &out, "wormhole")

	if err != nil {
		return *new(common.Address), err
	}

	out0 := *abi.ConvertType(out[0], new(common.Address)).(*common.Address)

	return out0, err

}

// Wormhole is a free data retrieval call binding the contract method 0x84acd1bb.
//
// Solidity: function wormhole() view returns(address)
func (_CoreRelayer *CoreRelayerSession) Wormhole() (common.Address, error) {
	return _CoreRelayer.Contract.Wormhole(&_CoreRelayer.CallOpts)
}

// Wormhole is a free data retrieval call binding the contract method 0x84acd1bb.
//
// Solidity: function wormhole() view returns(address)
func (_CoreRelayer *CoreRelayerCallerSession) Wormhole() (common.Address, error) {
	return _CoreRelayer.Contract.Wormhole(&_CoreRelayer.CallOpts)
}

// ConfirmOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x038c0b66.
//
// Solidity: function confirmOwnershipTransferRequest() returns()
func (_CoreRelayer *CoreRelayerTransactor) ConfirmOwnershipTransferRequest(opts *bind.TransactOpts) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "confirmOwnershipTransferRequest")
}

// ConfirmOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x038c0b66.
//
// Solidity: function confirmOwnershipTransferRequest() returns()
func (_CoreRelayer *CoreRelayerSession) ConfirmOwnershipTransferRequest() (*types.Transaction, error) {
	return _CoreRelayer.Contract.ConfirmOwnershipTransferRequest(&_CoreRelayer.TransactOpts)
}

// ConfirmOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x038c0b66.
//
// Solidity: function confirmOwnershipTransferRequest() returns()
func (_CoreRelayer *CoreRelayerTransactorSession) ConfirmOwnershipTransferRequest() (*types.Transaction, error) {
	return _CoreRelayer.Contract.ConfirmOwnershipTransferRequest(&_CoreRelayer.TransactOpts)
}

// Deliver is a paid mutator transaction binding the contract method 0x428f7d13.
//
// Solidity: function deliver((bytes,uint8,uint32) targetParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactor) Deliver(opts *bind.TransactOpts, targetParams CoreRelayerStructsTargetDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "deliver", targetParams)
}

// Deliver is a paid mutator transaction binding the contract method 0x428f7d13.
//
// Solidity: function deliver((bytes,uint8,uint32) targetParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerSession) Deliver(targetParams CoreRelayerStructsTargetDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Deliver(&_CoreRelayer.TransactOpts, targetParams)
}

// Deliver is a paid mutator transaction binding the contract method 0x428f7d13.
//
// Solidity: function deliver((bytes,uint8,uint32) targetParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactorSession) Deliver(targetParams CoreRelayerStructsTargetDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Deliver(&_CoreRelayer.TransactOpts, targetParams)
}

// FinaliseRewardPayout is a paid mutator transaction binding the contract method 0x205668cd.
//
// Solidity: function finaliseRewardPayout(bytes encodedVm) returns()
func (_CoreRelayer *CoreRelayerTransactor) FinaliseRewardPayout(opts *bind.TransactOpts, encodedVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "finaliseRewardPayout", encodedVm)
}

// FinaliseRewardPayout is a paid mutator transaction binding the contract method 0x205668cd.
//
// Solidity: function finaliseRewardPayout(bytes encodedVm) returns()
func (_CoreRelayer *CoreRelayerSession) FinaliseRewardPayout(encodedVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.FinaliseRewardPayout(&_CoreRelayer.TransactOpts, encodedVm)
}

// FinaliseRewardPayout is a paid mutator transaction binding the contract method 0x205668cd.
//
// Solidity: function finaliseRewardPayout(bytes encodedVm) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) FinaliseRewardPayout(encodedVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.FinaliseRewardPayout(&_CoreRelayer.TransactOpts, encodedVm)
}

// ReDeliver is a paid mutator transaction binding the contract method 0x24217508.
//
// Solidity: function reDeliver((bytes,uint8,uint32) targetParams, bytes encodedRedeliveryVm) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactor) ReDeliver(opts *bind.TransactOpts, targetParams CoreRelayerStructsTargetDeliveryParameters, encodedRedeliveryVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "reDeliver", targetParams, encodedRedeliveryVm)
}

// ReDeliver is a paid mutator transaction binding the contract method 0x24217508.
//
// Solidity: function reDeliver((bytes,uint8,uint32) targetParams, bytes encodedRedeliveryVm) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerSession) ReDeliver(targetParams CoreRelayerStructsTargetDeliveryParameters, encodedRedeliveryVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.ReDeliver(&_CoreRelayer.TransactOpts, targetParams, encodedRedeliveryVm)
}

// ReDeliver is a paid mutator transaction binding the contract method 0x24217508.
//
// Solidity: function reDeliver((bytes,uint8,uint32) targetParams, bytes encodedRedeliveryVm) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactorSession) ReDeliver(targetParams CoreRelayerStructsTargetDeliveryParameters, encodedRedeliveryVm []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.ReDeliver(&_CoreRelayer.TransactOpts, targetParams, encodedRedeliveryVm)
}

// ReSend is a paid mutator transaction binding the contract method 0xd21f4f50.
//
// Solidity: function reSend(bytes encodedVm, bytes newRelayerParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactor) ReSend(opts *bind.TransactOpts, encodedVm []byte, newRelayerParams []byte) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "reSend", encodedVm, newRelayerParams)
}

// ReSend is a paid mutator transaction binding the contract method 0xd21f4f50.
//
// Solidity: function reSend(bytes encodedVm, bytes newRelayerParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerSession) ReSend(encodedVm []byte, newRelayerParams []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.ReSend(&_CoreRelayer.TransactOpts, encodedVm, newRelayerParams)
}

// ReSend is a paid mutator transaction binding the contract method 0xd21f4f50.
//
// Solidity: function reSend(bytes encodedVm, bytes newRelayerParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactorSession) ReSend(encodedVm []byte, newRelayerParams []byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.ReSend(&_CoreRelayer.TransactOpts, encodedVm, newRelayerParams)
}

// RegisterChain is a paid mutator transaction binding the contract method 0x65bb3ea7.
//
// Solidity: function registerChain(uint16 relayerChainId, bytes32 relayerAddress) returns()
func (_CoreRelayer *CoreRelayerTransactor) RegisterChain(opts *bind.TransactOpts, relayerChainId uint16, relayerAddress [32]byte) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "registerChain", relayerChainId, relayerAddress)
}

// RegisterChain is a paid mutator transaction binding the contract method 0x65bb3ea7.
//
// Solidity: function registerChain(uint16 relayerChainId, bytes32 relayerAddress) returns()
func (_CoreRelayer *CoreRelayerSession) RegisterChain(relayerChainId uint16, relayerAddress [32]byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.RegisterChain(&_CoreRelayer.TransactOpts, relayerChainId, relayerAddress)
}

// RegisterChain is a paid mutator transaction binding the contract method 0x65bb3ea7.
//
// Solidity: function registerChain(uint16 relayerChainId, bytes32 relayerAddress) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) RegisterChain(relayerChainId uint16, relayerAddress [32]byte) (*types.Transaction, error) {
	return _CoreRelayer.Contract.RegisterChain(&_CoreRelayer.TransactOpts, relayerChainId, relayerAddress)
}

// RewardPayout is a paid mutator transaction binding the contract method 0x710cdd3c.
//
// Solidity: function rewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactor) RewardPayout(opts *bind.TransactOpts, rewardChain uint16, receiver [32]byte, nonce uint32) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "rewardPayout", rewardChain, receiver, nonce)
}

// RewardPayout is a paid mutator transaction binding the contract method 0x710cdd3c.
//
// Solidity: function rewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerSession) RewardPayout(rewardChain uint16, receiver [32]byte, nonce uint32) (*types.Transaction, error) {
	return _CoreRelayer.Contract.RewardPayout(&_CoreRelayer.TransactOpts, rewardChain, receiver, nonce)
}

// RewardPayout is a paid mutator transaction binding the contract method 0x710cdd3c.
//
// Solidity: function rewardPayout(uint16 rewardChain, bytes32 receiver, uint32 nonce) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactorSession) RewardPayout(rewardChain uint16, receiver [32]byte, nonce uint32) (*types.Transaction, error) {
	return _CoreRelayer.Contract.RewardPayout(&_CoreRelayer.TransactOpts, rewardChain, receiver, nonce)
}

// Send is a paid mutator transaction binding the contract method 0x1e2a68a5.
//
// Solidity: function send((uint16,bytes32,bytes,(bytes32,uint64)[],bytes,bytes,uint32,uint8) deliveryParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactor) Send(opts *bind.TransactOpts, deliveryParams CoreRelayerStructsDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "send", deliveryParams)
}

// Send is a paid mutator transaction binding the contract method 0x1e2a68a5.
//
// Solidity: function send((uint16,bytes32,bytes,(bytes32,uint64)[],bytes,bytes,uint32,uint8) deliveryParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerSession) Send(deliveryParams CoreRelayerStructsDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Send(&_CoreRelayer.TransactOpts, deliveryParams)
}

// Send is a paid mutator transaction binding the contract method 0x1e2a68a5.
//
// Solidity: function send((uint16,bytes32,bytes,(bytes32,uint64)[],bytes,bytes,uint32,uint8) deliveryParams) payable returns(uint64 sequence)
func (_CoreRelayer *CoreRelayerTransactorSession) Send(deliveryParams CoreRelayerStructsDeliveryParameters) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Send(&_CoreRelayer.TransactOpts, deliveryParams)
}

// SubmitOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x94cc743d.
//
// Solidity: function submitOwnershipTransferRequest(uint16 thisRelayerChainId, address newOwner) returns()
func (_CoreRelayer *CoreRelayerTransactor) SubmitOwnershipTransferRequest(opts *bind.TransactOpts, thisRelayerChainId uint16, newOwner common.Address) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "submitOwnershipTransferRequest", thisRelayerChainId, newOwner)
}

// SubmitOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x94cc743d.
//
// Solidity: function submitOwnershipTransferRequest(uint16 thisRelayerChainId, address newOwner) returns()
func (_CoreRelayer *CoreRelayerSession) SubmitOwnershipTransferRequest(thisRelayerChainId uint16, newOwner common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.SubmitOwnershipTransferRequest(&_CoreRelayer.TransactOpts, thisRelayerChainId, newOwner)
}

// SubmitOwnershipTransferRequest is a paid mutator transaction binding the contract method 0x94cc743d.
//
// Solidity: function submitOwnershipTransferRequest(uint16 thisRelayerChainId, address newOwner) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) SubmitOwnershipTransferRequest(thisRelayerChainId uint16, newOwner common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.SubmitOwnershipTransferRequest(&_CoreRelayer.TransactOpts, thisRelayerChainId, newOwner)
}

// UpdateEvmGasOverhead is a paid mutator transaction binding the contract method 0x00de5ec4.
//
// Solidity: function updateEvmGasOverhead(uint16 thisRelayerChainId, uint32 newGasOverhead) returns()
func (_CoreRelayer *CoreRelayerTransactor) UpdateEvmGasOverhead(opts *bind.TransactOpts, thisRelayerChainId uint16, newGasOverhead uint32) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "updateEvmGasOverhead", thisRelayerChainId, newGasOverhead)
}

// UpdateEvmGasOverhead is a paid mutator transaction binding the contract method 0x00de5ec4.
//
// Solidity: function updateEvmGasOverhead(uint16 thisRelayerChainId, uint32 newGasOverhead) returns()
func (_CoreRelayer *CoreRelayerSession) UpdateEvmGasOverhead(thisRelayerChainId uint16, newGasOverhead uint32) (*types.Transaction, error) {
	return _CoreRelayer.Contract.UpdateEvmGasOverhead(&_CoreRelayer.TransactOpts, thisRelayerChainId, newGasOverhead)
}

// UpdateEvmGasOverhead is a paid mutator transaction binding the contract method 0x00de5ec4.
//
// Solidity: function updateEvmGasOverhead(uint16 thisRelayerChainId, uint32 newGasOverhead) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) UpdateEvmGasOverhead(thisRelayerChainId uint16, newGasOverhead uint32) (*types.Transaction, error) {
	return _CoreRelayer.Contract.UpdateEvmGasOverhead(&_CoreRelayer.TransactOpts, thisRelayerChainId, newGasOverhead)
}

// UpdateGasOracleContract is a paid mutator transaction binding the contract method 0x3c07f767.
//
// Solidity: function updateGasOracleContract(uint16 thisRelayerChainId, address newGasOracleAddress) returns()
func (_CoreRelayer *CoreRelayerTransactor) UpdateGasOracleContract(opts *bind.TransactOpts, thisRelayerChainId uint16, newGasOracleAddress common.Address) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "updateGasOracleContract", thisRelayerChainId, newGasOracleAddress)
}

// UpdateGasOracleContract is a paid mutator transaction binding the contract method 0x3c07f767.
//
// Solidity: function updateGasOracleContract(uint16 thisRelayerChainId, address newGasOracleAddress) returns()
func (_CoreRelayer *CoreRelayerSession) UpdateGasOracleContract(thisRelayerChainId uint16, newGasOracleAddress common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.UpdateGasOracleContract(&_CoreRelayer.TransactOpts, thisRelayerChainId, newGasOracleAddress)
}

// UpdateGasOracleContract is a paid mutator transaction binding the contract method 0x3c07f767.
//
// Solidity: function updateGasOracleContract(uint16 thisRelayerChainId, address newGasOracleAddress) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) UpdateGasOracleContract(thisRelayerChainId uint16, newGasOracleAddress common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.UpdateGasOracleContract(&_CoreRelayer.TransactOpts, thisRelayerChainId, newGasOracleAddress)
}

// Upgrade is a paid mutator transaction binding the contract method 0x3522be7d.
//
// Solidity: function upgrade(uint16 thisRelayerChainId, address newImplementation) returns()
func (_CoreRelayer *CoreRelayerTransactor) Upgrade(opts *bind.TransactOpts, thisRelayerChainId uint16, newImplementation common.Address) (*types.Transaction, error) {
	return _CoreRelayer.contract.Transact(opts, "upgrade", thisRelayerChainId, newImplementation)
}

// Upgrade is a paid mutator transaction binding the contract method 0x3522be7d.
//
// Solidity: function upgrade(uint16 thisRelayerChainId, address newImplementation) returns()
func (_CoreRelayer *CoreRelayerSession) Upgrade(thisRelayerChainId uint16, newImplementation common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Upgrade(&_CoreRelayer.TransactOpts, thisRelayerChainId, newImplementation)
}

// Upgrade is a paid mutator transaction binding the contract method 0x3522be7d.
//
// Solidity: function upgrade(uint16 thisRelayerChainId, address newImplementation) returns()
func (_CoreRelayer *CoreRelayerTransactorSession) Upgrade(thisRelayerChainId uint16, newImplementation common.Address) (*types.Transaction, error) {
	return _CoreRelayer.Contract.Upgrade(&_CoreRelayer.TransactOpts, thisRelayerChainId, newImplementation)
}

// CoreRelayerAdminChangedIterator is returned from FilterAdminChanged and is used to iterate over the raw logs and unpacked data for AdminChanged events raised by the CoreRelayer contract.
type CoreRelayerAdminChangedIterator struct {
	Event *CoreRelayerAdminChanged // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerAdminChangedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerAdminChanged)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerAdminChanged)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerAdminChangedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerAdminChangedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerAdminChanged represents a AdminChanged event raised by the CoreRelayer contract.
type CoreRelayerAdminChanged struct {
	PreviousAdmin common.Address
	NewAdmin      common.Address
	Raw           types.Log // Blockchain specific contextual infos
}

// FilterAdminChanged is a free log retrieval operation binding the contract event 0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f.
//
// Solidity: event AdminChanged(address previousAdmin, address newAdmin)
func (_CoreRelayer *CoreRelayerFilterer) FilterAdminChanged(opts *bind.FilterOpts) (*CoreRelayerAdminChangedIterator, error) {

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "AdminChanged")
	if err != nil {
		return nil, err
	}
	return &CoreRelayerAdminChangedIterator{contract: _CoreRelayer.contract, event: "AdminChanged", logs: logs, sub: sub}, nil
}

// WatchAdminChanged is a free log subscription operation binding the contract event 0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f.
//
// Solidity: event AdminChanged(address previousAdmin, address newAdmin)
func (_CoreRelayer *CoreRelayerFilterer) WatchAdminChanged(opts *bind.WatchOpts, sink chan<- *CoreRelayerAdminChanged) (event.Subscription, error) {

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "AdminChanged")
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerAdminChanged)
				if err := _CoreRelayer.contract.UnpackLog(event, "AdminChanged", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseAdminChanged is a log parse operation binding the contract event 0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f.
//
// Solidity: event AdminChanged(address previousAdmin, address newAdmin)
func (_CoreRelayer *CoreRelayerFilterer) ParseAdminChanged(log types.Log) (*CoreRelayerAdminChanged, error) {
	event := new(CoreRelayerAdminChanged)
	if err := _CoreRelayer.contract.UnpackLog(event, "AdminChanged", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerBeaconUpgradedIterator is returned from FilterBeaconUpgraded and is used to iterate over the raw logs and unpacked data for BeaconUpgraded events raised by the CoreRelayer contract.
type CoreRelayerBeaconUpgradedIterator struct {
	Event *CoreRelayerBeaconUpgraded // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerBeaconUpgradedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerBeaconUpgraded)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerBeaconUpgraded)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerBeaconUpgradedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerBeaconUpgradedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerBeaconUpgraded represents a BeaconUpgraded event raised by the CoreRelayer contract.
type CoreRelayerBeaconUpgraded struct {
	Beacon common.Address
	Raw    types.Log // Blockchain specific contextual infos
}

// FilterBeaconUpgraded is a free log retrieval operation binding the contract event 0x1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e.
//
// Solidity: event BeaconUpgraded(address indexed beacon)
func (_CoreRelayer *CoreRelayerFilterer) FilterBeaconUpgraded(opts *bind.FilterOpts, beacon []common.Address) (*CoreRelayerBeaconUpgradedIterator, error) {

	var beaconRule []interface{}
	for _, beaconItem := range beacon {
		beaconRule = append(beaconRule, beaconItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "BeaconUpgraded", beaconRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerBeaconUpgradedIterator{contract: _CoreRelayer.contract, event: "BeaconUpgraded", logs: logs, sub: sub}, nil
}

// WatchBeaconUpgraded is a free log subscription operation binding the contract event 0x1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e.
//
// Solidity: event BeaconUpgraded(address indexed beacon)
func (_CoreRelayer *CoreRelayerFilterer) WatchBeaconUpgraded(opts *bind.WatchOpts, sink chan<- *CoreRelayerBeaconUpgraded, beacon []common.Address) (event.Subscription, error) {

	var beaconRule []interface{}
	for _, beaconItem := range beacon {
		beaconRule = append(beaconRule, beaconItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "BeaconUpgraded", beaconRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerBeaconUpgraded)
				if err := _CoreRelayer.contract.UnpackLog(event, "BeaconUpgraded", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseBeaconUpgraded is a log parse operation binding the contract event 0x1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e.
//
// Solidity: event BeaconUpgraded(address indexed beacon)
func (_CoreRelayer *CoreRelayerFilterer) ParseBeaconUpgraded(log types.Log) (*CoreRelayerBeaconUpgraded, error) {
	event := new(CoreRelayerBeaconUpgraded)
	if err := _CoreRelayer.contract.UnpackLog(event, "BeaconUpgraded", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerContractUpgradedIterator is returned from FilterContractUpgraded and is used to iterate over the raw logs and unpacked data for ContractUpgraded events raised by the CoreRelayer contract.
type CoreRelayerContractUpgradedIterator struct {
	Event *CoreRelayerContractUpgraded // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerContractUpgradedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerContractUpgraded)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerContractUpgraded)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerContractUpgradedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerContractUpgradedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerContractUpgraded represents a ContractUpgraded event raised by the CoreRelayer contract.
type CoreRelayerContractUpgraded struct {
	OldContract common.Address
	NewContract common.Address
	Raw         types.Log // Blockchain specific contextual infos
}

// FilterContractUpgraded is a free log retrieval operation binding the contract event 0x2e4cc16c100f0b55e2df82ab0b1a7e294aa9cbd01b48fbaf622683fbc0507a49.
//
// Solidity: event ContractUpgraded(address indexed oldContract, address indexed newContract)
func (_CoreRelayer *CoreRelayerFilterer) FilterContractUpgraded(opts *bind.FilterOpts, oldContract []common.Address, newContract []common.Address) (*CoreRelayerContractUpgradedIterator, error) {

	var oldContractRule []interface{}
	for _, oldContractItem := range oldContract {
		oldContractRule = append(oldContractRule, oldContractItem)
	}
	var newContractRule []interface{}
	for _, newContractItem := range newContract {
		newContractRule = append(newContractRule, newContractItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "ContractUpgraded", oldContractRule, newContractRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerContractUpgradedIterator{contract: _CoreRelayer.contract, event: "ContractUpgraded", logs: logs, sub: sub}, nil
}

// WatchContractUpgraded is a free log subscription operation binding the contract event 0x2e4cc16c100f0b55e2df82ab0b1a7e294aa9cbd01b48fbaf622683fbc0507a49.
//
// Solidity: event ContractUpgraded(address indexed oldContract, address indexed newContract)
func (_CoreRelayer *CoreRelayerFilterer) WatchContractUpgraded(opts *bind.WatchOpts, sink chan<- *CoreRelayerContractUpgraded, oldContract []common.Address, newContract []common.Address) (event.Subscription, error) {

	var oldContractRule []interface{}
	for _, oldContractItem := range oldContract {
		oldContractRule = append(oldContractRule, oldContractItem)
	}
	var newContractRule []interface{}
	for _, newContractItem := range newContract {
		newContractRule = append(newContractRule, newContractItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "ContractUpgraded", oldContractRule, newContractRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerContractUpgraded)
				if err := _CoreRelayer.contract.UnpackLog(event, "ContractUpgraded", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseContractUpgraded is a log parse operation binding the contract event 0x2e4cc16c100f0b55e2df82ab0b1a7e294aa9cbd01b48fbaf622683fbc0507a49.
//
// Solidity: event ContractUpgraded(address indexed oldContract, address indexed newContract)
func (_CoreRelayer *CoreRelayerFilterer) ParseContractUpgraded(log types.Log) (*CoreRelayerContractUpgraded, error) {
	event := new(CoreRelayerContractUpgraded)
	if err := _CoreRelayer.contract.UnpackLog(event, "ContractUpgraded", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerEVMGasOverheadUpdatedIterator is returned from FilterEVMGasOverheadUpdated and is used to iterate over the raw logs and unpacked data for EVMGasOverheadUpdated events raised by the CoreRelayer contract.
type CoreRelayerEVMGasOverheadUpdatedIterator struct {
	Event *CoreRelayerEVMGasOverheadUpdated // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerEVMGasOverheadUpdatedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerEVMGasOverheadUpdated)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerEVMGasOverheadUpdated)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerEVMGasOverheadUpdatedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerEVMGasOverheadUpdatedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerEVMGasOverheadUpdated represents a EVMGasOverheadUpdated event raised by the CoreRelayer contract.
type CoreRelayerEVMGasOverheadUpdated struct {
	OldOverhead uint32
	NewOverhead uint32
	Raw         types.Log // Blockchain specific contextual infos
}

// FilterEVMGasOverheadUpdated is a free log retrieval operation binding the contract event 0x39b49e3d7d01371a25a01c8cfd3e6daafc69f017c13b0f9fcb633d97d16c87b9.
//
// Solidity: event EVMGasOverheadUpdated(uint32 indexed oldOverhead, uint32 indexed newOverhead)
func (_CoreRelayer *CoreRelayerFilterer) FilterEVMGasOverheadUpdated(opts *bind.FilterOpts, oldOverhead []uint32, newOverhead []uint32) (*CoreRelayerEVMGasOverheadUpdatedIterator, error) {

	var oldOverheadRule []interface{}
	for _, oldOverheadItem := range oldOverhead {
		oldOverheadRule = append(oldOverheadRule, oldOverheadItem)
	}
	var newOverheadRule []interface{}
	for _, newOverheadItem := range newOverhead {
		newOverheadRule = append(newOverheadRule, newOverheadItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "EVMGasOverheadUpdated", oldOverheadRule, newOverheadRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerEVMGasOverheadUpdatedIterator{contract: _CoreRelayer.contract, event: "EVMGasOverheadUpdated", logs: logs, sub: sub}, nil
}

// WatchEVMGasOverheadUpdated is a free log subscription operation binding the contract event 0x39b49e3d7d01371a25a01c8cfd3e6daafc69f017c13b0f9fcb633d97d16c87b9.
//
// Solidity: event EVMGasOverheadUpdated(uint32 indexed oldOverhead, uint32 indexed newOverhead)
func (_CoreRelayer *CoreRelayerFilterer) WatchEVMGasOverheadUpdated(opts *bind.WatchOpts, sink chan<- *CoreRelayerEVMGasOverheadUpdated, oldOverhead []uint32, newOverhead []uint32) (event.Subscription, error) {

	var oldOverheadRule []interface{}
	for _, oldOverheadItem := range oldOverhead {
		oldOverheadRule = append(oldOverheadRule, oldOverheadItem)
	}
	var newOverheadRule []interface{}
	for _, newOverheadItem := range newOverhead {
		newOverheadRule = append(newOverheadRule, newOverheadItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "EVMGasOverheadUpdated", oldOverheadRule, newOverheadRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerEVMGasOverheadUpdated)
				if err := _CoreRelayer.contract.UnpackLog(event, "EVMGasOverheadUpdated", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseEVMGasOverheadUpdated is a log parse operation binding the contract event 0x39b49e3d7d01371a25a01c8cfd3e6daafc69f017c13b0f9fcb633d97d16c87b9.
//
// Solidity: event EVMGasOverheadUpdated(uint32 indexed oldOverhead, uint32 indexed newOverhead)
func (_CoreRelayer *CoreRelayerFilterer) ParseEVMGasOverheadUpdated(log types.Log) (*CoreRelayerEVMGasOverheadUpdated, error) {
	event := new(CoreRelayerEVMGasOverheadUpdated)
	if err := _CoreRelayer.contract.UnpackLog(event, "EVMGasOverheadUpdated", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerGasOracleUpdatedIterator is returned from FilterGasOracleUpdated and is used to iterate over the raw logs and unpacked data for GasOracleUpdated events raised by the CoreRelayer contract.
type CoreRelayerGasOracleUpdatedIterator struct {
	Event *CoreRelayerGasOracleUpdated // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerGasOracleUpdatedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerGasOracleUpdated)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerGasOracleUpdated)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerGasOracleUpdatedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerGasOracleUpdatedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerGasOracleUpdated represents a GasOracleUpdated event raised by the CoreRelayer contract.
type CoreRelayerGasOracleUpdated struct {
	OldOracle common.Address
	NewOracle common.Address
	Raw       types.Log // Blockchain specific contextual infos
}

// FilterGasOracleUpdated is a free log retrieval operation binding the contract event 0x73832aa215e2812d2f0c40bd0cf9df82495d3a46da4be338a17d63fb20e108f9.
//
// Solidity: event GasOracleUpdated(address indexed oldOracle, address indexed newOracle)
func (_CoreRelayer *CoreRelayerFilterer) FilterGasOracleUpdated(opts *bind.FilterOpts, oldOracle []common.Address, newOracle []common.Address) (*CoreRelayerGasOracleUpdatedIterator, error) {

	var oldOracleRule []interface{}
	for _, oldOracleItem := range oldOracle {
		oldOracleRule = append(oldOracleRule, oldOracleItem)
	}
	var newOracleRule []interface{}
	for _, newOracleItem := range newOracle {
		newOracleRule = append(newOracleRule, newOracleItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "GasOracleUpdated", oldOracleRule, newOracleRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerGasOracleUpdatedIterator{contract: _CoreRelayer.contract, event: "GasOracleUpdated", logs: logs, sub: sub}, nil
}

// WatchGasOracleUpdated is a free log subscription operation binding the contract event 0x73832aa215e2812d2f0c40bd0cf9df82495d3a46da4be338a17d63fb20e108f9.
//
// Solidity: event GasOracleUpdated(address indexed oldOracle, address indexed newOracle)
func (_CoreRelayer *CoreRelayerFilterer) WatchGasOracleUpdated(opts *bind.WatchOpts, sink chan<- *CoreRelayerGasOracleUpdated, oldOracle []common.Address, newOracle []common.Address) (event.Subscription, error) {

	var oldOracleRule []interface{}
	for _, oldOracleItem := range oldOracle {
		oldOracleRule = append(oldOracleRule, oldOracleItem)
	}
	var newOracleRule []interface{}
	for _, newOracleItem := range newOracle {
		newOracleRule = append(newOracleRule, newOracleItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "GasOracleUpdated", oldOracleRule, newOracleRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerGasOracleUpdated)
				if err := _CoreRelayer.contract.UnpackLog(event, "GasOracleUpdated", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseGasOracleUpdated is a log parse operation binding the contract event 0x73832aa215e2812d2f0c40bd0cf9df82495d3a46da4be338a17d63fb20e108f9.
//
// Solidity: event GasOracleUpdated(address indexed oldOracle, address indexed newOracle)
func (_CoreRelayer *CoreRelayerFilterer) ParseGasOracleUpdated(log types.Log) (*CoreRelayerGasOracleUpdated, error) {
	event := new(CoreRelayerGasOracleUpdated)
	if err := _CoreRelayer.contract.UnpackLog(event, "GasOracleUpdated", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerOwnershipTransferedIterator is returned from FilterOwnershipTransfered and is used to iterate over the raw logs and unpacked data for OwnershipTransfered events raised by the CoreRelayer contract.
type CoreRelayerOwnershipTransferedIterator struct {
	Event *CoreRelayerOwnershipTransfered // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerOwnershipTransferedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerOwnershipTransfered)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerOwnershipTransfered)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerOwnershipTransferedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerOwnershipTransferedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerOwnershipTransfered represents a OwnershipTransfered event raised by the CoreRelayer contract.
type CoreRelayerOwnershipTransfered struct {
	OldOwner common.Address
	NewOwner common.Address
	Raw      types.Log // Blockchain specific contextual infos
}

// FilterOwnershipTransfered is a free log retrieval operation binding the contract event 0x0d18b5fd22306e373229b9439188228edca81207d1667f604daf6cef8aa3ee67.
//
// Solidity: event OwnershipTransfered(address indexed oldOwner, address indexed newOwner)
func (_CoreRelayer *CoreRelayerFilterer) FilterOwnershipTransfered(opts *bind.FilterOpts, oldOwner []common.Address, newOwner []common.Address) (*CoreRelayerOwnershipTransferedIterator, error) {

	var oldOwnerRule []interface{}
	for _, oldOwnerItem := range oldOwner {
		oldOwnerRule = append(oldOwnerRule, oldOwnerItem)
	}
	var newOwnerRule []interface{}
	for _, newOwnerItem := range newOwner {
		newOwnerRule = append(newOwnerRule, newOwnerItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "OwnershipTransfered", oldOwnerRule, newOwnerRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerOwnershipTransferedIterator{contract: _CoreRelayer.contract, event: "OwnershipTransfered", logs: logs, sub: sub}, nil
}

// WatchOwnershipTransfered is a free log subscription operation binding the contract event 0x0d18b5fd22306e373229b9439188228edca81207d1667f604daf6cef8aa3ee67.
//
// Solidity: event OwnershipTransfered(address indexed oldOwner, address indexed newOwner)
func (_CoreRelayer *CoreRelayerFilterer) WatchOwnershipTransfered(opts *bind.WatchOpts, sink chan<- *CoreRelayerOwnershipTransfered, oldOwner []common.Address, newOwner []common.Address) (event.Subscription, error) {

	var oldOwnerRule []interface{}
	for _, oldOwnerItem := range oldOwner {
		oldOwnerRule = append(oldOwnerRule, oldOwnerItem)
	}
	var newOwnerRule []interface{}
	for _, newOwnerItem := range newOwner {
		newOwnerRule = append(newOwnerRule, newOwnerItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "OwnershipTransfered", oldOwnerRule, newOwnerRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerOwnershipTransfered)
				if err := _CoreRelayer.contract.UnpackLog(event, "OwnershipTransfered", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseOwnershipTransfered is a log parse operation binding the contract event 0x0d18b5fd22306e373229b9439188228edca81207d1667f604daf6cef8aa3ee67.
//
// Solidity: event OwnershipTransfered(address indexed oldOwner, address indexed newOwner)
func (_CoreRelayer *CoreRelayerFilterer) ParseOwnershipTransfered(log types.Log) (*CoreRelayerOwnershipTransfered, error) {
	event := new(CoreRelayerOwnershipTransfered)
	if err := _CoreRelayer.contract.UnpackLog(event, "OwnershipTransfered", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}

// CoreRelayerUpgradedIterator is returned from FilterUpgraded and is used to iterate over the raw logs and unpacked data for Upgraded events raised by the CoreRelayer contract.
type CoreRelayerUpgradedIterator struct {
	Event *CoreRelayerUpgraded // Event containing the contract specifics and raw log

	contract *bind.BoundContract // Generic contract to use for unpacking event data
	event    string              // Event name to use for unpacking event data

	logs chan types.Log        // Log channel receiving the found contract events
	sub  ethereum.Subscription // Subscription for errors, completion and termination
	done bool                  // Whether the subscription completed delivering logs
	fail error                 // Occurred error to stop iteration
}

// Next advances the iterator to the subsequent event, returning whether there
// are any more events found. In case of a retrieval or parsing error, false is
// returned and Error() can be queried for the exact failure.
func (it *CoreRelayerUpgradedIterator) Next() bool {
	// If the iterator failed, stop iterating
	if it.fail != nil {
		return false
	}
	// If the iterator completed, deliver directly whatever's available
	if it.done {
		select {
		case log := <-it.logs:
			it.Event = new(CoreRelayerUpgraded)
			if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
				it.fail = err
				return false
			}
			it.Event.Raw = log
			return true

		default:
			return false
		}
	}
	// Iterator still in progress, wait for either a data or an error event
	select {
	case log := <-it.logs:
		it.Event = new(CoreRelayerUpgraded)
		if err := it.contract.UnpackLog(it.Event, it.event, log); err != nil {
			it.fail = err
			return false
		}
		it.Event.Raw = log
		return true

	case err := <-it.sub.Err():
		it.done = true
		it.fail = err
		return it.Next()
	}
}

// Error returns any retrieval or parsing error occurred during filtering.
func (it *CoreRelayerUpgradedIterator) Error() error {
	return it.fail
}

// Close terminates the iteration process, releasing any pending underlying
// resources.
func (it *CoreRelayerUpgradedIterator) Close() error {
	it.sub.Unsubscribe()
	return nil
}

// CoreRelayerUpgraded represents a Upgraded event raised by the CoreRelayer contract.
type CoreRelayerUpgraded struct {
	Implementation common.Address
	Raw            types.Log // Blockchain specific contextual infos
}

// FilterUpgraded is a free log retrieval operation binding the contract event 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b.
//
// Solidity: event Upgraded(address indexed implementation)
func (_CoreRelayer *CoreRelayerFilterer) FilterUpgraded(opts *bind.FilterOpts, implementation []common.Address) (*CoreRelayerUpgradedIterator, error) {

	var implementationRule []interface{}
	for _, implementationItem := range implementation {
		implementationRule = append(implementationRule, implementationItem)
	}

	logs, sub, err := _CoreRelayer.contract.FilterLogs(opts, "Upgraded", implementationRule)
	if err != nil {
		return nil, err
	}
	return &CoreRelayerUpgradedIterator{contract: _CoreRelayer.contract, event: "Upgraded", logs: logs, sub: sub}, nil
}

// WatchUpgraded is a free log subscription operation binding the contract event 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b.
//
// Solidity: event Upgraded(address indexed implementation)
func (_CoreRelayer *CoreRelayerFilterer) WatchUpgraded(opts *bind.WatchOpts, sink chan<- *CoreRelayerUpgraded, implementation []common.Address) (event.Subscription, error) {

	var implementationRule []interface{}
	for _, implementationItem := range implementation {
		implementationRule = append(implementationRule, implementationItem)
	}

	logs, sub, err := _CoreRelayer.contract.WatchLogs(opts, "Upgraded", implementationRule)
	if err != nil {
		return nil, err
	}
	return event.NewSubscription(func(quit <-chan struct{}) error {
		defer sub.Unsubscribe()
		for {
			select {
			case log := <-logs:
				// New log arrived, parse the event and forward to the user
				event := new(CoreRelayerUpgraded)
				if err := _CoreRelayer.contract.UnpackLog(event, "Upgraded", log); err != nil {
					return err
				}
				event.Raw = log

				select {
				case sink <- event:
				case err := <-sub.Err():
					return err
				case <-quit:
					return nil
				}
			case err := <-sub.Err():
				return err
			case <-quit:
				return nil
			}
		}
	}), nil
}

// ParseUpgraded is a log parse operation binding the contract event 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b.
//
// Solidity: event Upgraded(address indexed implementation)
func (_CoreRelayer *CoreRelayerFilterer) ParseUpgraded(log types.Log) (*CoreRelayerUpgraded, error) {
	event := new(CoreRelayerUpgraded)
	if err := _CoreRelayer.contract.UnpackLog(event, "Upgraded", log); err != nil {
		return nil, err
	}
	event.Raw = log
	return event, nil
}
