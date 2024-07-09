# Trust Setup - Compound's governance proposal

## Background

The Compound Trust setup has being developed in response to concerns raised during a previous Compound proposal. Its objective is to create a trustworthy environment for implementing the strategy detailed in Proposal [247](https://www.tally.xyz/gov/compound/proposal/247), addressing the following issues:

1. Concerns regarding authority and security around multisig
2. Unclear investment strategy

The setup offers clarity when Goldenboyz multisig has the authority to trigger specific actions and what each involves, key actions such as "invest" and "divest" requires prior approval from Compound Governance through a process referred to as granting a "Phase".

## Architecture

### Contract workflow

1. COMP funds will be transferred into the setup by the Compound's comptroller.
2. Compound Governance will invoke `grantPhase(uint8)` updating the "Phase" to `ALLOW_INVESTMENT`, which will grant to the Goldenboyz multisig rights to call `invest(uint256)`.
    1. Once the phase is updated successfully. The Goldenboyz multisig will be able to call `invest(uint256)`, and will periodically call `swapRewardsForWeth(uint256)` for rewards handling.
    2. Bots will call `buyWethWithComp(uint256,uint256)` when the optimal opportunity arises, sending COMP's proceeds to the Compound comptroller directly.
3. If complete or partial divestment from the setup is desired, Compound Governance will call again `grantPhase(uint8)` setting the "Phase" to `ALLOW_DIVESTMENT`.
4. To finalize the investment, after the withdrawal time delay from goldCOMP has elapsed, the Goldenboyz multisig will call the `completeDivestment()` method. Sending all COMP balance back into the Compound's comptroller.

### Goldenboyz multisig controls

1. Invest
2. Divest (including queuing a divestment and its completion)
3. Convert rewards into WETH
4. Update oracle fee (setter)

Actions **(i)** and **(ii)** requires previous approval from Compound Governance to be able to trigger, rest can be call at any time.

### Why is the `swapRewardsForWeth(uint256)` function restricted to being called only by the multisig?

Due to the presence of a single pool with concentrated GOLD liquidity on the mainnet, it is considered safe to hardcode the path. Conversely, using onchain helper contracts like Balancer Queries to determine the minimum expected output could be vulnerable to manipulation while using it atomically. Restricting the `swapRewardsForWeth(uint256)` function to multisig operations enhances the security of the strategy, allowing the multisig to calculate the minimum expected output offchain.

### Permissionless `buyWethWithComp(uint256)` method

The decision to leave `buyWethWithComp(uint256)` accessible to anyone was driven by the potential drawbacks of hardcoding a path for this pair, which would likely result in suboptimal rates and complex architecture. Instead, we chose to allow researchers to identify market discrepancies relative to the oracle and verify the comp/weth rate against the oracle at the time of execution. The proceeds are then sent directly to the comptroller atomically.

### How is the COMP/BPT ratio calculated onchain?

Refer to the following official Balancer [source](https://docs.balancer.fi/concepts/advanced/valuing-bpt/valuing-bpt.html#on-chain-price-evaluation).

## Running tests

- Create `.env` file and place `ALCHEMY_API_KEY={YOUR KEY HERE}` env var there
- Run `forge test` to run test suite
