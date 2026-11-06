# CLAUDE.md

Foundry project for `FundsDispenser`, a native token faucet. `README.md` has the contract, roles, threat model and operations.

## Workflow

- Commit directly to `main`. Open a pull request only when the user asks.
- Before each commit, run `make ci-gate` (see [Checks](#checks)). It must exit 0. If it fails, do not commit.
- Ask the user before each push.
- Use Conventional Commits (`feat:`, `fix:`, `test:`, `ci:`, `docs:`, `chore:`). Keep one topic per commit.
- Dependabot opens pull requests for actions and submodules. Merge them only when CI passes.

## Checks

Install the pinned toolchain, then run all checks. `mise.toml` pins Foundry (the same version as CI) and uv.

```sh
mise install
make ci-gate
```

Each check is a target in the `Makefile`: `fmt`, `lint`, `build`, `test`, `coverage`, `test-solc`, `slither`. `.github/workflows/test.yml` calls the same targets, one per step. `make ci-gate` runs them in sequence and stops at the first failure. Do not use `make -j`: the solc and Solar builds share `out/` and `cache/`.

To add a check, add a target to the `Makefile`, add it to `ci-gate`, and call it from the workflow. Do not put check commands directly in the workflow.

## Compiler

The contracts compile with Solar. Coverage, Slither and `test-solc` use solc (`SOLC` in the `Makefile`). Live deploys use solc too (`--use 0.8.38`, see `README.md`). Issue #6 tracks the move to Solar. Remove a solc setting only after the check in its sub-issue passes.
