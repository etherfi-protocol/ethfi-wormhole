// SPDX license identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

address constant MAINNET_NTT_MANAGER = 0x344169Cc4abE9459e77bD99D13AA8589b55b6174;
address constant MAINNET_TRANSCEIVER = 0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186;
address constant MAINNET_ETHFI = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;

address constant ARB_NTT_MANAGER = 0x90A82462258F79780498151EF6f663f1D4BE4E3b;
address constant ARB_TRANSCEIVER = 0x4386e36B96D437b0F1C04A35E572C10C6627d88a;
address constant ARB_ETHFI = 0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27;

contract TransferCrossChain is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        if (block.chainid == 1) {
            _transferEthtoArb();
        } else if (block.chainid == 42161) {
            _transferArbToEth();
        } else {
            revert("Unsupported chain");
        }
        vm.stopBroadcast();
    }

    function _transferEthtoArb() internal {
        IERC20 ethfi = IERC20(MAINNET_ETHFI);

        ethfi.approve(MAINNET_NTT_MANAGER, 1000000000000000000);

        NttManager mainnetNttManager = NttManager(MAINNET_NTT_MANAGER);
       (,uint256 price) = mainnetNttManager.quoteDeliveryPrice(23, new bytes(1));

        price = price * 11 / 10;
        mainnetNttManager.transfer{value: price}(
            1000000000000000000,
            23,
            0x000000000000000000000000C83bb94779c5577AF1D48dF8e2A113dFf0cB127c
        );
    }

    function _transferArbToEth() internal {
        IERC20 ethfi = IERC20(ARB_ETHFI);

        ethfi.approve(ARB_NTT_MANAGER, 1000000000000000000);

        NttManager arbNttManager = NttManager(ARB_NTT_MANAGER);
       (,uint256 price) = arbNttManager.quoteDeliveryPrice(2, new bytes(1));

        price = price * 11 / 10;
        arbNttManager.transfer{value: price}(
            1000000000000000000,
            2,
            0x000000000000000000000000C83bb94779c5577AF1D48dF8e2A113dFf0cB127c
        );
    }
}
