// SPDX license identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {NttManager, toWormholeFormat} from "@wormhole-foundation/native_token_transfer/NttManager/NttManager.sol";

import {NttConstants} from "../utils/constants.sol";

contract TransferCrossChain is Script, NttConstants {

    address public deployer;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        // set the destination chain
        uint16 desinationChain = BASE_WORMHOLE_ID;

        if (block.chainid == 1) {
            _transferFromEth(desinationChain);
        } else if (block.chainid == 42161) {
            _transferFromArb(desinationChain);
        } else if (block.chainid == 8453){
            _transferFromBase(desinationChain);
        }
        vm.stopBroadcast();
    }

    function _transferFromEth(uint16 destinationEndpoint) internal {
        IERC20 ethfi = IERC20(MAINNET_ETHFI);

        ethfi.approve(MAINNET_NTT_MANAGER, 0.5 ether);

        NttManager mainnetNttManager = NttManager(MAINNET_NTT_MANAGER);
       (,uint256 price) = mainnetNttManager.quoteDeliveryPrice(destinationEndpoint, new bytes(1));

        mainnetNttManager.transfer{value: price}(
            0.5 ether,
            destinationEndpoint,
            toWormholeFormat(deployer)
        );
    }

    function _transferFromArb(uint16 destinationEndpoint) internal {
        IERC20 ethfi = IERC20(ARB_ETHFI);

        ethfi.approve(ARB_NTT_MANAGER, 0.5 ether);

        NttManager arbNttManager = NttManager(ARB_NTT_MANAGER);
       (,uint256 price) = arbNttManager.quoteDeliveryPrice(destinationEndpoint, new bytes(1));

        price = price * 11 / 10;
        arbNttManager.transfer{value: price}(
            0.5 ether,
            destinationEndpoint,
            toWormholeFormat(deployer)
        );
    }

    function _transferFromBase(uint16 destinationEndpoint) internal {
        IERC20 ethfi = IERC20(BASE_ETHFI);

        ethfi.approve(BASE_NTT_MANAGER, 0.5 ether);

        NttManager baseNttManager = NttManager(BASE_NTT_MANAGER);
       (,uint256 price) = baseNttManager.quoteDeliveryPrice(destinationEndpoint, new bytes(1));

        price = price * 11 / 10;
        baseNttManager.transfer{value: price}(
            0.5 ether,
            destinationEndpoint,
            toWormholeFormat(deployer)
        );
    }
}
