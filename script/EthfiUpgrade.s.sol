// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {EthfiL2Token} from "../src/token/EthFiL2Token.sol";

import {NttConstants} from "../utils/constants.sol";

contract UpgradeEthfiL2 is Script, NttConstants {
    
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        vm.startBroadcast(deployer);

        EthfiL2Token impl = new EthfiL2Token();

        EthfiL2Token tokenProxy = EthfiL2Token(payable(ARB_ETHFI));

        bytes memory data = "";
        tokenProxy.upgradeToAndCall(address(impl), data);
        vm.stopBroadcast();
    }
}