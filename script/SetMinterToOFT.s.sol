// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";

import {NttConstants} from "../utils/constants.sol";
import {GnosisHelpers} from "./utils/GnosisHelpers.sol";

contract SetMinterToOFT is Test, NttConstants, GnosisHelpers {

    struct ChainConfig {
        string chainId;
        string rpc;
        address controller;
        address token;
        address oft;
        string name;
    }

    function run() public {
        ChainConfig[3] memory chains = [
            ChainConfig("42161", "https://arbitrum-one.public.blastapi.io", ARB_CONTRACT_CONTROLLER, ARB_ETHFI, OFT, "arbitrum"),
            ChainConfig("8453", "https://mainnet.base.org", BASE_CONTRACT_CONTROLLER, BASE_ETHFI, OFT, "base"),
            ChainConfig("534352", "https://rpc.scroll.io", SCROLL_CONTRACT_CONTROLLER, SCROLL_ETHFI, OFT, "scroll")
        ];

        for (uint256 i = 0; i < chains.length; i++) {
            string memory path = string.concat("./output/2_set_minter_OFT/setMinter_", chains[i].name, ".json");
            _generateSetMinterJson(chains[i], path);
            _testSetMinterOnFork(chains[i], path);
        }
    }

    function _generateSetMinterJson(ChainConfig memory chain, string memory path) internal {
        string memory transactions = _getGnosisHeader(chain.chainId, addressToHex(chain.controller));
        bytes memory setMinterData = abi.encodeWithSignature("setMinter(address)", chain.oft);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(addressToHex(chain.token), iToHex(setMinterData), "0", true)
        );

        vm.writeFile(path, transactions);
        console.log(string.concat(chain.name, " setMinter transaction written to ", path));
    }

    function _testSetMinterOnFork(ChainConfig memory chain, string memory path) internal {
        vm.createSelectFork(chain.rpc);

        EthfiL2Token token = EthfiL2Token(chain.token);
        address currentMinter = token.minter();
        console.log(string.concat(chain.name, " current minter:"));
        console.log(currentMinter);

        executeGnosisTransactionBundle(path);

        require(token.minter() == chain.oft, string.concat(chain.name, " minter not set to OFT"));
        console.log(string.concat(chain.name, " minter set to OFT successfully"));
    }
}
