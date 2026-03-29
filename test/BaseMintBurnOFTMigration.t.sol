// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";
import {EtherfiMintBurnOFTAdapter} from "../src/OFT/EtherfiMintBurnOFTAdapter.sol";
import {SimpleEndpointMock} from "./mocks/SimpleEndpointMock.sol";
import {NttConstants} from "../utils/constants.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @title BaseMintBurnOFTMigration
/// @notice Fork test to validate the migration from NTT to OFT on Base
/// @dev Tests the upgrade of EthfiL2Token to V2 and deployment of MintBurnOFTAdapter
contract BaseMintBurnOFTMigrationTest is Test, NttConstants {
    // Base token owner is BASE_CONTRACT_CONTROLLER (from NttConstants)
    
    // LayerZero endpoint IDs
    uint32 public constant BASE_LZ_EID = 30184;
    uint32 public constant MAINNET_LZ_EID = 30101;

    EthfiL2Token public token;
    EtherfiMintBurnOFTAdapter public adapter;
    SimpleEndpointMock public lzEndpoint;

    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://mainnet.base.org");
        
        token = EthfiL2Token(BASE_ETHFI);
        
        // Deploy mock LayerZero endpoint
        lzEndpoint = new SimpleEndpointMock(BASE_LZ_EID);
        
        // Fund test users
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
    }

    /// @notice Test upgrading EthfiL2Token to V2 with initializeV2
    function testUpgradeToV2() public {
        // Deploy new implementation
        EthfiL2Token newImplementation = new EthfiL2Token();
        
        // Verify we can call the upgrade as owner
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSelector(EthfiL2Token.initializeV2.selector)
        );
        
        // Verify AccessControl is initialized - owner should have DEFAULT_ADMIN_ROLE
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), BASE_CONTRACT_CONTROLLER));
        
        // Verify token still works (basic functionality preserved)
        assertEq(token.name(), "ether.fi governance token");
        assertEq(token.symbol(), "ETHFI");
        assertEq(token.owner(), BASE_CONTRACT_CONTROLLER);
    }

    /// @notice Test deploying the MintBurnOFTAdapter and setting it as minter
    function testDeployAdapterAndSetMinter() public {
        // First upgrade the token
        _upgradeTokenToV2();
        
        // Deploy the adapter
        adapter = new EtherfiMintBurnOFTAdapter(
            address(token),
            IMintableBurnable(address(token)),
            address(lzEndpoint),
            BASE_CONTRACT_CONTROLLER
        );
        
        // Set adapter as minter (replacing NTT manager)
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.setMinter(address(adapter));
        
        // Verify minter is set
        assertEq(token.minter(), address(adapter));
        
        // Verify adapter configuration
        assertEq(adapter.token(), address(token));
        assertEq(adapter.owner(), BASE_CONTRACT_CONTROLLER);
    }

    /// @notice Test that send operation burns tokens from the sender
    function testSendBurnsTokens() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Mint tokens to user for testing
        vm.prank(address(adapter));
        token.mint(user, 1000 ether);
        
        uint256 userBalanceBefore = token.balanceOf(user);
        assertEq(userBalanceBefore, 1000 ether);
        
        // Set up peer for destination chain
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        // Prepare send parameters
        uint256 sendAmount = 100 ether;
        SendParam memory sendParam = SendParam({
            dstEid: MAINNET_LZ_EID,
            to: bytes32(uint256(uint160(user2))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        
        // Execute send
        vm.prank(user);
        adapter.send{value: 0}(sendParam, fee, user);
        
        // Verify tokens were burned
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceAfter, userBalanceBefore - sendAmount);
        
        // Verify adapter didn't receive tokens (burn not lock)
        assertEq(token.balanceOf(address(adapter)), 0);
    }

    /// @notice Test that receive operation mints tokens to the recipient
    function testReceiveMintsTokens() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Set up peer for source chain
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        uint256 user2BalanceBefore = token.balanceOf(user2);
        assertEq(user2BalanceBefore, 0);
        
        // Simulate receiving a cross-chain message
        uint256 receiveAmount = 100 ether;
        uint64 amountSD = uint64(receiveAmount / 1e12); // Convert from 18 decimals to 6 shared decimals
        
        // Encode OFT message: recipient (bytes32) + amount (uint64)
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(user2))), // sendTo
            amountSD // amount in shared decimals
        );
        
        Origin memory origin = Origin({
            srcEid: MAINNET_LZ_EID,
            sender: peerAddress,
            nonce: 1
        });
        
        bytes32 guid = keccak256("test-guid");
        
        // Execute receive via mock endpoint
        lzEndpoint.lzReceive(address(adapter), origin, guid, message);
        
        // Verify tokens were minted to recipient
        uint256 user2BalanceAfter = token.balanceOf(user2);
        assertEq(user2BalanceAfter, receiveAmount);
    }

    /// @notice Test full migration flow: NTT minter -> OFT adapter minter
    function testMigrationFromNTT() public {
        // Verify current minter is NTT manager
        address currentMinter = token.minter();
        assertEq(currentMinter, BASE_NTT_MANAGER);
        
        // Upgrade token to V2
        _upgradeTokenToV2();
        
        // Deploy adapter
        adapter = new EtherfiMintBurnOFTAdapter(
            address(token),
            IMintableBurnable(address(token)),
            address(lzEndpoint),
            BASE_CONTRACT_CONTROLLER
        );
        
        // Change minter from NTT to OFT adapter
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.setMinter(address(adapter));
        
        // Verify minter changed
        assertEq(token.minter(), address(adapter));
        assertTrue(token.minter() != BASE_NTT_MANAGER);
        
        // Verify old NTT manager can no longer mint
        vm.prank(BASE_NTT_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(EthfiL2Token.CallerNotMinter.selector, BASE_NTT_MANAGER));
        token.mint(user, 100 ether);
        
        // Verify new adapter can mint
        vm.prank(address(adapter));
        token.mint(user, 100 ether);
        assertEq(token.balanceOf(user), 100 ether);
    }

    /// @notice Test that adapter doesn't require token approval (uses mint/burn)
    function testApprovalNotRequired() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Verify approval is not required
        assertFalse(adapter.approvalRequired());
    }

    /// @notice Test round-trip: send tokens out, receive tokens back
    function testRoundTrip() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Set up peer
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        // Mint initial tokens
        vm.prank(address(adapter));
        token.mint(user, 1000 ether);
        
        uint256 initialBalance = token.balanceOf(user);
        uint256 sendAmount = 100 ether;
        
        // Send tokens out (burns)
        SendParam memory sendParam = SendParam({
            dstEid: MAINNET_LZ_EID,
            to: bytes32(uint256(uint160(user))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        
        vm.prank(user);
        adapter.send{value: 0}(sendParam, fee, user);
        
        assertEq(token.balanceOf(user), initialBalance - sendAmount);
        
        // Receive tokens back (mints)
        uint64 amountSD = uint64(sendAmount / 1e12);
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(user))),
            amountSD
        );
        
        Origin memory origin = Origin({
            srcEid: MAINNET_LZ_EID,
            sender: peerAddress,
            nonce: 1
        });
        
        lzEndpoint.lzReceive(address(adapter), origin, keccak256("return-guid"), message);
        
        // Balance should be back to initial
        assertEq(token.balanceOf(user), initialBalance);
    }

    // ==================== Pause Tests ====================

    /// @notice Test that outbound send (burn) is blocked when token is paused
    function testOutboundSendBlockedWhenPaused() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Set up peer
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        // Mint some tokens to user first while unpaused
        vm.prank(address(adapter));
        token.mint(user, 100 ether);
        
        // Grant pauser role and pause
        vm.startPrank(BASE_CONTRACT_CONTROLLER);
        token.grantRole(token.PAUSER_ROLE(), BASE_CONTRACT_CONTROLLER);
        token.pause();
        vm.stopPrank();
        
        assertTrue(token.paused());
        
        // Prepare outbound send
        uint256 sendAmount = 50 ether;
        SendParam memory sendParam = SendParam({
            dstEid: MAINNET_LZ_EID,
            to: bytes32(uint256(uint160(user2))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        
        // Outbound send should fail because burn is blocked when paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        adapter.send{value: 0}(sendParam, fee, user);
        
        // Verify balance unchanged
        assertEq(token.balanceOf(user), 100 ether);
    }

    /// @notice Test that inbound receive (mint) is blocked when token is paused
    function testInboundReceiveBlockedWhenPaused() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Set up peer
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        // Grant pauser role and pause
        vm.startPrank(BASE_CONTRACT_CONTROLLER);
        token.grantRole(token.PAUSER_ROLE(), BASE_CONTRACT_CONTROLLER);
        token.pause();
        vm.stopPrank();
        
        assertTrue(token.paused());
        
        // Prepare inbound receive message
        uint256 receiveAmount = 100 ether;
        uint64 amountSD = uint64(receiveAmount / 1e12); // Convert to shared decimals
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(user2))),
            amountSD
        );
        
        Origin memory origin = Origin({
            srcEid: MAINNET_LZ_EID,
            sender: peerAddress,
            nonce: 1
        });
        
        // Inbound receive should fail because mint is blocked when paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        lzEndpoint.lzReceive(address(adapter), origin, keccak256("test-guid"), message);
        
        // Verify no tokens were minted
        assertEq(token.balanceOf(user2), 0);
    }

    /// @notice Test that send and receive work after unpause
    function testSendReceiveWorkAfterUnpause() public {
        _upgradeTokenToV2();
        _deployAdapter();
        
        // Set up peer
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        vm.prank(BASE_CONTRACT_CONTROLLER);
        adapter.setPeer(MAINNET_LZ_EID, peerAddress);
        
        // Grant roles
        vm.startPrank(BASE_CONTRACT_CONTROLLER);
        token.grantRole(token.PAUSER_ROLE(), BASE_CONTRACT_CONTROLLER);
        token.grantRole(token.UNPAUSER_ROLE(), BASE_CONTRACT_CONTROLLER);
        vm.stopPrank();
        
        // Mint initial tokens
        vm.prank(address(adapter));
        token.mint(user, 100 ether);
        
        // Pause
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.pause();
        assertTrue(token.paused());
        
        // Unpause
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.unpause();
        assertFalse(token.paused());
        
        // Outbound send should work after unpause
        uint256 sendAmount = 50 ether;
        SendParam memory sendParam = SendParam({
            dstEid: MAINNET_LZ_EID,
            to: bytes32(uint256(uint160(user2))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});
        
        vm.prank(user);
        adapter.send{value: 0}(sendParam, fee, user);
        assertEq(token.balanceOf(user), 50 ether);
        
        // Inbound receive should work after unpause
        uint64 amountSD = uint64(sendAmount / 1e12);
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(user2))),
            amountSD
        );
        
        Origin memory origin = Origin({
            srcEid: MAINNET_LZ_EID,
            sender: peerAddress,
            nonce: 1
        });
        
        lzEndpoint.lzReceive(address(adapter), origin, keccak256("test-guid"), message);
        assertEq(token.balanceOf(user2), sendAmount);
    }

    // ==================== Helper Functions ====================

    function _upgradeTokenToV2() internal {
        EthfiL2Token newImplementation = new EthfiL2Token();
        
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSelector(EthfiL2Token.initializeV2.selector)
        );
    }

    function _deployAdapter() internal {
        adapter = new EtherfiMintBurnOFTAdapter(
            address(token),
            IMintableBurnable(address(token)),
            address(lzEndpoint),
            BASE_CONTRACT_CONTROLLER
        );
        
        vm.prank(BASE_CONTRACT_CONTROLLER);
        token.setMinter(address(adapter));
    }
}
