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
    update `CHANGELOG.md` before finalizing the commit only when the task
    changes behavior, interfaces, outputs, supported workflow, or other
    user-facing/developer-facing repository contracts in a way that is useful
    to changelog readers.
  - do not add changelog entries for planning maintenance, history files,
    task-status bookkeeping, or agent-only workflow/process notes.
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
  - when investigation reveals cleanup, compatibility debt, or doc/code drift
    that is intentionally left for later, capture it in planning as a
    refinement note or new task before closing the current task.
- Process self-refinement:
  - when human feedback, reviewer feedback, or agent experience reveals a
    durable process improvement, ambiguity, or recurring failure mode, codify
    it in the owning repository documentation instead of leaving it only in
    chat or task-local memory,
  - update `AGENTS.md`, `docs/WORKFLOW.md`, and/or planning notes in the
    owning repository according to the scope of the improvement.
- Repository-local ownership:
  - in a multi-repository checkout, work is tracked per repository, even when
    development starts from one superproject root.

## Multi-Repository Development Model

Development starts from the `grisp_alloy` repository root. That checkout is
the daily working context even when the active implementation task is owned by
the `smelterl/` submodule.

Ownership rules:
- `grisp_alloy` planning/workflow/history/changelog cover Alloy orchestration,
  shared workflow, and Alloy-owned design/docs.
- `smelterl/` planning/workflow/history/changelog cover Smelterl
  implementation, tests, and Smelterl-owned planning/history.
- A user request that makes substantive changes in both repositories must be
  represented as linked repo-local tasks, not as one unowned cross-repo
  change.
- A Smelterl-only implementation task does not require an immediate
  `grisp_alloy` planning task when the only eventual Alloy-side change is a
  later submodule-pointer sync.
- Pure submodule-pointer sync work in `grisp_alloy` may batch multiple already
  completed Smelterl commits into one later Alloy task/commit.

Execution rules for linked tasks:
- Keep only one task marked `[IN_PROGRESS]` at a time across the active
  planning files.
- Start with the repository that owns the current implementation change.
- If `smelterl/` changes are required, complete and commit the Smelterl task
  first.
- Create or move a `grisp_alloy` follow-up task to `[IN_PROGRESS]` only when
  the superproject is actually being changed:
  - immediately, when Alloy-side code/docs/tests also change as part of the
    same overall feature/fix,
  - later, when development returns to `grisp_alloy` and a batched submodule
    sync commit is being prepared.
- A cross-repository feature/fix is not fully complete until every touched
  repository task is done and `grisp_alloy` records the final Smelterl
  submodule commit.

Current-repository terms used below:
- `current repository`: the repository that owns the task currently marked
  `[IN_PROGRESS]` (`grisp_alloy` or `smelterl/`).
- `current planning file`: `docs/PLANNING.md` in the current repository.
- `current history directory`: `history/` in the current repository.
- `current changelog`: `CHANGELOG.md` in the current repository.
- `current commit-message file`: `$(git rev-parse --git-dir)/ALLOY_COMMIT_MSG`
  when run in the current repository root. In a superproject checkout, a
  Smelterl task may use `git -C smelterl rev-parse --git-dir` to resolve the
  Smelterl repository git dir without relying on `smelterl/.git` being a
  directory.

Standalone Smelterl note:
- The same repository-local rules apply when `smelterl` is checked out on its
  own.
- A standalone Smelterl change that would require a later `grisp_alloy`
  submodule-pointer update, shared-doc update, or orchestration change must
  call out that downstream follow-up explicitly in planning/history/completion
  reporting instead of silently treating the Smelterl commit as the whole job.
- That downstream follow-up does not need an immediate `grisp_alloy` planning
  task if the superproject will be synchronized later in one batched commit.

## Task Status Convention

Use these conventions in the current planning file:
- TODO: `- [ ] **Task ...**`
- IN_PROGRESS: `- [ ] **[IN_PROGRESS] Task ...**`
- DONE: `- [x] **Task ...**`

Rationale:
- Markdown task-list standards (GitHub/CommonMark) define checkbox states as unchecked `[ ]` and checked `[x]` only.
- In-progress state is represented by an unchecked item with an explicit `[IN_PROGRESS]` label.

Rules:
- only one task marked `[IN_PROGRESS]` per agent at a time across the active
  repository planning files,
- select from the highest-priority pending task unless instructed otherwise.

## Task ID Source (Mandatory)

Task ID must be explicit in every context file and must come from:
- primary source: the selected task identifier in the current planning file
  (example: `Task 3.7`),
- if no matching planning task exists: create one in the current planning file
  first, then use that ID.

Do not invent standalone IDs that are not represented in the current planning
file.

## Mandatory Task Lifecycle

For every task, execute these steps in order.

1. Read and ground context before any code edits.
   - Read design documents `00/01/02/03`.
   - Read current code paths related to the task.
   - Validate assumptions against actual implementation.

2. Select task and mark it `[IN_PROGRESS]` in the current planning file.
   - If the task is Smelterl-owned, use `smelterl/docs/PLANNING.md` instead.
   - If the request makes substantive changes in both repositories, split it
     into linked repo-local tasks and mark only the currently edited
     repository task `[IN_PROGRESS]`.
   - Do not create a `grisp_alloy` task yet when the only expected Alloy-side
     work is a future submodule-pointer sync that will be batched later.

3. Perform focused investigation.
   - Deep-read relevant design sections for the selected task.
   - Inspect exact modules/files/functions to be changed.
   - Identify ambiguities, risks, and impact surfaces.
   - Analyze the requirement and interface contracts thoroughly enough to catch
     ambiguities or internal conflicts before implementation starts.
   - If design docs, workflow rules, parser contracts, tests, or the human
     request conflict, stop and escalate to the human with a concise summary of
     the issue and the available contract choices.
   - Do not implement a silent compatibility workaround just to keep moving
     when the intended contract is unclear.

4. Create initial task context file.
   - Location:
     `history/<YYYYMMDDTHHMMSSZ>__task-<task-id>__<short-description>.md` in
     the current repository.
   - Create the current history directory if missing.
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
   - For orchestrator commands and wrappers, add or update debug logging for
     new behavior in the same change. Use `log_info` for high-level progress
     that helps users understand what `-d` changed, and `log_debug` for
     developer-facing details such as resolved paths, selected targets,
     delegated commands, and staging decisions.
   - For nugget hook scripts, source `scripts/utils/hook_common.sh` and use
     the shared `alloy_log_*` / `alloy_die` API from `debug_tools.sh`.
     Do not add ad-hoc hook-local logging wrappers or direct `echo`-based
     diagnostic output unless a task explicitly documents and justifies an
     exception.
   - For Smelterl Erlang code, treat `smelterl.erl` as the canonical home for
     cross-module shared types. Before adding a new shared `-type`, check
     whether the shape already exists there; prefer remote type references
     (`smelterl:type_name()`) over duplicating shared type declarations across
     modules.
   - For reusable/exported functions and similar callable interfaces
     (for example shell functions, Erlang functions, or other developer-facing
     helper APIs), keep the implementation-facing documentation in sync with
     the code.
   - Whenever a function/interface is added or modified, its documentation
     MUST be added, updated, and validated in the same change so there is no
     drift between behavior and documentation.
   - For sourceable shell utilities, every exported/reusable function MUST have
     a compact interface comment immediately above it describing:
     - purpose,
     - arguments,
     - stdout/return behavior,
     - required environment inputs and side effects,
     - error handling / failure mode.

8. Handle failures with discipline.
   - Do not modify tests unless the test itself is clearly wrong.
   - Any test expectation adjustment must be justified in context file.

9. Iterate with focused tests; complete with full suites.
   - During implementation: run targeted tests.
   - Before completion: rerun all full suites.
   - For touched Erlang code, Common Test MUST pass and Dialyzer MUST report
     zero warnings before the task is considered complete.

10. Handle design changes through human approval.
   - If design gaps/contradictions are found:
     - document issue/proposal in context file,
     - discuss with human manager,
     - when approved, update design docs in same commit as code.
   - The same rule applies to requirement-level incoherence that does not yet
     require a broad design change (for example an ambiguous CLI short option):
     document the conflict, ask the human to choose the intended contract, and
     only then implement the approved behavior.

11. Finalize context file.
   - Record only durable information:
     - objective/outcome,
     - key decisions and rationale,
     - unexpected issues/divergences and resolution,
     - residual risks or intentionally deferred follow-up.
   - Keep the file future-facing:
     - write for a later reviewer/agent who was not present during the task,
     - prefer problem/constraint/decision context over process narration,
     - include a note only if it will still matter after the commit already
       exists and the local working session is gone.
   - Treat the standard workflow as implicit:
     - do not restate mandatory process steps just because they happened,
     - record process details only when the task deviated from the workflow,
       when a step failed/was blocked, or when a validation result explained a
       design or implementation decision.
     - successful execution of the normal required validation commands is not,
       by itself, durable history-file content.
   - Write sections from the final-state perspective of the commit.
     Do not describe within-task intermediate versions unless an unexpected
     issue materially affected the final design, tests, or risks.
   - Avoid chronological transcripts and low-signal planning leftovers.
   - Exclude local or ephemeral workflow state from the history file, for
     example:
     - reminders that a human still needs to create a signed commit,
     - notes about transient `gpg` / `pinentry` / blocked-amend friction that
       did not change the engineering result,
     - notes that a commit message file was prepared or changes were staged,
     - statements that only describe the current checkout state rather than the
       durable engineering context of the task.

12. Finalize records and commit preparation.
   - When the task is changelog-relevant, update the current changelog using
     Keep a Changelog:
     - https://keepachangelog.com/en/1.1.0/
   - Skip the changelog when the task only changes planning/history/internal
     process bookkeeping and does not materially affect repository consumers or
     contributors.
   - MUST create a fresh current commit-message file for the current task with
     a clear commit message (scope + final outcomes). Do not duplicate
     commit-message text in the history context file.
   - Write commit-message content from the parent-commit perspective:
     describe what this commit changes in behavior, interfaces, architecture,
     or developer workflow after it lands.
   - Subject/body should be imperative and outcome-focused; avoid first-person
     process narration (“I changed...”, “during this task we...”).
   - Commit-message content MUST focus on final task outcomes (behavior,
     architecture, key user-visible effects). Avoid administrative noise
     (for example: marking task status, updating changelog/history files)
     unless that process change is itself part of the task outcome.
   - Commit-message content MUST NOT include “process completed” bullets unless
     the process contract itself changed. Exclude by default:
     - task-status transitions in planning files,
     - history/context file creation/update,
     - changelog bookkeeping statements,
     - staging/index state,
     - “tests were run/passed” execution logs.
   - Commit-message content MUST NOT include acceptance criteria or validation
     logs (for example: `tests: ...`, gate names, PASS/FAIL statements).
     Validation evidence belongs in completion reporting and in task context
     only when it adds durable information beyond the expected workflow
     (for example a task-specific gap, failure, deviation, or result that
     explains a design/debugging decision).
   - If the repository or user workflow requires signed commits, the agent MUST
     stop after preparing the current commit-message file, the staged changes,
     and the completion report, then ask the human manager to run the signed
     commit.
     The agent must not weaken or bypass signing requirements in repository or
     test configuration just to complete the commit non-interactively.
   - In cross-repository work, apply this per repository:
     - prepare and complete the Smelterl repository commit first when
       `smelterl/` changed,
     - prepare and complete the `grisp_alloy` commit only when the superproject
       is actually being changed; that commit may batch multiple completed
       Smelterl commits when it only records a submodule-pointer sync.
   - MUST commit using the current commit-message file.
   - Example resolution:
     `COMMIT_MSG_FILE="$(git rev-parse --git-dir)/ALLOY_COMMIT_MSG"`
   - Example draft command (outcome-focused, no process-only bullets):
     `cat > "${COMMIT_MSG_FILE}" <<'EOF'
     feat(scope): short summary

     - key change 1
     - key change 2
     EOF`
   - Example commit command:
     `git commit -F "${COMMIT_MSG_FILE}"`
   - Mark task DONE in the current planning file.

13. Refine future planning items.
   - Review the current planning file and update relevant future tasks with
     implementation knowledge discovered in the completed task.
   - If the task uncovered deferred cleanup, compatibility debt, or
     documentation drift that is not fixed immediately, add it to planning
     explicitly as a refinement note or a new task; do not leave it only in
     chat, history, or changelog prose.
   - If the task or its review surfaced a durable workflow/process correction,
     update the owning repository workflow/agent/planning docs in the same
     overall task or record a linked follow-up task explicitly.
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
   - For cross-repository work, also include:
     - which repository task(s) were completed,
     - whether the Smelterl commit already exists,
     - whether a later `grisp_alloy` sync commit is still pending.

## Definition of Done (Per Task)

A task is DONE only if all are true:
- task marked `[x]` in the current planning file,
- context file exists and is fully updated,
- tests added/updated and passing,
- full relevant suites rerun after code changes,
- for touched Erlang code, Common Test passes and Dialyzer reports zero
  warnings,
- design docs updated when behavior/spec changed,
- current changelog updated when the task is changelog-relevant,
- current commit-message file prepared,
- when signed commits are required, the user has been asked to perform the
  signed commit after reviewing the prepared staged changes and commit message,
- planning refinement pass completed for future tasks (or explicitly `None`),
- completion report provided to human manager.

For linked cross-repository work, the overall user request is DONE only when:
- each touched repository task meets the definition of done in its own repo,
- the Smelterl commit exists before the `grisp_alloy` submodule-pointer commit,
- the `grisp_alloy` repository records the final `smelterl/` submodule commit.

For Smelterl-only development that intentionally defers superproject sync:
- the Smelterl task may be DONE in `smelterl/` without an immediate
  `grisp_alloy` task,
- the completion report must call out that a later batched `grisp_alloy`
  synchronization commit is still pending.

## Commit Quality Policy

- one task => one small self-contained commit whenever possible,
- every commit includes tests,
- if design changed, include code + docs + context rationale together,
- split oversized tasks before implementation.

## Quality Gates

Before finalizing a task:
- tests:
  - relevant unit/integration/golden/property suites pass,
  - for touched Erlang code, run the relevant Common Test suite and require it
    to pass,
- static checks:
  - run relevant linters and static analysis for touched components
    (for example `shellcheck` for touched shell scripts when available;
    prefer strict mode in CI, Dialyzer for Erlang modules when applicable),
  - for touched Erlang code, run Dialyzer and require zero warnings,
  - fix lint warnings by changing code/tests whenever feasible,
  - add lint-rule suppressions (`# shellcheck disable=...`, etc.) only as a
    last resort when no practical code change can preserve required behavior,
  - every suppression MUST include an inline reason comment explaining:
    - why the warning is triggered,
    - why the code is still correct/safe,
    - why an alternative fix is not suitable in this context,
  - never add suppressions just to silence warnings or make gates pass quickly,
- docs:
  - update design docs for approved design changes,
  - update the current changelog when the task is changelog-relevant,
- planning:
  - refine relevant future tasks in the current planning file based on
    discovered implementation constraints (or explicitly record `None` in task
    context),
  - codify durable workflow/process improvements in the owning repository docs
    instead of leaving them only in conversational feedback,
- commit preparation:
  - the current commit-message file exists, is non-empty, and reflects the
    current task,
  - example check:
    `test -s "$(git rev-parse --git-dir)/ALLOY_COMMIT_MSG"`,
- context history quality:
  - task id is present and matches the current planning file,
  - filename is prefixed with UTC timestamp for deterministic ordering,
  - context includes decisions/rationale and any task-specific validation or
    exception context that materially helps later review,
  - context and, when present, changelog describe final commit state (not
    implementation churn within the same task),
  - context excludes low-value noise (full terminal transcripts, duplicated diffs).

## Context History Signal/Noise Rules

Include (high signal):
- concise problem statement and expected behavior,
- before/after behavior and scope boundaries,
- key decisions with rationale and tradeoffs,
- design deltas with exact section references,
- task-specific validation findings, gaps, or risk-relevant focused coverage
  when they materially explain confidence or remaining uncertainty,
- residual risks and follow-up items.

Exclude (noise):
- full command logs/transcripts,
- copied large code blocks already in the repository,
- repetitive step-by-step notes without decisions or deviations,
- speculative alternatives that did not influence implementation.
- proposed commit messages (store ephemeral drafts in the current repository
  git dir instead).
- within-task rewrites described as change-chains (`A -> B -> C`) when only the
  final result matters.
- confirmations that standard required process steps occurred normally
  (for example: baseline ran, full suite ran, changelog updated) when those
  facts add no task-specific information.
- local workflow reminders or session-state notes that expire immediately
  after completion (for example: "signed commit still needs to be run",
  "changes are staged", "submodule bump still pending" when that fact is only
  relevant to the current release bookkeeping rather than the task's technical
  context).

Rule of thumb:
- if a detail does not help future review, regression investigation, or safe
  extension, leave it out.

## Task Context File Template (Mandatory)

Filename format is mandatory and must be sortable:
- `history/<YYYYMMDDTHHMMSSZ>__task-<task-id>__<short-description>.md` in the
  current repository
- Example:
  `history/20260301T154210Z__task-3.7__smelterl-capabilities.md`

Every context file using this format must contain at least:

1. `# Task <id>: <title>`
2. Metadata block
   - Date,
   - Author/Agent identifier,
   - Related task id (from the current planning file) and design anchors.
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
8. `## Validation Notes` (optional)
   - include only deviations from the standard validation process, task-specific
     focused coverage that explains the main risk, or meaningful verification
     gaps/limitations.
   - do not use this section to list the routine successful validation commands
     already required by the workflow.
   - omit this section entirely when validation followed the normal workflow
     and produced no task-specific insight worth carrying forward.
9. `## Design Changes`
   - `None` or approved changes + rationale + decision link/summary.
10. `## Residual Risks / Follow-ups`
    - only durable technical uncertainty, intentionally deferred engineering
      work, or future design/implementation follow-up.
    - do not use this section for local process reminders, commit/signing
      status, staging status, transient local signing friction, or temporary
      superproject bookkeeping.
11. `## Changed Artifacts`
    - concise list of touched files/areas by purpose.
12. `## Completion Summary`
    - concise handover for future agents/reviewers.
