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
- Updated `docs/WORKFLOW.md` to enforce concise, final-state history/changelog
  writing and mandatory `.git/ALLOY_COMMIT_MSG` commit-message preparation.
