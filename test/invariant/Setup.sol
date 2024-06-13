
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";

import "../../src/TrustSetup.sol";

// Interfaces
import {IBalancerVault} from "../../src/interfaces/IBalancerVault.sol";
import {IWeightedPool} from "../../src/interfaces/IWeightedPool.sol";
import {IGauge} from "../../src/interfaces/IGauge.sol";
import {IGoldComp} from "../../src/interfaces/IGoldComp.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
      This sets up the forked fuzzing for the TrustSetup fuzzing suite.
      It uses Echidna, in combination with a **fork at a specific block**, to test the behaviour of the contract.

      Note that the block target is set in the anvil command

      Setup Overview:

  1.  We are on a forked block, we set the time equal to the target block (time-sensitive oracles)
  2.  Connect Vault
  3.  Connect Balancer Pool (goldComp:WETH)
  4.  Connect Gauge
  5.  Deploy TrustSetup contract (the target of our fuzzing campaign)
  6.  Setup the tokens (fetch from whales and convert to goldComp)

 */
abstract contract Setup is BaseSetup {

    TrustSetup trustSetup;

    IBalancerVault internal vault;
    IGauge internal gauge;
    IWeightedPool internal pool;

    // Trusted Addresses
    address internal compoundTimelock = 0x6d903f6003cca6255D85CcA4D3B5E5146dC33925;
    address internal goldMultisig = 0x941dcEA21101A385b979286CC6D6A9Bf435EB1C2;

    // Tokens addresses
    IERC20 internal constant GOLD = IERC20(0x9DeB0fc809955b79c85e82918E8586d3b7d2695a);
    IERC20 internal constant COMP = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    IERC20 internal constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // GoldComp
    IGoldComp internal constant GOLD_COMP = IGoldComp(0x939CED8875d1Cd75D8b9aca439e6526e9A822A48);

    // Limits
    uint256 internal compLimit = 90_000e18;
    uint256 internal compTracker;

    function setup() internal virtual override {
      vm.warp(1717746731);

      vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
      pool = IWeightedPool(0x56bc9d9987edeC2fC6e1990e27AF4A0987b53096);
      gauge = IGauge(0x4DcfB8105C663F199c1a640549FC3579db4E3e65);

      trustSetup = new TrustSetup();

      // Setup the needed tokens
      _setUpTokens(); 

      // Setup goldComp
      COMP.approve(address(GOLD_COMP), COMP.balanceOf(address(this)) * 8 / 10);
      GOLD_COMP.deposit(COMP.balanceOf(address(this)) * 8 / 10);
    }

    // Give the tokens that we need
    // Note: Make sure to check the on-chain balances regularly to ensure they are as expected
    // (sometimes a whale becomes a guppy and this effects the tokens transferred)
    function _setUpTokens() internal {
      // COMP whale: 0xf7Ba2631166e4f7A22a91Def302d873106f0beD8
      _whaleSend(COMP, 0xf7Ba2631166e4f7A22a91Def302d873106f0beD8, address(this));

      // WETH whale: 0x57757E3D981446D585Af0D9Ae4d7DF6D64647806
      _whaleSend(WETH, 0x57757E3D981446D585Af0D9Ae4d7DF6D64647806, address(this));
    }

    // Convenience function to mock COMP provision to the strategy
    // @audit Capped at 90k COMP
    function _supplyToInvest(uint256 _amount) internal {
      require(compTracker + _amount <= compLimit);

      // Give the strat some COMP from Comptroller
      vm.prank(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
      COMP.transfer(address(trustSetup), _amount);
      compTracker += _amount;
    }

    // Convenience function for tranferring the balance of an account to another address
    function _whaleSend(IERC20 token, address whale, address to) internal {
        uint256 balToSend = token.balanceOf(whale);
        vm.prank(whale);
        token.transfer(to, balToSend);
    }

    /// @return The pool assets in the 99goldCOMP-1WETH Balancer pool
    function _poolAssets() internal pure returns (address[] memory) {
        address[] memory poolAssets = new address[](2);
        poolAssets[0] = address(GOLD_COMP);
        poolAssets[1] = address(WETH);

        return poolAssets;
    }
}
