// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IMintableBurnable} from "@layerzerolabs/oft-evm/contracts/interfaces/IMintableBurnable.sol";

import {EtherfiOFTAdapterUpgradeable} from "../src/OFT/EtherfiOFTAdapterUpgradeable.sol";
import {EtherfiMintBurnOFTAdapter} from "../src/OFT/EtherfiMintBurnOFTAdapter.sol";

import {NttConstants} from "../utils/constants.sol";
import {ICreateX} from "./utils/ICreateX.sol";

/// @title DeployOFT
/// @notice Deploys OFT adapters via CREATE3 for deterministic same-address across chains,
///         configures a full LayerZero mesh with LZ Labs + Nethermind DVNs, and transfers ownership.
/// @dev Run once per chain from the same deployer EOA:
///   forge script script/DeployOFT.s.sol --rpc-url <rpc> --broadcast --account deployer
contract DeployOFT is Script, NttConstants {
    using OptionsBuilder for bytes;

    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    bytes32 internal constant DEPLOY_SALT = keccak256("etherfi-oft-adapter-v1");

    struct ChainConfig {
        uint256 chainId;
        uint32 eid;
        uint64 confirmations;
        address token;
        address controller;
        address endpoint;
        address sendLib;
        address receiveLib;
        address dvn1;  // sorted: dvn1 < dvn2
        address dvn2;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);

        ChainConfig[4] memory chains = _getChainConfigs();

        uint256 localIndex = _findLocalChain(chains);

        vm.startBroadcast(deployerPrivateKey);

        address oft = _deploy(chains[localIndex], deployer, chains[localIndex].endpoint);
        console.log("Deployed OFT at:", oft);

        _configureMesh(oft, chains, localIndex);

        _transferOwnership(oft, chains[localIndex], deployer);

        vm.stopBroadcast();

        console.log("=== Deployment complete on chain", block.chainid, "===");
    }

    function _getChainConfigs() internal pure returns (ChainConfig[4] memory chains) {
        chains[0] = ChainConfig({
            chainId: 1,
            eid: 30101,
            confirmations: 20,
            token: MAINNET_ETHFI,
            controller: MAINNET_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
            receiveLib: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,
            dvn1: 0x589dEDbD617e0CBcB916A9223F4d1300c294236b, // LZ Labs
            dvn2: 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5  // Nethermind
        });
        chains[1] = ChainConfig({
            chainId: 42161,
            eid: 30110,
            confirmations: 20,
            token: ARB_ETHFI,
            controller: ARB_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
            receiveLib: 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6,
            dvn1: 0x2f55C492897526677C5B68fb199ea31E2c126416, // LZ Labs
            dvn2: 0xa7b5189bcA84Cd304D8553977c7C614329750d99  // Nethermind
        });
        chains[2] = ChainConfig({
            chainId: 8453,
            eid: 30184,
            confirmations: 20,
            token: BASE_ETHFI,
            controller: BASE_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
            receiveLib: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
            dvn1: 0x9e059a54699a285714207b43B055483E78FAac25, // LZ Labs
            dvn2: 0xcd37CA043f8479064e10635020c65FfC005d36f6  // Nethermind
        });
        chains[3] = ChainConfig({
            chainId: 534352,
            eid: 30214,
            confirmations: 20,
            token: SCROLL_ETHFI,
            controller: SCROLL_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B,
            receiveLib: 0x8363302080e711E0CAb978C081b9e69308d49808,
            dvn1: 0x446755349101cB20c582C224462c3912d3584dCE, // Nethermind
            dvn2: 0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2  // LZ Labs
        });
    }

    function _findLocalChain(ChainConfig[4] memory chains) internal view returns (uint256) {
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i].chainId == block.chainid) return i;
        }
        revert("Unsupported chain");
    }

    // ========================= DEPLOYMENT =========================================

    function _deploy(ChainConfig memory chain, address deployer, address lzEndpoint) internal returns (address) {
        if (block.chainid == 1) {
            return _deployMainnet(chain.token, deployer, lzEndpoint);
        } else {
            return _deployL2(chain.token, deployer, lzEndpoint);
        }
    }

    function _deployMainnet(address token, address deployer, address lzEndpoint) internal returns (address) {
        EtherfiOFTAdapterUpgradeable impl = new EtherfiOFTAdapterUpgradeable(token, lzEndpoint);
        console.log("Mainnet impl deployed at:", address(impl));

        bytes memory initData = abi.encodeCall(EtherfiOFTAdapterUpgradeable.initialize, (deployer));
        bytes memory proxyInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(impl), initData)
        );

        return CREATEX.deployCreate3(DEPLOY_SALT, proxyInitCode);
    }

    function _deployL2(address token, address deployer, address lzEndpoint) internal returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(EtherfiMintBurnOFTAdapter).creationCode,
            abi.encode(token, IMintableBurnable(token), lzEndpoint, deployer)
        );

        return CREATEX.deployCreate3(DEPLOY_SALT, initCode);
    }

    // ========================= LZ MESH CONFIG =====================================

    struct LZContext {
        address endpoint;
        address sendLib;
        address receiveLib;
        address[] dvns;
        uint64 localConfirmations;
    }

    function _configureMesh(
        address oft,
        ChainConfig[4] memory chains,
        uint256 localIndex
    ) internal {
        ChainConfig memory local = chains[localIndex];
        address[] memory dvns = new address[](2);
        dvns[0] = local.dvn1;
        dvns[1] = local.dvn2;

        LZContext memory lz = LZContext({
            endpoint: local.endpoint,
            sendLib: local.sendLib,
            receiveLib: local.receiveLib,
            dvns: dvns,
            localConfirmations: local.confirmations
        });

        for (uint256 i = 0; i < chains.length; i++) {
            if (i == localIndex) continue;
            _configurePathway(oft, lz, chains[i].eid, chains[i].confirmations);
            console.log("Configured pathway to EID:", chains[i].eid);
        }
    }

    function _configurePathway(address oft, LZContext memory lz, uint32 remoteEid, uint64 remoteConfirmations) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(lz.endpoint);

        endpoint.setSendLibrary(oft, remoteEid, lz.sendLib);
        endpoint.setReceiveLibrary(oft, remoteEid, lz.receiveLib, 0);

        _setSendConfig(lz.endpoint, oft, lz.sendLib, lz.dvns, remoteEid, remoteConfirmations);
        _setReceiveConfig(lz.endpoint, oft, lz.receiveLib, lz.dvns, remoteEid, lz.localConfirmations);
        _setEnforcedOptions(oft, remoteEid);

        IOAppCore(oft).setPeer(remoteEid, bytes32(uint256(uint160(oft))));
    }

    function _setSendConfig(
        address lzEndpoint,
        address oft,
        address sendLib,
        address[] memory dvns,
        uint32 remoteEid,
        uint64 confirmations
    ) internal {
        SetConfigParam[] memory params = new SetConfigParam[](1);

        params[0] = SetConfigParam({
            eid: remoteEid,
            configType: 2,
            config: abi.encode(UlnConfig({
                confirmations: confirmations,
                requiredDVNCount: 2,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: dvns,
                optionalDVNs: new address[](0)
            }))
        });

        ILayerZeroEndpointV2(lzEndpoint).setConfig(oft, sendLib, params);
    }

    function _setReceiveConfig(
        address lzEndpoint,
        address oft,
        address receiveLib,
        address[] memory dvns,
        uint32 remoteEid,
        uint64 confirmations
    ) internal {
        SetConfigParam[] memory params = new SetConfigParam[](1);

        params[0] = SetConfigParam({
            eid: remoteEid,
            configType: 2,
            config: abi.encode(UlnConfig({
                confirmations: confirmations,
                requiredDVNCount: 2,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: dvns,
                optionalDVNs: new address[](0)
            }))
        });

        ILayerZeroEndpointV2(lzEndpoint).setConfig(oft, receiveLib, params);
    }

    function _setEnforcedOptions(address oft, uint32 remoteEid) internal {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);

        enforcedOptions[0] = EnforcedOptionParam({
            eid: remoteEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: remoteEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });

        IOAppOptionsType3(oft).setEnforcedOptions(enforcedOptions);
    }

    // ========================= OWNERSHIP ==========================================

    function _transferOwnership(address oft, ChainConfig memory chain, address deployer) internal {
        IOAppCore(oft).setDelegate(chain.controller);

        if (block.chainid == 1) {
            EtherfiOFTAdapterUpgradeable adapter = EtherfiOFTAdapterUpgradeable(oft);
            adapter.grantRole(adapter.DEFAULT_ADMIN_ROLE(), chain.controller);
            adapter.renounceRole(adapter.DEFAULT_ADMIN_ROLE(), deployer);
            adapter.transferOwnership(chain.controller);
        } else {
            EtherfiMintBurnOFTAdapter(oft).transferOwnership(chain.controller);
        }

        console.log("Ownership & delegate transferred to:", chain.controller);
    }

}
