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
import {GnosisHelpers} from "../utils/GnosisHelpers.sol";

contract ScrollDeploysSimSends is Test, NttConstants, GnosisHelpers {

    ERC20Upgradeable public mainnetEthfi;
    ERC20Upgradeable public arbEthfi;
    ERC20Upgradeable public baseEthfi;
    EthfiL2Token public scrollEthfi;

    NttManager public mainnetNttManager;
    NttManager public arbNttManager;
    NttManager public baseNttManager;
    NttManager public scrollNttManager;

    IWormholeTransceiver public mainnetTransceiver;
    IWormholeTransceiver public arbTransceiver;
    IWormholeTransceiver public baseTransceiver;
    IWormholeTransceiver public scrollTransceiver;

    address public scrollContractController;
    address public baseContractController;
    address public mainnetContractController;
    address public arbContractController;

    function setUp() public {
        mainnetEthfi = ERC20Upgradeable(MAINNET_ETHFI);
        arbEthfi = ERC20Upgradeable(ARB_ETHFI);
        baseEthfi = ERC20Upgradeable(BASE_ETHFI);
        scrollEthfi = EthfiL2Token(SCROLL_ETHFI);

        mainnetNttManager = NttManager(MAINNET_NTT_MANAGER);
        arbNttManager = NttManager(ARB_NTT_MANAGER);
        baseNttManager = NttManager(BASE_NTT_MANAGER);
        scrollNttManager = NttManager(SCROLL_NTT_MANAGER);

        mainnetTransceiver = IWormholeTransceiver(MAINNET_TRANSCEIVER);
        arbTransceiver = IWormholeTransceiver(ARB_TRANSCEIVER);
        baseTransceiver = IWormholeTransceiver(BASE_TRANSCEIVER);
        scrollTransceiver = IWormholeTransceiver(SCROLL_TRANSCEIVER);

        mainnetContractController = MAINNET_CONTRACT_CONTROLLER;
        arbContractController = ARB_CONTRACT_CONTROLLER;
        baseContractController = BASE_CONTRACT_CONTROLLER;
        scrollContractController = SCROLL_CONTRACT_CONTROLLER;
    }

    function testCrossChainSend() public {
        vm.createSelectFork("https://scroll-mainnet.public.blastapi.io");
        vm.prank(0xd8F3803d8412e61e04F53e1C9394e13eC8b32550);
        scrollEthfi.transferOwnership(scrollContractController);

        string memory scrollJson = _getGnosisHeader("534351");
        scrollJson = string.concat(scrollJson, _getGnosisTransaction(address(scrollEthfi), abi.encodeWithSignature("acceptOwnership()", scrollContractController), true));

        vm.writeFile("output/scroll-transfer-ownership.json", scrollJson);
        executeGnosisTransactionBundle("output/scroll-transfer-ownership.json", scrollContractController);

        simulateSend(ARB_WORMHOLE_ID);
        simulateSend(MAINNET_WORMHOLE_ID);
        simulateSend(BASE_WORMHOLE_ID);

        string memory BaseJson = _getGnosisHeader("8453");
        BaseJson = string.concat(BaseJson, _getGnosisTransaction(address(baseTransceiver), abi.encodeWithSignature("setIsWormholeRelayingEnabled(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        BaseJson = string.concat(BaseJson, _getGnosisTransaction(address(baseTransceiver), abi.encodeWithSignature("setWormholePeer(uint16,bytes32)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_TRANSCEIVER)), false));
        BaseJson = string.concat(BaseJson, _getGnosisTransaction(address(baseTransceiver), abi.encodeWithSignature("setIsWormholeEvmChain(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        BaseJson = string.concat(BaseJson, _getGnosisTransaction(address(baseNttManager), abi.encodeWithSignature("setPeer(uint16,bytes32,uint8,uint256)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_NTT_MANAGER), 18, 150000000000000000000000), true));

        vm.writeFile("output/add-scroll-peer-base.json", BaseJson);

        vm.createSelectFork("https://mainnet.base.org");
        executeGnosisTransactionBundle("output/add-scroll-peer-base.json", baseContractController);
        simulateSend(SCROLL_WORMHOLE_ID);

        string memory mainnetJson = _getGnosisHeader("1");
        mainnetJson = string.concat(mainnetJson, _getGnosisTransaction(address(mainnetTransceiver), abi.encodeWithSignature("setIsWormholeRelayingEnabled(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        mainnetJson = string.concat(mainnetJson, _getGnosisTransaction(address(mainnetTransceiver), abi.encodeWithSignature("setWormholePeer(uint16,bytes32)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_TRANSCEIVER)), false));
        mainnetJson = string.concat(mainnetJson, _getGnosisTransaction(address(mainnetTransceiver), abi.encodeWithSignature("setIsWormholeEvmChain(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        mainnetJson = string.concat(mainnetJson, _getGnosisTransaction(address(mainnetNttManager), abi.encodeWithSignature("setPeer(uint16,bytes32,uint8,uint256)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_NTT_MANAGER), 18, 150000000000000000000000), true));

        vm.writeFile("output/add-scroll-peer-mainnet.json", mainnetJson);
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");
        executeGnosisTransactionBundle("output/add-scroll-peer-mainnet.json", mainnetContractController);
        simulateSend(SCROLL_WORMHOLE_ID);


        string memory arbJson = _getGnosisHeader("42161");
        arbJson = string.concat(arbJson, _getGnosisTransaction(address(arbTransceiver), abi.encodeWithSignature("setIsWormholeRelayingEnabled(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        arbJson = string.concat(arbJson, _getGnosisTransaction(address(arbTransceiver), abi.encodeWithSignature("setWormholePeer(uint16,bytes32)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_TRANSCEIVER)), false));
        arbJson = string.concat(arbJson, _getGnosisTransaction(address(arbTransceiver), abi.encodeWithSignature("setIsWormholeEvmChain(uint16,bool)", SCROLL_WORMHOLE_ID, true), false));
        arbJson = string.concat(arbJson, _getGnosisTransaction(address(arbNttManager), abi.encodeWithSignature("setPeer(uint16,bytes32,uint8,uint256)", SCROLL_WORMHOLE_ID, toWormholeFormat(SCROLL_NTT_MANAGER), 18, 150000000000000000000000), true));

        vm.writeFile("output/add-scroll-peer-arb.json", arbJson);
        vm.createSelectFork("https://arbitrum-one.public.blastapi.io");
        executeGnosisTransactionBundle("output/add-scroll-peer-arb.json", arbContractController);
        simulateSend(SCROLL_WORMHOLE_ID);
       
    }

    function simulateSend(uint16 destinationPeer) public {
        address user = address(0x123);
        ERC20Upgradeable localEthfi = ERC20Upgradeable(address(0x0));
        NttManager localNttManager = NttManager(address(0x0));

        if (block.chainid == 1)  {
            localEthfi = mainnetEthfi;
            localNttManager = mainnetNttManager;

            deal(address(localEthfi), user, 50_000_000 ether);
            
        } else if (block.chainid == 42161) {
            vm.prank(ARB_NTT_MANAGER);
            EthfiL2Token(ARB_ETHFI).mint(user, 50_000_000 ether);

            localEthfi = arbEthfi;
            localNttManager = arbNttManager;
        } else if (block.chainid == 8453) {
            vm.prank(BASE_NTT_MANAGER);
            EthfiL2Token(BASE_ETHFI).mint(user, 50_000_000 ether);

            localEthfi = baseEthfi;
            localNttManager = baseNttManager;
        } else {
            vm.prank(SCROLL_NTT_MANAGER);
            EthfiL2Token(SCROLL_ETHFI).mint(user, 50_000_000 ether);

            localEthfi = scrollEthfi;
            localNttManager = scrollNttManager;
        }

        startHoax(user);
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


