
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {TrustInvestTargets} from "./targets/TrustInvestTargets.sol";
import {TrustAdminTargets} from "./targets/TrustAdminTargets.sol";
import {MaverickTargets} from "./targets/MaverickTargets.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {FixedPointMathLib} from "solady/FixedPointMathLib.sol";

interface IActualSupply {
  function getActualSupply() external returns (uint256);
}

/// @notice Convenience contract to quickly convert test broken properties 
contract CryticToFoundry is 
    Test,
    MaverickTargets,
    TrustAdminTargets,
    TrustInvestTargets,
    FoundryAsserts 
{
    uint256 constant GOLD_COMP_NORMALIZED_WEIGHT = 990000000000000000;
    uint256 constant ORACLE_DECIMALS_BASE = 1e8;
    uint256 constant BASE_ORACLE_DIFF_PRECISION = 1e10;

    uint256 constant BASE_PRECISION = 1e18;
    uint256 constant BASE_PRECISION_TWOFOLD = 1e36;

    function setUp() public {
        vm.createSelectFork("mainnet", 20038576/*20055170*/);
        uint256 cacheTimestamp = block.timestamp;
        setup();
        vm.warp(cacheTimestamp);
    }

    // Simple test to investigate stale oracle
    function test_oracleLiveness() public {
        console2.log("Time: ", block.timestamp);
        vm.startPrank(compoundTimelock);
        trustSetup.invest();
        trustSetup.commenceDivestment(100 ether);
        trustSetup.completeDivestment();
    }

    // Run with: `forge test --match-test test_investFail -vvvv`
    function test_investFail_PoC() public {
        supply_funds(37218690640251059336851577914070236679517717381574142764778149591600162043877);
        supply_funds(115792089237316195423570985008687907853269984665640564039457584007913129639935);

        balancer_swap(0,10457393105336675900);

        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
        console2.log("Delta: ", IActualSupply(address(pool)).getActualSupply() - pool.totalSupply());
        console2.log("Invariant: ", pool.getInvariant());
        console2.log("");

        trustSetup_invest();
        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
    }

    function test_investFail_Control() public {
        supply_funds(37218690640251059336851577914070236679517717381574142764778149591600162043877);
        supply_funds(115792089237316195423570985008687907853269984665640564039457584007913129639935);
        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
        console2.log("Delta: ", IActualSupply(address(pool)).getActualSupply() - pool.totalSupply());
        console2.log("");

        trustSetup_invest();
    }

    // To test the real amount of BPT received we check the balance of the strategy in the `gauge`
    // Run with `forge test --match-test test_TVL_comparison -vvv`
    // Note: you may need to set the minBpt expected in the `_depositInBalancerPool` to 0 to allow the test to complete
    function test_TVL_comparison() public {
        uint256[] memory tvls = new uint256[](5);
        tvls[0] = 0;
        tvls[1] = 1_000 ether;
        tvls[2] = 5_000 ether;
        tvls[3] = 10_000 ether;
        tvls[4] = 20_000 ether;

        uint256 snap = vm.snapshot();

        for (uint256 i; i < tvls.length; ++i) {
            console2.log("For extra TVL of: ", tvls[i]);
            balancer_supply_equal(tvls[i]);
            test_optimalInvest_Control();
            console2.log("");

            // we revert to previous state to redo the next tvl
            vm.revertTo(snap);
        }

    }

    // Run both PoC and Control with `forge test --match-test test_optimalInvest_PoC -vvv
    function test_optimalInvest_PoC() public returns (uint256 bptOut) {
        supply_funds(10_000 ether);
        balancer_supply_equal(20_000 ether);
        trustSetup_invest();

        bptOut = gauge.balanceOf(address(trustSetup));
        console2.log("Max BPT for strat: ", bptOut);
        return bptOut;
    }

    function test_optimalInvest_Control() public returns (uint256 bptOut) {
        supply_funds(10_000 ether);

        trustSetup_invest();

        bptOut = gauge.balanceOf(address(trustSetup));
        console2.log("BPT received: ", bptOut);

        return bptOut;
    }
}
