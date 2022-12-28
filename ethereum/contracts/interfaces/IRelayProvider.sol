// contracts/Messages.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IRelayProvider {

    
    function quoteDeliveryOverhead(uint16 targetChain) external view returns (uint256 deliveryOverhead);

    function quoteRedeliveryOverhead(uint16 targetChain) external view returns (uint256 redeliveryOverhead);

    function quoteGasPrice(uint16 targetChain) external view returns (uint256 gasPriceSource);

    function quoteAssetPrice(uint16 chainId) external view returns (uint256 usdPrice);

    // should this have source chain as a parameter, or default to current chain id?
    function assetConversionBuffer(uint16 sourceChain, uint16 targetChain) external view returns (uint16 tolerance, uint16 toleranceDenominator);

    // should this have target chain as a parameter, or default to current chain id?
    //This function must be invertible in order to be considered compliant.
    // revise: There seems to be no need for the provider to provide quotes that don't include chainId() as one of the source or target chain?
    //I.E quoteAssetConversion(targetChain, quoteAssetConversion(sourceChain, sourceAmount, targetChain), sourceChain) == sourceAmount;
    function quoteAssetConversion(uint16 sourceChain, uint256 sourceAmount, uint16 targetChain) external view returns (uint256 targetAmount);

    //In order to be compliant, this must return an amount larger than both
    // quoteDeliveryOverhead(targetChain) and quoteRedeliveryOverhead(targetChain)
    function quoteMaximumBudget(uint16 targetChain) external view returns (uint256 maximumTargetBudget);

    //If this returns 0, the targetChain will be considered unsupported.
    //Otherwise, the delivery on the target chain (msg.sender) must equal this address.
    function getDeliveryAddress(uint16 targetChain) external view returns (bytes32 whAddress);

    function getRewardAddress() external view returns (address rewardAddress);

    function getConsistencyLevel() external view returns (uint8 consistencyLevel);

}
