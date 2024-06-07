
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {TargetFunctions} from "./targets/TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        vm.createSelectFork("mainnet");
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
        trustSetup_invest();
    }
}
