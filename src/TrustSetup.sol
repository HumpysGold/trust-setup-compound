// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {FixedPointMathLib} from "solady/FixedPointMathLib.sol";

import {IOracle} from "./interfaces/IOracle.sol";
import {IWeightedPool} from "./interfaces/IWeightedPool.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IGoldComp} from "./interfaces/IGoldComp.sol";

import {IAsset} from "./interfaces/IAsset.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";

/// @title TrustSetup
/// @author GoldenBoyz
/// @notice Allows to invest and divest from the strategy outlined in the Compound's governance proposal in a trustless fashion
contract TrustSetup {
    using SafeERC20 for IERC20;

    ///////////////////////////// Constants ///////////////////////////////
    uint256 constant ORACLE_DECIMALS_BASE = 1e8;
    uint256 constant BASE_ORACLE_DIFF_PRECISION = 1e10;

    uint256 constant BASE_PRECISION = 1e18;
    uint256 constant BASE_PRECISION_TWOFOLD = 1e36;

    uint256 constant MIN_SLIPPAGE_VALUE = 9_100;
    uint256 constant SLIPPAGE_PRECISION = 10_000;

    address public constant GOLD_MSIG = 0x941dcEA21101A385b979286CC6D6A9Bf435EB1C2;
    address public constant COMPOUND_TIMELOCK = 0x6d903f6003cca6255D85CcA4D3B5E5146dC33925;
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    IERC20 constant GOLD = IERC20(0x9DeB0fc809955b79c85e82918E8586d3b7d2695a);
    IERC20 constant COMP = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IGoldComp public constant GOLD_COMP = IGoldComp(0x939CED8875d1Cd75D8b9aca439e6526e9A822A48);

    IWeightedPool public constant BPT = IWeightedPool(0x56bc9d9987edeC2fC6e1990e27AF4A0987b53096);
    uint256 constant GOLD_COMP_NORMALIZED_WEIGHT = 990000000000000000;
    uint256 constant WETH_NORMALIZED_WEIGHT = 10000000000000000;
    uint256 constant BPT_INVARIANT_RATIO = 300000000000000000;

    IGauge public constant GAUGE = IGauge(0x4DcfB8105C663F199c1a640549FC3579db4E3e65);

    IOracle public constant ORACLE_COMP_ETH = IOracle(0x1B39Ee86Ec5979ba5C322b826B3ECb8C79991699);
    uint256 constant ORACLE_COMP_ETH_HEART_BEAT = 24 hours;

    IOracle public constant ORACLE_COMP_USD = IOracle(0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5);
    uint256 constant ORACLE_COMP_USD_HEART_BEAT = 1 hours;

    IOracle public constant ORACLE_ETH_USD = IOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 constant ORACLE_ETH_USD_HEART_BEAT = 1 hours;

    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 public constant GOLD_COMP_WETH_POOL_ID = 0x56bc9d9987edec2fc6e1990e27af4a0987b53096000200000000000000000686;
    bytes32 public constant GOLD_POOL_ID = 0x0ec120ed63212a4cb018795b43c0b03c5919042400010000000000000000068f;

    /////////////////////////////// Storage ////////////////////////////////
    bool public divestmentQueued;

    uint256 public slippageMinOut;

    /////////////////////////////// Errors ////////////////////////////////
    error NotCompTimelock();
    error NotGoldenBoyzMultisig();

    error NotCompBalance();
    error NothingStakedInGauge();
    error DivestmentGreaterThanBalance();
    error DisproportionateExit();
    error NoDivestmentQueued();

    error MisconfiguredSlippage();

    error NegativeOracleAnswer();
    error StaleOracle();

    /////////////////////////////// Events ////////////////////////////////
    event CompInvested(uint256 compAmount, uint256 bptReceived, uint256 timestampt);
    event CompDivestedQueue(uint256 compAmount, uint256 bptWithdrawn, uint256 timestampt);
    event CompDivestedCompleted(uint256 compAmount, uint256 timestampt);

    event RewardSwapped(uint256 goldBalance, uint256 wethReceived, uint256 timestampt);
    event WethBoughtWithComp(address indexed buyer, uint256 compAmount, uint256 wethAmount);

    /////////////////////////////// Modifiers ////////////////////////////////
    /// @notice Restricts the invocation of methods exclusively to the Compound Timelock
    modifier onlyCompTimelock() {
        if (msg.sender != COMPOUND_TIMELOCK) revert NotCompTimelock();
        _;
    }

    /// @notice Restricts the invocation of methods exclusively to the GoldenBoyz multisig
    modifier onlyGoldenBoyzMultisig() {
        if (msg.sender != GOLD_MSIG) revert NotGoldenBoyzMultisig();
        _;
    }

    /// @notice Grants unlimited approvals at deployment time to facilitate internal operations for trusted contracts
    constructor() {
        COMP.approve(address(GOLD_COMP), type(uint256).max);

        GOLD.approve(address(BALANCER_VAULT), type(uint256).max);
        GOLD_COMP.approve(address(BALANCER_VAULT), type(uint256).max);

        BPT.approve(address(GAUGE), type(uint256).max);

        // default value at deployment, it can be modified by the Compound Timelock
        // to avoid funds being frozen on periods on high volatility
        slippageMinOut = 9_400;
    }

    /////////////////////////////// External methods ////////////////////////////////

    /// @notice Allocates the entire idle balance of COMP within the contract into the invesment strategy
    function invest() external onlyCompTimelock {
        uint256 compBalance = COMP.balanceOf(address(this));
        if (compBalance == 0) revert NotCompBalance();

        // 1:1 ratio (COMP:GOLDCOMP)
        GOLD_COMP.deposit(compBalance);

        _depositInBalancerPool(compBalance);

        uint256 bptBalance = BPT.balanceOf(address(this));

        GAUGE.deposit(bptBalance);

        emit CompInvested(compBalance, bptBalance, block.timestamp);
    }

    /// @notice Divest partial or all positions from Balancer and queue withdrawal into GOLDCOMP
    /// @dev Given the constrainst determined by the Balancer V2 pool, at once no more than 30% of the supply should be withdrawn
    /// @param _bptToDivest Amount of BPT to divest from the strategy. If null assumes full divestment
    function commenceDivestment(uint256 _bptToDivest) external onlyCompTimelock {
        // strict input checks since transaction is going via Compound's Timelock
        uint256 bptStaked = GAUGE.balanceOf(address(this));
        if (bptStaked == 0) revert NothingStakedInGauge();
        if (_bptToDivest > bptStaked) revert DivestmentGreaterThanBalance();

        // avoids BAL#306: otherwise could bricked the divestment process
        uint256 invariantRatio = _bptToDivest * BASE_PRECISION / BPT.getActualSupply();
        if (invariantRatio >= BPT_INVARIANT_RATIO) revert DisproportionateExit();

        // 1:1 ratio
        GAUGE.withdraw(_bptToDivest);

        _withdrawFromBalancerPool(_bptToDivest);
        uint256 goldCompBalance = GOLD_COMP.balanceOf(address(this));

        GOLD_COMP.queueWithdraw(goldCompBalance);

        divestmentQueued = true;
        emit CompDivestedQueue(goldCompBalance, _bptToDivest, block.timestamp);
    }

    /// @notice Completes the divestment by withdrawing from GOLDCOMP vault and sending COMP to the comptroller
    /// @dev This method should be called only after commence divest method has been executed and the cooldown period has passed
    function completeDivestment() external onlyCompTimelock {
        if (!divestmentQueued) revert NoDivestmentQueued();

        GOLD_COMP.withdraw();

        uint256 compBalance = COMP.balanceOf(address(this));
        // COMP is sent directly into comptroller
        COMP.safeTransfer(COMPTROLLER, compBalance);

        divestmentQueued = false;
        emit CompDivestedCompleted(compBalance, block.timestamp);
    }

    /// @notice Sets the slippage for the Balancer pool operations
    /// @param _slippageMinOut The new slippage margin
    function setSlippageMinOut(uint256 _slippageMinOut) external onlyCompTimelock {
        if (_slippageMinOut > SLIPPAGE_PRECISION || _slippageMinOut < MIN_SLIPPAGE_VALUE) {
            revert MisconfiguredSlippage();
        }
        slippageMinOut = _slippageMinOut;
    }

    /// @notice Swaps gauge rewards for WETH. Only callable by the GoldenBoyz multisig, primarily intended to safeguard the minimum amount expected
    /// @dev The multisig should simulate the swap and ensure the minimum amount of WETH expected is well protected calling offchain querySwap method
    /// @param _minWethOut The minimum amount of WETH expected, calculated offchain
    function swapRewardsForWeth(uint256 _minWethOut) external onlyGoldenBoyzMultisig {
        GAUGE.claim_rewards();

        // assumes only GOLD as reward as per specifications
        uint256 goldBalance = GOLD.balanceOf(address(this));
        uint256 wethReceived = _swapRewardForWeth(goldBalance, _minWethOut);

        emit RewardSwapped(goldBalance, wethReceived, block.timestamp);
    }

    /// @notice The caller is swapping a specific amount of COMP tokens at the oracle price (COMP/ETH) for WETH. Permissionless
    /// @param _compAmount The amount of COMP token being sent into the contract
    function buyWethWithComp(uint256 _compAmount) external {
        uint256 wethAmount = _compToWethRatio(_compAmount);

        // COMP is sent directly into comptroller
        COMP.safeTransferFrom(msg.sender, COMPTROLLER, _compAmount);
        WETH.safeTransfer(msg.sender, wethAmount);

        emit WethBoughtWithComp(msg.sender, _compAmount, wethAmount);
    }

    /// @notice Public helper method for buying COMP with WETH and being aware of oracle latest answer
    /// @param _compAmount The amount of COMP token to be converted into WETH
    function getCompToWethRatio(uint256 _compAmount) public returns (uint256) {
        return _compToWethRatio(_compAmount);
    }

    /////////////////////////////// Internal methods ////////////////////////////////

    /// @param _oracle The oracle contract to be queried
    /// @param _heartBeat Amount of seconds that can pass between oracle updates in a healthy environment
    /// @return The latest oracle answer casted as uint256
    function _oracleHelper(IOracle _oracle, uint256 _heartBeat) internal returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = _oracle.latestRoundData();

        if (answer < 0) revert NegativeOracleAnswer();
        if (block.timestamp - updatedAt > _heartBeat) revert StaleOracle();

        return uint256(answer);
    }

    /// @notice Internally checks the latest oracle price and convert the COMP amount into WETH ratio to facilitate the swap
    /// @param _compAmount The amount of COMP token
    /// @return The amount of WETH expected given the COMP amount and current oracle latest answer
    function _compToWethRatio(uint256 _compAmount) internal returns (uint256) {
        // COMP / ETH oracle has 18 decimals
        return (_compAmount * _oracleHelper(ORACLE_COMP_ETH, ORACLE_COMP_ETH_HEART_BEAT)) / BASE_PRECISION;
    }

    /// @return The pool assets in the 99goldCOMP-1WETH Balancer pool
    function _poolAssets() internal pure returns (address[] memory) {
        address[] memory poolAssets = new address[](2);
        poolAssets[0] = address(GOLD_COMP);
        poolAssets[1] = address(WETH);

        return poolAssets;
    }

    /// @param _goldCompBalance The amount of GOLDCOMP to be deposit into the pool
    function _depositInBalancerPool(uint256 _goldCompBalance) internal {
        // single sided deposit
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = _goldCompBalance;

        BALANCER_VAULT.joinPool(
            GOLD_COMP_WETH_POOL_ID,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest({
                assets: _poolAssets(),
                maxAmountsIn: amountsIn,
                userData: abi.encode(
                    IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, _calcMinBpt(_goldCompBalance)
                ),
                fromInternalBalance: false
            })
        );
    }

    /// @param _bptBalance The amount of BPT to be withdraw from the pool
    function _withdrawFromBalancerPool(uint256 _bptBalance) internal {
        uint256[] memory minAmountsOut = new uint256[](2);
        // index 0 is the minimum amount of COMP expected
        minAmountsOut[0] = _minCompOut(_bptBalance);

        BALANCER_VAULT.exitPool(
            GOLD_COMP_WETH_POOL_ID,
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

    /// @param _goldAmount The amount of GOLD to be swapped for WETH
    /// @param _minWethOut The minimum amount of WETH expected
    /// @return The amount of WETH received
    function _swapRewardForWeth(uint256 _goldAmount, uint256 _minWethOut) internal returns (uint256) {
        // only pool in mainnet with GOLD liquidity
        // GIVEN_IN type of swap, internally in balancer vault _getAmounts returns amountOut
        return BALANCER_VAULT.swap(
            IBalancerVault.SingleSwap({
                poolId: GOLD_POOL_ID,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(GOLD)),
                assetOut: IAsset(address(WETH)),
                amount: _goldAmount,
                userData: new bytes(0)
            }),
            IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            _minWethOut,
            block.timestamp
        );
    }

    /// @dev Explanation at: https://docs.balancer.fi/concepts/advanced/valuing-bpt/valuing-bpt.html#weighted-pools
    /// @return The ratio of COMP/BPT
    function _ratioCompBpt() internal returns (uint256) {
        // 1:1 ratio (COMP:GOLDCOMP). COMP / USD oracle has 8 decimals
        uint256 compToUsd = _oracleHelper(ORACLE_COMP_USD, ORACLE_COMP_USD_HEART_BEAT);
        // 1:1 ratio (ETH:WETH). ETH / USD oracle has 8 decimals
        uint256 ethToUsd = _oracleHelper(ORACLE_ETH_USD, ORACLE_ETH_USD_HEART_BEAT);

        uint256 invariantDivSupply = (BPT.getInvariant() * BASE_PRECISION) / BPT.getActualSupply();
        uint256 productSequenceOne = uint256(
            FixedPointMathLib.powWad(
                int256((compToUsd * BASE_PRECISION / GOLD_COMP_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(GOLD_COMP_NORMALIZED_WEIGHT)
            )
        );
        uint256 productSequenceTwo = uint256(
            FixedPointMathLib.powWad(
                int256((ethToUsd * BASE_PRECISION / WETH_NORMALIZED_WEIGHT) * BASE_ORACLE_DIFF_PRECISION),
                int256(WETH_NORMALIZED_WEIGHT)
            )
        );

        // formula summary: bpt = invariantDivSupply * productSequenceOne * productSequenceTwo
        uint256 bptToUsd = (invariantDivSupply * productSequenceOne * productSequenceTwo) / BASE_PRECISION_TWOFOLD;
        return compToUsd * BASE_PRECISION / bptToUsd;
    }

    /// @param _goldCompBalance The amount of GOLDCOMP to be converted into minimum BPT expected
    /// @return The minimum amount of BPT expected
    function _calcMinBpt(uint256 _goldCompBalance) internal returns (uint256) {
        uint256 ratio = _ratioCompBpt();
        uint256 minBpt = (_goldCompBalance * ratio) / ORACLE_DECIMALS_BASE;

        // use of fixed point arithmetic and the powWad operation introduces a loss of precision, causing productSequenceTwo to be slightly higher than its theoretical value.
        // to mitigate this, we apply a more aggressive slippage margin, ensuring the minimum expected output amount is protected
        return minBpt * slippageMinOut / SLIPPAGE_PRECISION;
    }

    /// @param _bptBalance The amount of BPT to be converted into minimum COMP out expected
    /// @return The minimum amount of COMP expected
    function _minCompOut(uint256 _bptBalance) internal returns (uint256) {
        uint256 ratio = _ratioCompBpt();
        uint256 minComp = (_bptBalance * ORACLE_DECIMALS_BASE) / ratio;

        // use of fixed point arithmetic and the powWad operation introduces a loss of precision, causing productSequenceTwo to be slightly higher than its theoretical value.
        // to mitigate this, we apply a more aggressive slippage margin, ensuring the minimum expected output amount is protected
        return minComp * slippageMinOut / SLIPPAGE_PRECISION;
    }
}
