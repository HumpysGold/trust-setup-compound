# TrustSetup <> Recon Readme  
 
## Table of Contents

- [Introduction](#introduction)
- [Get Started](#get-started)
- [Architecture](#architecture)
- [Setup](#setup)
  - [Setup Overview](#setup-overview)
- [Targets](#targets)
  - [TrustInvestTargets](#trustinvesttargets)
    - [`trustSetup_invest()`](#trustsetup_invest)
    - [`trustSetup_commenceDivestment()`](#trustsetup_commencedivestment)
    - [`completeDivestment()`](#completedivestment)
  - [TrustAdminTargets](#trustadmintargets)
    - [`supply_funds(uint256 _amount)`](#supply_fundsuint256-_amount)
  - [MaverickTargets](#mavericktargets)
    - [`balancer_swap(uint256 directionality, uint256 amountIn)`](#balancer_swapuint256-directionality-uint256-amountin)
    - [`balancer_supply(bool assetIn, uint256 amountIn)`](#balancer_supplybool-assetin-uint256-amountin)
    - [`balancer_supply_equal(uint256 amountIn)`](#balancer_supply_equaluint256-amountin)
    - [`balancer_withdraw(bool assetOut, uint256 _bptBalance)`](#balancer_withdrawbool-assetout-uint256-_bptbalance)
- [Fuzzing Runs](#fuzzing-runs)
  - [Broken Properties](#broken-properties)
- [Limitations](#limitations)
- [Thoughts and Recommendations](#thoughts-and-recommendations)
  - [Slippage](#slippage)  

## Introduction  

[Alex](https://x.com/GalloDaSballo) and [Lourens](https://x.com/LourensLinde) have performed a manual review followed by fuzz testing for `TrustSetup.sol`.  

This document contains details regarding the fuzzing suite implemented by Recon and it's use.

## Get Started  

To run locally you need two commands (in seperate terminals):  

```
anvil --hardfork cancun -f https://eth-mainnet.g.alchemy.com/v2/${YOUR_API_KEY} --fork-block-number 20038576
```

Then, for a normal assertion run:  

```
echidna . --contract CryticForkTester --config echidna.yaml --rpc-url http://127.0.0.1:8545 --test-limit 500000 --workers 8
```

For an optimization run:  
```
echidna . --contract CryticForkTester --config echidnaOptimize.yaml --rpc-url http://127.0.0.1:8545 --test-limit 500000 --workers 8
```

Note that you can change the `--test-limit` and `--workers` flags as required.

## Architecture

For maintainability the suite is structured to have a `Setup` file with multiple target contracts. The target contracts are split into `TrustInvestTargets`, `TrustAminTargets` and `MaverickTargets`.  

This structure makes maintenance easier by splitting admin, business operations (what we like to call the "story") and outside actor functions.  

Please see `Targets` for more details.  

---

## Setup  
This is an overview of the setup logic to set up the forked fuzzing for the TrustSetup fuzzing suite. It uses Echidna, in combination with a **fork at a specific block**, to test the behaviour of the contract.  

### Setup Overview  
  1.  We are on a forked block, so we set the time equal to the target block (time-sensitive oracles)
  2.  Connect Vault
  3.  Connect Balancer Pool (goldComp:WETH)
  4.  Connect Gauge
  5.  Deploy TrustSetup contract (the target of our fuzzing campaign)
  6.  Setup the tokens (fetch from whales and convert to goldComp)

--- 

## Targets  

### TrustInvestTargets  
Sets the targets of the `TrustSetup` contract that should be triggered during the normal course of operations.

#### `trustSetup_invest():`  

Allows the strategy to enter the Balancer pool with it's `GoldComp` balance.

Note that `COMP` balance must be sufficient.  

We do not flag when a `BAL#208` error (min slippage bpt out) is thrown, as this is would be considered a healthy response to an imbalanced pool.  

#### `trustSetup_commenceDivestment():`  

Allows the strategy to start it's exit flow.

Note that the strategy must have funds in the gauge.  

We do not flag when a `BAL#5054` error (min slippage token out) is thrown, as this is would be considered a healthy response to an imbalanced pool.  

#### `completeDivestment():`  
Completes the divestment by withdrawing from GOLDCOMP vault and sending COMP to the comptroller.  

This method should be called only after commence divest method has been executed and the cooldown period has passed.

### TrustAdminTargets  
These are targets that are admin-related. Useful for tweaking behaviour of the supplied COMP to the strategy.

#### `supply_funds(uint256 _amount):`  

Allows mocking the intermittent the supply of COMP to the Strategy.  

Note that it is clamped to a limit in `Setup`.  

### MaverickTargets  
These are functions that may not be related to the strat contract itself but alter state in integrated contracts.  

Useful in fuzzing how other actors may change the pool and if such behaviour can trigger reverts.  

#### `balancer_swap(uint256 directionality, uint256 amountIn):`  

Useful for allowing an actor to make swaps and accrue fees.  

#### `balancer_supply(bool assetIn, uint256 amountIn):`  

Single-sided supply into the Balancer pool.  

Useful to mimic a hostile actor imbalancing the pool.  

#### `balancer_supply_equal(uint256 amountIn):`  

Proportional supply into the Balancer pool.  

#### `balancer_withdraw(bool assetOut, uint256 _bptBalance):`  

Allows a single-sided withdraw. May have the same practical impact as a single-sided supply.

---

## Fuzzing Runs  

Multiple fuzzing runs were conducted over the course of the engagement.  

These runs were split into assertion runs and optimization runs. The assertion runs were to check if there are any broken properties or unexpected reverts. The optimization runs were used to test ways in which to maximise the amount of BPT received by the protocol.

The latest runs revealed no broken properties.  

Please see slippage section at the end of the document regarding recommendations on slippage.

### Broken Properties  

Please see the Manual review report for the findings identified.  

--- 

## Limitations  

The forked nature of the fuzzing suite and the time-boxed nature of the engagement does mean that there are some limitations to the current suite.

- We do not advance time (to prevent reverts due to oracle staleness)  
- We do not manipulate oracle prices  
- We did not alter admin functions (slippage etc)  

## Thoughts and Recommendations  

### Slippage  

The below table contains a breakdown of the slippage expected due to the one-sided supply of 10 000 COMP in the `invest()` call at various TVL's. The TVLs were scaled linearly by `base TVL + (base TVL * scale factor)`.  

| TVL (scaled) | Amount Expected (BPT) | Amount Received (BPT) | Sippage |
| --- | --- | --- | --- |
| Base | 18140873900000000000000 | 17856364312608456251114 | 1.57% |
| 1 | 18140873900000000000000 | 17931341566010114302594 | 1.16% |
| 2 | 18140873900000000000000 | 17974226108012357766177 | 0.92% |
| 5 | 18140873900000000000000 |18033286293104968340884 | 0.6% |
| 10 | 18140873900000000000000 | 18070160184228809179858 | 0.39% |
| 15 | 18140873900000000000000 | 18086764054871194253356 | 0.3% |  

The slippage described here is due to the swap fees charged on a single-sided supply. As expected the impact on the invariant ratio decreases as the depth of the pool increases.