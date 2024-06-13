
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {RevertHelper} from "../RevertHelper.sol";
import {vm} from "@chimera/Hevm.sol";

import {IAsset} from "../../../src/interfaces/IAsset.sol";
import {IBalancerVault} from "../../../src/interfaces/IBalancerVault.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

// If `getActualSuppy` is added to the interface we can remove this
interface IActualSupply {
  function getActualSupply() external returns (uint256);
}

// Sets the targets of the `TrustSetup` contract that should be triggered during the normal course of operations.
abstract contract TrustInvestTargets is BaseTargetFunctions, Properties, BeforeAfter, RevertHelper {
    // Extra emissions
    event DebugDust(string, uint256);

    // Enter pool
    // Note Uses the formula
    function trustSetup_invest() public {
      // Note the clamping of COMP
      require(COMP.balanceOf(address(trustSetup)) > 1 ether, "Only valid if contract can invest funds");

      // Prank the timelock
      vm.prank(compoundTimelock);

      // If there are enough funds in the strategy invest should never fail
      try trustSetup.invest() {
        // Simple dust invariant emissions
        if (COMP.balanceOf(address(trustSetup)) != 0) {
          emit DebugDust("Comp", COMP.balanceOf(address(this)));
          emit DebugDust("BPT", pool.balanceOf(address(this)));
        }

        // Assert no dust
        t(COMP.balanceOf(address(trustSetup)) == 0, "Dust Comp");
        t(pool.balanceOf(address(trustSetup)) == 0, "Dust BPT");

      } catch (bytes memory errorData){
        assertRevertReasonNotEqual(errorData, "Panic(17)"); // No overflow
        assertRevertReasonNotEqual(errorData, "Panic(18)"); // No division by 0

        // `totalSupply` and `getActualSupply` could diverge and cause an overstatement of `minAmounts` on pool join  
        if (!_isRevertReasonEqual(errorData, "BAL#208")) {
          // Allows us to skip known reverts and flag any unexpected reverts
          t(false, "Invest Failed");
        }
      }
    }

    // Exit pool
    // Note Uses the formula
    function trustSetup_commenceDivestment(uint256 _bptToDivest) public {
      require(gauge.balanceOf(address(trustSetup)) > 0, "Only valid if contract has invested funds");

      // Note the clamp for a maximum of 30%
      _bptToDivest = between(_bptToDivest, 5e17, pool.totalSupply() * 30 / 100);
      require(_bptToDivest < gauge.balanceOf(address(trustSetup)));

      // Prank the timelock
      vm.prank(compoundTimelock);

      // Same check as for `invest`
      try trustSetup.commenceDivestment(_bptToDivest) {} catch (bytes memory errorData){
        assertRevertReasonNotEqual(errorData, "Panic(17)"); // No overflow
        assertRevertReasonNotEqual(errorData, "Panic(18)"); // No division by 0

        // Divergent supply may lead to BAL#505 error
        // This is a healthy response to an imbalanced pool
        if (!_isRevertReasonEqual(errorData, "BAL#505")) {
          // Allows us to skip known reverts and flag any unexpected reverts
          t(false, "Divest Failed");
        }
      }
    }

    // Complete divestment
    // @audit Take care with the block timestamp resets
    function trustSetup_completeDivestment() public {
      uint256 cachedTimestamp = block.timestamp;

      if (trustSetup.divestmentQueued()) {
        vm.warp(block.timestamp + 7 days);

        // Prank the timelock
        vm.prank(compoundTimelock);

        try trustSetup.completeDivestment() {} catch {
          // Complete Divestment should not fail
          t(false, "Complete Divestment Failed");
        }

        vm.warp(cachedTimestamp);
      }
    }

    // Allows us to optimize for the most BPT out
    function optimize_max_bpt_for_comp() public returns (uint256) {
      return gauge.balanceOf(address(trustSetup));
    }

    /* Note: Skipped - no rewards as we are not moving time forward
    function trustSetup_swapRewardsForWeth(uint256 _minWethOut) public {
      trustSetup.swapRewardsForWeth(_minWethOut);
    }
    */

    /* Note: Skipped - no rewards means no WETH in this contract
    function trustSetup_buyWethWithComp(uint256 _compAmount) public {
      _compAmount = between(_compAmount, 5e9, COMP.balanceOf(address(this)));

      trustSetup.buyWethWithComp(_compAmount);
    }
    */
}
