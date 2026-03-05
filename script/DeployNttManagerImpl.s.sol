// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {IManagerBase} from "@wormhole-foundation/native_token_transfer/interfaces/IManagerBase.sol";
import {NttManagerUpgradeable} from "../src/NTT/NttManagerUpgradeable.sol";
import {NttConstants} from "../utils/constants.sol";

contract DeployNttManagerImpl is Script, NttConstants {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        NttManagerUpgradeable impl = new NttManagerUpgradeable(
            MAINNET_ETHFI,
            IManagerBase.Mode.LOCKING,
            MAINNET_WORMHOLE_ID,
            uint64(RATE_LIMIT_DURATION),
            false
        );
        console.log("NttManagerUpgradeable impl deployed at:", address(impl));

        vm.stopBroadcast();
    }
}
