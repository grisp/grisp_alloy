# AGENTS.md

This file is the operating manual for AI coding agents working in `grisp_alloy`.

## Start Here

Use this read order before implementation:

1. Read this file fully.
2. Read the design source of truth:
   - `docs/00_OVERVIEW.md`
   - `docs/01_DATA_DESIGN.md`
   - `docs/02_SMELTERL_DESIGN.md` (Alloy-side redirect/reference page)
   - `docs/03_ALLOY_DESIGN.md`
   - if the task touches Smelterl itself and a local checkout is present:
     `smelterl/docs/DESIGN.md`
3. Read `docs/WORKFLOW.md`.
4. Read `docs/PLANNING.md` and select the highest-priority pending task unless the human directs otherwise.
5. Read `scripts/tests/README.md` before touching shell tests or validation gates.
6. Mark exactly one task as `[IN_PROGRESS]` before code edits. If the requested work is not represented in `docs/PLANNING.md`, add it there first.

Treat the design docs and workflow doc as authoritative. If implementation and docs disagree, do not guess; identify the gap and resolve it deliberately.

## Project Role

GRiSP Alloy is a build system for embedded Linux firmware for Erlang and Elixir applications.

Primary goal: preserve deterministic, reproducible, secure SDK, project, and firmware builds while moving the implementation toward the documented design.

## Architecture Boundaries

- `alloy` is the bash orchestrator. Keep CLI parsing, mode detection, Vagrant delegation, nugget staging, hook orchestration, SDK/project/firmware flow, and user-facing command behavior here.
- `smelterl` is the Erlang planner/generator. Keep nugget parsing, dependency resolution, validation, target ordering, config consolidation, and generated Buildroot/context/manifest artifacts here.
- Do not duplicate nugget or manifest parsing rules in bash when they belong in `smelterl` or the manifest tooling.
- Treat Buildroot as the execution backend, not the place where Alloy-specific business rules should live.
- Preserve the strict main-target versus auxiliary-target contract. Auxiliary targets produce SDK outputs for the main target; they do not own firmware orchestration.
- Preserve SDK self-containment and relocatability. Do not add fixed install paths, builder-only runtime assumptions, or new host-path leakage into shipped artifacts.
- Keep security material external. Never store keys, certificates, tokens, or signing secrets in the repository or in SDK outputs.

## Current Reality

- The design documents define the canonical CLI as `alloy ...`.
- This repository still contains transitional wrapper scripts such as `build-sdk.sh`, `build-project.sh`, and `build-firmware.sh`.
- Authoritative Smelterl implementation, planning, and history now live in the
  standalone `smelterl` repository; in a superproject checkout that usually
  appears at `./smelterl`.
- When implementing backlog tasks, align behavior and user-facing semantics with the design docs, but validate against the current repository state and existing tests instead of assuming the migration is already complete.

## Project Layout

- `alloy`: top-level bash entrypoint.
- `scripts/commands/`: command handlers.
- `scripts/utils/`: shared bash utilities. Reuse these instead of re-implementing helpers.
- `scripts/tests/`: shell test harness, gates, fixtures, and targeted tests.
- `smelterl/`: standalone Smelterl checkout/submodule when present locally;
  treat it as an external repository for ownership purposes.
- `system_common/`, `system_grisp2/`, `system_kontron-albl-imx8mm/`: current-repo Buildroot trees, overlays, packages, and patches from the implementation-era layout. Treat them as transitional structure, not the long-term architectural source of truth.
- `toolchain/`: current-repo toolchain configs and patches. Useful for the existing implementation, but long-term behavior should be guided by the nugget-based design rather than expanding legacy top-level layout.
- `docs/`: design, workflow, and planning.
- `history/`: one task context file per completed task.

## Commands To Run Early

Environment checks:

```bash
bash --version
git --version
```

Baseline validation before edits:

```bash
./scripts/tests/gates/baseline.sh
```

Full validation before finalizing:

```bash
./scripts/tests/gates/full.sh
```

Focused shell validation:

```bash
./scripts/tests/run_tests.sh
./scripts/tests/check_shell_syntax.sh
./scripts/tests/check_shell_lint.sh
```

Useful targeted tests:

```bash
./scripts/tests/test_alloy_entry.sh
./scripts/tests/test_argparse.sh
./scripts/tests/test_common_utils.sh
./scripts/tests/test_console_utils.sh
./scripts/tests/test_debug_utils.sh
./scripts/tests/test_file_utils.sh
```

If a `smelterl/` checkout is present, use the Smelterl test path documented in `scripts/tests/README.md`.

## Mandatory Workflow

Follow `docs/WORKFLOW.md` exactly:

1. Select a task from `docs/PLANNING.md` and mark it `[IN_PROGRESS]`.
2. Create `history/<YYYYMMDDTHHMMSSZ>__task-<task-id>__<short-description>.md` before implementation.
3. Run baseline tests before coding. If baseline fails, stop and report it before making changes.
4. Add or update tests for every behavior change.
5. Run focused tests during iteration and full relevant suites before finalizing.
6. Update design docs in the same commit when approved behavior or schema changes.
7. Update `CHANGELOG.md`.
8. Write `.git/ALLOY_COMMIT_MSG` and commit with `git commit -F .git/ALLOY_COMMIT_MSG`.
9. Mark the task done in `docs/PLANNING.md`.
10. Refine future planning items with any durable implementation knowledge discovered during the task.

## Bash Editing Rules

- Prefer existing helpers in `scripts/utils/` over ad-hoc shell logic.
- New sourceable utility files should use an explicit source-guard pattern.
- Use shared console and debug helpers for user-facing output and logs; avoid raw `echo` for durable command UX unless the surrounding code already does so for a reason.
- Fail early with clear, contextual error messages.
- Keep changes small, explicit, and task-scoped.
- Keep `shellcheck` clean. Add `# shellcheck disable=...` only as a last resort, and include an inline reason.
- Preserve documented portability assumptions: bash 4+, Linux-native execution, Vagrant delegation when required.

## Data and Build Rules

- Treat `.nuggets`, `.nugget`, and `ALLOY_*_MANIFEST` files as schema-controlled Erlang term files with versioned root tuples.
- Preserve deterministic ordering, reproducible outputs, and early validation behavior.
- Keep target identity, capability reporting, SDK outputs, firmware outputs, and relocation metadata aligned with the design docs.
- Do not introduce repo-only runtime dependencies into generated SDKs.
- Do not weaken mode-gating, command validation, or security-pack checks for convenience.

## Ask First

- Nugget schema or manifest schema changes.
- Changes that move responsibilities across the `alloy` and `smelterl` boundary.
- Main-target versus auxiliary-target contract changes.
- Security-pack interface or secret-handling changes.
- New dependencies, large refactors, or major planning reprioritization.
- Any case where implementation cannot satisfy the design docs without changing the design.

## Never

- Never commit secrets, PKI material, tokens, or `.grispio.token`.
- Never hardcode non-relocatable SDK paths into shipped artifacts.
- Never bypass required validation just to get a green run.
- Never use destructive git operations unless explicitly requested.
- Never weaken tests or specs without justification, documentation, and approval when required.
