# MultiPool Farm

A staking farm with several pools and a single reward token, built to stay solvent: rewards are paid only from what was funded, and every user can always get their stake back.

[![CI](https://github.com/m15flores/multipool-farm/actions/workflows/ci.yml/badge.svg)](https://github.com/m15flores/multipool-farm/actions)
![Solidity](https://img.shields.io/badge/solidity-0.8.34-363636)
![License](https://img.shields.io/badge/license-MIT-blue)

> **Status: unaudited.** Built as a portfolio project.

## Why

A team wants to reward people who lock tokens, paying a reward token per second. Everyone should get their fair share, the farm should never promise more than it can pay, and nobody should get stuck.

MultiPool Farm does that with:

- **Several pools, one reward token.** Each pool has its own stake token and reward rate. The owner can change a live rate or switch a pool off.
- **Strict funding.** The owner adds rewards with `fundRewards`, and a payout that exceeds what was funded reverts instead of paying less.
- **`emergencyWithdraw`**: "I want my stake back, now." It always works, even when rewards are underfunded, and the user gives up the pending rewards.

It is deliberately small: one reward token, no fixed duration, no locks. My earlier repo [`proportional-staking`](https://github.com/m15flores/proportional-staking) shows the basic reward accounting; this one builds on it with several pools, live rate changes, funding and safe exits.

## How it works

MasterChef-style accounting. Each pool keeps `rewardPerTokenStored`, an accumulator scaled by 1e18, and each user keeps a `rewardDebt`. What a user is owed is `amount × rewardPerTokenStored / 1e18 - rewardDebt`. Design choices:

| Choice | Why |
|---|---|
| Payout checked against `totalFunded`, not `balanceOf` | Donations are never paid out, and `totalDistributed <= totalFunded` holds by construction |
| Revert instead of a silent cap | An underfunded payout fails visibly; the owner funds more and it works again |
| `emergencyWithdraw` skips `_updatePool` and resets `rewardDebt` | The exit works even if an absurd rate makes the reward math overflow |
| `rescueTokens` moves only the surplus | Reward token: balance minus `totalFunded - totalDistributed`. Other tokens: balance minus `totalStakedByToken` |
| `totalStakedByToken` | Pools can share a stake token, so rescue cannot trust a single pool |
| A stake token cannot be the reward token | The two accountings never mix |
| `setPoolInactive` settles, zeroes the rate, then deactivates | The order keeps the last period of rewards; it is irreversible |
| `nonReentrant` on user calls, `SafeERC20` for transfers | Protection on every call that moves tokens for a user |

## API

Full NatSpec and errors in [`MultiPoolFarm`](src/MultiPoolFarm.sol).

| Function | What it does |
|---|---|
| `createPool(token, rewardRate)` | Owner creates a pool and gets its id |
| `stake(poolId, amount)` | Deposit stake tokens; pays pending rewards first |
| `withdraw(poolId, amount)` | Withdraw stake; pays pending rewards, reverts if they are underfunded |
| `claim(poolId)` | Pay the pending rewards |
| `emergencyWithdraw(poolId)` | Withdraw the whole stake and give up pending rewards |
| `pendingRewards(poolId, user)` | Quote pending rewards without sending a transaction |
| `updatePoolRewardRate(poolId, newRewardRate)` | Owner changes the rate of a live pool |
| `setPoolInactive(poolId)` | Owner stops a pool for good |
| `fundRewards(amount)` | Owner adds reward tokens |
| `rescueTokens(token, amount)` | Owner recovers tokens nobody is owed |
| `getPoolIds`, `getPoolCount`, `pools`, `userInfo`, `totalFunded`, `totalDistributed` | State |

## Tests

**75 tests, 100% coverage**

```text
╭-----------------------+-------------------+-------------------+-----------------+-----------------╮
| File                  | % Lines           | % Statements      | % Branches      | % Funcs         |
+===================================================================================================+
| src/MultiPoolFarm.sol | 100.00% (119/119) | 100.00% (135/135) | 100.00% (22/22) | 100.00% (16/16) |
|-----------------------+-------------------+-------------------+-----------------+-----------------|
| Total                 | 100.00% (119/119) | 100.00% (135/135) | 100.00% (22/22) | 100.00% (16/16) |
╰-----------------------+-------------------+-------------------+-----------------+-----------------╯
```

| Type | Tests | What it proves |
|---|---|---|
| Unit | 71 | Every function, custom error and event |
| Invariant | 4 | Random call sequences through a handler: `totalDistributed <= totalFunded`, user stakes add up to each pool total, token balances cover the stakes, rewards received add up to `totalDistributed` |

The handler uses 3 users and 3 pools, two of them sharing a stake token. Its actions are `stake`, `withdraw`, `claim`, `emergencyWithdraw`, time skips, rate changes, funding and direct donations of the reward token. Each run is 256 sequences of 50 calls.

<details>
<summary>Run them</summary>

```bash
forge test                                            # everything
forge test --match-contract MultiPoolFarmInvariants   # invariant tests only
forge coverage --no-match-coverage "test" --report summary
```

</details>

## Security

**Unaudited.** The [Tests](#tests) section lists what is covered. Rewards are paid only from funded tokens, exits never depend on reward math, user calls are `nonReentrant`, and transfers use OpenZeppelin `SafeERC20`.

Known limitations:

- **Owner trust.** The owner sets the reward rates and can switch pools off. There is no cap on a rate, so it can promise more than was funded; payouts then revert and `emergencyWithdraw` still lets everyone leave. The owner cannot take staked tokens or funded rewards.
- **Underfunded exits.** While rewards are underfunded, `claim` and `withdraw` revert, and the way out is `emergencyWithdraw`, which gives up the pending rewards.
- **Lost rewards.** Periods with no stakers accrue nothing, and the unsettled share of someone who leaves through `emergencyWithdraw` stays with the remaining stakers.
- **Simple choices.** Deactivating a pool cannot be undone, `fundRewards` is owner-only, and pool ids hash the token, rate, timestamp and chain id, so two identical pools in the same block collide.

## Development

Requires [Foundry](https://book.getfoundry.sh/).

```bash
git clone --recurse-submodules https://github.com/m15flores/multipool-farm
cd multipool-farm
forge build
forge test
```

## Future work

- A small frontend for an end-to-end demo.
- A fixed reward duration per funding round, as in Synthetix.

## License

MIT