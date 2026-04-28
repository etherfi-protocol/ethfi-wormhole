// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import {GnosisHelpers} from "./utils/GnosisHelpers.sol";

/// @notice Gnosis Safe batches for ETHFI OFT (CREATE3 mesh): pin LZ send/receive libraries + 4-DVN ULN (45 confirmations).
contract EthfiOftSecurityUpgrade is Script, GnosisHelpers {
    address internal constant ETHFI_OFT = 0xe0080d2F853ecDdbd81A643dC10DA075Df26fD3f;

    uint32 internal constant EID_ETHEREUM = 30101;
    uint32 internal constant EID_OP = 30111;
    uint32 internal constant EID_ARBITRUM = 30110;
    uint32 internal constant EID_BASE = 30184;
    uint32 internal constant EID_SCROLL = 30214;

    uint64 internal constant CONFIRMATIONS = 45;

    function run() external {
        _generateEthereum();
        _generateOptimism();
        _generateArbitrum();
        _generateBase();
        _generateScroll();
    }

    function _generateEthereum() internal {
        address[4] memory dvns = [
            0x589dEDbD617e0CBcB916A9223F4d1300c294236b,
            0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5,
            0x380275805876Ff19055EA900CDb2B46a94ecF20D,
            0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd
        ];
        uint32[] memory peers = new uint32[](4);
        peers[0] = EID_OP;
        peers[1] = EID_ARBITRUM;
        peers[2] = EID_BASE;
        peers[3] = EID_SCROLL;
        string memory json = _buildBatch(
            "1",
            0x2aCA71020De61bb532008049e1Bd41E451aE8AdC,
            0x1a44076050125825900e736c501f859c50fE728c,
            0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
            0xc02Ab410f0734EFa3F14628780e6e695156024C2,
            dvns,
            peers
        );
        vm.writeJson(json, "./output/ethfi-ethereum-SecurityUpgrade.json");
    }

    function _generateOptimism() internal {
        address[4] memory dvns = [
            0x6A02D83e8d433304bba74EF1c427913958187142,
            0xa7b5189bcA84Cd304D8553977c7C614329750d99,
            0x9E930731cb4A6bf7eCc11F695A295c60bDd212eB,
            0x5b6735c66d97479cCD18294fc96B3084EcB2fa3f
        ];
        uint32[] memory peers = new uint32[](4);
        peers[0] = EID_ETHEREUM;
        peers[1] = EID_ARBITRUM;
        peers[2] = EID_BASE;
        peers[3] = EID_SCROLL;
        string memory json = _buildBatch(
            "10",
            0x764682c769CcB119349d92f1B63ee1c03d6AECFf,
            0x1a44076050125825900e736c501f859c50fE728c,
            0x1322871e4ab09Bc7f5717189434f97bBD9546e95,
            0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063,
            dvns,
            peers
        );
        vm.writeJson(json, "./output/ethfi-op-SecurityUpgrade.json");
    }

    function _generateArbitrum() internal {
        address[4] memory dvns = [
            0x2f55C492897526677C5B68fb199ea31E2c126416,
            0xa7b5189bcA84Cd304D8553977c7C614329750d99,
            0x19670Df5E16bEa2ba9b9e68b48C054C5bAEa06B8,
            0xf2E380c90e6c09721297526dbC74f870e114dfCb
        ];
        uint32[] memory peers = new uint32[](4);
        peers[0] = EID_ETHEREUM;
        peers[1] = EID_OP;
        peers[2] = EID_BASE;
        peers[3] = EID_SCROLL;
        string memory json = _buildBatch(
            "42161",
            0x0c6ca434756EeDF928a55EBeAf0019364B279732,
            0x1a44076050125825900e736c501f859c50fE728c,
            0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
            0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6,
            dvns,
            peers
        );
        vm.writeJson(json, "./output/ethfi-arbitrum-SecurityUpgrade.json");
    }

    function _generateBase() internal {
        address[4] memory dvns = [
            0x9e059a54699a285714207b43B055483E78FAac25,
            0xcd37CA043f8479064e10635020c65FfC005d36f6,
            0xa7b5189bcA84Cd304D8553977c7C614329750d99,
            0x554833698Ae0FB22ECC90B01222903fD62CA4B47
        ];
        uint32[] memory peers = new uint32[](4);
        peers[0] = EID_ETHEREUM;
        peers[1] = EID_OP;
        peers[2] = EID_ARBITRUM;
        peers[3] = EID_SCROLL;
        string memory json = _buildBatch(
            "8453",
            0x7a00657a45420044bc526B90Ad667aFfaee0A868,
            0x1a44076050125825900e736c501f859c50fE728c,
            0xB5320B0B3a13cC860893E2Bd79FCd7e13484Dda2,
            0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf,
            dvns,
            peers
        );
        vm.writeJson(json, "./output/ethfi-base-SecurityUpgrade.json");
    }

    function _generateScroll() internal {
        address[4] memory dvns = [
            0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2,
            0x446755349101cB20c582C224462c3912d3584dCE,
            0x7fe673201724925B5c477d4E1A4Bd3E954688cF5,
            0xDF44a1594d3D516f7CDFb4DC275a79a5F6e3Db1d
        ];
        uint32[] memory peers = new uint32[](4);
        peers[0] = EID_ETHEREUM;
        peers[1] = EID_OP;
        peers[2] = EID_ARBITRUM;
        peers[3] = EID_BASE;
        string memory json = _buildBatch(
            "534352",
            0x3cD08f51D0EA86ac93368DE31822117cd70CECA3,
            0x1a44076050125825900e736c501f859c50fE728c,
            0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B,
            0x8363302080e711E0CAb978C081b9e69308d49808,
            dvns,
            peers
        );
        vm.writeJson(json, "./output/ethfi-scroll-SecurityUpgrade.json");
    }

    function _buildBatch(
        string memory chainIdStr,
        address controller,
        address endpoint,
        address sendLib,
        address recvLib,
        address[4] memory dvns,
        uint32[] memory peerEids
    ) internal returns (string memory json) {
        address oft = ETHFI_OFT;
        string memory safeHex = _toLowerString(addressToHex(controller));
        json = _getGnosisHeader(chainIdStr, safeHex);
        string memory endpointHex = addressToHex(endpoint);

        for (uint256 i = 0; i < peerEids.length; i++) {
            string memory sendData = iToHex(
                abi.encodeWithSignature("setSendLibrary(address,uint32,address)", oft, peerEids[i], sendLib)
            );
            json = string.concat(json, _getGnosisTransaction(endpointHex, sendData, "0", false));
            string memory recvData = iToHex(
                abi.encodeWithSignature("setReceiveLibrary(address,uint32,address,uint256)", oft, peerEids[i], recvLib, uint256(0))
            );
            json = string.concat(json, _getGnosisTransaction(endpointHex, recvData, "0", false));
        }

        bytes memory ulnBytes = _encode4DVNUlnConfig(dvns);
        SetConfigParam[] memory dvnParams = new SetConfigParam[](peerEids.length);
        for (uint256 j = 0; j < peerEids.length; j++) {
            dvnParams[j] = SetConfigParam({eid: peerEids[j], configType: 2, config: ulnBytes});
        }

        string memory sendCfg =
            iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", oft, sendLib, dvnParams));
        json = string.concat(json, _getGnosisTransaction(endpointHex, sendCfg, "0", false));

        string memory recvCfg =
            iToHex(abi.encodeWithSignature("setConfig(address,address,(uint32,uint32,bytes)[])", oft, recvLib, dvnParams));
        json = string.concat(json, _getGnosisTransaction(endpointHex, recvCfg, "0", true));
    }

    function _toLowerString(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                b[i] = bytes1(uint8(b[i]) + 32);
            }
        }
        return string(b);
    }

    function _encode4DVNUlnConfig(address[4] memory dvn) internal pure returns (bytes memory) {
        address[] memory requiredDVNs = new address[](4);
        requiredDVNs[0] = dvn[0];
        requiredDVNs[1] = dvn[1];
        requiredDVNs[2] = dvn[2];
        requiredDVNs[3] = dvn[3];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3 - i; j++) {
                if (requiredDVNs[j] > requiredDVNs[j + 1]) {
                    (requiredDVNs[j], requiredDVNs[j + 1]) = (requiredDVNs[j + 1], requiredDVNs[j]);
                }
            }
        }
        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: CONFIRMATIONS,
            requiredDVNCount: 4,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });
        return abi.encode(ulnConfig);
    }
}
