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
  - record the final commit outcome, not intermediate drafts/rewrites that
    happened during task implementation.
- Context signal over volume:
  - keep history files compact and decision-focused,
  - include only durable information useful for future review/debugging.
- No test gaming:
  - never change tests only to force a green run.
- Deterministic verification:
  - establish baseline before changes; rerun full relevant suites at the end.
- Human-in-the-loop design governance:
  - any design change must be justified, discussed, and documented.
- Persistent task memory:
  - each task maintains a context file for future agents/reviewers.
- Progressive planning refinement:
  - after each completed task, refine future planning items with newly
    discovered constraints/notes so critical implementation details are not
    forgotten.

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
   - Record only durable information:
     - objective/outcome,
     - key decisions and rationale,
     - unexpected issues/divergences and resolution,
     - concise validation evidence and residual risks.
   - Write sections from the final-state perspective of the commit.
     Do not describe within-task intermediate versions unless an unexpected
     issue materially affected the final design, tests, or risks.
   - Avoid chronological transcripts and low-signal planning leftovers.

12. Finalize records and commit preparation.
   - Update root `CHANGELOG.md` using Keep a Changelog:
     - https://keepachangelog.com/en/1.1.0/
   - MUST create a fresh `.git/ALLOY_COMMIT_MSG` for the current task with a
     clear commit message (scope + final outcomes). Do not duplicate
     commit-message text in the history context file.
   - Commit-message content MUST focus on final task outcomes (behavior,
     architecture, key user-visible effects). Avoid administrative noise
     (for example: marking task status, updating changelog/history files)
     unless that process change is itself part of the task outcome.
   - Commit-message content MUST NOT include acceptance criteria or validation
     logs (for example: `tests: ...`, gate names, PASS/FAIL statements).
     Validation evidence belongs in task context and completion reporting.
   - MUST commit using this file:
     `git commit -F .git/ALLOY_COMMIT_MSG`
   - Example draft command:
     `cat > .git/ALLOY_COMMIT_MSG <<'EOF'
     feat(scope): short summary

     - key change 1
     - key change 2
     EOF`
   - Mark task DONE in `docs/PLANNING.md`.

13. Refine future planning items.
   - Review `docs/PLANNING.md` and update relevant future tasks with
     implementation knowledge discovered in the completed task.
   - Scope is flexible: update any future task that benefits from the
     refinement, not only immediately next tasks.
   - Allowed without extra approval:
     - add clarification notes,
     - add dependencies/order notes,
     - add missing acceptance details,
     - add clearly missing tasks.
   - Requires human-manager approval:
     - major scope rewrites,
     - phase-wide reprioritization/resequencing,
     - design-behavior changes not already approved.
   - Keep refinements concise and evidence-based.

14. Report completion to human manager.
   - Include:
     - task completed,
     - baseline and final test results,
     - design changes (if any),
     - residual risks/follow-ups,
     - planning refinements applied for future tasks.

## Definition of Done (Per Task)

A task is DONE only if all are true:
- task marked `[x]` in `docs/PLANNING.md`,
- context file exists and is fully updated,
- tests added/updated and passing,
- full relevant suites rerun after code changes,
- design docs updated when behavior/spec changed,
- `CHANGELOG.md` updated,
- `.git/ALLOY_COMMIT_MSG` prepared,
- planning refinement pass completed for future tasks (or explicitly `None`),
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
    (for example `shellcheck` for touched shell scripts when available;
    prefer strict mode in CI, Dialyzer for Erlang modules when applicable),
- docs:
  - update design docs for approved design changes,
  - update `CHANGELOG.md`,
- planning:
  - refine relevant future tasks in `docs/PLANNING.md` based on discovered
    implementation constraints (or explicitly record `None` in task context),
- commit preparation:
  - `.git/ALLOY_COMMIT_MSG` exists, is non-empty, and reflects the current
    task (check: `test -s .git/ALLOY_COMMIT_MSG`),
- context history quality:
  - task id is present and matches `docs/PLANNING.md`,
  - filename is prefixed with UTC timestamp for deterministic ordering,
  - context includes decisions/rationale/test evidence,
  - context and changelog describe final commit state (not implementation
    churn within the same task),
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
- repetitive step-by-step notes without decisions or deviations,
- speculative alternatives that did not influence implementation.
- proposed commit messages (store ephemeral drafts in `.git/` instead).
- within-task rewrites described as change-chains (`A -> B -> C`) when only the
  final result matters.

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
3. `## Objective`
   - problem statement and intended outcome.
4. `## Design References`
   - exact section links used.
5. `## Code References (Initial)`
   - relevant modules/files/functions before changes.
6. `## Key Decisions`
   - implementation choices and rationale.
7. `## Unexpected Issues And Resolution`
   - only divergences, failures, or ambiguities that affected implementation.
8. `## Validation Evidence`
   - concise baseline/final command evidence and outcomes.
9. `## Design Changes`
   - `None` or approved changes + rationale + decision link/summary.
10. `## Residual Risks / Follow-ups`
    - what remains uncertain or intentionally deferred.
11. `## Changed Artifacts`
    - concise list of touched files/areas by purpose.
12. `## Completion Summary`
    - concise handover for future agents/reviewers.
