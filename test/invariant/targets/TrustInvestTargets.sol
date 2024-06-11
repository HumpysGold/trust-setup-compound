
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

import {IAsset} from "../../../src/interfaces/IAsset.sol";
import {IBalancerVault} from "../../../src/interfaces/IBalancerVault.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IActualSupply {
  function getActualSupply() external returns (uint256);
}

abstract contract TrustInvestTargets is BaseTargetFunctions, Properties, BeforeAfter {

    event DebugDust(string, uint256);

    // Enter pool
    // Note Uses the formula
    function trustSetup_invest() public {
      require(COMP.balanceOf(address(trustSetup)) > 0, "Only valid if contract can invest funds");

      // Prank the timelock
      vm.prank(compoundTimelock);

      // If there are enough funds in the strategy invest should never fail
      try trustSetup.invest() {} catch {
        // We have a hunch that `totalSupply` and `getActualSupply` will diverge and cause an overstatement of `minAmounts` on pool join
        // @audit the hunch was confirmed
        t(pool.totalSupply() == IActualSupply(address(pool)).getActualSupply(), "Invest failed and supply equality violated");
      }

      // Simple dust invariant emissions
      if (COMP.balanceOf(address(trustSetup)) != 0) {
        emit DebugDust("Comp", COMP.balanceOf(address(this)));
        emit DebugDust("BPT", pool.balanceOf(address(this)));
      }

      // Assert no dust
      t(COMP.balanceOf(address(trustSetup)) == 0, "Dust Comp");
      t(pool.balanceOf(address(trustSetup)) == 0, "Dust BPT");
    }

    // Exit pool
    // Note Uses the formula
    function trustSetup_commenceDivestment(uint256 _bptToDivest) public {
      require(gauge.balanceOf(address(trustSetup)) > 0, "Only valid if contract has invested funds");

      _bptToDivest = between(_bptToDivest, 5e17, pool.totalSupply() * 30 / 100);
      require(_bptToDivest < gauge.balanceOf(address(trustSetup)));

      // Prank the timelock
      vm.prank(compoundTimelock);

      // Same check as for `invest`, but never triggers
      // TODO refine assertion here
      try trustSetup.commenceDivestment(_bptToDivest) {} catch {
        t(pool.totalSupply() == IActualSupply(address(pool)).getActualSupply(), "Divest failed");
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
        trustSetup.completeDivestment();
        vm.warp(cachedTimestamp);
      }
    }

    function optimize_max_bpt_for_comp() public returns (uint256) {
      return gauge.balanceOf(address(trustSetup));
    }
}
