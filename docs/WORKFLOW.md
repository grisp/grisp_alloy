# AI Agent Development Workflow

## Purpose

This document defines the mandatory development workflow for AI agents.
It is the process source of truth; task backlog and prioritization live in
`docs/PLANNING.md`.

Goals:
- high quality and reliability through disciplined testing and verification,
- traceability of decisions and implementation history,
- maintainability for future agents and human reviewers.

## Companion Documents

- Design source of truth:
  - `docs/00_OVERVIEW.md`
  - `docs/01_DATA_DESIGN.md`
  - `docs/02_SMELTERL_DESIGN.md`
  - `docs/03_ALLOY_DESIGN.md`
- Task backlog and status:
  - `docs/PLANNING.md`

## Core Principles

- Test-driven or test-first delivery:
  - write expected-behavior tests before or alongside implementation.
- Small, focused commits:
  - one logical task per commit whenever possible.
- Changelog discipline:
  - keep traceability notes in the task context file during development and
    update `CHANGELOG.md` before finalizing the commit.
- No test gaming:
  - never change tests only to force a green run.
- Deterministic verification:
  - establish baseline before changes; rerun full relevant suites at the end.
- Human-in-the-loop design governance:
  - any design change must be justified, discussed, and documented.
- Persistent task memory:
  - each task maintains a context file for future agents/reviewers.

## Task Status Convention

Use these conventions in `docs/PLANNING.md`:
- TODO: `- [ ] **Task ...**`
- IN_PROGRESS: `- [ ] **[IN_PROGRESS] Task ...**`
- DONE: `- [x] **Task ...**`

Rationale:
- Markdown task-list standards (GitHub/CommonMark) define checkbox states as unchecked `[ ]` and checked `[x]` only.
- In-progress state is represented by an unchecked item with an explicit `[IN_PROGRESS]` label.

Rules:
- only one task marked `[IN_PROGRESS]` per agent at a time,
- select from the highest-priority pending task unless instructed otherwise.

## Task ID Source (Mandatory)

Task ID must be explicit in every context file and must come from:
- primary source: the selected task identifier in `docs/PLANNING.md`
  (example: `Task 3.7`),
- if no matching planning task exists: create one in `docs/PLANNING.md` first,
  then use that ID.

Do not invent standalone IDs that are not represented in `docs/PLANNING.md`.

## Mandatory Task Lifecycle

For every task, execute these steps in order.

1. Read and ground context before any code edits.
   - Read design documents `00/01/02/03`.
   - Read current code paths related to the task.
   - Validate assumptions against actual implementation.

2. Select task and mark it `[IN_PROGRESS]` in `docs/PLANNING.md`.

3. Perform focused investigation.
   - Deep-read relevant design sections for the selected task.
   - Inspect exact modules/files/functions to be changed.
   - Identify ambiguities, risks, and impact surfaces.

4. Create initial task context file.
   - Location:
     `history/<YYYYMMDDTHHMMSSZ>__task-<task-id>__<short-description>.md`.
   - Create `history/` if missing.
   - Write initial version before implementation starts.
   - Timestamp must be UTC and generated at context-file creation time.

5. Run baseline tests.
   - Run full relevant suites before coding.
   - If baseline fails, stop and report before implementing.

6. Define and write tests for expected behavior.
   - Prefer simple, readable tests.
   - Reuse helper functions, shared fixtures, and custom assertions.

7. Implement code.
   - Keep scope constrained to the selected task.
   - Favor small, explicit, readable changes.
   - Avoid unrelated refactors unless necessary for correctness.

8. Handle failures with discipline.
   - Do not modify tests unless the test itself is clearly wrong.
   - Any test expectation adjustment must be justified in context file.

9. Iterate with focused tests; complete with full suites.
   - During implementation: run targeted tests.
   - Before completion: rerun all full suites.

10. Handle design changes through human approval.
   - If design gaps/contradictions are found:
     - document issue/proposal in context file,
     - discuss with human manager,
     - when approved, update design docs in same commit as code.

11. Finalize context file.
   - Record what was implemented, issues encountered, resolutions, rationale,
     test evidence, and any design updates.
   - Keep only durable review/debug information (no noisy transcripts).

12. Finalize records and commit preparation.
   - Update root `CHANGELOG.md` using Keep a Changelog:
     - https://keepachangelog.com/en/1.1.0/
   - Prepare clear commit message (scope + tests).
   - Mark task DONE in `docs/PLANNING.md`.

13. Report completion to human manager.
   - Include:
     - task completed,
     - baseline and final test results,
     - design changes (if any),
     - residual risks/follow-ups.

## Definition of Done (Per Task)

A task is DONE only if all are true:
- task marked `[x]` in `docs/PLANNING.md`,
- context file exists and is fully updated,
- tests added/updated and passing,
- full relevant suites rerun after code changes,
- design docs updated when behavior/spec changed,
- `CHANGELOG.md` updated,
- commit message prepared,
- completion report provided to human manager.

## Commit Quality Policy

- one task => one small self-contained commit whenever possible,
- every commit includes tests,
- if design changed, include code + docs + context rationale together,
- split oversized tasks before implementation.

## Quality Gates

Before finalizing a task:
- tests:
  - relevant unit/integration/golden/property suites pass,
- static checks:
  - run relevant linters and static analysis for touched components
    (for example Dialyzer for Erlang modules when applicable),
- docs:
  - update design docs for approved design changes,
  - update `CHANGELOG.md`,
- context history quality:
  - task id is present and matches `docs/PLANNING.md`,
  - filename is prefixed with UTC timestamp for deterministic ordering,
  - no commit SHA is required in-context (file is committed together with code),
  - context includes decisions/rationale/test evidence,
  - context excludes low-value noise (full terminal transcripts, duplicated diffs).

## Context History Signal/Noise Rules

Include (high signal):
- concise problem statement and expected behavior,
- before/after behavior and scope boundaries,
- key decisions with rationale and tradeoffs,
- design deltas with exact section references,
- baseline and final validation evidence,
- residual risks and follow-up items.

Exclude (noise):
- full command logs/transcripts,
- copied large code blocks already in the repository,
- repetitive step-by-step notes without decisions,
- speculative alternatives that did not influence implementation.

Rule of thumb:
- if a detail does not help future review, regression investigation, or safe
  extension, leave it out.

## Task Context File Template (Mandatory)

Filename format is mandatory and must be sortable:
- `history/<YYYYMMDDTHHMMSSZ>__task-<task-id>__<short-description>.md`
- Example:
  `history/20260301T154210Z__task-3.7__smelterl-capabilities.md`

Every context file using this format must contain at least:

1. `# Task <id>: <title>`
2. Metadata block
   - Date,
   - Author/Agent identifier,
   - Related task id (from `docs/PLANNING.md`) and design anchors.
   - `Commit SHA`: omit in this file (not available pre-commit and redundant
     because this file is part of the commit).
3. `## Objective`
   - problem statement and intended outcome.
4. `## Design References`
   - exact section links used.
5. `## Code References (Initial)`
   - relevant modules/files/functions before changes.
6. `## Focused Investigation Notes`
   - findings, ambiguities, risks.
7. `## Implementation Plan`
   - concrete implementation steps.
8. `## Expected File Changes`
   - explicit list of files expected to be touched and why.
9. `## Test Plan`
   - baseline suites,
   - new/updated tests,
   - final full-suite validation plan.
10. `## Execution Log`
   - chronological development notes,
   - failures and resolutions.
11. `## Design Changes`
   - `None` or approved changes + rationale + decision link/summary.
12. `## Final Validation`
    - test runs and outcomes,
    - residual risks.
13. `## Commit Preparation`
    - changelog entries,
    - proposed commit message.
14. `## Completion Summary`
    - concise handover for future agents/reviewers.
