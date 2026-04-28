// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, OFTReceipt, MessagingReceipt, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {GnosisHelpers} from "../script/utils/GnosisHelpers.sol";

interface IOFT_Send {
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory, OFTReceipt memory);

    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory);

    function paused() external view returns (bool);
}

/// @notice Post-upgrade smoke test: after the ETHFI SecurityUpgrade Safe batch executes on each
/// chain, confirm that bridging still works (oft.send does not revert on the source chain).
///
/// Source-side only: deal ETHFI to a sender, build a SendParam to a peer EID, get a quote, call
/// send, assert OFTReceipt.amountSentLD > 0. We do NOT verify destination delivery (that requires
/// a separate destination fork + executor stub).
contract SecurityUpgradeSendSimTest is Test, GnosisHelpers {
    using OptionsBuilder for bytes;

    address constant ETHFI_OFT = 0xe0080d2F853ecDdbd81A643dC10DA075Df26fD3f;
    // Underlying ETHFI ERC20s. On Optimism the OFT *is* the ERC20 (vanilla OFT). On every other
    // chain, the OFT is an Adapter that wraps the per-chain ERC20.
    address constant ETHFI_TOKEN_ETH = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    address constant ETHFI_TOKEN_ARB = 0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27;
    address constant ETHFI_TOKEN_BASE = 0x6C240DDA6b5c336DF09A4D011139beAAa1eA2Aa2;
    address constant ETHFI_TOKEN_SCROLL = 0x056A5FA5da84ceb7f93d36e545C5905607D8bD81;

    uint32 constant EID_ETHEREUM = 30101;
    uint32 constant EID_OP = 30111;
    uint32 constant EID_ARBITRUM = 30110;
    uint32 constant EID_BASE = 30184;
    uint32 constant EID_SCROLL = 30214;

    uint128 constant GAS_LIMIT = 200_000;
    uint256 constant SEND_AMOUNT = 1 ether;

    string constant ETH_RPC = "https://mainnet.gateway.tenderly.co";
    string constant OP_RPC = "https://optimism-rpc.publicnode.com";
    string constant ARB_RPC = "https://arb1.arbitrum.io/rpc";
    string constant BASE_RPC = "https://mainnet.base.org";
    string constant SCROLL_RPC = "https://rpc.scroll.io";

    string constant ETH_BATCH = "./output/ethfi-ethereum-SecurityUpgrade.json";
    string constant OP_BATCH = "./output/ethfi-op-SecurityUpgrade.json";
    string constant ARB_BATCH = "./output/ethfi-arbitrum-SecurityUpgrade.json";
    string constant BASE_BATCH = "./output/ethfi-base-SecurityUpgrade.json";
    string constant SCROLL_BATCH = "./output/ethfi-scroll-SecurityUpgrade.json";

    /// @dev Tests assume `forge script script/SecurityUpgrade.s.sol --sig run` has already been
    /// run to populate ./output/. Each test forks one chain and replays the corresponding JSON.

    function _buildSendParam(uint32 dstEid, address recipient, uint256 amount)
        internal
        pure
        returns (SendParam memory)
    {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(recipient))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
    }

    function _simulateSend(IOFT_Send oft, uint32 dstEid, address sender, string memory label) internal {
        SendParam memory sendParam = _buildSendParam(dstEid, sender, SEND_AMOUNT);
        MessagingFee memory fee = oft.quoteSend(sendParam, false);

        console2.log(string.concat("  [", label, "] quoteSend nativeFee:"), fee.nativeFee);

        vm.deal(sender, fee.nativeFee + 1 ether);
        vm.prank(sender);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
            oft.send{value: fee.nativeFee}(sendParam, fee, sender);

        console2.log(string.concat("  [", label, "] amountSentLD:"), oftReceipt.amountSentLD);
        console2.log(string.concat("  [", label, "] guid:"));
        console2.logBytes32(receipt.guid);

        assertGt(oftReceipt.amountSentLD, 0, string.concat(label, ": amountSentLD should be > 0"));
    }

    function testEthereumEthfiSend() public {
        vm.createSelectFork(ETH_RPC);
        console2.log("=== ETHEREUM (ETHFI Adapter) ===");

        executeGnosisTransactionBundle(ETH_BATCH);
        console2.log("  ETHFI SecurityUpgrade batch applied");

        assertFalse(IOFT_Send(ETHFI_OFT).paused(), "Adapter should be unpaused");

        address sender = makeAddr("ethfi-eth-sender");
        _simulateAdapterSend(IOFT_Send(ETHFI_OFT), ETHFI_TOKEN_ETH, EID_OP, sender, "ETHFI ETH->OP");
    }

    function testOpEthfiSend() public {
        vm.createSelectFork(OP_RPC);
        console2.log("=== OPTIMISM (ETHFI OFT) ===");

        executeGnosisTransactionBundle(OP_BATCH);
        console2.log("  ETHFI SecurityUpgrade batch applied");

        address sender = makeAddr("ethfi-op-sender");
        deal(ETHFI_OFT, sender, 5 ether);

        _simulateSend(IOFT_Send(ETHFI_OFT), EID_ETHEREUM, sender, "ETHFI OP->ETH");
    }

    /// @dev On L2s where the OFT is an Adapter (arb / base / scroll / ethereum), we need to deal
    /// the underlying ERC20 to the sender and approve the adapter.
    function _simulateAdapterSend(
        IOFT_Send oft,
        address underlying,
        uint32 dstEid,
        address sender,
        string memory label
    ) internal {
        deal(underlying, sender, 5 ether);
        vm.prank(sender);
        IERC20(underlying).approve(address(oft), type(uint256).max);
        _simulateSend(oft, dstEid, sender, label);
    }

    function testArbitrumEthfiSend() public {
        vm.createSelectFork(ARB_RPC);
        console2.log("=== ARBITRUM (ETHFI Adapter) ===");

        executeGnosisTransactionBundle(ARB_BATCH);
        console2.log("  ETHFI SecurityUpgrade batch applied");

        address sender = makeAddr("ethfi-arb-sender");
        _simulateAdapterSend(IOFT_Send(ETHFI_OFT), ETHFI_TOKEN_ARB, EID_ETHEREUM, sender, "ETHFI Arb->ETH");
    }

    function testBaseEthfiSend() public {
        vm.createSelectFork(BASE_RPC);
        console2.log("=== BASE (ETHFI Adapter) ===");

        executeGnosisTransactionBundle(BASE_BATCH);
        console2.log("  ETHFI SecurityUpgrade batch applied");

        address sender = makeAddr("ethfi-base-sender");
        _simulateAdapterSend(IOFT_Send(ETHFI_OFT), ETHFI_TOKEN_BASE, EID_ETHEREUM, sender, "ETHFI Base->ETH");
    }

    function testScrollEthfiSend() public {
        vm.createSelectFork(SCROLL_RPC);
        console2.log("=== SCROLL (ETHFI Adapter) ===");

        executeGnosisTransactionBundle(SCROLL_BATCH);
        console2.log("  ETHFI SecurityUpgrade batch applied");

        address sender = makeAddr("ethfi-scroll-sender");
        _simulateAdapterSend(IOFT_Send(ETHFI_OFT), ETHFI_TOKEN_SCROLL, EID_ETHEREUM, sender, "ETHFI Scroll->ETH");
    }
}
