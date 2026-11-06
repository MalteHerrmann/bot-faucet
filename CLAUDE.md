# CLAUDE.md

Foundry project for `FundsDispenser`, a native token faucet. `README.md` has the contract, roles, threat model and operations.

## Workflow

- Commit directly to `main`. Open a pull request only when the user asks.
- Before each commit, run all commands in [Checks](#checks). Each command must exit 0. If one fails, do not commit.
- Ask the user before each push.
- Use Conventional Commits (`feat:`, `fix:`, `test:`, `ci:`, `docs:`, `chore:`). Keep one topic per commit.
- Dependabot opens pull requests for actions and submodules. Merge them only when CI passes.

## Checks

These commands are the same steps as `.github/workflows/test.yml`. When you change one, change the other in the same commit.

Install the pinned toolchain first. `mise.toml` pins Foundry (the same version as CI) and uv.

```sh
mise install
```

Job `test`:

```sh
export FOUNDRY_PROFILE=ci
forge fmt --check
forge lint --deny warnings
forge build --sizes
forge test -vvv
cov=$(mktemp)
forge coverage --use 0.8.38 --no-match-coverage "(test|script|lib)/" --report summary > "$cov"
grep -q '^| src/' "$cov"
awk -F'|' '/^\| src\//{ for (i = 3; i <= 6; i++) if ($i !~ /100\.00%/) bad = 1 } END { exit bad }' "$cov"
```

The last two commands are the coverage gate. Each `src/` file must have 100% lines, statements, branches and functions.

Job `test-solc`:

```sh
FOUNDRY_PROFILE=ci forge test --use 0.8.38 -vvv
```

Job `slither`:

```sh
FOUNDRY_PROFILE=default FOUNDRY_SOLC_VERSION=0.8.38 uvx --python 3.12 --from slither-analyzer==0.11.6 slither . --config-file slither.config.json
```

## Compiler

The contracts compile with Solar. Coverage, Slither, `test-solc` and live deploys use solc 0.8.38. Issue #6 tracks the move to Solar. Remove a solc setting only after the check in its sub-issue passes.
