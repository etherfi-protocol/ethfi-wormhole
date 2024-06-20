// SPDX-License-Identifier: MIT

pragma solidity >=0.8.8 <0.9.0;

import "forge-std/Test.sol";


import {IRateLimiter} from "@wormhole-foundation/native_token_transfer/interfaces/IRateLimiter.sol";
import {IRateLimiterEvents} from "@wormhole-foundation/native_token_transfer/interfaces/IRateLimiterEvents.sol";
import {NttManager, toWormholeFormat} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";
import {IWormholeTransceiver} from "@wormhole-foundation/native_token_transfer/interfaces/IWormholeTransceiver.sol";
import {TrimmedAmountLib, TrimmedAmount, eq} from "@wormhole-foundation/native_token_transfer/libraries/TrimmedAmount.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";    
import {NttConstants} from "../utils/constants.sol";

contract TestRateLimit is Test, NttConstants, IRateLimiterEvents {

    using TrimmedAmountLib for uint256;
    using TrimmedAmountLib for TrimmedAmount;

    ERC20Upgradeable public mainnetEthfi;
    ERC20Upgradeable public arbEthfi;
    EthfiL2Token public arEthfiMintable;

    NttManager public mainnetNttManager;
    NttManager public arbNttManager;

    IWormholeTransceiver public mainnetTransceiver;
    IWormholeTransceiver public arbTransceiver;

    TrimmedAmount public maxWindowTrimmedAmount;

    function setUp() public {
        mainnetEthfi = ERC20Upgradeable(MAINNET_ETHFI);
        arbEthfi = ERC20Upgradeable(ARB_ETHFI);
        arEthfiMintable = EthfiL2Token(ARB_ETHFI);

        mainnetNttManager = NttManager(MAINNET_NTT_MANAGER);
        arbNttManager = NttManager(ARB_NTT_MANAGER);

        mainnetTransceiver = IWormholeTransceiver(MAINNET_TRANSCEIVER);
        arbTransceiver = IWormholeTransceiver(ARB_TRANSCEIVER);

        // solana only supports uint64 for token atms so all amts are stored as uint64s using `TrimmedAmount`
        maxWindowTrimmedAmount = MAX_WINDOW.trim(18, 18);
    }

    function testRateLimitConfigs() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");
        checkRateLimitConfigs(mainnetNttManager, ARB_WORMHOLE_ID);

        vm.createSelectFork("https://arbitrum-one.public.blastapi.io");
        checkRateLimitConfigs(arbNttManager, MAINNET_WORMHOLE_ID);
    }

    function checkRateLimitConfigs(NttManager localNttManager, uint16 peerId) public {
        assertEq(localNttManager.rateLimitDuration(), RATE_LIMIT_DURATION);
        
        eq(localNttManager.getOutboundLimitParams().limit, maxWindowTrimmedAmount);
        eq(localNttManager.getInboundLimitParams(peerId).limit, maxWindowTrimmedAmount);
    }

    function testOutboundRateLimit() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");
        uint256 initialBlockTimestamp = vm.getBlockTimestamp();
        outboundRateLimit(mainnetEthfi, mainnetNttManager, ARB_WORMHOLE_ID, initialBlockTimestamp);
        vm.createSelectFork("https://arbitrum-one.public.blastapi.io");
        initialBlockTimestamp = vm.getBlockTimestamp();
        outboundRateLimit(arbEthfi, arbNttManager, MAINNET_WORMHOLE_ID, initialBlockTimestamp);
    }

    function outboundRateLimit(ERC20Upgradeable localEthfi, NttManager localNttManager, uint16 peerId, uint256 initialBlockTimestamp) public {
        address user = address(0x123);

        vm.deal(user, 100_000 ether);
        if (block.chainid == 1)  {
            deal(address(localEthfi), user, 50_000_000 ether);
        } else {
            vm.prank(ARB_NTT_MANAGER);
            // the forge deal cheatcode doesn't work for our custom ERC-20 deployed to L2s in certain cases
            arEthfiMintable.mint(user, 50_000_000 ether);
        }

        vm.startPrank(user);

        (,uint256 price) = localNttManager.quoteDeliveryPrice(peerId, new bytes(1));

        // test a successful transfer within rate limit bounds
        uint256 transferAmountSmall = 1 ether;
        localEthfi.approve(address(localNttManager), transferAmountSmall);
        localNttManager.transfer{value: price}(
            transferAmountSmall,
            peerId,
            toWormholeFormat(user),
            toWormholeFormat(user),
            false, 
            new bytes(1)
        );

        uint256 durationElapsedTime = initialBlockTimestamp + (localNttManager.rateLimitDuration());
        vm.warp(durationElapsedTime);

        uint256 transferTooLarge = MAX_WINDOW + 1 ether;
        localEthfi.approve(address(localNttManager), transferTooLarge);

        // test revert on a transfer that is larger than max window size without enabling queueing
        vm.expectRevert(
            abi.encodeWithSelector(
                IRateLimiter.NotEnoughCapacity.selector, MAX_WINDOW, transferTooLarge
            )
        );
        localNttManager.transfer{value: price}(
            transferTooLarge,
            peerId,
            toWormholeFormat(user),
            toWormholeFormat(user),
            false, 
            new bytes(1)
        );

        vm.recordLogs();
        // same transaciton is successful with queueing enabled
        localNttManager.transfer{value: price}(
            transferTooLarge,
            peerId,
            toWormholeFormat(user),
            toWormholeFormat(user),
            true, 
            new bytes(1)
        );

        durationElapsedTime = initialBlockTimestamp + (durationElapsedTime);
        vm.warp(durationElapsedTime);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint64 transferId = abi.decode(entries[entries.length - 1].data, (uint64));
        
        uint64 seq = localNttManager.completeOutboundQueuedTransfer{value: price}(transferId);
        assertEq(seq, transferId);

        vm.stopPrank();
    }
}
