# Each target is one CI step. The workflow calls the targets one by one.
# `make ci-gate` runs all of them in sequence. Run it before each commit.

# solc for the steps that Solar does not support yet (issue #6).
SOLC := 0.8.38
FORGE := FOUNDRY_PROFILE=ci forge

.PHONY: ci-gate fmt lint build test coverage test-solc slither

ci-gate: fmt lint build test coverage test-solc slither

fmt:
	$(FORGE) fmt --check

# Fails on any lint warning (high, medium, low severity).
lint:
	$(FORGE) lint --deny warnings

build:
	$(FORGE) build --sizes

test:
	$(FORGE) test -vvv

# Solar source maps make coverage too low (paradigmxyz/solar#2300).
# Fails when the table is missing or a src/ file is below 100% on lines, statements, branches or functions.
coverage:
	$(FORGE) coverage --use $(SOLC) --no-match-coverage "(test|script|lib)/" --report summary --report lcov --report-file lcov.info > coverage.txt
	cat coverage.txt
	grep -q '^| src/' coverage.txt
	awk -F'|' '/^\| src\//{ for (i = 3; i <= 6; i++) if ($$i !~ /100\.00%/) bad = 1 } END { exit bad }' coverage.txt

# Live deploys use solc bytecode. This tests it with the optimizer on.
test-solc:
	$(FORGE) test --use $(SOLC) -vvv

# Slither needs the solc AST. On Solar, it checks nothing (paradigmxyz/solar#2293).
slither:
	FOUNDRY_PROFILE=default FOUNDRY_SOLC_VERSION=$(SOLC) uvx --python 3.12 --from slither-analyzer==0.11.6 slither . --config-file slither.config.json
