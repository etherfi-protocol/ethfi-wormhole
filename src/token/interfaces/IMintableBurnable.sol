// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/// @title IMintableBurnable
/// @notice OFT-compliant interface for mint and burn (including burnFrom) used by LayerZero OFT.
interface IMintableBurnable {
    /// @notice Mints `amount` tokens to `to`.
    /// @param to Address to receive minted tokens.
    /// @param amount Amount to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Burns `amount` tokens from `from` (e.g. when OFT sends cross-chain).
    /// @param from Address to burn tokens from.
    /// @param amount Amount to burn.
    function burnFrom(address from, uint256 amount) external;
}
