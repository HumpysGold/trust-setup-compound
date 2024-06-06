
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

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {

    event DebugDust(string, uint256);

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

      try trustSetup.commenceDivestment(_bptToDivest) {} catch {
        t(pool.totalSupply() == IActualSupply(address(pool)).getActualSupply(), "Divest failed");
      }

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

    // Maverick functions
    // These are functions that may not be related to the strat contract itself but alter state in integrated contracts
    function balancer_swap(uint256 directionality, uint256 amountIn) public {
      address tokenIn;
      address tokenOut;

      if (directionality % 2 == 0) {
        tokenIn = address(GOLD_COMP);
        tokenOut = address(WETH);
      } else {
        tokenIn = address(WETH);
        tokenOut = address(GOLD_COMP);
      }
      
      amountIn = between(amountIn, 1, IERC20(tokenIn).balanceOf(address(this)));
      IERC20(tokenIn).approve(address(vault), amountIn);

      vault.swap(
        IBalancerVault.SingleSwap({
            poolId: trustSetup.GOLD_COMP_WETH_POOL_ID(),
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(tokenIn),
            assetOut: IAsset(tokenOut),
            amount: amountIn,
            userData: new bytes(0)
        }),
        IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        }),
        0, // @audit This is zero because we don't fear MEV (locally)
        block.timestamp
    );
    }

    function balancer_supply(bool assetIn, uint256 amountIn) public {
        address tokenIn;

        if (assetIn) {
          tokenIn = address(GOLD_COMP);
        } else {
          tokenIn = address(WETH);
        }
        // single sided deposit
        amountIn = between(amountIn, 0, IERC20(tokenIn).balanceOf(address(this)));
        IERC20(tokenIn).approve(address(vault), amountIn);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amountIn;

        vault.joinPool(
          trustSetup.GOLD_COMP_WETH_POOL_ID(),
          address(this),
          address(this),
          IBalancerVault.JoinPoolRequest({
              assets: _poolAssets(),
              maxAmountsIn: amountsIn,
              userData: abi.encode(
                  IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0
              ),
              fromInternalBalance: false
          })
      );
    }

    function balancer_withdraw(bool assetOut, uint256 _bptBalance) public {
        uint256[] memory minAmountsOut = new uint256[](2);

        // Which asset are we withdrawing
        if (assetOut) {
          minAmountsOut[1] = 1;
        } else {
          minAmountsOut[0] = 1;
        }
        // single sided deposit
        _bptBalance = between(_bptBalance, 1, pool.balanceOf(address(this)));
        // index 0 is the minimum amount of COMP expected

        vault.exitPool(
            trustSetup.GOLD_COMP_WETH_POOL_ID(),
            address(this),
            address(this),
            IBalancerVault.ExitPoolRequest({
                assets: _poolAssets(),
                minAmountsOut: minAmountsOut,
                userData: abi.encode(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, _bptBalance, 0),
                toInternalBalance: false
            })
        );
    }

    // Some assertions to detect hunches
    /**
    function supply_equality() public {
      t(pool.totalSupply() == IActualSupply(address(pool)).getActualSupply(), "Flag: divergent supply");
    }

    */
}
