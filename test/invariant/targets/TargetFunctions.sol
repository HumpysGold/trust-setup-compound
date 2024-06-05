
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";


abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {

    event DebugDust(string, uint256);

    function trustSetup_invest() public {
      uint256 startingBal = COMP.balanceOf(address(this));
      // Prank the timelock
      vm.prank(compoundTimelock);

      trustSetup.invest();
      if (COMP.balanceOf(address(trustSetup)) != 0) {
        emit DebugDust("Comp", COMP.balanceOf(address(this)));
        emit DebugDust("BPT", pool.balanceOf(address(this)));
      }

      // Assert no dust
      t(COMP.balanceOf(address(trustSetup)) == 0, "Dust Comp");
      t(pool.balanceOf(address(trustSetup)) == 0, "Dust BPT");
    }

    function trustSetup_commenceDivestment(uint256 _bptToDivest) public {
      // Prank the timelock
      vm.prank(compoundTimelock);

      trustSetup.commenceDivestment(_bptToDivest);
    }

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


    // @audit Skipped
    /**
    function trustSetup_setSlippageMinOut(uint256 _slippageMinOut) public {
      trustSetup.setSlippageMinOut(_slippageMinOut);
    }

    function trustSetup_swapRewardsForWeth(uint256 _minWethOut) public {
      trustSetup.swapRewardsForWeth(_minWethOut);
    }

    function trustSetup_buyWethWithComp(uint256 _compAmount) public {
      trustSetup.buyWethWithComp(_compAmount);
    }

    function trustSetup_getCompToWethRatio(uint256 _compAmount) public {
      trustSetup.getCompToWethRatio(_compAmount);
    }

    */
}
