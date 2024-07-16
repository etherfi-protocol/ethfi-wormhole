// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {NttManager, toWormholeFormat} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract transferNTT is Test {

    address public NTT_MANAGER = 0x344169Cc4abE9459e77bD99D13AA8589b55b6174;
    address public L1_ETHFI = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    uint16 public RECIPIENT_CHAIN = 23;

    // Gnosis Safe addresses
    address public SENDING_GNOSIS = 0x2382aAb6FDEDCc58bb07d692eda79bE96eb794bD;
    address public RECEIVING_GNOSIS = 0xbe2cfe1a304B6497E6f64525D0017AbaB7a5E8Cb;

    // CONFIGURATION VARS

    uint256 public transferAmount = 500000000000000000; // 1 ethfi

    function test_Transfer() public {
        vm.createSelectFork("https://mainnet.gateway.tenderly.co");

        vm.startPrank(SENDING_GNOSIS);

        NttManager nttManager = NttManager(NTT_MANAGER);
        ERC20Upgradeable ethfi = ERC20Upgradeable(L1_ETHFI);

        bytes32 destinationBytes = toWormholeFormat(RECEIVING_GNOSIS);

        ( , uint256 fee) = nttManager.quoteDeliveryPrice(RECIPIENT_CHAIN, new bytes(1));

        // simulating the approve and transfer
        ethfi.approve(NTT_MANAGER, transferAmount);
        nttManager.transfer{value: fee}(
            transferAmount,
            RECIPIENT_CHAIN,
            destinationBytes,
            destinationBytes,
            false,
            new bytes(1)
        );

        // building transaction based on simulation
        string memory gnosisString = _getGnosisHeader("1");

        // building the approval transaction
        bytes memory dataString = abi.encodeWithSignature("approve(address,uint256)", NTT_MANAGER, transferAmount);
        gnosisString = string.concat(gnosisString, _getGnosisTransaction(L1_ETHFI, 0, dataString, false));

        // building the transfer transaction
        bytes memory transferData = abi.encodeWithSignature("transfer(uint256,uint16,bytes32,bytes32,bool,bytes)", transferAmount, RECIPIENT_CHAIN, destinationBytes, destinationBytes, false, new bytes(1));
        gnosisString = string.concat(gnosisString, _getGnosisTransaction(NTT_MANAGER, fee, transferData, true));

        vm.writeJson(gnosisString, "./output/ethfiTransfer.json");

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
