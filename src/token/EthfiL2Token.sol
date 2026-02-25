// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {Ownable2StepUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC20Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from 
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {UUPSUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";

/// @title EthfiL2Token
/// @notice A UUPS upgradeable token with access controlled minting and burning.
/// @dev Implements IMintableBurnable for LayerZero OFT cross-chain compatibility.
contract EthfiL2Token is
    IMintableBurnable,
    UUPSUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20VotesUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    // =============== Constants ==============================================================

    /// @notice Role identifier for accounts that can pause the token
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role identifier for accounts that can unpause the token
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    // =============== Errors & Events ========================================================

    /// @notice Error when the caller is not the minter.
    /// @param caller The caller of the function.
    error CallerNotMinter(address caller);

    /// @notice Error when the minter is the zero address.
    error InvalidMinterZeroAddress();

    /// @notice The minter has been changed.
    /// @param previousMinter The previous minter address.
    /// @param newMinter The new minter address.
    event NewMinter(address previousMinter, address newMinter);

    // =============== Public Functions =======================================================

    /// @dev Increases the allowance granted to `_spender` by the caller.
    function increaseAllowance(address _spender, uint256 _increaseAmount) external returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, _spender);
        _approve(owner, _spender,currentAllowance + _increaseAmount);
        return true;
    }

    /// @dev decreases the allowance granted to `_spender` by the caller.
    function decreaseAllowance(address _spender, uint256 _decreaseAmount) external returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, _spender);
        require(currentAllowance >= _decreaseAmount, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, _spender, currentAllowance - _decreaseAmount);
        }
        return true;
    }

    // =============== Storage ==============================================================

    struct MinterStorage {
        address _minter;
    }

    bytes32 private constant MINTER_SLOT = bytes32(uint256(keccak256("ethfi.minter")) - 1);

    // =============== Storage Getters/Setters ==============================================

    function _getMinterStorage() internal pure returns (MinterStorage storage $) {
        uint256 slot = uint256(MINTER_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// @notice A function to set the new minter for the tokens.
    /// @param newMinter The address to add as both a minter and burner.
    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) {
            revert InvalidMinterZeroAddress();
        }
        address previousMinter = _getMinterStorage()._minter;
        _getMinterStorage()._minter = newMinter;
        emit NewMinter(previousMinter, newMinter);
    }

    /// @dev Returns the address of the current minter.
    function minter() public view returns (address) {
        MinterStorage storage $ = _getMinterStorage();
        return $._minter;
    }

    /// @dev Throws if called by any account other than the minter.
    modifier onlyMinter() {
        if (minter() != _msgSender()) {
            revert CallerNotMinter(_msgSender());
        }
        _;
    }

    /// @dev An error thrown when a method is not implemented.
    error UnimplementedMethod();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice A one-time configuration method meant to be called immediately upon the deployment of `EthfiL2Token`. It sets
    /// up the token's name, symbol, and owner
    function initialize(
        string memory _name,
        string memory _symbol,
        address _owner
    ) external initializer {
        // OpenZeppelin upgradeable contracts documentation says:
        //
        // "Use with multiple inheritance requires special care. Initializer
        // functions are not linearized by the compiler like constructors.
        // Because of this, each __{ContractName}_init function embeds the
        // linearized calls to all parent initializers. As a consequence,
        // calling two of these init functions can potentially initialize the
        // same contract twice."
        //
        // Note that ERC20 extensions do not linearize calls to ERC20Upgradeable
        // initializer so we call all extension initializers individually.
        __ERC20_init(_name, _symbol);
        __Ownable_init(_owner);

        // These initializers don't do anything, so we won't call them
        // __ERC20Burnable_init();
        // __UUPSUpgradeable_init();
    }

    /// @notice V2 initialization to add AccessControl and Pausable functionality for OFT migration
    /// @dev Must be called via upgradeToAndCall during the upgrade to V2
    /// @dev Grants DEFAULT_ADMIN_ROLE to the current owner
    function initializeV2() external reinitializer(2) {
        __AccessControlEnumerable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner());
    }

    // =============== Pause Functions ========================================================

    /// @notice Pauses the token, preventing transfers
    /// @dev Can only be called by accounts with the PAUSER_ROLE
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the token, allowing transfers
    /// @dev Can only be called by accounts with the UNPAUSER_ROLE
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /// @notice A function that will burn tokens held by the `msg.sender`.
    /// @param _from The address from which the tokens will be burned.
    /// @param _amount The amount of tokens to be burned.
    /// @dev Can only be called when not paused
    function burn(address _from, uint256 _amount) external onlyMinter whenNotPaused returns (bool) {
        _burn(_from, _amount);
        return true;
    }

    /// @notice This method is not implemented and should not be called.
    function burnFrom(address, uint256) public pure override {
        revert UnimplementedMethod();
    }

    /// @notice A function that mints new tokens to a specific account.
    /// @param _to The address where new tokens will be minted.
    /// @param _amount The amount of new tokens that will be minted.
    /// @dev Can only be called when not paused
    function mint(address _to, uint256 _amount) external onlyMinter whenNotPaused returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function _authorizeUpgrade(address /* newImplementation */ ) internal view override onlyOwner {}

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }
}
