// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IManagerBase} from "@wormhole-foundation/native_token_transfer/interfaces/IManagerBase.sol";
import {NttManagerUpgradeable} from "../src/NTT/NttManagerUpgradeable.sol";

import {NttConstants} from "../utils/constants.sol";
import {GnosisHelpers} from "./utils/GnosisHelpers.sol";

contract UpgradeNttAndTransfer is Test, NttConstants, GnosisHelpers {

    uint256 constant SMALL_TRANSFER = 1_000 ether;
    uint256 constant MEDIUM_TRANSFER = 50_000 ether;
    uint256 constant LARGE_TRANSFER = 10_000_000 ether;

    string constant OUTPUT_PATH = "./output/3_upgrade_ntt_transfer_OFT/upgradeNttAndTransfer_mainnet.json";

    function run() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        NttManagerUpgradeable newImpl = new NttManagerUpgradeable(
            MAINNET_ETHFI,
            IManagerBase.Mode.LOCKING,
            MAINNET_WORMHOLE_ID,
            uint64(RATE_LIMIT_DURATION),
            false
        );

        _generateJson(address(newImpl));
        _testOnFork();
    }

    function _generateJson(address newImpl) internal {
        string memory nttManagerHex = addressToHex(MAINNET_NTT_MANAGER);
        string memory transactions = _getGnosisHeader("1", addressToHex(MAINNET_CONTRACT_CONTROLLER));

        bytes memory upgradeData = abi.encodeWithSignature("upgrade(address)", newImpl);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(nttManagerHex, iToHex(upgradeData), "0", false)
        );

        bytes memory setAdapterData = abi.encodeWithSignature("setOftAdapter(address)", MAINNET_OFT);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(nttManagerHex, iToHex(setAdapterData), "0", false)
        );

        bytes memory smallTransferData = abi.encodeWithSignature("transferToOftAdapter(uint256)", SMALL_TRANSFER);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(nttManagerHex, iToHex(smallTransferData), "0", false)
        );

        bytes memory mediumTransferData = abi.encodeWithSignature("transferToOftAdapter(uint256)", MEDIUM_TRANSFER);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(nttManagerHex, iToHex(mediumTransferData), "0", false)
        );

        bytes memory largeTransferData = abi.encodeWithSignature("transferToOftAdapter(uint256)", LARGE_TRANSFER);
        transactions = string.concat(
            transactions,
            _getGnosisTransaction(nttManagerHex, iToHex(largeTransferData), "0", true)
        );

        vm.writeFile(OUTPUT_PATH, transactions);
        console.log("Upgrade + transfer transactions written to", OUTPUT_PATH);
    }

    function _testOnFork() internal {
        IERC20 ethfi = IERC20(MAINNET_ETHFI);

        uint256 managerBalanceBefore = ethfi.balanceOf(MAINNET_NTT_MANAGER);
        uint256 oftBalanceBefore = ethfi.balanceOf(MAINNET_OFT);
        uint256 totalTransfer = SMALL_TRANSFER + MEDIUM_TRANSFER + LARGE_TRANSFER;

        console.log("NTT Manager ETHFI balance before:", managerBalanceBefore);
        require(managerBalanceBefore >= totalTransfer, "NTT Manager has insufficient ETHFI balance");

        executeGnosisTransactionBundle(OUTPUT_PATH);

        NttManagerUpgradeable upgraded = NttManagerUpgradeable(MAINNET_NTT_MANAGER);
        require(upgraded.getOftAdapter() == MAINNET_OFT, "OFT adapter not set correctly");

        uint256 managerBalanceAfter = ethfi.balanceOf(MAINNET_NTT_MANAGER);
        uint256 oftBalanceAfter = ethfi.balanceOf(MAINNET_OFT);

        require(
            managerBalanceAfter == managerBalanceBefore - totalTransfer,
            "NTT Manager balance mismatch"
        );
        require(
            oftBalanceAfter == oftBalanceBefore + totalTransfer,
            "OFT adapter balance mismatch"
        );

        console.log("NTT Manager ETHFI balance after:", managerBalanceAfter);
        console.log("OFT adapter ETHFI balance after:", oftBalanceAfter);
        console.log("Upgrade and transfer verified successfully");
    }
}
