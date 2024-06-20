// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {NttManager} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";

contract NttManagerUpgradeable is NttManager {
    // Call the parents constructor
    constructor(
        address token,
        Mode mode,
        uint16 chainId,
        uint64 rateLimitDuration,
        bool skipRateLimiting
    ) NttManager(token, mode, chainId, rateLimitDuration, skipRateLimiting) {}

    // Turns on the capability to EDIT the immutables
    function _migrate() internal override {
        _checkThresholdInvariants();
        _checkTransceiversInvariants();
        _setMigratesImmutables(true);
    }
}
