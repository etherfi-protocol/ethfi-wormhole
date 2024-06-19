// SPDX license identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {NttManager} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {NttConstants} from "../utils/constants.sol";

contract TransferCrossChain is Script, NttConstants {
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
