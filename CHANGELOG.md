# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning.

## [Unreleased]

### Changed
- Updated `alloy build sdk` summary and Alloy-owned log path reporting to show paths relative to the current working directory when they are inside that directory, while preserving absolute paths for out-of-tree locations.
- Updated SDK packing to run deterministic ELF RPATH hardening before text
  relocation sanitization: `pack_sdk` now scans embedded ELF files across
  `host/`, `images/`, `motherlode/`, and `staging`, rewrites fixable absolute
  RPATH entries to `$ORIGIN`-relative paths with `patchelf`, and fails
  immediately on malformed or non-relocatable entries.
- Updated `alloy build sdk` to execute SDK packing after the target build and
  legal/manifest consolidation phases, producing a packed SDK tree under
  `staging/sdk` and a versioned SDK archive in `artefacts/sdk/`.
- Updated `alloy build sdk` summary output to report the packed SDK directory
  and resulting SDK archive path.
- Updated `alloy build sdk` to run a final main-target legal/manifest
  consolidation pass after per-target `make legal-info`, invoking
  `smelterl generate` with repeatable `--buildroot-legal` inputs plus
  `--output-manifest` and `--export-legal legal-info` to produce staged merged
  legal output and `ALLOY_SDK_MANIFEST`.
- Updated `alloy build sdk` summary output to report staged
  `ALLOY_SDK_MANIFEST` and merged `legal-info/` paths now that the
  consolidation pass is implemented.
- Updated `alloy build sdk` Buildroot execution to prefer
  `BUILDROOT_DIR/utils/brmake` (instead of `make`) for defconfig/build and
  `legal-info` invocations when `ALLOY_DEBUG=0`, reducing default command
  verbosity while preserving `make` execution for higher debug levels.
- Updated `alloy build sdk` to collect declared auxiliary `.sdk_outputs`
  registrations after per-target legal-info, validate absolute/existing output
  paths, stage them under
  `staging/auxiliary/<AUX_ID>/outputs/<OUTPUT_ID>/...`, and inject
  main-context `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` mappings plus
  unique-only `ALLOY_SDK_OUTPUT_<OUTPUT_ID>` aliases.
- Updated `alloy build sdk` to run `make legal-info` for every planned target
  (auxiliaries first, main last) after the per-target Buildroot build loop,
  using the same target-local `O=` and `BR2_EXTERNAL=` execution context.
- Updated `alloy build sdk` to execute per-target Buildroot builds after
  Smelterl generation (`make <target>_defconfig` then `make`) with isolated
  target-local `O=` and `BR2_EXTERNAL=` contexts, preserving auxiliary-first
  then main build order.
- Updated `alloy build sdk` to source `build_plan.env` after `smelterl plan`
  and run one shared-plan `smelterl generate` loop for every target,
  generating auxiliary targets first and the main target last under
  `targets/<TARGET_ID>/`.
- Updated `alloy build sdk` to run the first Smelterl orchestration pass,
  writing `plan/build_plan.term` and `plan/build_plan.env` after nugget
  staging and Smelterl binary resolution, while preserving literal plan-time
  path placeholders for later generate/build phases.
- Updated `alloy build sdk` to resolve the checked-out Smelterl version,
  reuse `artefacts/tools/smelterl-<VERSION>` when available, build it with
  `rebar3 escriptize` when missing, and force a clean rebuild in development
  mode while maintaining `artefacts/tools/smelterl` as a relative symlink to
  the current versioned executable.
- Made `alloy build sdk --help` surface the relevant global debug/trace flags
  and added `-d`/`-dd` staging observability for SDK workspace and motherlode
  setup.
- Updated the workflow implementation rules to require debug logging alongside
  new orchestrator command/wrapper behavior.
- Updated `alloy build sdk` to stage nugget repositories into the product
  motherlode before later plan/generate phases, preserving the command-layer
  `ALLOY_MOTHERLODE` path as the single source of truth.
- Replaced the transitional `scripts/commands/build-sdk.sh` wrapper with a
  canonical `alloy build sdk` command implementation that validates
  repository-mode usage, parses Task 5.1 options with the shared
  `scripts/argparse.sh` contract, initializes `_build/sdk/<product>/`
  workspace roots (`plan/`, `targets/`, `staging/`, `motherlode/`), and
  exports the shared `ALLOY_SDK_*` / `ALLOY_MOTHERLODE` paths for later Phase
  5 orchestration tasks; when run directly, it infers SDK mode only to reject
  the command rather than fabricating SDK-mode build paths for a repo-only
  operation.
- Tightened the `alloy build sdk` option contract so `-c` means only
  `--clean`; package-specific cleanup is now `--clean-package PKG` long-only,
  matching the clarified design and avoiding context-dependent short-option
  parsing.
- Updated `AGENTS.md` and `docs/WORKFLOW.md` to require agents to stop and ask
  for human clarification whenever requirements or documented contracts are
  ambiguous or internally inconsistent, instead of inventing compatibility
  workarounds.
- Updated the repository `smelterl` submodule to include the latest
  plan/generate pipeline work through `smelterl: finalize review fixes for
  generate outputs`, bringing in packaged-escript `priv/` embedding,
  Alloy-specific legal export support, Buildroot path/manifest legal-path
  fixes, and expanded Smelterl generate/plan validation coverage.
- Refined the Alloy-side multi-repository workflow documentation so
  Smelterl-owned work can defer a pure `grisp_alloy` submodule-pointer sync
  until later batched synchronization, while still requiring linked
  repo-local tasks for substantive cross-repository changes.
- Refined `AGENTS.md`, `docs/WORKFLOW.md`, and `docs/PLANNING.md` to require
  durable process improvements discovered in review or implementation to be
  codified in repository docs instead of being left only in conversation or
  task-local notes.
- Switched the repository `smelterl` dependency to an HTTPS Git submodule
  bootstrap flow and updated `alloy build sdk` to fail fast with explicit
  checkout/init guidance instead of assuming a local embedded Smelterl tree.
- Aligned Alloy-side Smelterl references, documentation links, and validation
  guidance with the canonical Smelterl checkout and repository documentation.

### Added
- Added initial SDK packer support in `scripts/utils/sdk_utils.sh` via
  `pack_sdk` and pack-time text path sanitization that emits
  `.alloy_relocation_manifest` and `.alloy_sdk_dir` relocation metadata in the
  packed SDK tree.
- Added focused `sdk_utils` coverage for pack-time path sanitization and
  relocation-manifest/state-file generation.
- Added `alloy build sdk` integration coverage for packed SDK output layout and
  relocation-marker files.
- Added focused `alloy build sdk` coverage for the main legal/manifest
  consolidation pass, including repeatable `--buildroot-legal` wiring,
  staged manifest/legal outputs, and `--include-sources` forwarding.
- Added hook-side SDK output registration support via
  `scripts/utils/hook_common.sh` and `scripts/utils/sdk_tools.sh`, including
  `alloy_sdk_add_output`, `alloy_sdk_has_output`, and `alloy_sdk_get_output`
  for SDK-time hooks.
- Added focused hook-wrapper coverage that sources `hook_common.sh` in a real
  `post_build` hook and verifies `.sdk_outputs` registration through
  `alloy_sdk_add_output`.
- Added focused `alloy build sdk` coverage for auxiliary sdk output
  collection/validation: valid staging and mapping export, missing registry
  failure, and duplicate output-id alias suppression.
- Added focused `alloy build sdk` coverage asserting per-target `make
  legal-info` invocation order and target-isolated Buildroot context.
- Added target-local executable `make_alloy` helpers under
  `targets/<TARGET_ID>/workspace/` so manual Buildroot debugging can reuse the
  same `ALLOY_*`, `O=`, and `BR2_EXTERNAL=` context as orchestrator runs.
- Added focused `alloy build sdk` coverage for per-target Buildroot make-loop
  execution and `make_alloy` forwarding behavior.
- Added focused `alloy build sdk` coverage for per-target `smelterl generate`
  ordering plus generated target-local `br2_external/`, defconfig, context,
  and workspace paths.
- Added focused `alloy build sdk` coverage for `smelterl plan` invocation,
  plan artefact creation, output path handling, and placeholder extra-config
  propagation.
- Added focused `alloy build sdk` coverage for cached Smelterl reuse, missing
  artefact build fallback, development-mode rebuild behavior, and current
  Smelterl symlink updates.
- Added Task 5.2 shell coverage for mixed builtin, local, and VCS nugget
  staging, basename-conflict suffixing, missing local sources, and explicit
  dirty-check policy propagation.
- Added a real builtin `nuggets/` repository with a bootstrap sample product
  chain for early Alloy/Smelterl Phase 5 validation:
  `builder_buildroot`, `toolchain_smoke`, `platform_smoke`,
  `system_smoke`, `bootflow_smoke`, and `smoke_product`.
- Added lightweight bootstrap Buildroot integration for the smoke nuggets,
  including a `builder_buildroot` pre-build hook that downloads/extracts
  Buildroot and wires cache directories, host-architecture exports for
  `platform_smoke`, and defconfig fragments for the builder, toolchain,
  platform, and system smoke chain.
- Added focused repository coverage in `scripts/tests/test_builtin_nuggets.sh`
  for the builtin `.nuggets` registry, the sample product dependency chain,
  builder pre-build hook, and bootstrap platform/toolchain/bootflow metadata
  contract.
- Added focused shell coverage for `scripts/commands/build-sdk.sh`, including
  canonical help output, repository-mode validation, workspace creation,
  `--clean-package` handling, rejection of ambiguous `-c VALUE` usage, and
  `ALLOY_ALLOW_DIRTY` validation.
- Added explicit Smelterl submodule bootstrap guidance in `README.md`, an
  opt-in `--init-deps` initialization path for repository-mode `alloy build
  sdk`, and a GitLab CI validation job that syncs/initializes the submodule
  before running the full gate.
- Added a GitHub Actions validation workflow that checks out submodules,
  installs the shell/Erlang test dependencies, and runs the same explicit
  submodule-aware full gate used locally.
- Added focused shell coverage for missing-Smelterl and explicit submodule-init
  paths in `alloy` entry and full-gate tests.
- Added end-to-end artefact-server tests covering direct HTTP serving,
  manual-TLS HTTPS serving, and tar-member serving from `<name>.tar`.
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
