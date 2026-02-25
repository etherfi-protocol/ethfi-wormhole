// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";
import {ICreateX} from "./utils/ICreateX.sol";

contract DeployL2Token is Script {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    bytes32 internal constant DEPLOY_SALT = keccak256("ethfi-l2-token-v2");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        address predicted = CREATEX.computeCreate3Address(DEPLOY_SALT, deployer);
        console.log("Predicted address:", predicted);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory initCode = type(EthfiL2Token).creationCode;
        address impl = CREATEX.deployCreate3(DEPLOY_SALT, initCode);
        console.log("Implementation deployed at:", impl);

        vm.stopBroadcast();
    }
}
