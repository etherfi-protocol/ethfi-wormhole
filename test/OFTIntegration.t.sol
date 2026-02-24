// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {ILayerZeroReceiver} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import {IManagerBase} from "@wormhole-foundation/native_token_transfer/interfaces/IManagerBase.sol";

import {NttManagerUpgradeable} from "../src/NTT/NttManagerUpgradeable.sol";
import {NttConstants} from "../utils/constants.sol";
import {GnosisHelpers} from "../script/utils/GnosisHelpers.sol";

contract OFTIntegrationTest is Test, NttConstants, GnosisHelpers {
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    bytes32 constant PEER = bytes32(uint256(uint160(0xe0080d2F853ecDdbd81A643dC10DA075Df26fD3f)));

    uint32 constant MAINNET_EID = 30101;
    uint32 constant ARB_EID = 30110;
    uint32 constant BASE_EID = 30184;
    uint32 constant SCROLL_EID = 30214;

    uint256 constant SEND_AMOUNT = 100 ether;
    uint256 constant TRANSFER_AMOUNT = 10_000_000 ether;

    address user = makeAddr("user");

    // ========================= L2 TESTS =========================================

    function test_arbitrum() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        executeGnosisTransactionBundle("./output/2_set_minter_OFT_upgrade_token/setMinterUpgradeToken_arbitrum.json");
        _testL2(ARB_ETHFI, MAINNET_EID);
    }

    function test_base() public {
        vm.createSelectFork("https://mainnet.base.org");
        executeGnosisTransactionBundle("./output/2_set_minter_OFT_upgrade_token/setMinterUpgradeToken_base.json");
        _testL2(BASE_ETHFI, MAINNET_EID);
    }

    function test_scroll() public {
        vm.createSelectFork("https://rpc.scroll.io");
        executeGnosisTransactionBundle("./output/2_set_minter_OFT_upgrade_token/setMinterUpgradeToken_scroll.json");
        _testL2(SCROLL_ETHFI, MAINNET_EID);
    }

    function _testL2(address token, uint32 dstEid) internal {
        // Inbound: simulate receive from mainnet, mints tokens to user
        _simulateInbound(user, SEND_AMOUNT, dstEid);
        assertEq(IERC20(token).balanceOf(user), SEND_AMOUNT, "Inbound mint failed");
        console.log("Inbound (mint) successful");

        // Outbound: user sends tokens back, burns them
        SendParam memory sendParam = _buildSendParam(dstEid, user, SEND_AMOUNT);
        MessagingFee memory fee = IOFT(OFT).quoteSend(sendParam, false);
        vm.deal(user, fee.nativeFee);

        vm.prank(user);
        IOFT(OFT).send{value: fee.nativeFee}(sendParam, fee, user);

        assertEq(IERC20(token).balanceOf(user), 0, "Outbound burn failed");
        console.log("Outbound (burn) successful");
    }

    // ========================= MAINNET TEST =====================================

    function test_mainnet() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        _upgradeNttAndTransfer();

        uint256 oftBalance = IERC20(MAINNET_ETHFI).balanceOf(OFT);
        assertTrue(oftBalance >= TRANSFER_AMOUNT, "OFT should hold transferred ETHFI");

        // Outbound: user locks tokens in OFT
        deal(MAINNET_ETHFI, user, SEND_AMOUNT);
        uint256 oftBefore = IERC20(MAINNET_ETHFI).balanceOf(OFT);

        vm.prank(user);
        IERC20(MAINNET_ETHFI).approve(OFT, SEND_AMOUNT);

        SendParam memory sendParam = _buildSendParam(ARB_EID, user, SEND_AMOUNT);
        MessagingFee memory fee = IOFT(OFT).quoteSend(sendParam, false);
        vm.deal(user, fee.nativeFee);

        vm.prank(user);
        IOFT(OFT).send{value: fee.nativeFee}(sendParam, fee, user);

        assertEq(IERC20(MAINNET_ETHFI).balanceOf(user), 0, "User should have 0 after lock");
        assertEq(IERC20(MAINNET_ETHFI).balanceOf(OFT), oftBefore + SEND_AMOUNT, "OFT should hold locked tokens");
        console.log("Outbound (lock) successful");

        // Inbound: simulate receive from Arbitrum, unlocks tokens to user
        oftBefore = IERC20(MAINNET_ETHFI).balanceOf(OFT);
        _simulateInbound(user, SEND_AMOUNT, ARB_EID);

        assertEq(IERC20(MAINNET_ETHFI).balanceOf(user), SEND_AMOUNT, "User should receive unlocked tokens");
        assertEq(IERC20(MAINNET_ETHFI).balanceOf(OFT), oftBefore - SEND_AMOUNT, "OFT should release tokens");
        console.log("Inbound (unlock) successful");
    }

    // ========================= HELPERS ==========================================

    function _upgradeNttAndTransfer() internal {
        NttManagerUpgradeable newImpl = new NttManagerUpgradeable(
            MAINNET_ETHFI,
            IManagerBase.Mode.LOCKING,
            MAINNET_WORMHOLE_ID,
            uint64(RATE_LIMIT_DURATION),
            false
        );

        vm.startPrank(MAINNET_CONTRACT_CONTROLLER);
        NttManagerUpgradeable ntt = NttManagerUpgradeable(MAINNET_NTT_MANAGER);
        ntt.upgrade(address(newImpl));
        ntt.setOftAdapter(OFT);
        ntt.transferToOftAdapter(TRANSFER_AMOUNT);
        vm.stopPrank();

        console.log("NTT upgraded, OFT adapter set, ETHFI transferred");
    }

    function _simulateInbound(address recipient, uint256 amount, uint32 srcEid) internal {
        uint64 amountSD = uint64(amount / 1e12);
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(recipient))),
            amountSD
        );

        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: PEER,
            nonce: 1
        });

        vm.prank(LZ_ENDPOINT);
        ILayerZeroReceiver(OFT).lzReceive(origin, keccak256(abi.encode(srcEid, amount)), message, address(0), "");
    }

    function _buildSendParam(uint32 dstEid, address recipient, uint256 amount) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(recipient))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }
}
