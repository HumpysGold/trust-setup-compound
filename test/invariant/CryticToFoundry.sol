
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
    function test_investFail() public {
        balancer_swap(0,10457393105336675900);

        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
        console2.log("Delta: ", IActualSupply(address(pool)).getActualSupply() - pool.totalSupply());
        console2.log("");

        trustSetup_invest();
        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
    }

    function test_investFail_Control() public {

        console2.log("Total Supply: ", pool.totalSupply());
        console2.log("Actual Supply: ", IActualSupply(address(pool)).getActualSupply());
        console2.log("Delta: ", IActualSupply(address(pool)).getActualSupply() - pool.totalSupply());
        console2.log("");

        trustSetup_invest();
    }

    function test_products() public {
        uint256 productSequenceOne = uint256(
            FixedPointMathLib.powWad(
                int256((uint256(5448476635) * BASE_PRECISION / GOLD_COMP_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(GOLD_COMP_NORMALIZED_WEIGHT)
            )
        );
/*
        uint256 productSequenceTwo = uint256(
            FixedPointMathLib.powWad(
                int256((ethToUsd * BASE_PRECISION / WETH_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(WETH_NORMALIZED_WEIGHT)
            )
        );
*/
        int256 productSequenceOneInt = 
            FixedPointMathLib.powWad(
                int256((uint256(5448476635) * BASE_PRECISION / GOLD_COMP_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(GOLD_COMP_NORMALIZED_WEIGHT)
            );
/*
        int256 productSequenceTwoInt =
            FixedPointMathLib.powWad(
                int256((ethToUsd * BASE_PRECISION / WETH_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(WETH_NORMALIZED_WEIGHT)
        );
*/
        console2.log("Uint256: ", productSequenceOne);
        console2.log("Int256:  ", productSequenceOneInt);
    }
}
