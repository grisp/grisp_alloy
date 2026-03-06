# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- Bootstrapped `scripts/tests/` harness with canonical workflow gates:
  - `./scripts/tests/gates/baseline.sh`
  - `./scripts/tests/gates/full.sh`
- Added shared shell test helper library:
  - `scripts/tests/lib/test_helpers.sh`
- Added shell runners/checkers:
  - `scripts/tests/run_tests.sh`
  - `scripts/tests/check_shell_syntax.sh`
  - `scripts/tests/check_shell_lint.sh`
- Full gate delegates Smelterl tests to `smelterl/` when present.
- Added reusable fixture scaffold under `scripts/tests/fixtures/`.
- Added bootstrap self-tests for harness wrappers and fixture sanity.
- Added top-level `alloy` entry script with global option parsing (`--help`,
  `--version`, `--debug`, `--trace`, `--dev`, Vagrant flags, `--forward-env`),
  repository/SDK mode detection, and command dispatch.
- Added `scripts/commands/` command handler wrappers for:
  - `build-sdk`
  - `build-project`
  - `build-firmware`
  - `grispio`
  - `serve-artefacts`
  - `prepare-sdk` (placeholder until full implementation)
- Added CLI unit tests for `alloy` global parsing, unknown-option handling, and
  dispatch normalization (`scripts/tests/test_alloy_entry.sh`).
- Added shared parser conformance tests covering `scripts/argparse.sh`
  count-option semantics and edge cases (`scripts/tests/test_argparse.sh`).
- Added mode-gating CLI tests for repository/SDK command matrix behavior in
  `scripts/tests/test_alloy_entry.sh`.
- Added shared orchestrator debug utilities in
  `scripts/utils/debug_utils.sh` (`log_*`, `set_debug_level`, `set_trace`,
  `enter_hidden`, `leave_hidden`, `die`) with dedicated tests in
  `scripts/tests/test_debug_utils.sh`.
- Added shared orchestrator/common utility entrypoint in
  `scripts/utils/common.sh`, including guardrails (`fail`, `require_var`),
  script preamble helpers (`resolve_script_dir`, `source_required_utility`,
  `is_non_negative_integer`), and user-facing output helpers
  (`print_result`, `print_note`, `print_hint`).
- Added dedicated `common.sh` unit tests in `scripts/tests/test_common_utils.sh`
  covering re-exported debug behavior, failure paths, path helpers, and output
  helper formatting.

### Changed
- Updated `docs/WORKFLOW.md` to enforce concise, final-state history/changelog
  writing, mandatory `.git/ALLOY_COMMIT_MSG` preparation, and outcome-focused
  commit messages (without acceptance-criteria/test-run logs).
- Updated `scripts/argparse.sh` to implement design-conformant `count` option
  behavior (`-d`, `-dd`, `-ddd`, `-dN`, `--debug`, `--debug=N`) with strict
  invalid-value errors and occurrence tracking.
- Updated top-level `alloy` dispatch to enforce mode-gated command availability:
  `build sdk` is repository-only and `prepare sdk` is SDK-only.
- Updated top-level `alloy --help` command listing to be mode-aware (repository
  vs SDK command availability), powered by centralized command metadata.
- Updated top-level `alloy` to source and use shared debug utilities for
  `ALLOY_DEBUG` and `ALLOY_TRACE` handling.
- Updated top-level `alloy` to source `scripts/utils/common.sh` and consume
  centralized helper functions instead of maintaining local helper duplicates.
- Updated SDK-mode alloy fixture setup in `scripts/tests/test_alloy_entry.sh`
  to copy `scripts/utils/common.sh` alongside required debug utilities.
