
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

import {IAsset} from "../../../src/interfaces/IAsset.sol";
import {IBalancerVault} from "../../../src/interfaces/IBalancerVault.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// These are targets that are admin-related. 
// Useful for tweaking behaviour of the supplied COMP to the strategy.
abstract contract TrustAdminTargets is BaseTargetFunctions, Properties, BeforeAfter {

    // @audit Skipped
    /**
    function trustSetup_setSlippageMinOut(uint256 _slippageMinOut) public {
      trustSetup.setSlippageMinOut(_slippageMinOut);
    }
    */

    // Allows mocking the intermittent the supply of COMP to the Strategy
    // @audit Clamped to 90_000 COMP in `Setup`
    function supply_funds(uint256 _amount) public {
      uint256 startingComp = COMP.balanceOf(address(trustSetup));

      _amount = between(_amount, 1_000 ether, 90_000 ether);
      _supplyToInvest(_amount);

      t(COMP.balanceOf(address(trustSetup)) == startingComp + _amount, "Flag Supply");
    }

}
