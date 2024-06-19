// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {EthfiL2Token} from "../src/token/EthFiL2Token.sol";

// =============== Deployment Constants ================================================
string constant TOKEN_SYMBOL = "ETHFI";
string constant TOKEN_NAME = "ether.fi governance token";
// =====================================================================================

contract DeployEthfiL2 is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);
        
        bytes32 SALT = keccak256(abi.encodePacked(deployer, TOKEN_NAME, TOKEN_SYMBOL));

        EthfiL2Token impl = new EthfiL2Token{salt: SALT}();
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(address(impl), "");
        EthfiL2Token token = EthfiL2Token(address(proxy));
        token.initialize(TOKEN_NAME, TOKEN_SYMBOL, deployer);

        console.log("Ethfi L2 token impl deployed at:", address(impl));
        console.log("Ethfi L2 token proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
