// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EtherfiOFTAdapterUpgradeable} from "../src/OFT/EtherfiOFTAdapterUpgradeable.sol";
import {EtherfiOFTAdapterUpgradeableV2Mock} from "./mocks/EtherfiOFTAdapterUpgradeableV2Mock.sol";
import {SimpleEndpointMock} from "./mocks/SimpleEndpointMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract EtherfiOFTAdapterUpgradeableTest is Test {
    EtherfiOFTAdapterUpgradeable public etherfiOFTAdapter;
    SimpleEndpointMock public lzEndpoint;
    ERC20Mock public token;

    address public owner = makeAddr("owner");
    address public pauser = makeAddr("pauser");
    address public unpauser = makeAddr("unpauser");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    // Cache role values to avoid prank issues
    bytes32 public PAUSER_ROLE;
    bytes32 public UNPAUSER_ROLE;
    bytes32 public DEFAULT_ADMIN_ROLE;

    function setUp() public {
        lzEndpoint = new SimpleEndpointMock(1);
        token = new ERC20Mock("Test Token", "TEST");

        EtherfiOFTAdapterUpgradeable etherfiOFTAdapterImpl = new EtherfiOFTAdapterUpgradeable(
            address(token),
            address(lzEndpoint)
        );
        etherfiOFTAdapter = EtherfiOFTAdapterUpgradeable(address(new ERC1967Proxy(
            address(etherfiOFTAdapterImpl),
            abi.encodeWithSelector(EtherfiOFTAdapterUpgradeable.initialize.selector, owner)
        )));

        // Cache role values
        PAUSER_ROLE = etherfiOFTAdapter.PAUSER_ROLE();
        UNPAUSER_ROLE = etherfiOFTAdapter.UNPAUSER_ROLE();
        DEFAULT_ADMIN_ROLE = etherfiOFTAdapter.DEFAULT_ADMIN_ROLE();

        vm.deal(user, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /// @notice Helper to get all members of a role (since getRoleMembers doesn't exist in OZ v5)
    function _getRoleMembers(bytes32 role) internal view returns (address[] memory) {
        uint256 count = etherfiOFTAdapter.getRoleMemberCount(role);
        address[] memory members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = etherfiOFTAdapter.getRoleMember(role, i);
        }
        return members;
    }

    function test_RoleManagement() public {
        // Verify initial state - no role holders
        address[] memory initialPausers = _getRoleMembers(PAUSER_ROLE);
        address[] memory initialUnpausers = _getRoleMembers(UNPAUSER_ROLE);

        assertEq(initialPausers.length, 0);
        assertEq(initialUnpausers.length, 0);

        assertFalse(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));
        assertFalse(etherfiOFTAdapter.hasRole(UNPAUSER_ROLE, unpauser));

        // Test that non-admin cannot grant roles
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(user);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);

        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(UNPAUSER_ROLE, unpauser);
        vm.stopPrank();

        assertTrue(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));
        assertTrue(etherfiOFTAdapter.hasRole(UNPAUSER_ROLE, unpauser));

        address[] memory pausers = _getRoleMembers(PAUSER_ROLE);
        address[] memory unpausers = _getRoleMembers(UNPAUSER_ROLE);

        assertEq(pausers.length, 1);
        assertEq(unpausers.length, 1);
        assertEq(pausers[0], pauser);
        assertEq(unpausers[0], unpauser);
    }

    function test_PauseBridge_WithoutRole() public {
        assertFalse(etherfiOFTAdapter.paused());

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,
            PAUSER_ROLE
        ));
        vm.prank(user);
        etherfiOFTAdapter.pauseBridge();

        assertFalse(etherfiOFTAdapter.paused());
    }

    function test_PauseBridge_WithRole() public {
        vm.prank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);

        assertFalse(etherfiOFTAdapter.paused());

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();

        assertTrue(etherfiOFTAdapter.paused());
    }

    function test_UnpauseBridge_WithoutRole() public {
        vm.prank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,
            UNPAUSER_ROLE
        ));
        vm.prank(user);
        etherfiOFTAdapter.unpauseBridge();

        assertTrue(etherfiOFTAdapter.paused());
    }

    function test_UnpauseBridge_WithRole() public {
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(UNPAUSER_ROLE, unpauser);
        vm.stopPrank();

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());

        vm.prank(unpauser);
        etherfiOFTAdapter.unpauseBridge();

        assertFalse(etherfiOFTAdapter.paused());
    }

    function test_RoleRevocation() public {
        vm.prank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        assertTrue(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));

        vm.prank(owner);
        etherfiOFTAdapter.revokeRole(PAUSER_ROLE, pauser);
        assertFalse(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));

        address[] memory pausers = _getRoleMembers(PAUSER_ROLE);
        assertEq(pausers.length, 0);

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            pauser,
            PAUSER_ROLE
        ));
        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
    }

    function test_MultipleRoleHolders() public {
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, user);
        etherfiOFTAdapter.grantRole(UNPAUSER_ROLE, unpauser);
        vm.stopPrank();

        address[] memory pausers = _getRoleMembers(PAUSER_ROLE);
        address[] memory unpausers = _getRoleMembers(UNPAUSER_ROLE);

        assertEq(pausers.length, 2);
        assertEq(unpausers.length, 1);

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());

        vm.prank(unpauser);
        etherfiOFTAdapter.unpauseBridge();
        assertFalse(etherfiOFTAdapter.paused());

        vm.prank(user);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());
    }

    function test_RoleMemberCount() public {
        assertEq(etherfiOFTAdapter.getRoleMemberCount(PAUSER_ROLE), 0);
        assertEq(etherfiOFTAdapter.getRoleMemberCount(UNPAUSER_ROLE), 0);

        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, user);
        etherfiOFTAdapter.grantRole(UNPAUSER_ROLE, unpauser);
        vm.stopPrank();

        assertEq(etherfiOFTAdapter.getRoleMemberCount(PAUSER_ROLE), 2);
        assertEq(etherfiOFTAdapter.getRoleMemberCount(UNPAUSER_ROLE), 1);
    }

    function test_RoleMemberAt() public {
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, user);
        vm.stopPrank();

        address firstPauser = etherfiOFTAdapter.getRoleMember(PAUSER_ROLE, 0);
        address secondPauser = etherfiOFTAdapter.getRoleMember(PAUSER_ROLE, 1);

        // The order might vary, but both addresses should be present
        assertTrue(firstPauser == pauser || firstPauser == user);
        assertTrue(secondPauser == pauser || secondPauser == user);
        assertTrue(firstPauser != secondPauser);
    }

    function test_RenounceRole() public {
        vm.prank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        assertTrue(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));

        // Renounce own role
        vm.prank(pauser);
        etherfiOFTAdapter.renounceRole(PAUSER_ROLE, pauser);
        assertFalse(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));
    }

    function test_CannotRenounceOthersRole() public {
        vm.prank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);

        // Try to renounce someone else's role
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlBadConfirmation.selector
        ));
        vm.prank(user);
        etherfiOFTAdapter.renounceRole(PAUSER_ROLE, pauser);
    }

    // ==================== Upgrade Tests ====================

    function test_Upgrade() public {
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.grantRole(UNPAUSER_ROLE, unpauser);
        vm.stopPrank();

        assertTrue(etherfiOFTAdapter.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(etherfiOFTAdapter.hasRole(PAUSER_ROLE, pauser));
        assertTrue(etherfiOFTAdapter.hasRole(UNPAUSER_ROLE, unpauser));
        assertEq(etherfiOFTAdapter.getRoleMemberCount(PAUSER_ROLE), 1);
        assertEq(etherfiOFTAdapter.getRoleMemberCount(UNPAUSER_ROLE), 1);
        assertEq(etherfiOFTAdapter.token(), address(token));

        address implBefore = _getImplementation(address(etherfiOFTAdapter));

        EtherfiOFTAdapterUpgradeableV2Mock v2Impl = new EtherfiOFTAdapterUpgradeableV2Mock(
            address(token),
            address(lzEndpoint)
        );

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(user);
        etherfiOFTAdapter.upgradeToAndCall(address(v2Impl), "");

        vm.prank(owner);
        etherfiOFTAdapter.upgradeToAndCall(address(v2Impl), "");

        address implAfter = _getImplementation(address(etherfiOFTAdapter));

        assertTrue(implBefore != implAfter);
        assertEq(implAfter, address(v2Impl));

        EtherfiOFTAdapterUpgradeableV2Mock upgradedAdapter = EtherfiOFTAdapterUpgradeableV2Mock(address(etherfiOFTAdapter));
        assertEq(upgradedAdapter.version(), 2);

        assertTrue(upgradedAdapter.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(upgradedAdapter.hasRole(PAUSER_ROLE, pauser));
        assertTrue(upgradedAdapter.hasRole(UNPAUSER_ROLE, unpauser));
        assertEq(upgradedAdapter.getRoleMemberCount(PAUSER_ROLE), 1);
        assertEq(upgradedAdapter.getRoleMemberCount(UNPAUSER_ROLE), 1);
        assertEq(upgradedAdapter.token(), address(token));

        vm.prank(pauser);
        upgradedAdapter.pauseBridge();
        assertTrue(upgradedAdapter.paused());

        vm.prank(unpauser);
        upgradedAdapter.unpauseBridge();
        assertFalse(upgradedAdapter.paused());
    }

    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        return address(uint160(uint256(vm.load(proxy, slot))));
    }

    // ==================== Simulation Tests ====================

        function test_PauseBridge_BlocksOutboundSend() public {
        uint32 dstEid = 2;
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.setPeer(dstEid, peerAddress);
        vm.stopPrank();

        uint256 sendAmount = 1000 ether;
        token.mint(user, sendAmount);
        vm.prank(user);
        token.approve(address(etherfiOFTAdapter), sendAmount);

        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(user2))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = MessagingFee({nativeFee: 0, lzTokenFee: 0});

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        etherfiOFTAdapter.send{value: 0}(sendParam, fee, user);
    }

    function test_PauseBridge_BlocksInboundReceive() public {
        uint32 srcEid = 2;
        bytes32 peerAddress = bytes32(uint256(uint160(makeAddr("remotePeer"))));
        
        vm.startPrank(owner);
        etherfiOFTAdapter.grantRole(PAUSER_ROLE, pauser);
        etherfiOFTAdapter.setPeer(srcEid, peerAddress);
        vm.stopPrank();

        uint256 receiveAmount = 1000 ether;
        token.mint(address(etherfiOFTAdapter), receiveAmount);

        uint64 amountSD = uint64(receiveAmount / 1e12); // Convert from 18 decimals to 6
        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(user2))), // sendTo
            amountSD // amount in shared decimals
        );

        Origin memory origin = Origin({
            srcEid: srcEid,
            sender: peerAddress,
            nonce: 1
        });

        bytes32 guid = keccak256("test-guid");

        vm.prank(pauser);
        etherfiOFTAdapter.pauseBridge();
        assertTrue(etherfiOFTAdapter.paused());

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        lzEndpoint.lzReceive(address(etherfiOFTAdapter), origin, guid, message);
    }
}
