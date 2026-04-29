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

interface ILzEndpointReader {
    function isDefaultSendLibrary(address oapp, uint32 eid) external view returns (bool);
    function getSendLibrary(address oapp, uint32 eid) external view returns (address);
    function getReceiveLibrary(address oapp, uint32 eid) external view returns (address lib, bool isDefault);
}

/// @notice End-to-end verification of 3CP-474:
///         (a) apply the combined 3CP-secure Gnosis batch on a fork of every chain in scope,
///         (b) call oft.send for every asset deployed on that chain,
///         (c) iterate every (oft, peer) route and assert both libraries are custom-pinned to
///             the chain's audited SendUln302 / ReceiveUln302.
///
/// Reads the combined batches directly from the parent 3CP-secure repo so the test exercises the
/// exact bytes signers will execute (not the per-token outputs in this repo's ./output/).
contract Post474SendAndPinSim is Test, GnosisHelpers {
    using OptionsBuilder for bytes;

    // ---------- Endpoint + OFTs ----------
    address constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant EURC_OFT = 0xDCB612005417Dc906fF72c87DF732e5a90D49e11;
    address constant ETHFI_OFT = 0xe0080d2F853ecDdbd81A643dC10DA075Df26fD3f;

    // ---------- Underlying ERC20s (when the OFT is an Adapter) ----------
    address constant EURC_TOKEN_ETH = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c;
    address constant ETHFI_TOKEN_ETH = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    address constant ETHFI_TOKEN_ARB = 0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27;
    address constant ETHFI_TOKEN_BASE = 0x6C240DDA6b5c336DF09A4D011139beAAa1eA2Aa2;
    address constant ETHFI_TOKEN_SCROLL = 0x056A5FA5da84ceb7f93d36e545C5905607D8bD81;

    // ---------- LZ EIDs ----------
    uint32 constant EID_ETH = 30101;
    uint32 constant EID_OP = 30111;
    uint32 constant EID_ARB = 30110;
    uint32 constant EID_BASE = 30184;
    uint32 constant EID_SCROLL = 30214;

    // ---------- Library targets per chain (audited SendUln302 / ReceiveUln302) ----------
    address constant ETH_SEND_LIB = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant ETH_RECV_LIB = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    address constant OP_SEND_LIB = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;
    address constant OP_RECV_LIB = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;
    address constant ARB_SEND_LIB = 0x975bcD720be66659e3EB3C0e4F1866a3020E493A;
    address constant ARB_RECV_LIB = 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6;
    address constant BASE_SEND_LIB = 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2;
    address constant BASE_RECV_LIB = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;
    address constant SCROLL_SEND_LIB = 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B;
    address constant SCROLL_RECV_LIB = 0x8363302080e711E0CAb978C081b9e69308d49808;

    // ---------- RPCs ----------
    string constant ETH_RPC = "https://mainnet.gateway.tenderly.co";
    string constant OP_RPC = "https://optimism-rpc.publicnode.com";
    string constant ARB_RPC = "https://arb1.arbitrum.io/rpc";
    string constant BASE_RPC = "https://mainnet.base.org";
    string constant SCROLL_RPC = "https://rpc.scroll.io";

    // ---------- Combined 3CP-secure batches ----------
    string constant ETH_BATCH = "../3CP-secure/queued/474/eurc-ethfi-ethereum-SecurityUpgrade.json";
    string constant OP_BATCH = "../3CP-secure/queued/474/eurc-ethfi-op-SecurityUpgrade.json";
    string constant ARB_BATCH = "../3CP-secure/queued/474/ethfi-arbitrum-SecurityUpgrade.json";
    string constant BASE_BATCH = "../3CP-secure/queued/474/ethfi-base-SecurityUpgrade.json";
    string constant SCROLL_BATCH = "../3CP-secure/queued/474/eurc-ethfi-scroll-SecurityUpgrade.json";

    uint128 constant LZ_RECEIVE_GAS = 200_000;

    // ============================================================================================
    //                                     Send helpers
    // ============================================================================================

    function _buildSendParam(uint32 dstEid, address recipient, uint256 amount)
        internal
        pure
        returns (SendParam memory)
    {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0);
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

    function _simulateSend(
        address oft,
        address underlying,
        uint32 dstEid,
        uint256 amount,
        string memory label
    ) internal {
        address sender = makeAddr(string.concat(label, "-sender"));

        if (underlying == address(0) || underlying == oft) {
            deal(oft, sender, amount * 5);
        } else {
            deal(underlying, sender, amount * 5);
            vm.prank(sender);
            IERC20(underlying).approve(oft, type(uint256).max);
        }

        SendParam memory sendParam = _buildSendParam(dstEid, sender, amount);
        MessagingFee memory fee = IOFT_Send(oft).quoteSend(sendParam, false);

        vm.deal(sender, fee.nativeFee + 1 ether);
        vm.prank(sender);
        (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
            IOFT_Send(oft).send{value: fee.nativeFee}(sendParam, fee, sender);

        console2.log(string.concat("    [", label, "] amountSentLD:"), oftReceipt.amountSentLD);
        console2.log(string.concat("    [", label, "] guid:"));
        console2.logBytes32(receipt.guid);

        assertGt(oftReceipt.amountSentLD, 0, string.concat(label, ": amountSentLD should be > 0"));
    }

    // ============================================================================================
    //                                Pinning verification helpers
    // ============================================================================================

    function _assertRoutePinned(address oft, uint32 peerEid, address sendLib, address recvLib, string memory label)
        internal
        view
    {
        ILzEndpointReader ep = ILzEndpointReader(ENDPOINT);

        assertFalse(
            ep.isDefaultSendLibrary(oft, peerEid),
            string.concat(label, ": send library is still default for peer eid")
        );
        assertEq(
            ep.getSendLibrary(oft, peerEid), sendLib, string.concat(label, ": send library != target SendUln302")
        );

        (address lib, bool isDefault) = ep.getReceiveLibrary(oft, peerEid);
        assertFalse(isDefault, string.concat(label, ": receive library is still default for peer eid"));
        assertEq(lib, recvLib, string.concat(label, ": receive library != target ReceiveUln302"));
    }

    function _verifyAllRoutes(
        address oft,
        uint32[] memory peers,
        address sendLib,
        address recvLib,
        string memory label
    ) internal view {
        for (uint256 i = 0; i < peers.length; i++) {
            string memory tag = string.concat(label, " peer eid=", vm.toString(uint256(peers[i])));
            _assertRoutePinned(oft, peers[i], sendLib, recvLib, tag);
        }
        console2.log(string.concat("    ", label, " all "), peers.length, "routes pinned");
    }

    // ============================================================================================
    //                                       Per-chain tests
    // ============================================================================================

    function testEthereum() public {
        vm.createSelectFork(ETH_RPC);
        console2.log("=== ETHEREUM (chainId 1) ===");

        executeGnosisTransactionBundle(ETH_BATCH);
        console2.log("  combined eurc+ethfi batch applied");

        // Send EURC ETH -> OP (Adapter on Ethereum)
        _simulateSend(EURC_OFT, EURC_TOKEN_ETH, EID_OP, 1e6, "EURC ETH->OP");
        // Send ETHFI ETH -> OP (Adapter on Ethereum)
        _simulateSend(ETHFI_OFT, ETHFI_TOKEN_ETH, EID_OP, 1 ether, "ETHFI ETH->OP");

        // EURC peers from ethereum: OP (30111), Scroll (30214)
        uint32[] memory eurcPeers = new uint32[](2);
        eurcPeers[0] = EID_OP;
        eurcPeers[1] = EID_SCROLL;
        _verifyAllRoutes(EURC_OFT, eurcPeers, ETH_SEND_LIB, ETH_RECV_LIB, "EURC ethereum");

        // ETHFI peers from ethereum: OP (30111), Arb (30110), Base (30184), Scroll (30214)
        uint32[] memory ethfiPeers = new uint32[](4);
        ethfiPeers[0] = EID_OP;
        ethfiPeers[1] = EID_ARB;
        ethfiPeers[2] = EID_BASE;
        ethfiPeers[3] = EID_SCROLL;
        _verifyAllRoutes(ETHFI_OFT, ethfiPeers, ETH_SEND_LIB, ETH_RECV_LIB, "ETHFI ethereum");
    }

    function testOptimism() public {
        vm.createSelectFork(OP_RPC);
        console2.log("=== OPTIMISM (chainId 10) ===");

        executeGnosisTransactionBundle(OP_BATCH);
        console2.log("  combined eurc+ethfi batch applied");

        // EURC on OP is a vanilla OFT (token() == itself), ETHFI on OP is a vanilla OFT too
        _simulateSend(EURC_OFT, EURC_OFT, EID_ETH, 1e6, "EURC OP->ETH");
        _simulateSend(ETHFI_OFT, ETHFI_OFT, EID_ETH, 1 ether, "ETHFI OP->ETH");

        // EURC peers from OP: ETH (30101), Scroll (30214)
        uint32[] memory eurcPeers = new uint32[](2);
        eurcPeers[0] = EID_ETH;
        eurcPeers[1] = EID_SCROLL;
        _verifyAllRoutes(EURC_OFT, eurcPeers, OP_SEND_LIB, OP_RECV_LIB, "EURC optimism");

        // ETHFI peers from OP: ETH (30101), Arb (30110), Base (30184), Scroll (30214)
        uint32[] memory ethfiPeers = new uint32[](4);
        ethfiPeers[0] = EID_ETH;
        ethfiPeers[1] = EID_ARB;
        ethfiPeers[2] = EID_BASE;
        ethfiPeers[3] = EID_SCROLL;
        _verifyAllRoutes(ETHFI_OFT, ethfiPeers, OP_SEND_LIB, OP_RECV_LIB, "ETHFI optimism");
    }

    function testArbitrum() public {
        vm.createSelectFork(ARB_RPC);
        console2.log("=== ARBITRUM (chainId 42161) ===");

        executeGnosisTransactionBundle(ARB_BATCH);
        console2.log("  ethfi-only batch applied");

        // ETHFI Adapter on Arbitrum
        _simulateSend(ETHFI_OFT, ETHFI_TOKEN_ARB, EID_ETH, 1 ether, "ETHFI Arb->ETH");

        // ETHFI peers from Arb: ETH (30101), OP (30111), Base (30184), Scroll (30214)
        uint32[] memory ethfiPeers = new uint32[](4);
        ethfiPeers[0] = EID_ETH;
        ethfiPeers[1] = EID_OP;
        ethfiPeers[2] = EID_BASE;
        ethfiPeers[3] = EID_SCROLL;
        _verifyAllRoutes(ETHFI_OFT, ethfiPeers, ARB_SEND_LIB, ARB_RECV_LIB, "ETHFI arbitrum");
    }

    function testBase() public {
        vm.createSelectFork(BASE_RPC);
        console2.log("=== BASE (chainId 8453) ===");

        executeGnosisTransactionBundle(BASE_BATCH);
        console2.log("  ethfi-only batch applied");

        // ETHFI Adapter on Base
        _simulateSend(ETHFI_OFT, ETHFI_TOKEN_BASE, EID_ETH, 1 ether, "ETHFI Base->ETH");

        // ETHFI peers from Base: ETH (30101), OP (30111), Arb (30110), Scroll (30214)
        uint32[] memory ethfiPeers = new uint32[](4);
        ethfiPeers[0] = EID_ETH;
        ethfiPeers[1] = EID_OP;
        ethfiPeers[2] = EID_ARB;
        ethfiPeers[3] = EID_SCROLL;
        _verifyAllRoutes(ETHFI_OFT, ethfiPeers, BASE_SEND_LIB, BASE_RECV_LIB, "ETHFI base");
    }

    function testScroll() public {
        vm.createSelectFork(SCROLL_RPC);
        console2.log("=== SCROLL (chainId 534352) ===");

        executeGnosisTransactionBundle(SCROLL_BATCH);
        console2.log("  combined eurc+ethfi batch applied");

        // EURC on Scroll = vanilla OFT (OFTUpgradeableFiat, token()==itself)
        _simulateSend(EURC_OFT, EURC_OFT, EID_ETH, 1e6, "EURC Scroll->ETH");
        // ETHFI Adapter on Scroll
        _simulateSend(ETHFI_OFT, ETHFI_TOKEN_SCROLL, EID_ETH, 1 ether, "ETHFI Scroll->ETH");

        // EURC peers from Scroll: ETH (30101), OP (30111)
        uint32[] memory eurcPeers = new uint32[](2);
        eurcPeers[0] = EID_ETH;
        eurcPeers[1] = EID_OP;
        _verifyAllRoutes(EURC_OFT, eurcPeers, SCROLL_SEND_LIB, SCROLL_RECV_LIB, "EURC scroll");

        // ETHFI peers from Scroll: ETH (30101), OP (30111), Arb (30110), Base (30184)
        uint32[] memory ethfiPeers = new uint32[](4);
        ethfiPeers[0] = EID_ETH;
        ethfiPeers[1] = EID_OP;
        ethfiPeers[2] = EID_ARB;
        ethfiPeers[3] = EID_BASE;
        _verifyAllRoutes(ETHFI_OFT, ethfiPeers, SCROLL_SEND_LIB, SCROLL_RECV_LIB, "ETHFI scroll");
    }
}
