// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {ContractCodeChecker} from "../script/utils/ContractCodeChecker.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EtherfiOFTAdapterUpgradeable} from "../src/OFT/EtherfiOFTAdapterUpgradeable.sol";
import {EtherfiMintBurnOFTAdapter} from "../src/OFT/EtherfiMintBurnOFTAdapter.sol";
import {EthfiL2Token} from "../src/token/EthfiL2Token.sol";
import {IManagerBase} from "@wormhole-foundation/native_token_transfer/interfaces/IManagerBase.sol";
import {NttManagerUpgradeable} from "../src/NTT/NttManagerUpgradeable.sol";
import {NttConstants} from "../utils/constants.sol";

contract VerifyOFTDeployments is ContractCodeChecker, Test, NttConstants {
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant MAINNET_OFT_IMPL = 0xCc2b11A4Ff737F4A23f55d49eca7D9b03E502b9D;
    address constant DEPLOYER = 0x5fd4b71C0e46FFb377EF6111459d0Fb1C968395e;

    function test_mainnet() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        address localOFTImpl = address(new EtherfiOFTAdapterUpgradeable(MAINNET_ETHFI, LZ_ENDPOINT));
        console.log("Mainnet - verifying OFT implementation at", MAINNET_OFT_IMPL);
        verifyContractByteCodeMatch(MAINNET_OFT_IMPL, localOFTImpl);

        bytes memory initData = abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (DEPLOYER));
        address localProxy = address(new ERC1967Proxy(localOFTImpl, initData));
        console.log("Mainnet - verifying OFT proxy at", OFT);
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

/// @notice NttManager impl was deployed with FOUNDRY_PROFILE=production (via_ir=true)
///         and --optimizer-runs 100. Run with: FOUNDRY_PROFILE=production forge test
///         --match-contract VerifyNttManagerDeployment --optimizer-runs 100 -vv
contract VerifyNttManagerDeployment is ContractCodeChecker, Test, NttConstants {

    function test_mainnet() public {
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io");

        address localNttImpl = address(new NttManagerUpgradeable(
            MAINNET_ETHFI,
            IManagerBase.Mode.LOCKING,
            MAINNET_WORMHOLE_ID,
            uint64(RATE_LIMIT_DURATION),
            false
        ));
        console.log("Mainnet - verifying NttManager impl at", MAINNET_NTT_MANAGER_IMPL);
        verifyContractByteCodeMatch(MAINNET_NTT_MANAGER_IMPL, localNttImpl);
    }
}
