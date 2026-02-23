// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {NttManager, toWormholeFormat} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "../lib/example-native-token-transfers/evm/src/libraries/PausableUpgradeable.sol";

import {NttConstants} from "../utils/constants.sol";
import {GnosisHelpers} from "./utils/GnosisHelpers.sol";

contract PauseNttManagers is Test, NttConstants, GnosisHelpers {

    struct ChainConfig {
        string chainId;
        string rpc;
        address controller;
        address nttManager;
        address token;
        uint16 peerChainId;
        string name;
    }

    function run() public {
        ChainConfig[4] memory chains = [
            ChainConfig("1", "https://eth-mainnet.public.blastapi.io", MAINNET_CONTRACT_CONTROLLER, MAINNET_NTT_MANAGER, MAINNET_ETHFI, ARB_WORMHOLE_ID, "mainnet"),
            ChainConfig("42161", "https://arbitrum-one.public.blastapi.io", ARB_CONTRACT_CONTROLLER, ARB_NTT_MANAGER, ARB_ETHFI, MAINNET_WORMHOLE_ID, "arbitrum"),
            ChainConfig("8453", "https://mainnet.base.org", BASE_CONTRACT_CONTROLLER, BASE_NTT_MANAGER, BASE_ETHFI, MAINNET_WORMHOLE_ID, "base"),
            ChainConfig("534352", "https://rpc.scroll.io", SCROLL_CONTRACT_CONTROLLER, SCROLL_NTT_MANAGER, SCROLL_ETHFI, MAINNET_WORMHOLE_ID, "scroll")
        ];

        for (uint256 i = 0; i < chains.length; i++) {
            string memory path = string.concat("./output/1_pause_NTT/pauseNttManager_", chains[i].name, ".json");
            _generatePauseJson(chains[i], path);
            _testPauseOnFork(chains[i], path);
        }
    }

    function _generatePauseJson(ChainConfig memory chain, string memory path) internal {
        string memory transactions = _getGnosisHeader(chain.chainId, addressToHex(chain.controller));
        bytes memory pauseData = abi.encodeWithSignature("pause()");
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(addressToHex(chain.nttManager), iToHex(pauseData), "0", true)
        );

        vm.writeFile(path, transactions);
        console.log(string.concat(chain.name, " pause transaction written to ", path));
    }

    function _testPauseOnFork(ChainConfig memory chain, string memory path) internal {
        vm.createSelectFork(chain.rpc);

        NttManager nttManager = NttManager(chain.nttManager);
        require(!nttManager.isPaused(), string.concat(chain.name, " NTT Manager already paused"));

        _tryBridge(chain, true);

        executeGnosisTransactionBundle(path);

        require(nttManager.isPaused(), string.concat(chain.name, " NTT Manager failed to pause"));

        _tryBridge(chain, false);

        console.log(string.concat(chain.name, " pause verified: bridge works before, reverts after"));
    }

    function _tryBridge(ChainConfig memory chain, bool shouldSucceed) internal {
        address user = address(0xdead);
        uint256 amount = 1 ether;

        deal(chain.token, user, amount);
        vm.deal(user, 1 ether);

        NttManager nttManager = NttManager(chain.nttManager);
        (, uint256 fee) = nttManager.quoteDeliveryPrice(chain.peerChainId, new bytes(1));

        vm.startPrank(user);
        ERC20Upgradeable(chain.token).approve(chain.nttManager, amount);

        if (!shouldSucceed) {
            vm.expectRevert(PausableUpgradeable.RequireContractIsNotPaused.selector);
        }

        nttManager.transfer{value: fee}(
            amount, chain.peerChainId, toWormholeFormat(user)
        );

        vm.stopPrank();
    }
}
