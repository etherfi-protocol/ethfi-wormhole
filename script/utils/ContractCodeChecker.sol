// SPDX-License-Identifier: MIT
pragma solidity >=0.8.8 <0.9.0;

import {console2} from "forge-std/console2.sol";

contract ContractCodeChecker {
    event ByteMismatchSegment(
        uint256 startIndex,
        uint256 endIndex,
        bytes aSegment,
        bytes bSegment
    );

    function compareBytes(bytes memory a, bytes memory b) internal returns (bool) {
        if (a.length != b.length) {
            return false;
        }

        uint256 len = a.length;
        uint256 start = 0;
        bool inMismatch = false;
        bool anyMismatch = false;

        for (uint256 i = 0; i < len; i++) {
            bool mismatch = (a[i] != b[i]);
            if (mismatch && !inMismatch) {
                start = i;
                inMismatch = true;
            } else if (!mismatch && inMismatch) {
                emitMismatchSegment(a, b, start, i - 1);
                inMismatch = false;
                anyMismatch = true;
            }
        }

        if (inMismatch) {
            emitMismatchSegment(a, b, start, len - 1);
            anyMismatch = true;
        }

        return !anyMismatch;
    }

    function emitMismatchSegment(
        bytes memory a,
        bytes memory b,
        uint256 start,
        uint256 end
    ) internal {
        uint256 segmentLength = end - start + 1;

        bytes memory aSegment = new bytes(segmentLength);
        bytes memory bSegment = new bytes(segmentLength);

        for (uint256 i = 0; i < segmentLength; i++) {
            aSegment[i] = a[start + i];
            bSegment[i] = b[start + i];
        }

        string memory aHex = bytesToHexString(aSegment);
        string memory bHex = bytesToHexString(bSegment);

        console2.log("- Mismatch segment at index [%s, %s]", start, end);
        console2.logString(string.concat(" - ", aHex));
        console2.logString(string.concat(" - ", bHex));

        emit ByteMismatchSegment(start, end, aSegment, bSegment);
    }

    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function verifyFullMatch(address deployedImpl, address localDeployed) public {
        console2.log("Verifying full bytecode match...");
        bytes memory localBytecode = address(localDeployed).code;
        bytes memory onchainRuntimeBytecode = address(deployedImpl).code;

        if (compareBytes(localBytecode, onchainRuntimeBytecode)) {
            console2.log("-> Full Bytecode Match: Success\n");
        } else {
            console2.log("-> Full Bytecode Match: Fail\n");
        }
    }

    function verifyPartialMatch(address deployedImpl, address localDeployed) public {
        console2.log("Verifying partial bytecode match...");

        bytes memory localBytecode = localDeployed.code;
        bytes memory onchainRuntimeBytecode = deployedImpl.code;

        if (localBytecode.length == 0 || onchainRuntimeBytecode.length == 0) {
            revert("One of the bytecode arrays is empty, cannot verify.");
        }

        bytes memory trimmedLocal = trimMetadata(localBytecode);
        bytes memory trimmedOnchain = trimMetadata(onchainRuntimeBytecode);

        if (trimmedLocal.length != trimmedOnchain.length) {
            revert("Post-trim length mismatch: potential code differences.");
        }

        if (compareBytes(trimmedLocal, trimmedOnchain)) {
            console2.log("-> Partial Bytecode Match: Success\n");
        } else {
            console2.log("-> Partial Bytecode Match: Fail\n");
        }
    }

    function verifyLengthMatch(address deployedImpl, address localDeployed) public view {
        console2.log("Verifying length match...");
        bytes memory localBytecode = localDeployed.code;
        bytes memory onchainRuntimeBytecode = deployedImpl.code;

        if (localBytecode.length == onchainRuntimeBytecode.length) {
            console2.log("-> Length Match: Success\n");
        } else {
            console2.log("-> Length Match: Fail\n");
        }
    }

    function verifyContractByteCodeMatch(address deployedImpl, address localDeployed) public {
        verifyLengthMatch(deployedImpl, localDeployed);
        verifyPartialMatch(deployedImpl, localDeployed);
        verifyFullMatch(deployedImpl, localDeployed);
    }

    function trimMetadata(bytes memory code) internal pure returns (bytes memory) {
        uint256 length = code.length;
        if (length < 4) {
            return code;
        }

        for (uint256 i = length - 1; i > 0; i--) {
            if (code[i] == 0xa2) {
                console2.log("Found metadata start at index: ", i);
                bytes memory trimmed = new bytes(i);
                for (uint256 j = 0; j < i; j++) {
                    trimmed[j] = code[j];
                }
                return trimmed;
            }
        }

        return code;
    }
}
