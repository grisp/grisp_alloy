# Test Harness Bootstrap

Canonical workflow commands:

- Baseline gate: `./scripts/tests/gates/baseline.sh`
- Full gate: `./scripts/tests/gates/full.sh`

Shell tests:

- Location: `scripts/tests/test_*.sh`
- Runner: `./scripts/tests/run_tests.sh`
- Framework: `bash_unit` (must be available on `PATH`)
- Syntax check: `./scripts/tests/check_shell_syntax.sh`
- Lint check: `./scripts/tests/check_shell_lint.sh` (runs in full gate)

Smelterl tests (delegated, not hosted here):

- If executable, full gate runs `./smelterl/scripts/tests/run_tests.sh`.
- Otherwise, if `./smelterl/rebar.config` exists, full gate runs `rebar3 as test ct` in `./smelterl`.
- When touching Smelterl/Erlang code, also run `rebar3 dialyzer` in `./smelterl`;
  workflow requires Common Test to pass and Dialyzer to report zero warnings.
- Set `ALLOY_REQUIRE_SMELTERL_TESTS=1` to fail when Smelterl tests cannot run.
- Set `ALLOY_REQUIRE_SHELLCHECK=1` to fail when `shellcheck` is unavailable.
- Set `ALLOY_SHELLCHECK_STRICT=1` to fail on shellcheck findings (default is non-blocking warning).
