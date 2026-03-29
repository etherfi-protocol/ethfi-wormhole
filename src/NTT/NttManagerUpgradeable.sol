// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {NttManager} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract NttManagerUpgradeable is NttManager {
    using SafeERC20 for IERC20;

    // =============== Events ===============================================================

    event OftAdapterSet(address indexed oldAdapter, address indexed newAdapter);
    event TokensTransferredToOftAdapter(address indexed adapter, uint256 amount);

    // =============== Errors ===============================================================

    error OftAdapterNotSet();
    error InvalidOftAdapter();

    // =============== Storage ==============================================================

    bytes32 private constant OFT_ADAPTER_SLOT = bytes32(uint256(keccak256("ntt.oftAdapter")) - 1);

    // =============== Constructor ==========================================================

    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration,
        bool skipRateLimiting
    ) NttManager(token, mode, chainId, rateLimitDuration, skipRateLimiting) {}


    // =============== Storage Getters/Setters ==============================================

    function _getOftAdapterStorage() private pure returns (bytes32 slot) {
        return OFT_ADAPTER_SLOT;
    }

    function _getOftAdapter() internal view returns (address adapter) {
        bytes32 slot = _getOftAdapterStorage();
        assembly ("memory-safe") {
            adapter := sload(slot)
        }
    }

    function _setOftAdapter(address adapter) internal {
        bytes32 slot = _getOftAdapterStorage();
        assembly ("memory-safe") {
            sstore(slot, adapter)
        }
    }

    // =============== Public Getters =======================================================

    function getOftAdapter() external view returns (address) {
        return _getOftAdapter();
    }

    // =============== Admin ================================================================

    /// @notice Set the OFT adapter address for token migration
    /// @param adapter The address of the new OFT adapter
    function setOftAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) {
            revert InvalidOftAdapter();
        }
        address oldAdapter = _getOftAdapter();
        _setOftAdapter(adapter);
        emit OftAdapterSet(oldAdapter, adapter);
    }

    /// @notice Transfer tokens to the OFT adapter
    /// @param amount The amount of tokens to transfer
    function transferToOftAdapter(uint256 amount) external onlyOwner {
        address adapter = _getOftAdapter();
        if (adapter == address(0)) {
            revert OftAdapterNotSet();
        }
        IERC20(token).safeTransfer(adapter, amount);
        emit TokensTransferredToOftAdapter(adapter, amount);
    }

    // =============== Migration ============================================================

    /// @dev Turns on the capability to EDIT the immutables
    function _migrate() internal override {
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
        _setMigratesImmutables(true);
    }
}
