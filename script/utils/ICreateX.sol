// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.8 <0.9.0;

/// @title Minimal CreateX Factory Interface
/// @notice Subset of the CreateX factory deployed at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed on all chains
/// @dev See https://github.com/pcaversaccio/createx
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress);
    function computeCreate3Address(bytes32 salt) external view returns (address computedAddress);
}
