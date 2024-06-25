// SPDX-License-Identifier: MIT

pragma solidity >=0.8.8 <0.9.0;

contract NttConstants {

    // chain agnostic constants
    uint256 public constant MAX_WINDOW = 150000000000000000000000;
    uint256 public constant RATE_LIMIT_DURATION = 43200;

    // mainnet constants
    uint16 public constant MAINNET_WORMHOLE_ID = 2;
    address public constant MAINNET_NTT_MANAGER = 0x344169Cc4abE9459e77bD99D13AA8589b55b6174;
    address public constant MAINNET_TRANSCEIVER = 0x3bf4AebcaD920447c5fdD6529239Ab3922ce2186;
    address public constant MAINNET_ETHFI = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;

    // arbitrum constants
    uint16 public constant ARB_WORMHOLE_ID = 23;
    address public constant ARB_NTT_MANAGER = 0x90A82462258F79780498151EF6f663f1D4BE4E3b;
    address public constant ARB_TRANSCEIVER = 0x4386e36B96D437b0F1C04A35E572C10C6627d88a;
    address public constant ARB_ETHFI = 0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27;
}