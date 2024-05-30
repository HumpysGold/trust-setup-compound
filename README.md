# Trust Setup - Compound's governance proposal

## Background

The Compound Trust setup has being developed in response to concerns raised during a previous Compound proposal. Its objective is to create a trustworthy environment for implementing the strategy detailed in Proposal [247](https://www.tally.xyz/gov/compound/proposal/247), addressing the following issues:

1. Concerns regarding authority and security around multisig
2. Unclear investment strategy

The setup offers clarity which entity has the authority to trigger specific actions, such as the Compounds' timelock and the multisig, while the entire investment strategy is verifiable onchain.

## Architecture

### Contract workflow

1. COMP funds will be transferred into the setup by the Compound's comptroller.
2. The Compound Timelock will invoke `invest()`.
    1. Once the timelock successfully calls `invest()`, Goldenboyz multisig will periodically call `swapRewardsForWeth(uint256)`.
    2. Bots will call `buyWethWithComp(uint256)` when the optimal opportunity arises, sending COMP's proceeds to the Compound comptroller directly.
3. If divestment from the setup is desired, the Compound Timelock will trigger `commenceDivestment()`.
4. To finalize the investment, after the withdrawal time delay from goldCOMP has elapsed, the Timelock will call the `completeDivestment()` method. Sending all COMP balance back into the Compound's comptroller.

### Compound's Timelock controls

1. Invest (see `invest()` method): Invests COMP funds into the Balancer pool and stakes the BPT into the appropriate gauge. The first step involves depositing COMP into goldCOMP, which is then single-sidedly deposited into the Balancer Pool.
2. Commence divestment (see `commenceDivestment()` method): Proceeds to withdraw from the gauge and the Balancer pool, and initiates the withdrawal queue from goldCOMP.
3. Complete divestment (see `completeDivestment()` method): Finalizes the divestment from the strategy by officially withdrawing the queued amount of goldCOMP and directly transferring the entire COMP balance in the contract to the Compound comptroller.

### Goldenboyz multisig controls

1. Swap gauge rewards for WETH (see `swapRewardsForWeth(uint256)` method)

### Why is the `swapRewardsForWeth(uint256)` function restricted to being called only by the multisig?

Due to the presence of a single pool with concentrated GOLD liquidity on the mainnet, it is considered safe to hardcode the path. Conversely, using onchain helper contracts like Balancer Queries to determine the minimum expected output could be vulnerable to manipulation while using it atomically. Restricting the `swapRewardsForWeth(uint256)` function to multisig operations enhances the security of the strategy, allowing the multisig to calculate the minimum expected output offchain.

### Permissionless `buyWethWithComp(uint256)` method

The decision to leave `buyWethWithComp(uint256)` accessible to anyone was driven by the potential drawbacks of hardcoding a path for this pair, which would likely result in suboptimal rates and complex architecture. Instead, we chose to allow researchers to identify market discrepancies relative to the oracle and verify the comp/weth rate against the oracle at the time of execution. The proceeds are then sent directly to the comptroller atomically.

### How is the COMP/BPT ratio calculated onchain?

Refer to the following official Balancer [source](https://docs.balancer.fi/concepts/advanced/valuing-bpt/valuing-bpt.html#on-chain-price-evaluation).

## Running tests

- Create `.env` file and place `ALCHEMY_API_KEY={YOUR KEY HERE}` env var there
- Run `forge test` to run test suite
