// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MintBurnOFTAdapter} from "@layerzerolabs/oft-evm/contracts/MintBurnOFTAdapter.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";

/// @title EtherfiMintBurnOFTAdapter
/// @notice A concrete MintBurnOFTAdapter for the EthfiL2Token that uses mint/burn for cross-chain transfers
/// @dev This adapter is used on L2 chains where the EthfiL2Token implements IMintableBurnable.
///      Unlike the lock/unlock OFTAdapter, this burns tokens on send and mints on receive.
///      The token and minterBurner can be the same address since EthfiL2Token implements IMintableBurnable.
contract EtherfiMintBurnOFTAdapter is MintBurnOFTAdapter {
    /// @notice Initializes the EtherfiMintBurnOFTAdapter
    /// @param _token The address of the EthfiL2Token
    /// @param _minterBurner The contract implementing IMintableBurnable (can be same as _token)
    /// @param _lzEndpoint The LayerZero endpoint address
    /// @param _delegate The address that will own the adapter and be the LayerZero delegate
    constructor(
        address _token,
        IMintableBurnable _minterBurner,
        address _lzEndpoint,
        address _delegate
    ) MintBurnOFTAdapter(_token, _minterBurner, _lzEndpoint, _delegate) Ownable(_delegate) {}
}
