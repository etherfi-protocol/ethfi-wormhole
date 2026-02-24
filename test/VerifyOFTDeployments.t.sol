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

    function test_mainnet() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        address localImpl = address(new EtherfiOFTAdapterUpgradeable(MAINNET_ETHFI, LZ_ENDPOINT));
        console.log("Mainnet - verifying implementation at", MAINNET_IMPL);
        verifyContractByteCodeMatch(MAINNET_IMPL, localImpl);

        bytes memory initData = abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (DEPLOYER));
        address localProxy = address(new ERC1967Proxy(localImpl, initData));
        console.log("Mainnet - verifying proxy at", OFT);
        verifyContractByteCodeMatch(OFT, localProxy);
    }

    function test_arbitrum() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        _verifyL2("Arbitrum", ARB_ETHFI);
    }

    function test_base() public {
        vm.createSelectFork("https://mainnet.base.org");
        _verifyL2("Base", BASE_ETHFI);
    }

    function test_scroll() public {
        vm.createSelectFork("https://rpc.scroll.io");
        _verifyL2("Scroll", SCROLL_ETHFI);
    }

    function _verifyL2(string memory chain, address token) internal {
        address localOFT = address(
            new EtherfiMintBurnOFTAdapter(token, IMintableBurnable(token), LZ_ENDPOINT, DEPLOYER)
        );
        console.log(string.concat(chain, " - verifying OFT at"), OFT);
        verifyContractByteCodeMatch(OFT, localOFT);

        address localTokenImpl = address(new EthfiL2Token());
        console.log(string.concat(chain, " - verifying L2 token impl at"), L2_TOKEN_IMPL);
        verifyContractByteCodeMatch(L2_TOKEN_IMPL, localTokenImpl);
    }
}
