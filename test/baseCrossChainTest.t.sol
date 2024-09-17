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
// testing sends from all peers after adding base as a peer
contract BaseDeploysSimSends is Test, NttConstants {

    ERC20Upgradeable public mainnetEthfi;
    ERC20Upgradeable public arbEthfi;
    ERC20Upgradeable public baseEthfi;

    NttManager public mainnetNttManager;
    NttManager public arbNttManager;
    NttManager public baseNttManager;

    IWormholeTransceiver public mainnetTransceiver;
    IWormholeTransceiver public arbTransceiver;
    IWormholeTransceiver public baseTransceiver;

    function setUp() public {
        mainnetEthfi = ERC20Upgradeable(MAINNET_ETHFI);
        arbEthfi = ERC20Upgradeable(ARB_ETHFI);
        baseEthfi = ERC20Upgradeable(BASE_ETHFI);

        mainnetNttManager = NttManager(MAINNET_NTT_MANAGER);
        arbNttManager = NttManager(ARB_NTT_MANAGER);
        baseNttManager = NttManager(BASE_NTT_MANAGER);

        mainnetTransceiver = IWormholeTransceiver(MAINNET_TRANSCEIVER);
        arbTransceiver = IWormholeTransceiver(ARB_TRANSCEIVER);
        baseTransceiver = IWormholeTransceiver(BASE_TRANSCEIVER);
    }

    function testCrossChainSend() public {
        vm.createSelectFork("https://mainnet.base.org");

        simulateSend(ARB_WORMHOLE_ID);
        simulateSend(MAINNET_WORMHOLE_ID);

        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        // transaction from gnosis to set base as a peer
        vm.startPrank(0x2aCA71020De61bb532008049e1Bd41E451aE8AdC);
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setIsWormholeRelayingEnabled(30, true);
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setWormholePeer(30, toWormholeFormat(0x2153bEa70D96cd804aCbC89D82Ab36638fc1A5F4));
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setIsWormholeEvmChain(30, true);
        NttManager(0x344169Cc4abE9459e77bD99D13AA8589b55b6174).setPeer(30, toWormholeFormat(0xE87797A1aFb329216811dfA22C87380128CA17d8), 18, 150000000000000000000000);
        vm.stopPrank();

        simulateSend(BASE_WORMHOLE_ID);

         vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        // transaction from gnosis to set base as a peer
        vm.startPrank(0x2aCA71020De61bb532008049e1Bd41E451aE8AdC);
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setIsWormholeRelayingEnabled(30, true);
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setWormholePeer(30, toWormholeFormat(0x2153bEa70D96cd804aCbC89D82Ab36638fc1A5F4));
        IWormholeTransceiver(0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186).setIsWormholeEvmChain(30, true);
        NttManager(0x344169Cc4abE9459e77bD99D13AA8589b55b6174).setPeer(30, toWormholeFormat(0xE87797A1aFb329216811dfA22C87380128CA17d8), 18, 150000000000000000000000);
        vm.stopPrank();
        
        simulateSend(BASE_WORMHOLE_ID);

        vm.createSelectFork("https://arbitrum-one.public.blastapi.io");

        // transaction from gnosis to set base as a peer
        vm.startPrank(0x0c6ca434756EeDF928a55EBeAf0019364B279732);
        IWormholeTransceiver(0x4386e36B96D437b0F1C04A35E572C10C6627d88a).setIsWormholeRelayingEnabled(30, true);
        IWormholeTransceiver(0x4386e36B96D437b0F1C04A35E572C10C6627d88a).setWormholePeer(30, toWormholeFormat(0x2153bEa70D96cd804aCbC89D82Ab36638fc1A5F4));
        IWormholeTransceiver(0x4386e36B96D437b0F1C04A35E572C10C6627d88a).setIsWormholeEvmChain(30, true);
        NttManager(0x90A82462258F79780498151EF6f663f1D4BE4E3b).setPeer(30, toWormholeFormat(0xE87797A1aFb329216811dfA22C87380128CA17d8), 18, 150000000000000000000000);
        vm.stopPrank();
        
        simulateSend(BASE_WORMHOLE_ID);
       
    }

    function simulateSend(uint16 destinationPeer) public {
        address user = address(0x123);

        ERC20Upgradeable localEthfi = ERC20Upgradeable(address(0x0));
        NttManager localNttManager = NttManager(address(0x0));

        vm.deal(user, 100_000 ether);
        if (block.chainid == 1)  {
            localEthfi = mainnetEthfi;
            localNttManager = mainnetNttManager;

            deal(address(localEthfi), user, 50_000_000 ether);
            
        } else if (block.chainid == 42161) {
            vm.prank(ARB_NTT_MANAGER);
            // the forge deal cheatcode doesn't work for our custom ERC-20 deployed to L2s in certain cases
            EthfiL2Token(ARB_ETHFI).mint(user, 50_000_000 ether);

            localEthfi = arbEthfi;
            localNttManager = arbNttManager;
        } else {
            // Minter hasn't been set yet
            vm.prank(0xaFa61D537A1814DE82776BF600cb10Ff26342208);
            EthfiL2Token(BASE_ETHFI).setMinter(BASE_NTT_MANAGER);
            vm.prank(BASE_NTT_MANAGER);
            // the forge deal cheatcode doesn't work for our custom ERC-20 deployed to L2s in certain cases
            EthfiL2Token(BASE_ETHFI).mint(user, 50_000_000 ether);

            localEthfi = baseEthfi;
            localNttManager = baseNttManager;
        }

        vm.startPrank(user);
        (,uint256 price) = localNttManager.quoteDeliveryPrice(destinationPeer, new bytes(1));

        // test a successful transfer
        uint256 transferAmount = 10 ether;
        localEthfi.approve(address(localNttManager), transferAmount);
        localNttManager.transfer{value: price}(
            transferAmount,
            destinationPeer,
            toWormholeFormat(user),
            toWormholeFormat(user),
            false, 
            new bytes(1)
        );
        vm.stopPrank(); 
    }

}


