// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EtherfiOFTAdapterUpgradeable} from "../../src/OFT/EtherfiOFTAdapterUpgradeable.sol";

/// @title EtherfiOFTAdapterUpgradeableV2Mock
/// @notice Mock V2 implementation for testing upgrades
contract EtherfiOFTAdapterUpgradeableV2Mock is EtherfiOFTAdapterUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _token,
        address _lzEndpoint
    ) EtherfiOFTAdapterUpgradeable(_token, _lzEndpoint) {}

    /// @notice Returns the version of this implementation
    function version() external pure returns (uint256) {
        return 2;
    }
}
