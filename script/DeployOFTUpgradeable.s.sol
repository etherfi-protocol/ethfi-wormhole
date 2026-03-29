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

import {OFTUpgradeable} from "../src/OFT/OFTUpgradeable.sol";
import {NttConstants} from "../utils/constants.sol";
import {ICreateX} from "./utils/ICreateX.sol";

/// @title DeployOFTUpgradeable
/// @notice Deploys the simplified OFTUpgradeable via CREATE3 (same address as existing chains),
///         configures a full LayerZero mesh with LZ Labs + Nethermind DVNs, and transfers ownership.
/// @dev Run on OP Mainnet:
///   forge script script/DeployOFTUpgradeable.s.sol --rpc-url <op-rpc> --broadcast --account deployer
contract DeployOFTUpgradeable is Script, NttConstants {
    using OptionsBuilder for bytes;

    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    bytes32 internal constant DEPLOY_SALT = keccak256("etherfi-oft-adapter-v1");

    string internal constant TOKEN_NAME = "ether.fi governance token";
    string internal constant TOKEN_SYMBOL = "ETHFI";

    struct LocalConfig {
        uint256 chainId;
        uint32 eid;
        uint64 confirmations;
        address controller;
        address endpoint;
        address sendLib;
        address receiveLib;
        address dvn1; // sorted: dvn1 < dvn2
        address dvn2;
    }

    struct RemoteChain {
        uint32 eid;
        uint64 confirmations;
    }

    // ========================= OP CONFIG =============================================

    function _getOPConfig() internal pure returns (LocalConfig memory) {
        return LocalConfig({
            chainId: 10,
            eid: 30111,
            confirmations: 20,
            controller: OP_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0x1322871e4ab09Bc7f5717189434f97bBD9546e95,
            receiveLib: 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063,
            dvn1: 0x6A02D83e8d433304bba74EF1c427913958187142, // LZ Labs
            dvn2: 0xa7b5189bcA84Cd304D8553977c7C614329750d99  // Nethermind
        });
    }

    function _getRemoteChains() internal pure returns (RemoteChain[4] memory remotes) {
        remotes[0] = RemoteChain({eid: 30101, confirmations: 20}); // Mainnet
        remotes[1] = RemoteChain({eid: 30110, confirmations: 20}); // Arbitrum
        remotes[2] = RemoteChain({eid: 30184, confirmations: 20}); // Base
        remotes[3] = RemoteChain({eid: 30214, confirmations: 20}); // Scroll
        // TODO: add remote chains here as we add new chains
    }

    // ========================= ENTRY POINT ===========================================

    function run() external {
        LocalConfig memory local = _getOPConfig();
        require(block.chainid == local.chainId, "Wrong chain");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);


        vm.startBroadcast(deployerPrivateKey);

        address oft = _deploy(local.endpoint, deployer);
        console.log("Deployed OFT at:", oft);
        require(oft == OFT, "CREATE3 address mismatch");

        _configureMesh(oft, local);

        _transferOwnership(oft, local.controller);

        vm.stopBroadcast();

        console.log("=== Deployment complete on OP ===");
    }

    // ========================= DEPLOYMENT ============================================

    function _deploy(address lzEndpoint, address deployer) internal returns (address) {
        OFTUpgradeable impl = new OFTUpgradeable(lzEndpoint);
        console.log("OFTUpgradeable impl deployed at:", address(impl));

        bytes memory initData = abi.encodeCall(
            OFTUpgradeable.initialize,
            (TOKEN_NAME, TOKEN_SYMBOL, deployer)
        );

        bytes memory proxyInitCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(address(impl), initData)
        );

        return CREATEX.deployCreate3(DEPLOY_SALT, proxyInitCode);
    }

    // ========================= LZ MESH CONFIG ========================================

    function _configureMesh(address oft, LocalConfig memory local) internal {
        RemoteChain[4] memory remotes = _getRemoteChains();

        address[] memory dvns = new address[](2);
        dvns[0] = local.dvn1;
        dvns[1] = local.dvn2;

        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(local.endpoint);

        for (uint256 i = 0; i < remotes.length; i++) {
            uint32 remoteEid = remotes[i].eid;

            endpoint.setSendLibrary(oft, remoteEid, local.sendLib);
            endpoint.setReceiveLibrary(oft, remoteEid, local.receiveLib, 0);

            _setSendConfig(local.endpoint, oft, local.sendLib, dvns, remoteEid, remotes[i].confirmations);
            _setReceiveConfig(local.endpoint, oft, local.receiveLib, dvns, remoteEid, local.confirmations);
            _setEnforcedOptions(oft, remoteEid);

            IOAppCore(oft).setPeer(remoteEid, bytes32(uint256(uint160(oft))));

            console.log("Configured pathway to EID:", remoteEid);
        }
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

    // ========================= OWNERSHIP =============================================

    function _transferOwnership(address oft, address controller) internal {
        IOAppCore(oft).setDelegate(controller);
        OFTUpgradeable(oft).transferOwnership(controller);
        console.log("Ownership & delegate transferred to:", controller);
    }
}
