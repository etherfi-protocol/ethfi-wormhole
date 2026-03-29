// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @title EtherfiOFTAdapterUpgradeable
/// @notice OFTAdapter uses a deployed ERC-20 token and SafeERC20 to interact with the OFTCore contract.
/// @dev This adapter enables cross-chain token transfers via LayerZero with pause functionality and role-based access control.
contract EtherfiOFTAdapterUpgradeable is OFTAdapterUpgradeable, UUPSUpgradeable, AccessControlEnumerableUpgradeable, PausableUpgradeable {
    /// @notice Role identifier for accounts that can pause the bridge
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Role identifier for accounts that can unpause the bridge
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the specified owner
    /// @param _owner The address that will be granted the default admin role and ownership
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __OFTAdapter_init(_owner);
        __AccessControlEnumerable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /// @notice Internal function to handle token debits with pause check
    /// @param _from The address to debit tokens from
    /// @param _amountLD The amount to debit in local decimals
    /// @param _minAmountLD The minimum amount expected in local decimals
    /// @param _dstEid The destination endpoint ID
    /// @return amountSentLD The amount actually sent in local decimals
    /// @return amountReceivedLD The amount that will be received on the destination in local decimals
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /// @notice Internal function to handle token credits with pause check
    /// @param _to The address to credit tokens to
    /// @param _amountLD The amount to credit in local decimals
    /// @param _srcEid The source endpoint ID
    /// @return amountReceivedLD The amount actually received in local decimals
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
        return super._credit(_to, _amountLD, _srcEid);
    }

    /// @notice Pauses the bridge, preventing debit and credit operations
    /// @dev Can only be called by accounts with the PAUSER_ROLE
    function pauseBridge() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the bridge, allowing debit and credit operations
    /// @dev Can only be called by accounts with the UNPAUSER_ROLE
    function unpauseBridge() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /// @notice Authorizes contract upgrades
    /// @param _newImplementation The address of the new implementation
    /// @dev Can only be called by accounts with the DEFAULT_ADMIN_ROLE
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
