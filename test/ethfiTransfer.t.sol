// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {NttManager, toWormholeFormat} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {NttConstants} from "../utils/constants.sol";

contract transferNTT is Test, NttConstants {

    // Gnosis Safe addresses
    address public SENDING_GNOSIS = 0x5f0E7A424d306e9E310be4f5Bb347216e473Ae55;
    address public ARB_RECEIVING_GNOSIS = 0xbe2cfe1a304B6497E6f64525D0017AbaB7a5E8Cb;
    address public BASE_RECEIVING_GNOSIS = 0x6e08f190933b537070995c555693e12439DE8fB4;

    /////////////////////// CONFIGURATION VARS /////////////////////////

    uint256 public TRANSFER_AMOUNT = 130000000000000000000000;
    uint16 public RECIPIENT_CHAIN = BASE_WORMHOLE_ID;

    /////////////////////// CONFIGURATION VARS /////////////////////////

    function test_Transfer() public {
        vm.createSelectFork("https://mainnet.gateway.tenderly.co");

        vm.startPrank(SENDING_GNOSIS);

        NttManager nttManager = NttManager(MAINNET_NTT_MANAGER);
        ERC20Upgradeable ethfi = ERC20Upgradeable(MAINNET_ETHFI);

        address receivingGnosis;
        if (RECIPIENT_CHAIN == ARB_WORMHOLE_ID) {
            receivingGnosis = ARB_RECEIVING_GNOSIS;
        } else if (RECIPIENT_CHAIN == BASE_WORMHOLE_ID) {
            receivingGnosis = BASE_RECEIVING_GNOSIS;
        } else {
            revert("Unsupported chain");
        }

        bytes32 destinationBytes = toWormholeFormat(receivingGnosis);

        (, uint256 fee) = nttManager.quoteDeliveryPrice(RECIPIENT_CHAIN, new bytes(1));

        fee = fee * 2;

        // simulating the approve and transfer
        ethfi.approve(MAINNET_NTT_MANAGER, TRANSFER_AMOUNT);
        nttManager.transfer{value: fee}(
            TRANSFER_AMOUNT,
            RECIPIENT_CHAIN,
            destinationBytes,
            destinationBytes,
            false,
            new bytes(1)
        );

        // building transaction based on simulation
        string memory gnosisString = _getGnosisHeader("1");

        // building the approval transaction
        bytes memory dataString = abi.encodeWithSignature("approve(address,uint256)", MAINNET_NTT_MANAGER, TRANSFER_AMOUNT);
        gnosisString = string.concat(gnosisString, _getGnosisTransaction(MAINNET_ETHFI, 0, dataString, false));

        // building the transfer transaction
        bytes memory transferData = abi.encodeWithSignature("transfer(uint256,uint16,bytes32,bytes32,bool,bytes)", TRANSFER_AMOUNT, RECIPIENT_CHAIN, destinationBytes, destinationBytes, false, new bytes(1));
        gnosisString = string.concat(gnosisString, _getGnosisTransaction(MAINNET_NTT_MANAGER, fee, transferData, true));

        string memory transferAmountInETH = vm.toString(TRANSFER_AMOUNT / 10**18);
        string memory destinationChain;
        if (RECIPIENT_CHAIN == ARB_WORMHOLE_ID) {
            destinationChain = "Arb";
        } else if (RECIPIENT_CHAIN == BASE_WORMHOLE_ID) {
            destinationChain = "Base";
        }

        vm.writeJson(gnosisString, string.concat("./output/ethfiTransfer_", transferAmountInETH,"_to", destinationChain, ".json"));
    }

    // Get the gnosis transaction header
    function _getGnosisHeader(string memory chainId) internal pure returns (string memory) {
        return string.concat('{"chainId":"', chainId, '","meta": { "txBuilderVersion": "1.16.5" }, "transactions": [');
    }

    // Create a gnosis transaction
    function _getGnosisTransaction(address to, uint256 value, bytes memory data, bool isLast) internal pure returns (string memory) {
        // convert the inputs to encoded hex string
        string memory toHex = bToHex(abi.encodePacked(to));
        string memory valueHex = bToHex(abi.encodePacked(value));
        string memory dataHex = bToHex(data);
        
        string memory suffix = isLast ? ']}' : ',';
        return string.concat('{"to":"', toHex, '","value":"', valueHex , '","data":"', dataHex, '"}', suffix);
    }

    // Helper function to convert bytes to hex strings 
    function bToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }
}
