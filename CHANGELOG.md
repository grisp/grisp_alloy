# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- Added focused shell tests covering the artefact-server CLI validation
  contract plus the `serve-artefacts.sh` wrapper dispatch path.
- Moved the authoritative artefact-server implementation into
  `scripts/tools/artefact-server` and removed the legacy repository-root copy.
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
  `is_non_negative_integer`).
- Added shared console utility module `scripts/utils/console_utils.sh` for
  terminal-aware ANSI formatting and shared user-facing print helpers
  (`print_result`, `print_note`, `print_hint`).
- Added dedicated `common.sh` unit tests in `scripts/tests/test_common_utils.sh`
  covering re-exported debug behavior, failure paths, path helpers, and output
  helper formatting.
- Added dedicated `console_utils.sh` unit tests in
  `scripts/tests/test_console_utils.sh` for plain/colored output behavior and
  source idempotence checks.
- Added `scripts/utils/file_utils.sh` with shared path/copy primitives:
  `normalize_path`, `relative_path`, `copy_with_exclusions`,
  `merge_directories`, and `make_symlink_relative`.
- Added dedicated file utility tests in `scripts/tests/test_file_utils.sh`
  covering path normalization, relative path derivation, exclusion-aware copy,
  merge override behavior, and symlink relativization.
- Added `scripts/utils/env_utils.sh` with SDK validation, deterministic
  cross-compilation environment setup, and release/overlay ELF target
  architecture validation helpers.
- Added dedicated env utility tests in `scripts/tests/test_env_utils.sh`
  covering SDK layout validation, triplet detection, cross-env exports,
  required-host-command failures, and wrong-architecture ELF rejection.
- Added compact interface documentation comments to reusable functions in
  `scripts/utils/common.sh`, `console_utils.sh`, `debug_utils.sh`,
  `file_utils.sh`, and `env_utils.sh`.
- Added `scripts/utils/vcs_utils.sh` with git-backed clone/validation helpers,
  provenance extraction, and `.alloy_repo_info` generation.
- Added dedicated VCS utility tests in `scripts/tests/test_vcs_utils.sh`
  covering clone/update/reclone behavior, dirty-check policy, provenance
  output, `.alloy_repo_info` writing, and source idempotence.
- Added `scripts/utils/sdk_utils.sh` with SDK relocation detection, first-use
  text-path fixup, and the `ensure_sdk_relocated` auto-relocation gate.
- Added dedicated SDK relocation tests in `scripts/tests/test_sdk_utils.sh`
  covering placeholder/stale-path fixup, writable vs non-writable SDK roots,
  and the explicit `prepare sdk` command flow.
- Added `scripts/utils/plugin_utils.sh` with deterministic plugin loading,
  function dispatch, capability checks, and typed `key=value` reads.
- Added dedicated plugin utility tests in `scripts/tests/test_plugin_utils.sh`
  covering sorted plugin loading, tracked plugin types, dispatch failures, and
  `plugin_read` parsing semantics.
- Added `scripts/utils/security_utils.sh` with security-pack path resolution,
  early `capabilities` validation, filtered `info` / `env` key=value helpers,
  and overlay command delegation for orchestrator-side security-pack flows.
- Added dedicated security utility tests in
  `scripts/tests/test_security_utils.sh` covering file-vs-directory pack
  resolution, invalid pack rejection, key validation, `info` / `env` parsing,
  and overlay unsupported/success paths.
- Added initial Erlang `scripts/tools/manifest-tool` escript with the Task 2.1
  manifest reader/root validator and a focused `validate-root` command for
  SDK/project/firmware manifest root tuples.
- Added dedicated manifest-tool tests in
  `scripts/tests/test_manifest_tool.sh` covering valid SDK/project/firmware
  roots, malformed term files, multiple-term files, and invalid root-shape
  failures.
- Added `manifest-tool get` support for top-level field lookup with plain
  output for binaries/atoms/integers/lists of atoms and `--format erlang` for
  raw Erlang term output.
- Added descriptive top-level `manifest-tool` usage output for the no-command
  path and `--help`, including the currently available commands and examples.
- Expanded `scripts/tests/test_manifest_tool.sh` to cover `get` output modes,
  missing fields, unsupported plain rendering for nested values, and preserved
  parse/structural exit-code behavior.
- Added `manifest-tool hash` support to recompute and rewrite manifest
  integrity sections in place using the documented `basic_term_canon` plus
  SHA-256 contract.
- Added manifest-tool golden tests for known integrity digests, field-order
  sensitivity, stale-integrity replacement, and preserved parse/structural
  failures in the new `hash` command path.
- Added `manifest-tool verify` support to validate embedded manifest integrity
  hashes, including `--integrity-only`, mismatch reporting, and explicit
  unsupported-algorithm / unsupported-canonical-form failures.
- Added manifest-tool verification tests covering successful verification,
  tampered manifests, missing integrity sections, unsupported integrity
  metadata, and preserved parse/structural exit-code behavior.
- Added `manifest-tool merge` support to assemble firmware manifests from one
  SDK manifest plus one or more project manifests, including input integrity
  verification, repository consolidation with reference rewriting, firmware
  metadata decoding from `--firmware-info`, and final integrity hashing.
- Added manifest-tool merge tests covering successful firmware manifest
  assembly, repository-ID conflict rewriting, tampered-input rejection, and
  required `project_root_<id>` enforcement.

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
  to copy `scripts/utils/console_utils.sh` and `scripts/utils/common.sh`
  alongside required debug utilities.
- Updated `scripts/utils/common.sh` and `scripts/utils/debug_utils.sh` to source
  `scripts/utils/console_utils.sh` directly, keeping logging and user-facing
  print formatting on one shared console path.
- Updated orchestrator logging output to support ANSI colors when terminal
  output supports it and `NO_COLOR` is unset.
- Updated file-copy behavior in `scripts/utils/file_utils.sh` to use a single
  `rsync`-based implementation with explicit runtime dependency validation.
- Updated top-level `alloy` startup flow to validate host-side runtime
  dependencies for Vagrant-delegated execution paths (currently `rsync`) before
  delegation begins.
- Updated `scripts/utils/common.sh` with reusable runtime dependency guards
  (`require_command`, `require_commands`).
- Updated `docs/01_DATA_DESIGN.md` and `docs/03_ALLOY_DESIGN.md` to document
  `console_utils.sh`, include-guard expectations for sourced utilities, and the
  revised common/debug utility contracts.
- Updated legacy `scripts/grisp-env.sh` to delegate SDK validation and
  cross-compilation exports to `scripts/utils/env_utils.sh` while preserving
  current sourced-wrapper behavior for existing callers.
- Updated `docs/WORKFLOW.md` to require compact interface comments for
  exported/reusable functions in sourceable shell utilities and to require
  documentation updates whenever callable interfaces change so docs do not
  drift from implementation.
- Updated `docs/03_ALLOY_DESIGN.md` so the VCS utility contract uses an
  explicit `ALLOW_DIRTY` argument, documents the safe dirty-ref behavior, and
  treats `ALLOY_ALLOW_DIRTY=true` as an Alloy command-level default for
  `build sdk` and `build project`.
- Updated `scripts/tests/test_vcs_utils.sh` to isolate fixture git commands
  from host-global git config instead of writing `commit.gpgsign=false` into
  the temporary repositories.
- Updated `docs/WORKFLOW.md` to require the agent to stop at commit
  preparation and ask the user to perform the signed commit whenever signing is
  required.
- Updated `scripts/commands/prepare-sdk.sh` to execute the documented SDK-mode
  relocation flow instead of failing as an unimplemented placeholder.
- Updated `docs/PLANNING.md` so the later project-plugin integration task
  explicitly builds on `plugin_utils.sh` instead of the older hard-coded
  project loader pattern.
- Updated `scripts/tools/manifest-tool` to use width-independent compact
  Erlang term rendering (`~0tp`) for machine-facing output and canonical
  manifest hashing, avoiding formatter-inserted line breaks in integrity
  digests.
