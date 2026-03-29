// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NttManagerUpgradeable} from "../src/NTT/NttManagerUpgradeable.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {IManagerBase} from "@wormhole-foundation/native_token_transfer/interfaces/IManagerBase.sol";

contract NttManagerUpgradeableTest is Test {
    NttManagerUpgradeable public nttManager;
    ERC20Mock public token;

    address public owner = makeAddr("owner");
    address public oftAdapter = makeAddr("oftAdapter");
    address public user = makeAddr("user");

    uint16 constant CHAIN_ID = 1;
    uint64 constant RATE_LIMIT_DURATION = 86400;

    function setUp() public {
        token = new ERC20Mock("Test Token", "TEST");

        // Deploy NttManager implementation
        vm.prank(owner);
        NttManagerUpgradeable implementation = new NttManagerUpgradeable(
            address(token),
            IManagerBase.Mode.LOCKING,
            CHAIN_ID,
            RATE_LIMIT_DURATION,
            false
        );

        // Deploy behind proxy and initialize
        vm.prank(owner);
        nttManager = NttManagerUpgradeable(address(new ERC1967Proxy(address(implementation), "")));
        
        vm.prank(owner);
        nttManager.initialize();
    }

    function test_SetOftAdapter() public {
        assertEq(nttManager.getOftAdapter(), address(0));

        vm.prank(owner);
        nttManager.setOftAdapter(oftAdapter);

        assertEq(nttManager.getOftAdapter(), oftAdapter);
    }
    function test_SetOftAdapter_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        nttManager.setOftAdapter(oftAdapter);
    }

    function test_TransferToOftAdapter() public {
        uint256 amount = 1000 ether;
        token.mint(address(nttManager), amount);

        vm.prank(owner);
        nttManager.setOftAdapter(oftAdapter);

        assertEq(token.balanceOf(address(nttManager)), amount);
        assertEq(token.balanceOf(oftAdapter), 0);

        vm.prank(owner);
        nttManager.transferToOftAdapter(amount);

        assertEq(token.balanceOf(address(nttManager)), 0);
        assertEq(token.balanceOf(oftAdapter), amount);
    }

    function test_TransferToOftAdapter_NotOwner() public {
        vm.prank(owner);
        nttManager.setOftAdapter(oftAdapter);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        nttManager.transferToOftAdapter(100 ether);
    }

    function test_TransferToOftAdapter_NotSet() public {
        token.mint(address(nttManager), 1000 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NttManagerUpgradeable.OftAdapterNotSet.selector));
        nttManager.transferToOftAdapter(100 ether);
    }
}
