// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTUpgradeable as OFTUpgradeableBase} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract OFTUpgradeable is OFTUpgradeableBase, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeableBase(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _owner) public initializer {
        __OFT_init(_name, _symbol, _owner);
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
