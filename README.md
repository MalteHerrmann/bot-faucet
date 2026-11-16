# FundsDispenser

`FundsDispenser` is a native token faucet. It gives known bot accounts recurring gas funding under per-account limits. Bots hold little gas, and the engineering team has a low operational load. The contract is not upgradeable by design.

## How it works

`requestFunds(address requester)` is permissionless. Anyone can call it. Funds always go to the registered `requester`, never to the caller.

The contract runs these checks in order. A failed check reverts the call.

1. The contract is not paused (`EnforcedPause`).
2. `requester` is registered (`NotRegistered`).
3. `requester.balance <= thresholdBalance` (`BalanceTooHigh`).
4. `cooldown` seconds have passed since the last payout (`CooldownNotElapsed`). The first payout has no cooldown.
5. Paid funds in the current epoch plus `amount` are at most `grantedFundsPerEpoch` (`LimitReached`).

If all checks pass, the contract records the payout, emits `FundsDistributed`, and sends `amount` to `requester`. The call reverts with `FailedToSend` if the contract balance is too low or the requester rejects the transfer.

Epoch `k` is the time range `[registeredAt + k*epochDuration, registeredAt + (k+1)*epochDuration)`. `registeredAt` is the block time of the last `registerConfig` call for that account. The paid amount resets when a new epoch starts. The cooldown does not reset. It always counts from the last payout.

Re-registering an account replaces its config and resets its payout counters.

`requestFunds` is permissionless because a bot with no gas cannot send a transaction. A keeper or a teammate can call it for the bot. The limits apply to `requester`, not to the caller. A caller cannot raise the limits or change the destination.

## Configuration

`registerConfig` takes a `FundsRequestConfig` for each bot. Amounts are in wei. Times are in seconds.

| Field | Meaning | Validation rule |
| --- | --- | --- |
| `amount` | Amount sent per payout. | `> 0` and `<= grantedFundsPerEpoch` |
| `cooldown` | Minimum time between two payouts. | `< epochDuration` (`0` means no cooldown) |
| `grantedFundsPerEpoch` | Total amount the bot can receive per epoch. | `> 0` |
| `epochDuration` | Length of one epoch. | `> 0` |
| `thresholdBalance` | Highest bot balance that can still request funds. | `> 0` |

An invalid config reverts with `InvalidConfig`. The zero address reverts with `EmptyAddress`.

Example, in field order:

| `amount` | `cooldown` | `grantedFundsPerEpoch` | `epochDuration` | `thresholdBalance` |
| --- | --- | --- | --- | --- |
| `2e15` | `1 days` | `3e17` | `28 days` | `1e15` |

The bot gets 0.002 tokens per request. It can request once per day. It can receive at most 0.3 tokens per 28 days. It can request only when its balance is 0.001 tokens or less.

## Roles

| Role | Holder | Functions |
| --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | Engineering multisig | `registerConfig`, `removeRequester`, `withdraw`, `unpause`, `grantRole` and `revokeRole` (for `PAUSER_ROLE`), admin transfer |
| `PAUSER_ROLE` | The admin, and any account the admin adds | `pause` |

- The deployer passes the admin address to the constructor. The deployer gets no role.
- The constructor also grants `PAUSER_ROLE` to the admin.
- Admin transfer has two steps. The admin calls `beginDefaultAdminTransfer`. The new admin calls `acceptDefaultAdminTransfer` after the delay. The delay is 0 (`INITIAL_ADMIN_DELAY`). The new admin accepts in a later block. The admin can change it with `changeDefaultAdminDelay`.
- `grantRole` and `revokeRole` revert for `DEFAULT_ADMIN_ROLE`. Use the transfer.
- The admin cannot renounce the role in one step. `renounceRole` works only after `beginDefaultAdminTransfer(address(0))`. The contract then has no admin. Do not do this.
- An admin transfer does not move `PAUSER_ROLE`. Revoke it from the old admin and grant it to the new admin by hand.

## Threat model

- A compromised bot key loses at most `grantedFundsPerEpoch` per epoch for that bot. Payouts around an epoch boundary can use the limits of two epochs in a short time, if the cooldown allows it. Remove the bot or pause the contract.
- A compromised pauser key can only stop payouts. Revoke the role and unpause.
- A misconfigured requester is bounded by its own limits.
- A compromised multisig loses the full contract balance. Keep the float small. Top up on a schedule.
- Reentrancy is blocked. The contract updates its state before it sends funds, and `ReentrancyGuard` protects `requestFunds` and `withdraw`.
- The balance threshold is a convenience, not a security control. A requester can move funds out before it calls.
- There is no global outflow cap. The contract balance is the maximum loss.

## Operations

Set `DISPENSER`, `RPC_URL`, and `BOT` in the shell. Replace `<keystore>` with the name of a Foundry keystore. Admin calls must come from the admin account. For a multisig admin, build the same call in the multisig interface.

### Fund

Anyone can send native tokens to the contract. The contract emits `Funded`.

```
cast send $DISPENSER --value 1ether --rpc-url $RPC_URL --account <keystore>
```

### Register

This call sets or replaces the config of `$BOT`. It resets the payout counters.

```
cast send $DISPENSER "registerConfig(address,(uint256,uint256,uint256,uint256,uint256))" $BOT "(2e15,86400,3e17,2419200,1e15)" --rpc-url $RPC_URL --account <keystore>
```

### Remove

```
cast send $DISPENSER "removeRequester(address)" $BOT --rpc-url $RPC_URL --account <keystore>
```

### Request for a bot

Any account with gas can send this call. The funds go to `$BOT`.

```
cast send $DISPENSER "requestFunds(address)" $BOT --rpc-url $RPC_URL --account <keystore>
```

Use `cast call` with the same arguments to simulate the request first.

### Pause and unpause

`pause` needs `PAUSER_ROLE`. `unpause` needs the admin. Pause stops `requestFunds` only. `withdraw`, `registerConfig`, and `removeRequester` still work.

```
cast send $DISPENSER "pause()" --rpc-url $RPC_URL --account <keystore>
cast send $DISPENSER "unpause()" --rpc-url $RPC_URL --account <keystore>
```

### Withdraw

```
cast send $DISPENSER "withdraw(address,uint256)" $TO 1ether --rpc-url $RPC_URL --account <keystore>
```

### Rotate the admin

1. The old admin schedules the transfer.

   ```
   cast send $DISPENSER "beginDefaultAdminTransfer(address)" $NEW_ADMIN --rpc-url $RPC_URL --account <keystore>
   ```

2. Read the schedule.

   ```
   cast call $DISPENSER "pendingDefaultAdmin()(address,uint48)" --rpc-url $RPC_URL
   ```

3. The new admin accepts.

   ```
   cast send $DISPENSER "acceptDefaultAdminTransfer()" --rpc-url $RPC_URL --account <keystore>
   ```

4. The new admin moves `PAUSER_ROLE`.

   ```
   cast send $DISPENSER "grantRole(bytes32,address)" $(cast keccak PAUSER_ROLE) $NEW_ADMIN --rpc-url $RPC_URL --account <keystore>
   cast send $DISPENSER "revokeRole(bytes32,address)" $(cast keccak PAUSER_ROLE) $OLD_ADMIN --rpc-url $RPC_URL --account <keystore>
   ```

### Monitoring

Alert on these events:

- `FundsDistributed`: every payout. Alert on a rate above the expected rate.
- `RegistrationUpdated`, `RegistrationRemoved`: any change to a bot config.
- `Withdrawn`: any withdrawal.
- `Funded`: top-ups. Use it to track the float.
- `Paused`, `Unpaused`: any state change.
- `RoleGranted`, `RoleRevoked`: any role change.
- `DefaultAdminTransferScheduled`: any scheduled admin transfer.

Also watch the contract balance. A low balance makes `requestFunds` revert with `FailedToSend`.

## Deploy

Install the submodules first.

```
forge install
```

Then deploy.

```
ADMIN=<multisig> forge script script/Deploy.s.sol --rpc-url $RPC_URL --account <keystore> --broadcast --verify --use 0.8.38
```

The script checks that `ADMIN` is the default admin and holds `PAUSER_ROLE`. Then it logs the contract address. The signer never comes from an env var. Pass it on the command line. `foundry.toml` has no `[etherscan]` section, so set a block explorer API key for `--verify`.

`--use 0.8.38` compiles with solc. Block explorers cannot verify Solar bytecode yet ([#5](https://github.com/MalteHerrmann/bot-faucet/issues/5)).

## Development

Install the toolchain. `mise.toml` pins Foundry 1.9.0, which includes Solar 0.3.0, and uv.

```
mise install
```

Run all checks. CI runs the same `Makefile` targets.

```
make ci-gate
```

To run one check, run its target: `make fmt`, `make lint`, `make build`, `make test`, `make coverage`, `make test-solc` or `make slither`.

The contracts compile with [Solar](https://github.com/paradigmxyz/solar) (`solc = "solar"` in `foundry.toml`). These steps use solc 0.8.38 (`SOLC` in the `Makefile`). [#6](https://github.com/MalteHerrmann/bot-faucet/issues/6) tracks the move to Solar.

- Live deploys. Block explorers cannot verify Solar bytecode ([sourcify#3043](https://github.com/argotorg/sourcify/issues/3043)). The `test-solc` CI job tests this bytecode.
- Coverage. Solar source maps report too low ([solar#2300](https://github.com/paradigmxyz/solar/issues/2300)).
- Slither. Solar gives no AST, and Slither then checks nothing and passes ([solar#2293](https://github.com/paradigmxyz/solar/issues/2293)).

In tests that call `vm.warp` or `vm.roll`, read the block values with `vm.getBlockTimestamp()` and `vm.getBlockNumber()`. Solar can read a saved `block.timestamp` again after the warp. `forge lint` flags this (`environment-read-across-mutation`).

Test layout:

- `test/FundsDispenser.t.sol`: unit tests.
- `test/FundsDispenser.invariants.t.sol`: invariant tests.
- `test/Deploy.t.sol`: deploy script test.
- `test/FundsDispenserHarness.sol`: harness that exposes internal state.
- `test/mocks/`: mock contracts for reentrancy and rejected transfers.

## CI

CI runs on pushes to `main`, on pull requests, and on manual dispatch. Actions are pinned by commit SHA. Foundry is pinned to v1.9.0. Each check step calls one `Makefile` target. The `test` job runs `make fmt`, `make lint` (any lint warning fails), `make build`, and `make test` with the `ci` profile (5000 fuzz runs, 1024 invariant runs). It then runs `make coverage`, which checks coverage with solc. Each step also runs when an earlier step fails. Every `src/` file must have 100% lines, statements, branches, and functions. The `slither` job runs `make slither`: Slither 0.11.6 on a solc build. It fails on medium severity or higher. The `test-solc` job runs `make test-solc`: the tests on solc with the optimizer on. Live deploys use this bytecode. Dependabot updates actions and git submodules every week.

## Design decisions

- Not upgradeable. To change the behavior, withdraw the funds, deploy a new instance, register the bots again, and fund it. A proxy adds a key that can change the code and drain the funds. Storage uses plain state variables because ERC-7201 has no use without a proxy.
- `requestFunds(address)` is permissionless. A bot with no gas cannot call for itself.
- `pause` needs `PAUSER_ROLE`, which can sit on a hot key. `unpause` needs the multisig.
- There is no global cap yet. Per-requester limits and a small float cover the risk. Add a daily cap if the float grows.
