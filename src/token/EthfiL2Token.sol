// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {OwnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from 
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {UUPSUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {INttToken} from "@wormhole-foundation/native_token_transfer/interfaces/INttToken.sol";

/// @title EthfiL2Token
/// @notice A UUPS upgradeable token with access controlled minting and burning.
contract EthfiL2Token is
    INttToken,
    UUPSUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20VotesUpgradeable,
    OwnableUpgradeable
{
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

    /// @notice A function that will burn tokens held by the `msg.sender`.
    /// @param _value The amount of tokens to be burned.
    function burn(uint256 _value) public override(INttToken, ERC20BurnableUpgradeable) onlyMinter {
        ERC20BurnableUpgradeable.burn(_value);
    }

    /// @notice This method is not implemented and should not be called.
    function burnFrom(address, uint256) public pure override {
        revert UnimplementedMethod();
    }

    /// @notice A function that mints new tokens to a specific account.
    /// @param _account The address where new tokens will be minted.
    /// @param _amount The amount of new tokens that will be minted.
    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    function _authorizeUpgrade(address /* newImplementation */ ) internal view override onlyOwner {}

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }
}
