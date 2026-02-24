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

    string constant OUTPUT_DIR = "./output/3_upgrade_ntt_transfer_OFT/";
    string constant UPGRADE_PATH = "./output/3_upgrade_ntt_transfer_OFT/upgradeNtt_mainnet.json";
    string constant TRANSFER_SMALL_PATH = "./output/3_upgrade_ntt_transfer_OFT/transfer_small_mainnet.json";
    string constant TRANSFER_MEDIUM_PATH = "./output/3_upgrade_ntt_transfer_OFT/transfer_medium_mainnet.json";
    string constant TRANSFER_LARGE_PATH = "./output/3_upgrade_ntt_transfer_OFT/transfer_large_mainnet.json";

    function run() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        NttManagerUpgradeable newImpl = new NttManagerUpgradeable(
            MAINNET_ETHFI,
            IManagerBase.Mode.LOCKING,
            MAINNET_WORMHOLE_ID,
            uint64(RATE_LIMIT_DURATION),
            false
        );

        _generateUpgradeJson(address(newImpl));
        _generateTransferJsons();
        _testOnFork();
    }

    function _generateUpgradeJson(address newImpl) internal {
        string memory nttManagerHex = addressToHex(MAINNET_NTT_MANAGER);
        string memory header = _getGnosisHeader("1", addressToHex(MAINNET_CONTRACT_CONTROLLER));

        bytes memory upgradeData = abi.encodeWithSignature("upgrade(address)", newImpl);
        bytes memory setAdapterData = abi.encodeWithSignature("setOftAdapter(address)", OFT);

        string memory bundle = string.concat(
            header,
            _getGnosisTransaction(nttManagerHex, iToHex(upgradeData), "0", false),
            _getGnosisTransaction(nttManagerHex, iToHex(setAdapterData), "0", true)
        );

        vm.writeFile(UPGRADE_PATH, bundle);
        console.log("Upgrade bundle written to", UPGRADE_PATH);
    }

    function _generateTransferJsons() internal {
        string memory nttManagerHex = addressToHex(MAINNET_NTT_MANAGER);
        string memory header = _getGnosisHeader("1", addressToHex(MAINNET_CONTRACT_CONTROLLER));

        _writeTransferJson(header, nttManagerHex, SMALL_TRANSFER, TRANSFER_SMALL_PATH);
        _writeTransferJson(header, nttManagerHex, MEDIUM_TRANSFER, TRANSFER_MEDIUM_PATH);
        _writeTransferJson(header, nttManagerHex, LARGE_TRANSFER, TRANSFER_LARGE_PATH);
    }

    function _writeTransferJson(string memory header, string memory nttManagerHex, uint256 amount, string memory path) internal {
        bytes memory data = abi.encodeWithSignature("transferToOftAdapter(uint256)", amount);
        string memory tx = string.concat(
            header,
            _getGnosisTransaction(nttManagerHex, iToHex(data), "0", true)
        );
        vm.writeFile(path, tx);
        console.log("Transfer transaction written to", path);
    }

    function _testOnFork() internal {
        IERC20 ethfi = IERC20(MAINNET_ETHFI);

        uint256 managerBalanceBefore = ethfi.balanceOf(MAINNET_NTT_MANAGER);
        uint256 oftBalanceBefore = ethfi.balanceOf(OFT);
        uint256 totalTransfer = SMALL_TRANSFER + MEDIUM_TRANSFER + LARGE_TRANSFER;

        console.log("NTT Manager ETHFI balance before:", managerBalanceBefore);
        require(managerBalanceBefore >= totalTransfer, "NTT Manager has insufficient ETHFI balance");

        executeGnosisTransactionBundle(UPGRADE_PATH);

        NttManagerUpgradeable upgraded = NttManagerUpgradeable(MAINNET_NTT_MANAGER);
        require(upgraded.getOftAdapter() == OFT, "OFT adapter not set correctly");

        executeGnosisTransactionBundle(TRANSFER_SMALL_PATH);
        executeGnosisTransactionBundle(TRANSFER_MEDIUM_PATH);
        executeGnosisTransactionBundle(TRANSFER_LARGE_PATH);

        uint256 managerBalanceAfter = ethfi.balanceOf(MAINNET_NTT_MANAGER);
        uint256 oftBalanceAfter = ethfi.balanceOf(OFT);

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
