
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {RevertHelper} from "../RevertHelper.sol";
import {RevertHelper} from "../RevertHelper.sol";
import {vm} from "@chimera/Hevm.sol";

import {IAsset} from "../../../src/interfaces/IAsset.sol";
import {IBalancerVault} from "../../../src/interfaces/IBalancerVault.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IActualSupply {
  function getActualSupply() external returns (uint256);
}

abstract contract MaverickTargets is BaseTargetFunctions, Properties, BeforeAfter {

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
        uint256[] memory amountsIn = new uint256[](2);

        if (assetIn) {
          tokenIn = address(GOLD_COMP);
          amountIn = between(amountIn, 10 ether, IERC20(tokenIn).balanceOf(address(this)));
          amountsIn[0] = amountIn;
        } else {
          tokenIn = address(WETH);
          amountIn = between(amountIn, 1 ether, IERC20(tokenIn).balanceOf(address(this)));
          amountsIn[1] = amountIn;
        }

        // single sided deposit
        IERC20(tokenIn).approve(address(vault), amountIn);

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

    function balancer_supply_equal(bool assetIn, uint256 amountIn) public {
        // single sided deposit
        uint256 amountInGold = between(amountIn, 1 ether, GOLD_COMP.balanceOf(address(this)));
        uint256 amountInWeth = between(amountIn, 1 ether, GOLD_COMP.balanceOf(address(this))) / 99;

        GOLD_COMP.approve(address(vault), amountInGold);
        WETH.approve(address(vault), amountInWeth);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = amountInGold;
        amountsIn[1] = amountInWeth;

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
