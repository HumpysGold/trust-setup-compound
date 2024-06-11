
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

abstract contract TrustAdminTargets is BaseTargetFunctions, Properties, BeforeAfter {

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

    // Separating out the supply of COMP to the Strategy
    // @audit Clamped to 90_000 COMP in `Setup`
    function supply_funds(uint256 _amount) public {
      uint256 startingComp = COMP.balanceOf(address(trustSetup));

      _amount = between(_amount, 1_000 ether, 90_000 ether);
      _supplyToInvest(_amount);

      t(COMP.balanceOf(address(trustSetup)) == startingComp + _amount, "Flag Supply");
    }

    // Some assertions to detect hunches
    function supply_equality() public {
      t(pool.totalSupply() == IActualSupply(address(pool)).getActualSupply(), "Flag: divergent supply");
    }
}
