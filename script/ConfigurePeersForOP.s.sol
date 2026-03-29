// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {NttConstants} from "../utils/constants.sol";
import {GnosisHelpers} from "./utils/GnosisHelpers.sol";

/// @title ConfigurePeersForOP
/// @notice Generates Gnosis Safe Transaction Builder JSON bundles for each existing chain
///         to peer their OFT with the new OP deployment.
/// @dev Run (no RPC needed, pure calldata generation):
///   forge script script/ConfigurePeersForOP.s.sol
contract ConfigurePeersForOP is GnosisHelpers, NttConstants {
    using OptionsBuilder for bytes;

    uint32 internal constant OP_EID = 30111;
    uint64 internal constant CONFIRMATIONS = 20;

    struct ChainConfig {
        string name;
        string chainId;
        address controller;
        address endpoint;
        address sendLib;
        address receiveLib;
        address dvn1; // sorted: dvn1 < dvn2
        address dvn2;
    }

    function _getChainConfigs() internal pure returns (ChainConfig[4] memory chains) {
        chains[0] = ChainConfig({
            name: "mainnet",
            chainId: "1",
            controller: MAINNET_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
            receiveLib: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,
            dvn1: 0x589dEDbD617e0CBcB916A9223F4d1300c294236b, // LZ Labs
            dvn2: 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5  // Nethermind
        });
        chains[1] = ChainConfig({
            name: "arbitrum",
            chainId: "42161",
            controller: ARB_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
            receiveLib: 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6,
            dvn1: 0x2f55C492897526677C5B68fb199ea31E2c126416, // LZ Labs
            dvn2: 0xa7b5189bcA84Cd304D8553977c7C614329750d99  // Nethermind
        });
        chains[2] = ChainConfig({
            name: "base",
            chainId: "8453",
            controller: BASE_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
            receiveLib: 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
            dvn1: 0x9e059a54699a285714207b43B055483E78FAac25, // LZ Labs
            dvn2: 0xcd37CA043f8479064e10635020c65FfC005d36f6  // Nethermind
        });
        chains[3] = ChainConfig({
            name: "scroll",
            chainId: "534352",
            controller: SCROLL_CONTRACT_CONTROLLER,
            endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            sendLib: 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B,
            receiveLib: 0x8363302080e711E0CAb978C081b9e69308d49808,
            dvn1: 0x446755349101cB20c582C224462c3912d3584dCE, // Nethermind
            dvn2: 0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2  // LZ Labs
        });
    }

    function run() external {
        ChainConfig[4] memory chains = _getChainConfigs();

        string memory setPeerData = iToHex(
            abi.encodeWithSignature(
                "setPeer(uint32,bytes32)",
                OP_EID,
                bytes32(uint256(uint160(OFT)))
            )
        );

        string memory setEnforcedOptionsData = _buildEnforcedOptionsData();

        for (uint256 i = 0; i < chains.length; i++) {
            string memory bundle = _buildBundle(chains[i], setPeerData, setEnforcedOptionsData);

            string memory path = string.concat("output/", chains[i].name, "-op-peer.json");
            vm.writeFile(path, bundle);
            console.log("Written:", path);
        }
    }

    function _buildBundle(
        ChainConfig memory chain,
        string memory setPeerData,
        string memory setEnforcedOptionsData
    ) internal pure returns (string memory) {
        string memory oftHex = addressToHex(OFT);
        string memory endpointHex = addressToHex(chain.endpoint);
        string memory safeHex = addressToHex(chain.controller);

        string memory setConfigSendData = _buildSetConfigData(OFT, chain.sendLib, chain.dvn1, chain.dvn2);
        string memory setConfigReceiveData = _buildSetConfigData(OFT, chain.receiveLib, chain.dvn1, chain.dvn2);

        return string.concat(
            _getGnosisHeader(chain.chainId, safeHex),
            _getGnosisTransaction(oftHex, setPeerData, "0", false),
            _getGnosisTransaction(oftHex, setEnforcedOptionsData, "0", false),
            _getGnosisTransaction(endpointHex, setConfigSendData, "0", false),
            _getGnosisTransaction(endpointHex, setConfigReceiveData, "0", true)
        );
    }

    function _buildEnforcedOptionsData() internal pure returns (string memory) {
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](2);
        opts[0] = EnforcedOptionParam({
            eid: OP_EID,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });
        opts[1] = EnforcedOptionParam({
            eid: OP_EID,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });

        return iToHex(abi.encodeWithSelector(IOAppOptionsType3.setEnforcedOptions.selector, opts));
    }

    function _buildSetConfigData(
        address oft,
        address lib,
        address dvn1,
        address dvn2
    ) internal pure returns (string memory) {
        address[] memory dvns = new address[](2);
        dvns[0] = dvn1;
        dvns[1] = dvn2;

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({
            eid: OP_EID,
            configType: 2,
            config: abi.encode(UlnConfig({
                confirmations: CONFIRMATIONS,
                requiredDVNCount: 2,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: dvns,
                optionalDVNs: new address[](0)
            }))
        });

        return iToHex(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                oft,
                lib,
                params
            )
        );
    }
}
