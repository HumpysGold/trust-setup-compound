
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract RevertHelper is Asserts {
  function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        // Check that the data has the right size: 4 bytes for signature + 32 bytes for panic code
        if (returnData.length == 4 + 32) {
            // Check that the data starts with the Panic signature
            bytes4 panicSignature = bytes4(keccak256(bytes("Panic(uint256)")));
            for (uint i = 0; i < 4; i++) {
                if (returnData[i] != panicSignature[i]) return "Undefined signature";
            }

            uint256 panicCode;
            for (uint i = 4; i < 36; i++) {
                panicCode = panicCode << 8;
                panicCode |= uint8(returnData[i]);
            }

            // Now convert the panic code into its string representation
            if (panicCode == 17) {
                return "Panic(17)";
            }
            if (panicCode == 18) {
                return "Panic(18)";
            }

            // Add other panic codes as needed or return a generic "Unknown panic"
            return "Undefined panic code";
        }

        // If the returnData length is less than 68, then the transaction failed silently (without a revert message)
        if (returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string)); // All that remains is the revert string
    }

    function _isRevertReasonEqual(
        bytes memory returnData,
        string memory reason
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(_getRevertMsg(returnData))) ==
            keccak256(abi.encodePacked(reason)));
    }
    function assertRevertReasonNotEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason);
        t(!isEqual, reason);
    }

    function testTheOverflow() external {
      uint256 x = type(uint256).max;
      uint256 y = x + 123;
    }
    function testTheDivisionByZero() external {
      uint256 x = 123;
      uint256 y = 0;
      uint256 z = x / y;
    }

    // NOTE: Canary just check them once then delete these
    /* Checked: OK - Loki
    function check_the_overflow() public {
      try this.testTheOverflow() {
      } catch (bytes memory errorData){
        assertRevertReasonNotEqual(errorData, "Panic(17)"); // 18 = div by 0
      }
    }
    function check_the_zero_div() public {
      try this.testTheDivisionByZero() {
      } catch (bytes memory errorData){
        assertRevertReasonNotEqual(errorData, "Panic(18)");
      }
    }
  */
}