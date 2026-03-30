# Project Plan

This file is the task backlog and execution status tracker.

Process definition for agents is maintained in:
- [Workflow](WORKFLOW.md)

Design references for implementation:
- [Overview](00_OVERVIEW.md)
- [Data Design](01_DATA_DESIGN.md)
- [Smelterl Design](02_SMELTERL_DESIGN.md)
- [Alloy Design](03_ALLOY_DESIGN.md)

Status convention:
- TODO: `- [ ] **Task ...**`
- IN_PROGRESS: `- [ ] **[IN_PROGRESS] Task ...**`
- DONE: `- [x] **Task ...**`
- Note: use standard markdown task checkboxes (`[ ]`, `[x]`) and encode in-progress explicitly with `[IN_PROGRESS]`.

Backlog policy:
- Prefer one task per commit whenever feasible.
- Every task commit should include tests.
- If design changes, update design docs in the same commit.

## Phase 1: CLI and Shared Utilities

- [x] **Task 1.0: Test harness bootstrap and baseline gates**
  - Scope: Establish shared test helpers/fixtures for shell and Erlang tests, and define baseline/full-suite commands used by workflow gates.
  - Tests: Self-tests for helper wrappers and fixture setup sanity checks.
  - Done when: Every subsequent task can reuse one canonical harness pattern and run baseline/full verification deterministically.

- [x] **Task 1.1: `alloy` main entry and global option parser**
  - Scope: Implement top-level dispatch bootstrap and global flags (`--help`, `--debug`, `--trace`, mode flags).
  - Tests: CLI parse unit tests for global options and unknown-option errors.
  - Done when: Entry script routes to command handlers with normalized argv/env.

- [x] **Task 1.1a: `scripts/argparse.sh` conformance to design contract**
  - Scope: Bring shared parser behavior in line with `docs/03_ALLOY_DESIGN.md` §8.6.2, including `count` option type and required count semantics (`-d`, `-dd`, `-ddd`, `-dN`, `--debug`, `--debug=N`).
  - Tests: Unit tests for parser API/types and count edge cases (valid and invalid forms), including `<VAR>_OPT` occurrence tracking and `POSITIONAL` behavior.
  - Done when: `scripts/argparse.sh` supports design-defined `flag|value|accum|count` behavior with deterministic tests covering `count` mapping and failures.

- [x] **Task 1.2: Mode detection and mode-gated command matrix**
  - Scope: Implement repository-vs-SDK mode detection and allow/deny matrix.
  - Tests: Mode-gating tests for allowed/disallowed commands.
  - Refinement note (from Task 1.1): Matrix must explicitly enforce `build sdk` as repository-only and `prepare sdk` as SDK-only, with clear user-facing errors.
  - Done when: Invalid command-in-mode combinations (including `build sdk` in SDK mode and `prepare sdk` in repository mode) fail with clear errors.

- [x] **Task 1.3: `scripts/utils/debug_utils.sh`**
  - Scope: Logging, debug levels, trace toggles, hidden-section helpers.
  - Tests: Unit tests for log level filtering and trace behavior.
  - Refinement note (from Task 1.1): Move debug/trace behavior now embedded in top-level `alloy` into shared utilities to avoid duplicated logic.
  - Done when: Output format and verbosity match design contracts and top-level entrypoint consumes shared debug utilities.

- [x] **Task 1.4: `scripts/utils/common.sh`**
  - Scope: Shared guardrails (`die`, `require_var`, script preamble helpers).
  - Tests: Unit tests for failure paths and messaging.
  - Refinement note (from Task 1.1): Consolidate generic entrypoint helpers (`fail`, path resolution, validation helpers) into shared common utilities where appropriate.
  - Refinement note (from Task 1.3): `common.sh` should source and re-export `scripts/utils/debug_utils.sh` behavior so command scripts/wrappers share one debug/trace implementation path.
  - Refinement note (from Task 1.3 review): Introduce explicit user-facing output helpers (`print_result`, `print_note`, `print_hint`) in `common.sh` so future tasks avoid raw `echo` for human-facing messaging and can support quiet-mode policies later without changing debug-level semantics.
  - Done when: Common failures are standardized across commands and generic bash helpers are centralized.

- [x] **Task 1.4a: `scripts/utils/console_utils.sh` extraction and logging/printing migration**
  - Scope: Introduce shared console utilities module (`console_utils.sh`) for terminal/ANSI behavior and generic user-facing printing primitives.
  - Scope: Migrate print helpers from `common.sh` into `console_utils.sh`; have both `common.sh` and `debug_utils.sh` source `console_utils.sh` directly (no implicit dependency through `common.sh`).
  - Scope: Standardize include-guard pattern for sourced utility files touched by this task.
  - Tests: Add/update unit tests for console helpers and for colored/plain output behavior in both logging and print paths.
  - Design update requirement: Update design docs (`docs/03_ALLOY_DESIGN.md` and `docs/01_DATA_DESIGN.md`) in the same commit to reflect directory structure and implementation contracts for `console_utils.sh`.
  - Done when: Console formatting/printing is centralized, orchestrator logging/printing paths share the new module, and design + implementation land together in one commit.

- [x] **Task 1.5: `scripts/utils/file_utils.sh`**
  - Scope: Path normalization, safe copy/sync helpers, deterministic directory ops.
  - Tests: Unit tests for path and copy edge cases.
  - Refinement note (from Task 1.4): New utility modules should rely on `scripts/utils/common.sh` as their entry point (`ALLOY_ROOT`/`ALLOY_ROOT_DIR` setup + `source_required_utility`) instead of duplicating bootstrap/path-resolution logic.
  - Refinement note (from Task 1.4a): User-facing command output in new utilities/commands should use `print_result`/`print_note`/`print_hint` from `console_utils.sh` instead of direct `echo`, so quiet/silent policy can be added without rewriting call sites.
  - Refinement note (from Task 1.4a): Any new sourced utility file should include an explicit source-guard pattern to stay idempotent when dependencies are sourced from multiple modules.
  - Done when: File operations are deterministic and error-safe.

- [x] **Task 1.6: `scripts/utils/env_utils.sh`**
  - Scope: SDK validation, cross-env setup primitives.
  - Tests: Unit tests with fixture SDK directories.
  - Refinement note (from Task 1.5): Maintain an explicit required-host-command compatibility check path (built on `common.sh` `require_command(s)`) so missing runtime dependencies fail fast before expensive build/setup operations.
  - Done when: Required env export set is reproducible and validated.

- [x] **Task 1.6a: Sourceable utility function interface documentation**
  - Scope: Add compact developer-facing interface comments for exported functions in `scripts/utils/*.sh`, covering purpose, arguments, outputs/return values, environment assumptions/side effects, and error handling.
  - Tests: Shell syntax/lint and baseline/full workflow gates.
  - Done when: Reusable shell utility functions are self-describing enough for both human maintainers and AI agents to use correctly without re-reading implementations.

- [x] **Task 1.7: `scripts/utils/vcs_utils.sh`**
  - Scope: Clone/fetch/checkout/dirty/ref validation helpers.
  - Tests: Unit tests with local git fixtures.
  - Refinement note (from Task 1.6a): Document every exported function with a compact interface comment describing purpose, arguments, stdout/return behavior, environment assumptions/side effects, and failure mode.
  - Done when: VCS source resolution is deterministic and safe.

- [ ] **Task 1.8: `scripts/utils/sdk_utils.sh`**
  - Scope: SDK relocation checks and relocation execution.
  - Tests: Unit tests for placeholder replacement and non-writable failures.
  - Refinement note (from Task 1.5): Reuse `file_utils.sh` primitives (`normalize_path`, `relative_path`, `make_symlink_relative`, `copy_with_exclusions`, `merge_directories`) for embed/relocation path handling instead of ad-hoc path and copy logic.
  - Refinement note (from Task 1.6a): Document every exported function with a compact interface comment describing purpose, arguments, stdout/return behavior, environment assumptions/side effects, and failure mode.
  - Done when: First-use relocation and explicit prepare flow work.

- [ ] **Task 1.9: `scripts/utils/plugin_utils.sh`**
  - Scope: Plugin load, detect, call, and typed-read wrappers.
  - Tests: Unit tests with mock plugins.
  - Refinement note (from Task 1.6a): Document every exported function with a compact interface comment describing purpose, arguments, stdout/return behavior, environment assumptions/side effects, and failure mode.
  - Done when: Plugin API dispatch is strict and predictable.

- [ ] **Task 1.10: `scripts/utils/security_utils.sh`**
  - Scope: Security pack resolve/validate/info/env primitives.
  - Tests: Unit tests with fake secpack executables.
  - Refinement note (from Task 1.6a): Document every exported function with a compact interface comment describing purpose, arguments, stdout/return behavior, environment assumptions/side effects, and failure mode.
  - Done when: Security pack path and command validation are stable.

## Phase 2: Tools (`scripts/tools`)

- [ ] **Task 2.1: `manifest-tool` term reader and root validation**
  - Scope: Parse and validate root tuple formats for SDK/project/firmware manifests.
  - Tests: Unit tests for valid/invalid root structures.
  - Done when: Tool can read all manifest types reliably.

- [ ] **Task 2.2: `manifest-tool get`**
  - Scope: Field retrieval with plain and Erlang output modes.
  - Tests: Unit tests for nested and missing fields.
  - Done when: `get` behavior is deterministic and documented.

- [ ] **Task 2.3: `manifest-tool hash` and canonicalization integration**
  - Scope: Hash generation against `basic_term_canon`.
  - Tests: Golden tests for known digest outputs.
  - Done when: Stable digest output matches spec.

- [ ] **Task 2.4: `manifest-tool verify`**
  - Scope: Integrity verification against embedded section.
  - Tests: Positive and tampered-manifest tests.
  - Done when: Corruption is always detected with clear failure reason.

- [ ] **Task 2.5: `manifest-tool merge` for firmware manifest**
  - Scope: Merge SDK + project manifests + firmware-info inputs.
  - Tests: Golden test for merged firmware manifest content.
  - Done when: Output structure and integrity are spec-compliant.

- [ ] **Task 2.6: `artefact-server` wrapper contract**
  - Scope: Command-level interface contract used by `alloy serve artefacts`.
  - Tests: Command invocation and arg-validation tests.
  - Done when: Wrapper integration points are stable.

## Phase 3: Smelterl Plan Pipeline (One-Time Resolution)

- [ ] **Task 3.1: `smelterl_cmd_plan` skeleton and option validation**
  - Scope: Command handler with strict required option checks.
  - Tests: Command-option unit tests, stderr/status behavior.
  - Done when: `plan` entry behavior is stable and test-covered.

- [ ] **Task 3.2: `smelterl_motherlode` load + schema checks**
  - Scope: `.nuggets` and `.nugget` parsing with defaults merge.
  - Tests: Parsing/unit tests for malformed and valid registries.
  - Done when: Motherlode map is complete and validated.

- [ ] **Task 3.3: `smelterl_tree` main+aux tree construction**
  - Scope: Main tree, auxiliary discovery, effective auxiliary trees.
  - Tests: Unit tests for dependency resolution and cycle detection.
  - Done when: All target trees are built deterministically.

- [ ] **Task 3.4: `smelterl_validate` target validation**
  - Scope: Category cardinality, constraints, auxiliary restrictions.
  - Tests: Unit tests for each validation family.
  - Done when: Invalid target graphs fail early with clear reasons.

- [ ] **Task 3.5: `smelterl_topology` deterministic ordering**
  - Scope: Stable topological order per target.
  - Tests: Determinism tests on repeated runs.
  - Done when: Same input yields same order every run.

- [ ] **Task 3.6: `smelterl_overrides` nugget/config/aux remap**
  - Scope: Apply overrides in deterministic order with scoped semantics.
  - Tests: Unit tests for last-wins and scope rules.
  - Done when: Overridden trees/motherlode/config are reproducible.

- [ ] **Task 3.7: `smelterl_capabilities` discovery output**
  - Scope: Main firmware capabilities + per-target `sdk_outputs`.
  - Tests: Unit tests for variant/output/param merging and sdk output mapping.
  - Done when: Discovery map is complete for context/manifest generation.

- [ ] **Task 3.8: `smelterl_config` consolidation**
  - Scope: Per-target config/exports with path/computed/exec handling.
  - Tests: Unit tests for substitution, script exec, path resolution.
  - Done when: Consolidated config is deterministic and spec-compliant.

- [ ] **Task 3.9: `smelterl_gen_defconfig` plan-stage model build**
  - Scope: Build structured defconfig model (not rendered file) at plan time.
  - Tests: Unit tests for cumulative keys and wrapper hook injection.
  - Done when: Model can be rendered later without re-resolution.

- [ ] **Task 3.10: `smelterl_gen_manifest` plan-stage seed build**
  - Scope: Build deterministic manifest seed (`auxiliary_products`, firmware `capabilities`, top-level `sdk_outputs` seed).
  - Tests: Unit tests for repository dedup/id stability and seed shape.
  - Done when: Seed is complete and independent from runtime/legal inputs.

- [ ] **Task 3.11: `smelterl_plan` serialization (`build_plan.term`)**
  - Scope: Serialize full plan structure and version markers.
  - Tests: Roundtrip read/write tests.
  - Done when: Plan can be consumed by generate without recomputation.

- [ ] **Task 3.12: `build_plan.env` export writer**
  - Scope: Bash-friendly target list and loop metadata export.
  - Tests: Golden test for env file content.
  - Done when: Orchestrator can source it for target loops.

## Phase 4: Smelterl Generate Pipeline (Target Rendering)

- [ ] **Task 4.1: `smelterl_cmd_generate` skeleton and option validation**
  - Scope: Selected-target generation, main-only option enforcement.
  - Tests: Command-option matrix tests (`--auxiliary` vs main-only options).
  - Done when: Invalid combos fail early and predictably.

- [ ] **Task 4.2: `smelterl_gen_external_desc` render/write**
  - Scope: Generate `external.desc` from selected target plan data.
  - Tests: Golden output test.
  - Done when: Output is deterministic and valid.

- [ ] **Task 4.3: `smelterl_gen_config_in` render/write**
  - Scope: Generate `Config.in` from selected target + plan-carried extra-config.
  - Tests: Golden output test including `ALLOY_MOTHERLODE` behavior.
  - Done when: Output matches design and Buildroot expectations.

- [ ] **Task 4.4: `smelterl_gen_external_mk` render/write**
  - Scope: Generate `external.mk`.
  - Tests: Golden output test.
  - Done when: Include order and content are deterministic.

- [ ] **Task 4.5: `smelterl_gen_defconfig` generate-stage render**
  - Scope: Render selected target defconfig from plan model.
  - Tests: Golden output test.
  - Done when: Generate stage does render only (no resolution).

- [ ] **Task 4.6: `smelterl_gen_context` selected-target context**
  - Scope: Generate target context with strict main-vs-aux boundaries.
  - Tests: Golden tests for one main and one auxiliary context.
  - Done when:
    - Auxiliary context omits firmware/embed/fs-priority control arrays.
    - Main context includes firmware arrays and sdk-output consumption support.

- [ ] **Task 4.7: `smelterl_legal` parse single legal tree**
  - Scope: Parse one Buildroot legal-info input.
  - Tests: Unit tests for parse failures and package extraction.
  - Done when: Parsed legal structure is reusable for merge/export.

- [ ] **Task 4.8: `smelterl_legal` merge/export multi-target legal trees**
  - Scope: Merge main+aux legal data and emit one legal-info export.
  - Tests: Golden export tree test including merged README blocks.
  - Done when: Final export has one merged tree with preserved target README content.

- [ ] **Task 4.9: `smelterl_gen_manifest` generate-stage finalize**
  - Scope: Finalize manifest from seed (runtime fields, legal sections, integrity).
  - Tests: Golden manifest test with and without Buildroot legal data.
  - Done when:
    - `capabilities` is firmware-only.
    - `sdk_outputs` is a separate top-level section.

- [ ] **Task 4.10: Plan/generate integration regression tests**
  - Scope: End-to-end smelterl tests for one main + one auxiliary sample.
  - Tests: Integration tests asserting no dependency resolution in generate.
  - Done when: Pipeline determinism and option gating are verified.

## Phase 5: `alloy build sdk` (Multi-Target Orchestration)

- [ ] **Task 5.1: build-sdk command parser and directory layout**
  - Scope: Build directory structure (`plan/`, `targets/`, `staging/`, `motherlode/`).
  - Tests: Command tests for directory creation and option validation.
  - Refinement note (from Task 1.1): Command help/usage output should present canonical `alloy build sdk ...` UX (not legacy script filename forms).
  - Refinement note (from Task 1.1a): Use shared `scripts/argparse.sh` parser contract for command options to keep option semantics and `<VAR>_OPT` behavior consistent.
  - Refinement note (from Task 1.5 review): Required-command compatibility checks must be execution-context aware: validate only host prerequisites before VM delegation, and validate VM-only prerequisites inside the VM path (do not require host-only tools inside VM or VM-only tools on host).
  - Done when: Layout matches current design and command help/usage is canonicalized.

- [ ] **Task 5.2: Nugget staging (builtin/local/VCS)**
  - Scope: Stage all nugget inputs into build motherlode.
  - Tests: Integration tests with mixed source types.
  - Refinement note (from Task 1.7): Resolve `--allow-dirty` and `ALLOY_ALLOW_DIRTY` in the command layer, then pass an explicit `true|false` dirty-policy argument into `vcs_clone_or_validate` for staged VCS sources.
  - Done when: Staging is reproducible and conflict-safe.

- [ ] **Task 5.3: Smelterl binary management**
  - Scope: Resolve/build/provision smelterl executable.
  - Tests: Command tests for resolution and fallback behavior.
  - Done when: SDK build always has a valid smelterl binary.

- [ ] **Task 5.4: Plan invocation and plan artefact handling**
  - Scope: Invoke `smelterl plan` and store `build_plan.term` (+ optional env).
  - Tests: Integration test validating produced plan artifacts.
  - Done when: One plan pass feeds all target generation passes.

- [ ] **Task 5.5: Target loop and per-target generate invocation**
  - Scope: Build order auxiliaries first, main last; per-target file outputs.
  - Tests: Integration test for target order and generated paths.
  - Done when: All targets are generated from one shared plan.

- [ ] **Task 5.6: Hook wrapper symlinks and target context symlink**
  - Scope: Populate `board/<target>/scripts` wrapper links.
  - Tests: Filesystem tests for expected link targets.
  - Done when: Buildroot hook wrappers resolve correctly for every target.

- [ ] **Task 5.7: Global pre_build dedup execution**
  - Scope: Run each nugget `pre_build` hook at most once across all targets.
  - Tests: Integration test with shared nuggets in multiple targets.
  - Done when: Duplicate execution is prevented with deterministic first-run order.

- [ ] **Task 5.8: Per-target Buildroot build execution**
  - Scope: `make <defconfig>` + `make` with target-local `O=` and `BR2_EXTERNAL=`.
  - Tests: Integration test for target workspace outputs.
  - Done when: Each target build is isolated and successful.

- [ ] **Task 5.9: Per-target legal-info execution**
  - Scope: Run `make legal-info` for every target workspace.
  - Tests: Integration test for expected legal-info directories.
  - Done when: Legal trees are available for merged pass.

- [ ] **Task 5.10: Auxiliary sdk output collection and validation**
  - Scope: Collect `.sdk_outputs` registrations and stage artifacts for main consumption.
  - Tests: Integration tests for missing/duplicate/valid outputs.
  - Done when: `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` mappings are complete and validated.

- [ ] **Task 5.11: Main legal/manifest consolidation pass**
  - Scope: Final main `smelterl generate` with repeatable `--buildroot-legal`, optional `--export-legal`, `--output-manifest`.
  - Tests: Integration tests for merged legal tree and manifest content.
  - Done when: One merged legal tree and final `ALLOY_SDK_MANIFEST` are emitted.

- [ ] **Task 5.12: SDK packing and relocation markers**
  - Scope: Package SDK and produce relocation metadata files.
  - Tests: Integration tests for archive structure and relocation metadata.
  - Done when: Packed SDK is self-contained and relocatable.

## Phase 6: `alloy build project`

- [ ] **Task 6.1: build-project command parser and SDK resolution**
  - Scope: Parse options, resolve SDK mode/repository mode behavior.
  - Tests: Command tests for `--sdk` and mode combinations.
  - Refinement note (from Task 1.1): Command help/usage output should present canonical `alloy build project ...` UX (not legacy script filename forms).
  - Refinement note (from Task 1.1a): Use shared `scripts/argparse.sh` parser contract for command options to keep option semantics and `<VAR>_OPT` behavior consistent.
  - Refinement note (from Task 1.7): Normalize `--allow-dirty` and `ALLOY_ALLOW_DIRTY` here so downstream VCS/project-source helpers receive an explicit dirty-policy boolean instead of reading ambient environment state.
  - Done when: Project command starts with a validated SDK context and command help/usage is canonicalized.

- [ ] **Task 6.2: Plugin detection and build dispatch**
  - Scope: Detect project type and call plugin build/info hooks.
  - Tests: Unit tests with mock plugin fixtures.
  - Done when: Plugin selection and dispatch are deterministic.

- [ ] **Task 6.3: Cross-compilation environment setup**
  - Scope: Use SDK host/staging toolchains and environment exports.
  - Tests: Unit/integration tests validating exported toolchain vars.
  - Refinement note (from Task 1.6): Reuse `scripts/utils/env_utils.sh` as the single source for SDK validation, triplet discovery, toolchain exports, and target-architecture probing; keep `scripts/grisp-env.sh` as a compatibility wrapper only until legacy callers are removed.
  - Done when: Plugin builds consume consistent cross env.

- [ ] **Task 6.4: Release scrubbing and architecture validation**
  - Scope: Strip/reduce release artifacts and verify target architecture.
  - Tests: Integration tests with valid and wrong-arch binaries.
  - Refinement note (from Task 1.6): Run `validate_release_target_arch` after release scrubbing and include both release and overlay staging trees in coverage so wrong-architecture NIFs or helper binaries fail before packaging.
  - Done when: Wrong-arch content fails early.

- [ ] **Task 6.5: Project manifest generation**
  - Scope: Build `ALLOY_PROJECT_MANIFEST` via manifest-tool.
  - Tests: Golden manifest tests and integrity verification tests.
  - Done when: Project artefact contains valid manifest.

- [ ] **Task 6.6: Project artifact packing**
  - Scope: Final project archive layout and metadata inclusion.
  - Tests: Integration archive-content test.
  - Done when: Output package layout is spec-compliant.

## Phase 7: `alloy build firmware` (Main-Context Ownership)

- [ ] **Task 7.1: build-firmware parser and project-spec normalization**
  - Scope: Parse project specs, `--name`, output flags, params, variant.
  - Tests: Parser unit tests with mixed option/project ordering.
  - Refinement note (from Task 1.1): Command help/usage output should present canonical `alloy build firmware ...` UX (not legacy script filename forms).
  - Refinement note (from Task 1.1a): Use shared `scripts/argparse.sh` parser contract for command options to keep option semantics and `<VAR>_OPT` behavior consistent.
  - Done when: Parsed model is deterministic, validated, and command help/usage is canonicalized.

- [ ] **Task 7.2: Main context load and guard checks**
  - Scope: Source main context and enforce `ALLOY_IS_AUXILIARY=false`.
  - Tests: Guard tests for auxiliary-context failure.
  - Done when: Firmware build is blocked outside main context.

- [ ] **Task 7.3: Project artifact resolution and extraction**
  - Scope: Resolve local/URL project artifacts and unpack to workspace.
  - Tests: Integration tests for resolution and extraction behavior.
  - Done when: Project staging is stable and deterministic.

- [ ] **Task 7.4: Overlay and filesystem priorities merge**
  - Scope: Merge nugget/project/security/CLI overlays and priorities.
  - Tests: Integration tests for merge order and conflict handling.
  - Done when: Final overlay and priority fragments are deterministic.

- [ ] **Task 7.5: Parameter and capability validation**
  - Scope: Validate `--variant`, output selection, and firmware parameters.
  - Tests: Validation tests for required/type/default semantics.
  - Done when: Invalid firmware invocation fails before hooks run.

- [ ] **Task 7.6: Firmware hook orchestration by variant**
  - Scope: Run `pre_firmware`, `firmware_build`, `post_firmware` chains.
  - Tests: Integration tests for array selection and execution order.
  - Done when: Variant-specific chain execution is deterministic.

- [ ] **Task 7.7: Firmware outputs registry and selectable output handling**
  - Scope: Register outputs, apply default/selectable selection rules.
  - Tests: Unit/integration tests for output enable/disable matrix.
  - Done when: Produced outputs match selected/default policy.

- [ ] **Task 7.8: Firmware manifest merge and rootfs inclusion**
  - Scope: Generate and place `ALLOY_FIRMWARE_MANIFEST` in rootfs overlay.
  - Tests: Integration tests for merge fields and integrity.
  - Done when: Final firmware includes valid merged manifest.

- [ ] **Task 7.9: Firmware artifact packaging**
  - Scope: Package final firmware outputs and optional legal attachments.
  - Tests: Integration tests for final artifact set and naming.
  - Done when: Firmware outputs are complete and reproducible.

## Phase 8: Security Pack, Serve, and GrispIO

- [ ] **Task 8.1: Security utility integration in firmware flow**
  - Scope: Wire `security_resolve_pack`, `security_info`, `security_export_env`.
  - Tests: Integration tests with fixture secpack implementations.
  - Done when: Security metadata/env flow is stable and validated.

- [ ] **Task 8.2: `security_tools.sh` hook-facing API**
  - Scope: Implement signing/credential/tls helper wrappers for hooks.
  - Tests: Unit tests against mocked secpack command outputs.
  - Done when: Hook API is stable and errors are actionable.

- [ ] **Task 8.3: `alloy serve artefacts` command**
  - Scope: Implement HTTP/TLS/mTLS serving command integration.
  - Tests: Command and integration tests for tls modes.
  - Refinement note (from Task 1.1): Command help/usage output should present canonical `alloy serve artefacts ...` UX.
  - Done when: Server starts with expected security mode from options/secpack and command help/usage is canonicalized.

- [ ] **Task 8.4: `alloy grispio` command**
  - Scope: Token management and upload command orchestration.
  - Tests: Unit tests for token handling and reference resolution.
  - Refinement note (from Task 1.1): Command help/usage output should present canonical `alloy grispio ...` UX.
  - Done when: Upload workflow is reproducible, validated, and command help/usage is canonicalized.

## Phase 9: Documentation and Consistency Gates

- [ ] **Task 9.1: Generated example sync tests**
  - Scope: Add tests/fixtures that assert docs examples match generated outputs.
  - Tests: Golden tests for `alloy_context.sh`, `ALLOY_SDK_MANIFEST`, legal README.
  - Done when: Example drift is caught automatically.

- [ ] **Task 9.2: Cross-reference and terminology audit**
  - Scope: Verify anchors, terms, and plan/generate semantics across all design docs.
  - Tests: Link-check and terminology grep checks in CI.
  - Done when:
    - No stale references to pre-plan/generate CLI (`smelterl generate --product/--motherlode`).
    - No stale references to `sdk_outputs` being nested inside `capabilities`.

- [ ] **Task 9.3: CLI help and error UX consistency audit**
  - Scope: Ensure all command handlers present canonical `alloy ...` help/usage and consistent user-facing error style.
  - Tests: Golden CLI-output tests for `--help` and representative error cases across major commands.
  - Refinement note (from Task 1.2): Include mode-gating error outputs in coverage (for example disallowed `build sdk` in SDK mode and `prepare sdk` in repository mode).
  - Done when: Help/error output is command-consistent and free from legacy script-name UX leakage.
