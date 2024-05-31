// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";
import {console} from "forge-std/Test.sol";

import {IOracle} from "../src/interfaces/IOracle.sol";
import {IBravoGovernance} from "../src/interfaces/IBravoGovernance.sol";
import {IBalancerQueriesHelper} from "../src/interfaces/IBalancerQueriesHelper.sol";

import {TrustSetup} from "../src/TrustSetup.sol";

contract TrustSetupTest is BaseFixture {
    error FailedCall();

    function testInvest_revert() public {
        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.invest();

        // no COMP balance
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompBalance.selector));
        trustSetup.invest();
    }

    function testInvest(uint256 _compToInvest) public {
        vm.assume(_compToInvest >= 1e18);
        vm.assume(_compToInvest <= COMP_INVESTED_AMOUNT);

        // assert: initial state of the trust setup
        assertEq(COMP.balanceOf(address(trustSetup)), 0);
        assertEq(trustSetup.GAUGE().balanceOf(address(trustSetup)), 0);

        uint256 compBalanceBeforeProposal = COMP.balanceOf(address(trustSetup.COMPTROLLER()));

        // propose: grant comp transfer into trust setup and invest
        uint256 proposalId = grantCompAndInvest(_compToInvest);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        syncOracleUpdateAt();

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));
        vm.clearMockedCalls();

        // assert: states expected changes
        assertGt(trustSetup.GAUGE().balanceOf(address(trustSetup)), _compToInvest);
        assertEq(COMP.balanceOf(address(trustSetup.COMPTROLLER())), compBalanceBeforeProposal - _compToInvest);
    }

    function testCommenceDivestment_revert() public {
        uint256 bptTotalSupply = trustSetup.GAUGE().totalSupply();

        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.commenceDivestment(50);

        // no gauge balance
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NothingStakedInGauge.selector));
        trustSetup.commenceDivestment(50);

        // divesting more than gauge balance
        deal(address(trustSetup.GAUGE()), address(trustSetup), 500e18);
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.DivestmentGreaterThanBalance.selector));
        trustSetup.commenceDivestment(501e18);

        // more than 30% BPT supply
        deal(address(trustSetup.GAUGE()), address(trustSetup), bptTotalSupply / 3);
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.DisproportionateExit.selector));
        trustSetup.commenceDivestment(bptTotalSupply / 3);
    }

    function testCommenceDivestment(uint256 _bptBalance) public {
        vm.assume(_bptBalance >= 1e18);
        // it should not be more than 30% of current BPT supply as per Balancer v2 invariants
        // BAL#306: https://docs.balancer.fi/reference/contracts/error-codes.html#pools
        // fuzzing _bptBalance value with up to 29.4% of the BPT supply
        vm.assume(_bptBalance < trustSetup.GAUGE().totalSupply() * 10_000 / 34_000);
        deal(address(trustSetup.GAUGE()), address(trustSetup), _bptBalance);

        // assert: initial state of the trust setup. nothing queued
        assertFalse(trustSetup.divestmentQueued());

        // propose: commence divestment
        uint256 proposalId = queueCommenceDivestment(_bptBalance);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        syncOracleUpdateAt();

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        (uint256 amount, uint256 timestamp, uint256 releaseTimestamp, bool withdrawn) =
            trustSetup.GOLD_COMP().queuedWithdrawals(address(trustSetup), 0);

        // assert: states expected changes
        assertEq(trustSetup.GAUGE().balanceOf(address(trustSetup)), 0);
        // gets burned while queuing
        assertEq(trustSetup.GOLD_COMP().balanceOf(address(trustSetup)), 0);

        assertGt(amount, 0);
        assertEq(timestamp, block.timestamp);
        assertEq(releaseTimestamp, block.timestamp + trustSetup.GOLD_COMP().daysToWait());
        assertFalse(withdrawn);

        assertTrue(trustSetup.divestmentQueued());
    }

    function testCompleteDivestment_revert() public {
        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.completeDivestment();

        // no divestment queued
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NoDivestmentQueued.selector));
        trustSetup.completeDivestment();
    }

    function testCompleteDivestment() public {
        deal(address(trustSetup.GAUGE()), address(trustSetup), 500e18);

        uint256 compBalance = COMP.balanceOf(address(trustSetup.COMPTROLLER()));
        // assert: initial state of the trust setup. nothing queued
        assertFalse(trustSetup.divestmentQueued());

        // propose: commence divestment
        uint256 proposalId = queueCommenceDivestment(500e18);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        syncOracleUpdateAt();

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        proposalId = queueCompleteDivestment();

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        // wait for the divestment to be withdrawable
        vm.warp(block.timestamp + trustSetup.GOLD_COMP().daysToWait() + 1);

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        (,,, bool withdrawn) = trustSetup.GOLD_COMP().queuedWithdrawals(address(trustSetup), 0);

        assertGt(COMP.balanceOf(address(trustSetup.COMPTROLLER())), compBalance);
        assertEq(trustSetup.GAUGE().balanceOf(address(trustSetup)), 0);
        assertEq(trustSetup.GOLD_COMP().balanceOf(address(trustSetup)), 0);
        assertEq(COMP.balanceOf(address(trustSetup)), 0);

        assertTrue(withdrawn);

        assertFalse(trustSetup.divestmentQueued());
    }

    function testSwapRewardsForWeth_revert() public {
        // no goldenboyz multisig caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotGoldenBoyzMultisig.selector));
        trustSetup.swapRewardsForWeth(10);
    }

    /// @notice operation carried by goldenboyz multisig to prevent minimum out token problems
    function testSwapRewardsForWeth(uint256 _gaugeBalance) public {
        vm.assume(_gaugeBalance >= 1e18);
        // at current prices doubt contract will hold more than $50k
        vm.assume(_gaugeBalance < trustSetup.GAUGE().totalSupply());

        deal(address(trustSetup.GAUGE()), address(trustSetup), _gaugeBalance);
        vm.roll(block.number + 20_000);

        uint256 claimableRewardAmount = trustSetup.GAUGE().claimable_reward(address(trustSetup), address(GOLD));
        assertGt(claimableRewardAmount, 0);
        assertEq(WETH.balanceOf(address(trustSetup)), 0);

        IBalancerQueriesHelper.SingleSwap memory singleSwapParams = IBalancerQueriesHelper.SingleSwap({
            poolId: trustSetup.GOLD_POOL_ID(),
            kind: 0,
            assetIn: address(GOLD),
            assetOut: address(WETH),
            amount: claimableRewardAmount,
            userData: new bytes(0)
        });
        IBalancerQueriesHelper.FundManagement memory funds = IBalancerQueriesHelper.FundManagement({
            sender: address(trustSetup),
            fromInternalBalance: false,
            recipient: address(trustSetup),
            toInternalBalance: false
        });
        uint256 minWethOut = BALANCER_QUERIES_HELPER.querySwap(singleSwapParams, funds);

        vm.prank(trustSetup.GOLD_MSIG());
        trustSetup.swapRewardsForWeth(minWethOut);

        assertEq(trustSetup.GAUGE().claimable_reward(address(trustSetup), address(GOLD)), 0);
        assertGe(WETH.balanceOf(address(trustSetup)), minWethOut);
    }

    function testBuyWethWithComp_revert() public {
        // oracle is staled
        vm.mockCall(
            address(trustSetup.ORACLE_COMP_ETH()),
            abi.encodeWithSelector(IOracle.latestRoundData.selector),
            abi.encode(
                0,
                500000, // answer
                0,
                1, // updatedAt
                0
            )
        );
        vm.prank(MEV_BOT_BUYER);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.StaleOracle.selector));
        trustSetup.buyWethWithComp(10);

        // oracle answer is negative
        vm.mockCall(
            address(trustSetup.ORACLE_COMP_ETH()),
            abi.encodeWithSelector(IOracle.latestRoundData.selector),
            abi.encode(
                0,
                -5, // answer
                0,
                block.timestamp - 2000, // updatedAt
                0
            )
        );
        vm.prank(MEV_BOT_BUYER);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NegativeOracleAnswer.selector));
        trustSetup.buyWethWithComp(10);
        vm.clearMockedCalls();

        // not approve for transferFrom
        deal(address(COMP), MEV_BOT_BUYER, 50e18);
        vm.prank(MEV_BOT_BUYER);
        vm.expectRevert("Comp::transferFrom: transfer amount exceeds spender allowance");
        trustSetup.buyWethWithComp(50e18);

        // not enough comp
        vm.prank(MEV_BOT_BUYER);
        COMP.approve(address(trustSetup), type(uint256).max);
        vm.prank(MEV_BOT_BUYER);
        vm.expectRevert("Comp::_transferTokens: transfer amount exceeds balance");
        trustSetup.buyWethWithComp(60e18);

        // not enough weth in contract compare to comp transfer
        vm.prank(MEV_BOT_BUYER);
        vm.expectRevert(abi.encodeWithSelector(FailedCall.selector));
        trustSetup.buyWethWithComp(30e18);
    }

    function testBuyWethWithComp(uint256 _compAmount) public {
        vm.assume(_compAmount >= 1e18);
        // at current prices doubt contract will hold more than $50k
        vm.assume(_compAmount < 1000e18);
        deal(address(COMP), MEV_BOT_BUYER, _compAmount);

        deal(address(WETH), address(trustSetup), trustSetup.getCompToWethRatio(_compAmount));

        uint256 compBalanceInCompotroller = COMP.balanceOf(trustSetup.COMPTROLLER());

        vm.prank(MEV_BOT_BUYER);
        COMP.approve(address(trustSetup), type(uint256).max);
        vm.prank(MEV_BOT_BUYER);
        trustSetup.buyWethWithComp(_compAmount);

        assertEq(COMP.balanceOf(MEV_BOT_BUYER), 0);
        assertEq(WETH.balanceOf(address(trustSetup)), 0);
        assertEq(COMP.balanceOf(trustSetup.COMPTROLLER()), compBalanceInCompotroller + _compAmount);
    }
}
