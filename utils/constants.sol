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
    address public constant MAINNET_CONTRACT_CONTROLLER = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC;
    address public constant MAINNET_OFT = 0x0000000000000000000000000000000000111111;

    // arbitrum constants
    uint16 public constant ARB_WORMHOLE_ID = 23;
    address public constant ARB_NTT_MANAGER = 0x90A82462258F79780498151EF6f663f1D4BE4E3b;
    address public constant ARB_TRANSCEIVER = 0x4386e36B96D437b0F1C04A35E572C10C6627d88a;
    address public constant ARB_ETHFI = 0x7189fb5B6504bbfF6a852B13B7B82a3c118fDc27;
    address public constant ARB_CONTRACT_CONTROLLER = 0x0c6ca434756EeDF928a55EBeAf0019364B279732;
    address public constant ARB_OFT = 0x0000000000000000000000000000000000111111;

    // base constants
    uint16 public constant BASE_WORMHOLE_ID = 30;
    address public constant BASE_NTT_MANAGER = 0xE87797A1aFb329216811dfA22C87380128CA17d8;
    address public constant BASE_TRANSCEIVER = 0x2153bEa70D96cd804aCbC89D82Ab36638fc1A5F4;
    address public constant BASE_ETHFI = 0x6C240DDA6b5c336DF09A4D011139beAAa1eA2Aa2;
    address public constant BASE_CONTRACT_CONTROLLER = 0x7a00657a45420044bc526B90Ad667aFfaee0A868;
    address public constant BASE_OFT = 0x0000000000000000000000000000000000111111;

    // scroll constants 
    uint16 public constant SCROLL_WORMHOLE_ID = 34;
    address public constant SCROLL_NTT_MANAGER = 0x552c09b224ec9146442767C0092C2928b61f62A1;
    address public constant SCROLL_TRANSCEIVER = 0xdd5567a62600709282d5ad35381505230e149B1a;
    address public constant SCROLL_ETHFI = 0x056A5FA5da84ceb7f93d36e545C5905607D8bD81;
    address public constant SCROLL_CONTRACT_CONTROLLER = 0x3cD08f51D0EA86ac93368DE31822117cd70CECA3;
    address public constant SCROLL_OFT = 0x0000000000000000000000000000000000111111;
}
