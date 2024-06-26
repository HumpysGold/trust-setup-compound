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

    function testGrantPhase_revert() public {
        // no comp timelock caller
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.grantPhase(TrustSetup.Phase.ALLOW_INVESTMENT);
    }

    function testGrantPhase() public {
        TrustSetup.Phase pB = trustSetup.currentPhase();
        // assert its state is neutral by default
        assertEq(uint8(pB), 0);

        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.grantPhase(TrustSetup.Phase.ALLOW_INVESTMENT);

        TrustSetup.Phase pA = trustSetup.currentPhase();
        assertNotEq(uint8(pB), uint8(pA));
        assertEq(uint8(pA), uint8(TrustSetup.Phase.ALLOW_INVESTMENT));
    }

    function testInvest_revert() public {
        // no granted investment phase by timelock
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.PhaseNotMatching.selector));
        trustSetup.invest(0);

        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.grantPhase(TrustSetup.Phase.ALLOW_INVESTMENT);

        // no comp multisig caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotGoldenBoyzMultisig.selector));
        trustSetup.invest(0);

        // no COMP balance
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompBalance.selector));
        trustSetup.invest(0);
    }

    function testInvest(uint256 _compToInvest) public {
        vm.assume(_compToInvest >= 1e18);
        vm.assume(_compToInvest <= COMP_INVESTED_AMOUNT);

        // assert: initial state of the trust setup
        assertEq(COMP.balanceOf(address(trustSetup)), 0);
        assertEq(trustSetup.GAUGE().balanceOf(address(trustSetup)), 0);

        uint256 compBalanceBeforeProposal = COMP.balanceOf(address(trustSetup.COMPTROLLER()));

        // propose: grant comp transfer into trust setup and invest
        uint256 proposalId = grantCompAndInvestmentPhaseToMultisig(_compToInvest);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        // execute (governance proposal): proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        syncOracleUpdateAt();
        // execute (GoldenBoyz multisig): after being granted succesfully
        vm.prank(trustSetup.GOLD_MSIG());
        trustSetup.invest(_compToInvest);
        vm.clearMockedCalls();

        // assert: states expected changes
        assertGt(trustSetup.GAUGE().balanceOf(address(trustSetup)), _compToInvest);
        assertEq(COMP.balanceOf(address(trustSetup.COMPTROLLER())), compBalanceBeforeProposal - _compToInvest);
    }

    function testCommenceDivestment_revert() public {
        uint256 bptTotalSupply = trustSetup.GAUGE().totalSupply();

        // no granted investment phase by timelock
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.PhaseNotMatching.selector));
        trustSetup.commenceDivestment(0, 0);

        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.grantPhase(TrustSetup.Phase.ALLOW_DIVESTMENT);

        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotGoldenBoyzMultisig.selector));
        trustSetup.commenceDivestment(50, 0);

        // no gauge balance
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NothingStakedInGauge.selector));
        trustSetup.commenceDivestment(50, 0);

        // divesting more than gauge balance
        deal(address(trustSetup.GAUGE()), address(trustSetup), 500e18);
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.DivestmentGreaterThanBalance.selector));
        trustSetup.commenceDivestment(501e18, 0);

        // more than 30% BPT supply
        deal(address(trustSetup.GAUGE()), address(trustSetup), bptTotalSupply / 3);
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.DisproportionateExit.selector));
        trustSetup.commenceDivestment(bptTotalSupply / 3, 0);
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
        uint256 proposalId = grantPhaseToMultisig(TrustSetup.Phase.ALLOW_DIVESTMENT);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        syncOracleUpdateAt();
        // execute (GoldenBoyz multisig): after being granted succesfully
        vm.prank(trustSetup.GOLD_MSIG());
        uint256 minGoldAmount = _bptBalance * 10_000 / 19_000;
        trustSetup.commenceDivestment(_bptBalance, minGoldAmount);
        vm.clearMockedCalls();

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
        // no granted investment phase by timelock
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.PhaseNotMatching.selector));
        trustSetup.completeDivestment();

        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.grantPhase(TrustSetup.Phase.ALLOW_DIVESTMENT);

        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotGoldenBoyzMultisig.selector));
        trustSetup.completeDivestment();

        // no divestment queued
        vm.prank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NoDivestmentQueued.selector));
        trustSetup.completeDivestment();
    }

    function testCompleteDivestment() public {
        uint256 bptBalance = 500e18;
        deal(address(trustSetup.GAUGE()), address(trustSetup), bptBalance);

        uint256 compBalance = COMP.balanceOf(address(trustSetup.COMPTROLLER()));
        // assert: initial state of the trust setup. nothing queued
        assertFalse(trustSetup.divestmentQueued());

        // propose: commence divestment
        uint256 proposalId = grantPhaseToMultisig(TrustSetup.Phase.ALLOW_DIVESTMENT);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(COMPOUND_GOVERNANCE.state(proposalId), uint8(IBravoGovernance.ProposalState.Executed));

        syncOracleUpdateAt();
        // execute (GoldenBoyz multisig): after being granted succesfully
        vm.prank(trustSetup.GOLD_MSIG());
        uint256 minGoldAmount = bptBalance * 10_000 / 19_000;
        trustSetup.commenceDivestment(bptBalance, minGoldAmount);
        vm.clearMockedCalls();

        // wait for the divestment to be withdrawable
        vm.warp(block.timestamp + trustSetup.GOLD_COMP().daysToWait() + 1);

        vm.prank(trustSetup.GOLD_MSIG());
        trustSetup.completeDivestment();

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
        vm.startPrank(MEV_BOT_BUYER);
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
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.StaleOracle.selector));
        trustSetup.buyWethWithComp(10, 0);

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
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NegativeOracleAnswer.selector));
        trustSetup.buyWethWithComp(10, 0);
        vm.clearMockedCalls();

        // not approve for transferFrom
        uint256 dummyCompAmount = 50e18;
        deal(address(COMP), MEV_BOT_BUYER, dummyCompAmount);
        vm.expectRevert("Comp::transferFrom: transfer amount exceeds spender allowance");
        trustSetup.buyWethWithComp(dummyCompAmount, 0);

        // not enough comp
        COMP.approve(address(trustSetup), type(uint256).max);
        vm.expectRevert("Comp::_transferTokens: transfer amount exceeds balance");
        trustSetup.buyWethWithComp(60e18, 0);

        // not enough weth in contract compare to comp transfer
        vm.expectRevert(abi.encodeWithSelector(FailedCall.selector));
        trustSetup.buyWethWithComp(30e18, 0);

        // minOut buyer protection is triggered
        uint256 wethToFund = trustSetup.getCompToWethRatio(dummyCompAmount) * 12_000 / 10_000;
        deal(address(WETH), address(trustSetup), wethToFund);

        vm.expectRevert(abi.encodeWithSelector(TrustSetup.BuyerProtectionTriggered.selector));
        trustSetup.buyWethWithComp(dummyCompAmount, wethToFund + 1);

        vm.stopPrank();
    }

    function testBuyWethWithComp(uint256 _compAmount) public {
        vm.assume(_compAmount >= 1e18);
        // at current prices doubt contract will hold more than $50k
        vm.assume(_compAmount < 1000e18);
        deal(address(COMP), MEV_BOT_BUYER, _compAmount);

        // amounts considers the 2% fee by default
        uint256 wethToFund = trustSetup.getCompToWethRatio(_compAmount) * 12_000 / 10_000;
        deal(address(WETH), address(trustSetup), wethToFund);

        uint256 compBalanceInCompotroller = COMP.balanceOf(trustSetup.COMPTROLLER());

        vm.prank(MEV_BOT_BUYER);
        COMP.approve(address(trustSetup), type(uint256).max);
        vm.prank(MEV_BOT_BUYER);
        trustSetup.buyWethWithComp(_compAmount, wethToFund);

        assertEq(COMP.balanceOf(MEV_BOT_BUYER), 0);
        assertEq(WETH.balanceOf(address(trustSetup)), 0);
        assertEq(COMP.balanceOf(trustSetup.COMPTROLLER()), compBalanceInCompotroller + _compAmount);
    }

    function testSetSlippageMinOut_revert() public {
        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.setSlippageMinOut(3243);

        // value below MIN_SLIPPAGE_VALUE
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.MisconfiguredSlippage.selector));
        trustSetup.setSlippageMinOut(8500);

        // value above SLIPPAGE_PRECISION
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.MisconfiguredSlippage.selector));
        trustSetup.setSlippageMinOut(11000);
    }

    function testSetSlippageMinOut() public {
        vm.prank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.setSlippageMinOut(9500);

        assertEq(trustSetup.slippageMinOut(), 9500);
    }

    function testSetWethCompOracleSwapFee_revert() public {
        // no goldenboyz multisig caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotGoldenBoyzMultisig.selector));
        trustSetup.setWethCompOracleSwapFee(3243);

        // values misconfigured (<10000 or >12000)
        vm.startPrank(trustSetup.GOLD_MSIG());
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.MisconfiguredOracleFee.selector));
        trustSetup.setWethCompOracleSwapFee(9999);

        vm.expectRevert(abi.encodeWithSelector(TrustSetup.MisconfiguredOracleFee.selector));
        trustSetup.setWethCompOracleSwapFee(12001);
        vm.stopPrank();
    }

    function testSetWethCompOracleSwapFee() public {
        uint256 oracleFeeCurrentValue = trustSetup.wethCompOracleSwapFee();
        uint256 newOracleFeeValue = 11500;

        vm.prank(trustSetup.GOLD_MSIG());
        trustSetup.setWethCompOracleSwapFee(11500);

        assertEq(trustSetup.wethCompOracleSwapFee(), newOracleFeeValue);
        assertNotEq(trustSetup.wethCompOracleSwapFee(), oracleFeeCurrentValue);
    }

    function testDeriskFromStrategy_revert() public {
        // no comp timelock caller
        address caller = address(4345454);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(TrustSetup.NotCompTimelock.selector));
        trustSetup.deriskFromStrategy();
    }

    function testDeriskFromStrategy() public {
        uint256 comptrollerBeforeBalance = COMP.balanceOf(trustSetup.COMPTROLLER());
        deal(address(COMP), address(trustSetup), COMP_INVESTED_AMOUNT);

        // propose: commence divestment
        uint256 proposalId = grantPhaseToMultisig(TrustSetup.Phase.ALLOW_DIVESTMENT);

        // vote in favour of proposalId
        voteForProposal(proposalId);

        // queue function can be called by any address
        COMPOUND_GOVERNANCE.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY);

        // execute: proposalId
        COMPOUND_GOVERNANCE.execute(proposalId);
        assertEq(uint8(trustSetup.currentPhase()), uint8(TrustSetup.Phase.ALLOW_DIVESTMENT));

        vm.startPrank(trustSetup.COMPOUND_TIMELOCK());
        trustSetup.deriskFromStrategy();

        assertEq(COMP.balanceOf(trustSetup.COMPTROLLER()), comptrollerBeforeBalance + COMP_INVESTED_AMOUNT);
        assertEq(uint8(trustSetup.currentPhase()), uint8(TrustSetup.Phase.NEUTRAL));
    }
}
