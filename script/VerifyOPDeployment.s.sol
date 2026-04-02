// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {Script, console2} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OFTUpgradeable} from "../src/OFT/OFTUpgradeable.sol";
import {NttConstants} from "../utils/constants.sol";
import {ContractCodeChecker} from "./utils/ContractCodeChecker.sol";

/// @title VerifyOPDeployment
/// @notice Verifies the OFTUpgradeable deployment on OP: bytecode for impl + proxy,
///         and ownership/delegate are held by OP_CONTRACT_CONTROLLER.
/// @dev forge script script/VerifyOPDeployment.s.sol:VerifyOPDeployment -vvvv
contract VerifyOPDeployment is ContractCodeChecker, Script, NttConstants, Test {

    string internal constant TOKEN_NAME = "ether.fi governance token";
    string internal constant TOKEN_SYMBOL = "ETHFI";

    string internal constant OP_RPC = "https://mainnet.optimism.io";
    address internal constant OP_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // ERC1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external {
        vm.createSelectFork(OP_RPC);

        address implOnchain = address(uint160(uint256(vm.load(OFT, IMPL_SLOT))));
        console2.log("On-chain impl address:", implOnchain);
        require(implOnchain != address(0), "No implementation found at proxy");

        _verifyImplBytecode(implOnchain);
        _verifyProxyBytecode(implOnchain);
        _verifyOwnershipAndDelegate();

        console2.log("=== All OP deployment verifications passed ===");
    }

    function _verifyImplBytecode(address implOnchain) internal {
        console2.log("\n#1. Verification of [OFTUpgradeable implementation] bytecode...");
        console2.log("    (UUPS immutable self-address will cause expected mismatches)\n");
        OFTUpgradeable localImpl = new OFTUpgradeable(OP_ENDPOINT);
        verifyContractByteCodeMatch(implOnchain, address(localImpl));
    }

    function _verifyProxyBytecode(address implOnchain) internal {
        console2.log("#2. Verification of [ERC1967Proxy] bytecode...");
        address dummyOwner = address(0xdead);
        bytes memory initData = abi.encodeCall(
            OFTUpgradeable.initialize,
            (TOKEN_NAME, TOKEN_SYMBOL, dummyOwner)
        );
        vm.prank(dummyOwner);
        ERC1967Proxy localProxy = new ERC1967Proxy(implOnchain, initData);
        verifyContractByteCodeMatch(OFT, address(localProxy));
    }

    function _verifyOwnershipAndDelegate() internal {
        console2.log("#3. Verifying ownership and delegate roles...\n");

        OFTUpgradeable oft = OFTUpgradeable(OFT);

        address owner = oft.owner();
        console2.log("  owner():", owner);
        assertEq(owner, OP_CONTRACT_CONTROLLER, "Owner mismatch");
        console2.log("  -> Owner is OP_CONTRACT_CONTROLLER: OK");

        address delegate = LZEndpointV2(OP_ENDPOINT).delegates(OFT);
        console2.log("  delegates(OFT):", delegate);
        assertEq(delegate, OP_CONTRACT_CONTROLLER, "Delegate mismatch");
        console2.log("  -> Delegate is OP_CONTRACT_CONTROLLER: OK\n");
    }
}

interface LZEndpointV2 {
    function delegates(address oapp) external view returns (address);
}
