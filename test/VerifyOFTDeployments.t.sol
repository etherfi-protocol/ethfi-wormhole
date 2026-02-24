// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {ContractCodeChecker} from "../script/utils/ContractCodeChecker.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EtherfiOFTAdapterUpgradeable} from "../src/OFT/EtherfiOFTAdapterUpgradeable.sol";
import {EtherfiMintBurnOFTAdapter} from "../src/OFT/EtherfiMintBurnOFTAdapter.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";
import {NttConstants} from "../utils/constants.sol";

contract VerifyOFTDeployments is ContractCodeChecker, Test, NttConstants {
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant MAINNET_IMPL = 0xCc2b11A4Ff737F4A23f55d49eca7D9b03E502b9D;
    address constant L2_TOKEN_IMPL = 0x5E5dB775D9D0049271E50a83E24663ac38F7ec34;
    address constant DEPLOYER = 0x5fd4b71C0e46FFb377EF6111459d0Fb1C968395e;

    function test_mainnet_verifyOFTAdapterImplBytecode() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        address localImpl = address(new EtherfiOFTAdapterUpgradeable(MAINNET_ETHFI, LZ_ENDPOINT));
        console.log("Mainnet - verifying implementation at", MAINNET_IMPL);
        verifyContractByteCodeMatch(MAINNET_IMPL, localImpl);
    }

    function test_mainnet_verifyOFTProxyBytecode() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        address localImpl = address(new EtherfiOFTAdapterUpgradeable(MAINNET_ETHFI, LZ_ENDPOINT));
        bytes memory initData = abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (DEPLOYER));
        address localProxy = address(new ERC1967Proxy(localImpl, initData));

        console.log("Mainnet - verifying proxy at", OFT);
        verifyContractByteCodeMatch(OFT, localProxy);
    }

    function test_arbitrum_verifyMintBurnOFTBytecode() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");

        address localDeploy = address(
            new EtherfiMintBurnOFTAdapter(ARB_ETHFI, IMintableBurnable(ARB_ETHFI), LZ_ENDPOINT, DEPLOYER)
        );
        console.log("Arbitrum - verifying OFT at", OFT);
        verifyContractByteCodeMatch(OFT, localDeploy);
    }

    function test_base_verifyMintBurnOFTBytecode() public {
        vm.createSelectFork("https://mainnet.base.org");

        address localDeploy = address(
            new EtherfiMintBurnOFTAdapter(BASE_ETHFI, IMintableBurnable(BASE_ETHFI), LZ_ENDPOINT, DEPLOYER)
        );
        console.log("Base - verifying OFT at", OFT);
        verifyContractByteCodeMatch(OFT, localDeploy);
    }

    function test_scroll_verifyMintBurnOFTBytecode() public {
        vm.createSelectFork("https://rpc.scroll.io");

        address localDeploy = address(
            new EtherfiMintBurnOFTAdapter(SCROLL_ETHFI, IMintableBurnable(SCROLL_ETHFI), LZ_ENDPOINT, DEPLOYER)
        );
        console.log("Scroll - verifying OFT at", OFT);
        verifyContractByteCodeMatch(OFT, localDeploy);
    }

    // ========================= L2 Token Impl Verification ========================

    function test_arbitrum_verifyL2TokenImplBytecode() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        _verifyL2TokenImpl("Arbitrum");
    }

    function test_base_verifyL2TokenImplBytecode() public {
        vm.createSelectFork("https://mainnet.base.org");
        _verifyL2TokenImpl("Base");
    }

    function test_scroll_verifyL2TokenImplBytecode() public {
        vm.createSelectFork("https://rpc.scroll.io");
        _verifyL2TokenImpl("Scroll");
    }

    function _verifyL2TokenImpl(string memory chain) internal {
        address local = address(new EthfiL2Token());
        console.log(string.concat(chain, " - verifying L2 token impl at"), L2_TOKEN_IMPL);
        verifyContractByteCodeMatch(L2_TOKEN_IMPL, local);
    }
}
