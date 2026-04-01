# GRiSP Alloy - Smelterl Design

**Version:** 2.0 (Draft)  
**Status:** Design Document  
**Last Updated:** 2026-02-09

This document specifies the **smelterl** Erlang tool: its role, responsibilities, CLI, processes, and implementation. It is self-contained for the tool; data formats (nugget metadata, manifest) are defined in [Data Design](01_DATA_DESIGN.md). For overview and glossary see [Overview](00_OVERVIEW.md).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Responsibilities](#2-responsibilities)
3. [Commands](#3-commands)
4. [Processes](#4-processes)
5. [Implementation Details](#5-implementation-details)
6. [Appendix A - Examples of Generated Files](#appendix-a-examples-of-generated-files)
7. [Appendix B - Format and Documentation](#appendix-b-format-and-documentation)

---

## 1. Overview

### 1.1 Role

**smelterl** is an Erlang-based code generator that:

- Discovers and parses nugget repositories from a **motherlode** directory.
- Builds a validated multi-target SDK build plan (main target + auxiliary targets).
- Resolves dependencies, validates target trees, and computes deterministic topological order per target.
- Consolidates nugget configuration per target (config, exports, overrides, paths, computed, exec).
- Generates Buildroot integration files (BR2_EXTERNAL content: `external.desc`, `Config.in`, `external.mk`) and a merged defconfig.
- Generates a target-scoped build-context shell script (`alloy_context.sh`) with nugget paths, config, and hook lists for every target; firmware-time capabilities and SDK embedding metadata are emitted only for the main target context.
- Generates and optionally augments the SDK manifest (including auxiliary products and SDK outputs capability data).

The tool does **not** clone VCS repositories, create directories or symlinks, or run Buildroot. It only reads the motherlode (assumed already staged by the caller), performs resolution and validation, and writes the files specified via `--output-*` parameters.

### 1.2 Invocation Model

- **Entry point:** Single executable (escript): `smelterl` or `smelterl-{VERSION}`.
- **Primary flow:** `smelterl plan` (resolve+validate all targets) followed by one or more `smelterl generate` calls (one selected target per invocation).
- **Platform:** Pure Erlang (no NIFs, no port drivers); one escript runs on any host with a compatible Erlang/OTP version.

### 1.3 Inputs and Outputs (Summary)

| Input | Description |
|-------|-------------|
| `--motherlode` | Directory containing one subdirectory per nugget repository; each repo has a `.nuggets` registry and one or more `.nugget` files. |
| `--product` | Nugget identifier of the top-level (main product) nugget. Used by `plan`. |
| `--extra-config` | Optional key=value pairs accepted by `plan` only. Used at plan-time for config/defconfig resolution and stored for `generate` Config.in Kconfig declarations. **ALLOY_MOTHERLODE must not** be specified here; it is always added to Config.in by smelterl and is not defined in alloy_context.sh (see [§1.4](#14-alloy_motherlode)). |
| `--buildroot-legal` | Optional **repeatable** path to Buildroot `legal-info/`, allowed only on main-target `generate` (no `--auxiliary`). Use one occurrence per target legal tree to consolidate legal and manifest data in one main pass. |
| `--export-legal` | Optional output directory for full legal-info tree export. Path is **relative to the generated manifest** (the directory of the file written to `--output-manifest`). |
| `--include-sources` | Optional flag (main-target `generate` only) to include Buildroot/alloy source trees in legal export; valid only with `--export-legal` and `--output-manifest`. |
| `--log`, `--verbose`, `--debug` | Optional logging controls. `--verbose` and `--debug` are equivalent to `--log debug`. |

| Output | Description |
|--------|-------------|
| `--output-plan` | Full Erlang-term build plan (`plan` command). |
| `--output-plan-env` | Bash-friendly target summary (`plan` command, optional). |
| `--output-external-desc` | Buildroot external tree descriptor (name, description). |
| `--output-config-in` | Kconfig file sourcing nugget packages and declaring extra-config variables. |
| `--output-external-mk` | Top-level makefile including nugget package `.mk` files. |
| `--output-defconfig` | Merged defconfig from nugget fragments (with template substitution and auto-injected target-local wrapper hook entries). |
| `--output-context` | Shell script `alloy_context.sh` for the selected target. |
| `--output-manifest` | Path for `ALLOY_SDK_MANIFEST` output and export-root anchoring. Main-target generation only (no `--auxiliary`). |

### 1.4 ALLOY_MOTHERLODE

- **ALLOY_MOTHERLODE** is **always** considered an extra-config variable (resolving to `${ALLOY_MOTHERLODE}`) for **Config.in** generation and template substitution: smelterl always emits a Kconfig declaration for `ALLOY_MOTHERLODE` in the generated Config.in (so that Buildroot accepts it when passed as a make parameter). The caller **must not** pass `--extra-config ALLOY_MOTHERLODE=...`; ALLOY_MOTHERLODE is never taken from `--extra-config`. The caller is expected to set `ALLOY_MOTHERLODE` before sourcing alloy_context.sh.
- **ALLOY_MOTHERLODE is not defined in alloy_context.sh.** The generated context script assumes `ALLOY_MOTHERLODE` is already set by the environment (e.g. by the wrapper that sources the script). The script may assert that it is set (e.g. `: "${ALLOY_MOTHERLODE:?..."`) but must not assign it, so that no local path information is embedded.
- **Path resolution for config/exports:** All `{path, PathSpec}` entries in `config` and `exports` that refer to nugget resources (relative paths or `@nugget/path`) are resolved to a path **prefixed by the bash variable `${ALLOY_MOTHERLODE}`**-e.g. `"${ALLOY_MOTHERLODE}/<repo>/<nugget>/path"`-rather than a fully specified absolute filesystem path. This keeps the generated alloy_context.sh free of host-specific paths; at runtime, when `ALLOY_MOTHERLODE` is set, the path becomes absolute. Only PathSpec values that are already absolute (leading `/`) are emitted as-is.

---

## 2. Responsibilities

Each responsibility is implemented by one or more processes; the section reference points to the detailed process description.

| # | Responsibility | Summary | See |
|---|----------------|---------|-----|
| 1 | **Load motherlode** | Scan motherlode for repos; load `.nuggets` and `.nugget` files; merge hybrid metadata; build in-memory nugget set keyed by identifier. | [§4.1 Loading the Motherlode](#41-loading-the-motherlode) |
| 2 | **Construct target trees** | Build main target tree and auxiliary target trees (from `auxiliary_products`), resolving nugget constraints and detecting cycles. | [§4.2 Constructing Target Trees](#42-constructing-target-trees) |
| 3 | **Validate target trees** | Validate main and auxiliary trees (category rules, version/flavor constraints, shared-flavor consistency, scoped hooks). | [§4.3 Validating Target Trees](#43-validating-target-trees) |
| 4 | **Compute topological order** | Order nuggets by dependency graph (dependencies before dependents); stable, deterministic. | [§4.4 Topological Order](#44-topological-order) |
| 5 | **Apply overrides** | Apply nugget/auxiliary overrides and scoped config overrides in declaration order (last-wins for matching overrides). | [§4.5 Applying Overrides](#45-applying-overrides) |
| 6 | **Discover capabilities** | From overridden target trees, derive firmware variants/outputs/parameters and SDK outputs metadata. | [§4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters](#46-discovering-firmware-variants-selectable-outputs-and-parameters) |
| 7 | **Consolidate configuration** | Merge config/exports in topological order; resolve paths, computed, exec, flavor_map; produce global and per-nugget config per target. | [§4.7 Consolidating Nugget Configuration](#47-consolidating-nugget-configuration) |
| 8 | **Generate Buildroot files** | Emit `external.desc`, `Config.in`, `external.mk`, and render defconfig for the selected target from the plan-carried defconfig model. | [§4.8-§4.11](#48-generating-externaldesc) |
| 9 | **Generate alloy_context.sh** | Render selected-target context: metadata, config, scoped hook arrays, and sdk output metadata. Main-only sections add firmware capability and embedding/fs-priority arrays used by firmware and SDK packing. | [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh) |
| 10 | **Collect legal info** | Parse legal-info for selected target and merge into one final legal-info export tree. | [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export) |
| 11 | **Generate manifest** | Build main SDK manifest including auxiliary products, firmware capabilities, and sdk output metadata section. | [§4.14 Generating Manifest](#414-generating-manifest) |

---

## 3. Commands

**Generic CLI interface:** To keep the CLI generic and extensible, **option definitions** (the spec for each command’s options) are owned by the **command module** (e.g. `smelterl_cmd_generate`). The **entry point** and **smelterl_cli** only **parse** argv using the option spec provided by the selected command module; they do not define per-command options. Thus adding a new command does not require changing the entry point; implement a new command module that defines its options and implements the behaviour callbacks.

### 3.0 CLI parsing flow (overview)

Parsing is **two-phase** so that global options and help work **without** requiring a command (e.g. `smelterl --help` shows global usage; `smelterl generate --help` shows command-specific help).

1. **First pass (reduce / global parse)**  
   Parse argv with a **minimal global spec** that recognizes only `--help` and `--version`. From the remaining tokens, the **first non-option** is taken as the **command** (if any). So `smelterl --help` yields no command; `smelterl generate --auxiliary encrypted_initramfs` yields command `generate` and rest `["--auxiliary", "encrypted_initramfs", ...]`. The command name is **not** obtained from the handler; it is the key used to look up the handler in the **config map** (e.g. `Config#{command_modules}` is a map `#{plan => smelterl_cmd_plan, generate => smelterl_cmd_generate, ...}`). Config is built once by the entry point from application env; the CLI receives this map and does not read app env.

2. **Second pass (command parse, when a command was found)**  
   Look up the command module from the config map. Ask the handler for its **option spec** via `options_spec(Action)` (Action may be the command itself or a sub-action). Parse the **rest** of argv (everything after the command token) with that spec to produce the option map for the command.

3. **Dispatch after parsing**  
   - If **`--version`** was seen (first pass): print version and exit.  
   - If **`--help`** was seen and **no command**: print **global** help (usage, list of commands from config map keys) and exit.  
   - If **command** is present and **`--help`** was seen: call the handler’s **`help(Action)`** and exit.  
   - Otherwise: call **`Module:run(Action, ParsedOpts)`** with the option map from the second pass.

So the CLI never needs a “dummy” command for `smelterl --help`; the first pass is enough to detect global help and version, and the command map (from config) is the single place that defines which commands exist and which module handles each.

### 3.1 Global Options and Pseudo-Commands

- **`smelterl --version`**  
  Print smelterl version (from config) and exit. Detected in the first parse pass; no command required.

- **`smelterl --help`**  
  Print **global** usage (synopsis and list of commands from the config map) and exit. Works without a command; detected in the first parse pass. For command-specific help, use e.g. `smelterl generate --help` (dispatched to the command handler’s `help/1`).

### 3.2 Command `plan`

**Synopsis:**  
`smelterl plan [OPTIONS]`

**Purpose:** Load motherlode, resolve/validate main and auxiliary targets, and produce a deterministic build plan consumed by the orchestrator and later `generate` calls.

**Required parameters:**
- `--product` main product nugget identifier.
- `--motherlode` path to staged nugget repositories.
- `--output-plan` path for full Erlang-term build plan.

**Optional parameters:**
- `--extra-config KEY=VALUE` (repeatable; used during `plan` for config consolidation/defconfig-model inputs and stored in the plan for later `generate` rendering inputs such as Config.in declarations).
- `--output-plan-env` path for minimal bash-friendly output (`build_plan.env`).
- `--log` / `--verbose`.

**Outputs:**
- Full plan term containing per-target resolved trees, consolidated config, target metadata (`AuxId`, root nugget, constraints), and validation results.
- Main-target manifest seed data (precomputed deterministic manifest model used later by `generate`).
- Optional bash-friendly plan metadata for orchestrator loops.

### 3.3 Command `generate`

**Synopsis:**  
`smelterl generate [OPTIONS]`

**Purpose:** Deterministically generate artefacts for one selected target from a precomputed plan.

**Required parameters:**
- `--plan <PATH>` generated by `smelterl plan`.

**Optional target selector:**
- `--auxiliary <AUX_ID>` (select one auxiliary target).
- If `--auxiliary` is omitted, `generate` targets `main`.

**Common output parameters:**
- `--output-external-desc`
- `--output-config-in`
- `--output-external-mk`
- `--output-defconfig`
- `--output-context`

**Main-target legal parameters (only when `--auxiliary` is omitted):**
- `--buildroot-legal <PATH>` (repeatable)
- `--export-legal`
- `--include-sources`

**Manifest/output-root parameter (main target only):**
- `--output-manifest`

**Rules:**
- `generate` does not re-resolve dependencies; it consumes the plan exactly.
- Context output is target-scoped and exports `ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, and `ALLOY_AUXILIARY`.
- `generate` does not accept `--extra-config`; it uses extra-config values captured in the plan.
- Main-target manifest generation consumes plan-carried manifest seed data; `generate` only finalizes runtime/legal/path-dependent sections.
- Plan-carried extra-config values are literal substitutions (used during `plan` for defconfig model building and during `generate` for Config.in declarations); they are not the source of target identity variables.
- `plan` injects target-local wrapper scripts into each target defconfig model cumulative hook keys: `$(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-build.sh`, `post-image.sh`, and `post-fakeroot.sh`; `generate` only renders the selected target model.
- `--output-manifest`, `--export-legal`, `--buildroot-legal`, and `--include-sources` are valid **only** when generating the main target (i.e. without `--auxiliary`).
- `--buildroot-legal` is repeatable on the main target. Each occurrence points to one target’s `legal-info/` directory (main and/or auxiliaries) to be consolidated in a single legal/manifest pass.
- `--export-legal` and `--include-sources` require `--output-manifest` because export paths are rooted relative to the manifest location.

#### Examples

```bash
# 1) Plan all targets
smelterl plan \
  --product kontron-albl-imx8mm_vanilla \
  --motherlode "${BUILD_DIR}/motherlode" \
  --output-plan "${BUILD_DIR}/plan/build_plan.term" \
  --output-plan-env "${BUILD_DIR}/plan/build_plan.env"

# 2) Generate one auxiliary target
smelterl generate \
  --plan "${BUILD_DIR}/plan/build_plan.term" \
  --auxiliary encrypted_initramfs \
  --output-config-in "${BUILD_DIR}/targets/encrypted_initramfs/br2_external/Config.in" \
  --output-external-mk "${BUILD_DIR}/targets/encrypted_initramfs/br2_external/external.mk" \
  --output-defconfig "${BUILD_DIR}/targets/encrypted_initramfs/br2_external/configs/encrypted_initramfs_defconfig" \
  --output-context "${BUILD_DIR}/targets/encrypted_initramfs/alloy_context.sh"

# 3) Generate main target (+ manifest/legal)
smelterl generate \
  --plan "${BUILD_DIR}/plan/build_plan.term" \
  --output-context "${BUILD_DIR}/targets/main/alloy_context.sh" \
  --output-manifest "${BUILD_DIR}/staging/ALLOY_SDK_MANIFEST" \
  --buildroot-legal "${BUILD_DIR}/targets/encrypted_initramfs/workspace/legal-info" \
  --buildroot-legal "${BUILD_DIR}/targets/main/workspace/legal-info" \
  --export-legal "legal-info"
```

---

## Status Code

- **0** - Success. All requested operations completed; requested output files were written (or validate-only run completed without error).
- **Non-zero** - Error. The command failed (e.g. validation error, I/O error, missing product or motherlode).

A descriptive error message **must** be printed to **standard error** when the exit status is non-zero, so the caller can report or log the failure.

---

## 4. Processes

Processes are split across `smelterl plan` and `smelterl generate`:
- `plan` executes full motherlode loading, target discovery, validation, and per-target resolution.
- `generate` is deterministic target-scoped rendering from the selected plan entry (main or one auxiliary).

Unless otherwise stated, sections below describe the shared logic used by planning and by per-target generation.

### 4.0 Plan/Generate Execution Model

1. Run `plan` once for a given motherlode + main product.
2. Capture extra-config at plan time and persist plan artefacts (`build_plan.term`, optional `build_plan.env`), including plan-prepared render models (defconfig model and manifest seed).
3. For each selected target (`main` or one `AuxId`), run `generate --plan ... [--auxiliary <AuxId>]`.
4. On the main-target `generate` pass (no `--auxiliary`), optionally parse/export one merged legal-info tree from repeatable `--buildroot-legal` inputs (main and/or auxiliary legal directories), then generate `ALLOY_SDK_MANIFEST`.
5. Keep generation deterministic: no dependency resolution in `generate`.

### 4.1 Loading the Motherlode

**Purpose:** Build an in-memory set of all nuggets available from the motherlode, with merged metadata (registry defaults + per-nugget overrides).

**Inputs:**

- **Motherlode path:** filesystem path to the motherlode directory. Usualy from `--motherlode` parameter.

**Process (bullet steps):**

1. List direct subdirectories of the motherlode; each subdirectory is treated as one **nugget repository** (e.g. `builtin`, or a VCS repo name).
2. For each repository directory:
   - Look for a `.nuggets` file (registry). If missing, output a warning.
   - Parse the `.nuggets` file as an Erlang term; validate root format `{nugget_registry, Version, Fields}`; obtain optional `defaults` and required `nuggets` list (paths to `.nugget` files, relative to the registry) from `Fields`.
   - For each path in `nuggets`, resolve to an absolute path relative to the registry location and check that the file exists.
   - If the file doesn't exists output a clear error message describing the error.
   - Parse each `.nugget` file as an Erlang term; validate root format `{nugget, Version, Fields}`; extract the `id` field from `Fields`.
   - Merge metadata: apply `defaults` from the registry first, then overlay fields from the `.nugget` file (per-nugget wins). Result is the **effective metadata** for that nugget.
   - For each entry in `config` and `exports`, associate a **nugget identifier** (the nugget this entry was declared in). This metadata is initialized here and may be updated during config overrides ([§4.5](#45-applying-overrides)); it is used during config collection ([§4.7](#47-consolidating-nugget-configuration)) to resolve nugget-dependent information (e.g. paths relative to a nugget directory, exec scripts run in a nugget context).
   - Resolve `license_file` / `license_files` paths relative to the declaring file (registry or .nugget) and store for later use.
   - Add the nugget to the motherlode set, keyed by nugget identifier. If the same identifier appears in more than one repository, fail with an error describing the conflict.
3. For each repository path, **attach VCS info** when available: call `smelterl_vcs:info/1` with the repository path. That function returns `vcs_info()` (name, url, commit, describe, dirty) either from a **`.alloy_repo_info`** file (if present in the path or a parent directory, per [Data Design - Alloy repository info file](01_DATA_DESIGN.md#alloy-repository-info-file-alloy_repo_info)) or from a real VCS checkout (e.g. `.git`). The rest of the process is unchanged; manifest generation (§4.14) uses this info for the repositories section.
4. Result: a **motherlode** structure that maps nugget identifier to effective metadata and repository path (so that nugget directory and repo context are known for path resolution and VCS provenance), with VCS info attached per repo when available.

**Output:**

- **Motherlode:** Map or structure: `NuggetId -> {Metadata, RepoPath, NuggetDir}` (or equivalent). NuggetDir is the directory containing the `.nugget` file (used for relative paths in buildroot, hooks, config, etc.). Repository paths have VCS info when `smelterl_vcs:info/1` returned data (from `.alloy_repo_info` or from `.git`).
- **Used by:**
  - [§4.2 Constructing Target Trees](#42-constructing-target-trees)
  - [§4.3 Validating Target Trees](#43-validating-target-trees)
  - [§4.5 Applying Overrides](#45-applying-overrides)

Subsequent processes ([§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters) through [§4.14](#414-generating-manifest)) use the **overridden motherlode** from §4.5, not the original motherlode.

Nugget registry and metadata formats are in [Data Design](01_DATA_DESIGN.md) (Nugget Registry, Nugget Metadata). Erlang term file conventions in [Overview](00_OVERVIEW.md).

---

### 4.2 Constructing Target Trees

**Purpose:** Build the main target tree and auxiliary target trees with no cycles and no duplicated nugget nodes per target.

**Inputs:**

- **Motherlode** from [§4.1](#41-loading-the-motherlode).
- **Product identifier** from plan input (`--product` at plan time).

**Process:**

1. Build the main tree from the main product nugget.
2. Discover auxiliary target specs from `auxiliary_products` in the main effective tree.
3. Resolve each auxiliary target (`AuxId`, root nugget, optional constraints) to one **auxiliary-specific subtree** (rooted at the auxiliary root nugget).
4. For each tree build (main and auxiliary-specific), initialize with an empty load path and resolve dependencies recursively:
   - For the current nugget, read `depends_on` from metadata.
   - For each entry, consider only **nugget-type** constraints: `{Constraint, nugget, Spec}` (e.g. `required`, `optional`, `one_of`, `any_of`). Ignore `category` and `capability` entries for tree construction.
   - For each nugget dependency (after resolving `one_of`/`any_of` to a set of nuggets to load):
     - If the dependency is already on the **load path**, report a **circular dependency** and abort.
     - If the dependency is already in the **tree** (fully loaded), reuse that node (do not add a second copy).
     - Otherwise, load the dependency from the motherlode; if not found and constraint is `required` (or required by one_of/any_of), fail; if `optional` and missing, skip.
     - Add the dependency to the tree, then recurse into it with an updated load path.
   - When returning from recursion, pop the current nugget from the load path.
5. Build the **main backbone set** from the main tree:
   - Start from all nuggets in main with category `builder`, `toolchain`, `platform`, or `system`.
   - Add their transitive nugget dependencies from the main tree.
6. Compose each **effective auxiliary tree**:
   - Union the auxiliary-specific subtree with the main backbone set.
   - Reuse existing nodes when overlap exists (single node per nugget id in the target tree).
   - Keep dependency edges from both inputs; deduplicate identical edges.
7. For each nugget in each resulting target tree (main + effective auxiliaries), record the **ordered list of its nugget dependencies** (the order in which they appear in `depends_on`, considering only nugget-type constraints). This ordering abstract is part of the tree so that later topological sort can be deterministic without re-reading the motherlode.
8. Result: a set of target trees (main + effective auxiliaries), each with per-nugget dependency order metadata.

**Output:**

- **Target trees:** Set of target graphs keyed by target id (`main` and `AuxId` values), where auxiliary targets are **effective trees** (auxiliary-specific subtree merged with the main backbone), each with dependency edges and stable dependency order metadata.
- **Used by:**
  - [§4.3 Validating Target Trees](#43-validating-target-trees)

---

### 4.3 Validating Target Trees

**Purpose:** Validate main and auxiliary target trees (category/cardinality rules, constraints, scoped hooks, shared-flavor consistency).

**Inputs:**

- **Target trees** from [§4.2](#42-constructing-target-trees).
- **Motherlode** from [§4.1 Loading the Motherlode](#41-loading-the-motherlode) (for metadata and version/flavor checks).

**Process:**

1. **Main-tree cardinality (exactly one):**
   For each of `builder`, `toolchain`, `platform`, `system`, count nuggets in the tree with that category.  
   - If count is not 1, fail (0 or >1 for any of these categories is an error). Include which nuggets were found in the error message where useful.

   **Note:** Bootflow uniqueness is validated **per firmware variant** in [§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters).

2. **Auxiliary-tree restrictions (introduction check):**  
   Auxiliary **effective** trees inherit the main backbone from [§4.2](#42-constructing-target-trees).  
   The auxiliary-specific subtree must not introduce `builder`, `toolchain`, `platform`, `system`, or `bootflow`.

3. **Auxiliary id checks:**  
   `AuxId` values must be globally unique across all discovered auxiliary target declarations (from all nuggets in the main effective tree), and must not be `main` or `all`.

4. **Category dependencies:**  
   For every `depends_on` entry of type `category` (e.g. `{required, category, platform}`), check that the tree contains at least one nugget of that category (or exactly one for `one_of`). Fail if not satisfied.

5. **Capability dependencies:**  
   For every `depends_on` entry of type `capability` (e.g. `{required, capability, secure_boot}`), check that at least one nugget in the tree has `provides` containing that capability. Fail if not satisfied.

6. **Conflicts:**  
   For every `{conflicts_with, nugget, X}` ensure X is not in the tree. For every `{conflicts_with, capability, Y}` ensure no nugget provides Y. Fail if a conflict is present.

7. **Version constraints:**  
   For each nugget dependency that specifies a version (e.g. `{nugget_name, <<"~> 1.0">>}`), resolve the target nugget’s version from metadata and check semantic compatibility. If multiple dependents constrain the same nugget, all constraints must be satisfied. Fail if any version check fails.

8. **Flavor constraints:**  
   If a dependency specifies `{flavor, F}`, the target nugget must declare `F` in its `flavors` list. All dependencies on the same nugget must agree on flavor (or all omit). Fail on inconsistency.

9. **Shared-nugget flavor consistency:**  
   If one nugget appears in main and any auxiliary tree, resolved flavor must match (or both unspecified).

10. **Hook scope checks:**  
   Hook scope accepts `main | auxiliary | all | <AuxId>`. `<AuxId>` scopes must match declared auxiliary targets and are valid only for SDK-time hook types.

**Output:**

- **Validated target trees:** Same structure as input target set; on failure, abort with clear error and no file outputs.
- **Used by:**
  - [§4.4 Topological Order](#44-topological-order)
  - [§4.5 Applying Overrides](#45-applying-overrides)

---

### 4.4 Topological Order

**Purpose:** Compute a deterministic order of nuggets such that every dependency appears before its dependents; used for override application order, config merge, defconfig merge, hook/embed lists, and manifest.

**Inputs:**

- **Validated nugget tree** from [§4.3](#43-validating-target-trees). The tree includes both the graph (nodes and edges)
- **Motherlode** from [§4.1 Loading the Motherlode](#41-loading-the-motherlode) (for `depends_on` metadata).

**Process:**

1. Build a directed graph from the tree: edge from A to B if B depends on A (so B comes after A).
2. Perform a topological sort (e.g. DFS or Kahn). When multiple valid orderings exist, use the **per-nugget dependency order** (the ordering abstract in the tree) as the stable tie-break: when choosing the next node, prefer the one that appears earlier in the dependent’s declared dependency list. The tree therefore carries all information needed for a deterministic order; the motherlode is not required at this step.
3. Ensure the product (root) is last.

**Output:**

- **Topology order:** Ordered list of nugget identifiers (deterministic; dependencies before dependents; product last).
- **Used by:**
  - [§4.5 Applying Overrides](#45-applying-overrides)
  - [§4.7 Consolidating Nugget Configuration](#47-consolidating-nugget-configuration)
  - [§4.9 Generating Config.in](#49-generating-configin)
  - [§4.10 Generating external.mk](#410-generating-externalmk)
  - [§4.11 Generating defconfig](#411-generating-defconfig)
  - [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh)
  - [§4.14 Generating Manifest](#414-generating-manifest)

---

### 4.5 Applying Overrides

**Purpose:** Apply nugget, auxiliary-target, and config overrides declared in metadata so final target trees and per-target configuration inputs reflect effective replacements and overridden values before configuration consolidation.

**Inputs:**

- **Validated target trees** from [§4.3](#43-validating-target-trees).
- **Per-target topology orders** from [§4.4](#44-topological-order).
- **Motherlode** from [§4.1](#41-loading-the-motherlode).

**Process:**

1. Collect all `overrides` entries from the main effective tree in a deterministic order: main topology order, and within each nugget, metadata declaration order.
2. Apply auxiliary remaps first (`{auxiliary_product, TargetAuxId, ReplacementAuxId}`):
   - Validate that referenced `AuxId` values are declared and legal.
   - Update planned auxiliary target selection, then rebuild/refresh impacted auxiliary effective trees and their topology orders.
3. Apply nugget replacements (`{nugget, Target, Replacement}`) to each target tree where `Target` exists:
   - Validate `Replacement` is loadable from motherlode.
   - Validate replacement dependencies are already satisfiable in that tree at `Target`'s position (no new dependency introduction).
   - Validate replacement dependency constraints (version/flavor) against the current tree using the same semantic rules as [§4.3](#43-validating-target-trees).
   - Replace `Target` with `Replacement` at the same execution position; refresh affected topology order entries.
4. Apply config overrides in the collected order:
   - `{config, Key, Value}` applies to the current target tree (backward-compatible form).
   - `{config, Scope, Key, Value}` applies when selector matches (`Scope = main | all | AuxId`).
   - For each matching target tree: last matching write wins.
5. Config-override validation and in-place update (per matching target tree):
   - Overridden key must be declared by at least one nugget `config` entry in that tree.
   - Overridden key must not appear in any nugget `exports` entry in that tree.
   - Scoped `AuxId` must refer to a declared auxiliary target.
   - For every nugget that declares the overridden config key, update that config entry in place with:
     - overridden value,
     - associated origin nugget identifier set to the nugget that declared the override entry.
   - These updated per-nugget entries are then consumed by [§4.7](#47-consolidating-nugget-configuration), which performs target-local last-wins global collection.

**Output:**

- **Overridden target trees:** main + auxiliaries with auxiliary remaps and nugget replacements applied.
- **Overridden per-target topology orders:** recomputed where needed after replacement/remap impact.
- **Overridden per-target motherlode views:** nugget config entries carry effective overridden value plus associated origin nugget identifier, ready for [§4.7](#47-consolidating-nugget-configuration).
- **Used by:**
  - [§4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters](#46-discovering-firmware-variants-selectable-outputs-and-parameters)
  - [§4.7 Consolidating Nugget Configuration](#47-consolidating-nugget-configuration)
  - [§4.8 Generating external.desc](#48-generating-externaldesc)
  - [§4.9 Generating Config.in](#49-generating-configin)
  - [§4.10 Generating external.mk](#410-generating-externalmk)
  - [§4.11 Generating defconfig](#411-generating-defconfig)
  - [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh)
  - [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export)
  - [§4.14 Generating Manifest](#414-generating-manifest)

---

### 4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters

**Purpose:** Derive build-time metadata from overridden target trees:
- firmware variants, selectable firmware outputs, firmware parameters (**main target tree only**),
- sdk_outputs declarations (per target, especially auxiliaries).

**Inputs:**

- **Overridden target trees** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden per-target topology orders** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides) (for nugget metadata: `firmware_variant`, `firmware_outputs`, and `firmware_parameters`).

**Process:**

1. **firmware_variants (main target only):** For each nugget in the **main target tree** (in topology order), check if it declares a `firmware_variant` metadata field. If present, it is a list of variant atoms. Collect the union of all declared variant atoms into an ordered set (preserving first-occurrence order from topology). **After collection, ensure `plain` is present:** if no nugget declared the `plain` variant, prepend it to the list - `plain` is the default variant and is always available.

   **Validation:**
   - Each variant atom within a single nugget's list must be unique.
   - The same variant atom MAY appear in multiple nuggets' lists (those nuggets all participate in that variant).
   - **Bootflow coverage:** For each discovered variant V, there MUST be exactly one nugget of category `bootflow` that participates in V (i.e. its `firmware_variant` list includes V). This ensures the SDK has a single, well-defined firmware assembly orchestrator per variant.
2. **selectable_outputs (main target only):** For each nugget in the **main target tree** (in topology order), read its `firmware_outputs` metadata. For each output entry, collect the output ID, its `selectable` flag (default `false`), its `default` flag (default `true`, only meaningful when `selectable` is `true`), display name, and description. Build an ordered list of output records from entries where `selectable` is `true`. **Validation:** Output IDs must be unique across the entire main tree; duplicate output IDs are an error. See [Data Design - Firmware Outputs Metadata](01_DATA_DESIGN.md#firmware-outputs-metadata).
3. **firmware_parameters (main target only):** For each nugget in the **main target tree** (in topology order), read its `firmware_parameters` metadata. For each parameter entry `{ParamId, Fields}`:
   - If `ParamId` has not been seen before: add it to the ordered list with its fields.
   - If `ParamId` was already declared by a previous nugget: merge the fields using the cross-nugget merge rules:
     - **`type`** must match. If the new nugget declares a different type, emit an error: `"Parameter '<ParamId>' declared as '<Type1>' in '<Nugget1>' but as '<Type2>' in '<Nugget2>'"`.
     - **`required`** - OR semantics: if either declaration has `{required, true}`, the merged result is required.
     - **`default`** - if both declarations specify a default, the values must match. Conflicting defaults are an error: `"Parameter '<ParamId>' has conflicting defaults: '<Default1>' in '<Nugget1>' vs '<Default2>' in '<Nugget2>'"`. If only one specifies a default, that default is used.
     - **`name`** - first non-empty value wins (from topological order).
     - **`description`** - first non-empty value wins (from topological order).
   - **Validation:** `ParamId` must follow the identifier format (`[a-z][a-z0-9_]*`). `type` must be one of `string`, `integer`, `boolean`. If `default` is specified, it must be compatible with `type`. See [Data Design - Firmware Parameters Metadata](01_DATA_DESIGN.md#firmware-parameters-metadata).

4. **SDK outputs (all targets):** For each target tree (`main` and each `AuxId`), collect `sdk_outputs` metadata records. Validate uniqueness of `OutputId` within each target. Preserve mapping `TargetId -> OutputId -> DeclaringNugget`.

**Output:**

- **Target discovery set:** structure containing:
  - Main-target firmware capabilities (`firmware_variants`, `variant_nuggets`, `selectable_outputs`, `firmware_parameters`).
  - Per-target sdk output declarations (`sdk_outputs_by_target`).
  - Auxiliary target metadata needed for context and manifest (`AuxId`, root nugget, resolved constraints).
- Consumed by:
  - The alloy_context.sh generator for:
    - In **main context only**:
      - `ALLOY_FIRMWARE_VARIANTS` array (the ordered variant names).
      - Variant-specific firmware-time hook arrays: `ALLOY_PRE_FIRMWARE_HOOKS_<VARIANT>`, `ALLOY_FIRMWARE_BUILD_HOOKS_<VARIANT>`, `ALLOY_POST_FIRMWARE_HOOKS_<VARIANT>` (see [§4.12](#412-generating-alloy_contextsh)).
      - `ALLOY_FIRMWARE_OUTPUTS` ID array and `ALLOY_FIRMWARE_OUT_<ID>_*` per-output metadata variables (including `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT`).
      - `ALLOY_OUTPUT_SELECTABLE` array (all selectable output identifiers; the orchestrator reads `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` per entry to determine the default selection).
      - `ALLOY_FIRMWARE_PARAMETERS` ID array and `ALLOY_FIRMWARE_PARAM_<ID>_*` per-parameter metadata variables.
    - In **all target contexts**:
      - Target-local `ALLOY_SDK_OUTPUTS` and per-output metadata variables.
- The manifest generator for `capabilities` (firmware-only), `sdk_outputs` (separate section), and `auxiliary_products`.
- **Used by:**
  - [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh) (for ALLOY_FIRMWARE_VARIANTS, per-variant hook arrays, ALLOY_FIRMWARE_OUTPUTS + per-output variables, ALLOY_OUTPUT_SELECTABLE, ALLOY_FIRMWARE_PARAMETERS + per-parameter variables)
  - [§4.14 Generating Manifest](#414-generating-manifest) (for the `capabilities` section with firmware fields and the separate `sdk_outputs` section)

---

### 4.7 Consolidating Nugget Configuration

**Purpose:** Produce a single consolidated configuration set from the nugget tree `config` and `exports`, with paths, computed, exec, and flavor_map resolved. Config overrides are already applied in [§4.5](#45-applying-overrides); consolidation collects per-nugget config and uses last-wins to build the global set.

**Inputs:**

- **Overridden tree** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden topology order** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides) (for nugget dirs and metadata, with config overrides applied in place).
- **Extra configuration** from plan (`--extra-config` captured by `plan`; used only for substitution and extra environment for scripts).

**Process:**

Consolidation runs in **three phases** so that computed values can reference already-resolved keys and exec scripts see a full environment. The tree is traversed **once** in topological order; entries that need deferred processing are appended to ordered lists (preserving topological order), then those lists are processed in phase 2 and 3.

**Phase 1 - Single pass over the tree (topological order):** For each nugget in overridden topology order, process its `config` entries in metadata order, then its `exports` entries in metadata order. Each entry carries its **associated nugget identifier** (set in [§4.1](#41-loading-the-motherlode), updated when overridden in [§4.5](#45-applying-overrides)). For each key, maintain a **per-nugget** slot and a **global** slot (last-wins for `config`; exports must not be duplicated). **Export exclusivity check:** when processing an export, fail if the key already appears in any nugget's `config`; when processing a config entry, fail if the key has already been exported by another nugget. See [Key conflict rules](01_DATA_DESIGN.md#key-conflict-rules). For each entry:

- **Plain value, path, or flavor_map:** Resolve immediately.
  - For **path**: use the entry's associated nugget identifier to resolve relative paths and `@nugget_id/path` (nugget dir from motherlode). Paths that refer to nugget resources are expressed as `"${ALLOY_MOTHERLODE}/<nugget_relative_path>/..."` (not host-absolute). Relative -> `"${ALLOY_MOTHERLODE}/<nugget_relative_path>/PathSpec"`; `@nugget_id/path` -> same for referenced nugget; absolute (leading `/`) -> as-is. Store the resolved value.
  - For **flavor_map**: select the branch using the nugget's resolved flavor; replace with the selected value and store.
- **Computed** `{computed, Template}`: Do not resolve yet. Append to a **computed list** an item containing all information needed to process it later: nugget identifier, config vs export and key. Order in the list follows topological order (nugget order x entry order).
- **Exec** `{exec, ScriptPath}`: Do not run yet. Append to an **exec list** an item containing: nugget identifier, config vs export, and key. Order in the list follows topological order.

**Phase 2 - Process computed list:** Iterate over the computed list in order. For each item, replace every `[[KEY]]` in the template with the already-resolved value of KEY (from merged config and plan-carried extra-config). Unresolved key are errors. Store the result in the per-nugget and global slots so later computed/exec can reference it.

**Phase 3 - Process exec list:** Iterate over the exec list in order. For each item, run the script (path relative to the nugget that originated the value, it may have been overriden) with config key as first argument; environment contains all already-resolved `ALLOY_CONFIG_*` and `ALLOY_NUGGET_*_CONFIG_*` (and optionally plan-carried extra-config). Stdout (trimmed) is the value; exit code must be 0. Store result. Scripts must not rely on unresolved configuration.

**Output:**

- **Consolidated config:** Paths, computed, exec, and flavor_map are resolved; overrides applied.
  - (1) per-nugget map `NuggetId -> [{Key, Value}]`
  - (2) global map `Key-> Value` (last-wins)
- **Used by:**
  - [§4.11 Generating defconfig](#411-generating-defconfig)
  - [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh)
  - [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export)
  - [§4.14 Generating Manifest](#414-generating-manifest)

[Data Design](01_DATA_DESIGN.md) Config Consolidation, Nugget Configuration Metadata; path resolution and value types are specified there.

#### Well-Known Export Keys

Certain export keys have conventional meaning across the system. `smelterl` reads them from the consolidated config during manifest and context generation. Nugget authors providing these keys should follow the documented types and semantics.

| Export Key | Type | Provided By | Purpose |
|------------|------|-------------|---------|
| `target_arch` | atom | Platform or toolchain nugget | Short architecture identifier (e.g. `arm`, `aarch64`, `riscv64`). Used in context (`ALLOY_CONFIG_TARGET_ARCH`). |
| `target_arch_triplet` | string (binary) | Platform or toolchain nugget | Full GNU target triplet (e.g. `<<"arm-buildroot-linux-gnueabihf">>`). **Required** - `smelterl` writes this value to the SDK manifest's `target_arch` field (see [§4.14](#414-generating-manifest)). If absent from the consolidated config, manifest generation fails with a validation error. Also used in context (`ALLOY_CONFIG_TARGET_ARCH_TRIPLET`) and propagated to the project manifest's `target_arch` field. |

> **Design note:** These keys are standard exports, not special metadata fields. They follow the same export exclusivity rules as all other exports: exactly one nugget in the tree may export each key. Typically the platform nugget exports both, but a standalone toolchain nugget could do so instead. The convention is intentionally minimal - only keys that `smelterl` or the orchestrator consumes for manifest/context generation are listed here. Other useful exports (e.g. `sysroot`, `device_tree`) are nugget-specific and do not need a system-level convention.

---

### 4.8 Generating external.desc

**Purpose:** Emit the Buildroot external tree descriptor (name and description).

**Inputs:**

- **External.desc template:** used for the Buildroot external tree descriptor (name and desc layout).
- **Overridden tree** from [§4.5 Applying Overrides](#45-applying-overrides) (for product metadata).
- **Product identifier** from the loaded plan (main target metadata).
- **Open output:** An open file or output stream provided by the caller (e.g. a file opened for the path given by `--output-external-desc`, or standard output when the option is `-`). The process writes to this output and does not open or close it; the caller thus decides whether the content goes to a file or to stdout without the process being affected. If the caller did not request this artefact, the process is not invoked.

**Process:**

1. Use the **external.desc template** so that comments and headers are defined in the template rather than in code; generic comments or headers can be added without touching the code.
2. **name:** Product identifier, converted to uppercase (e.g. `acme_app` -> `ACME_APP`). Buildroot uses this to define `BR2_EXTERNAL_<NAME>_PATH`; generated files should use `$(BR2_EXTERNAL)` for relocatability.
3. **desc:** Product nugget’s `description` field; optionally append ` - Version <version>` if `version` is present.
4. Render the template with the name and desc values; write the result to the **open output** provided by the caller. The output must be exactly two lines in Buildroot external.desc format: `name: VALUE` and `desc: VALUE` (the template defines layout and any leading comments).

**Output:**

- **external.desc content:** Two lines (name, desc) in Buildroot format. Written to the open output provided by the caller (file or stdout).
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.1](#a1-example-externaldesc).

---

### 4.9 Generating Config.in

**Purpose:** Generate Kconfig that declares extra-config variables and sources all nugget package Config.in files.

**Inputs:**

- **Config.in template:** used for Kconfig extra-config declarations and source lines.
- **Overridden topology order** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides) (nugget dirs and `buildroot` metadata).
- **Extra-config keys** from plan (`--extra-config` captured by `plan`; keys only, values are not embedded in Config.in).
- **Open output:** An open file or output stream provided by the caller (e.g. path from `--output-config-in`, or stdout when `-`). The process writes to it and does not open or close it; the caller decides file vs stdout. If the caller did not request this artefact, the process is not invoked.

**Process:**

1. Use the **Config.in template** so that comments and layout are defined in the template rather than in code. Build the data needed for the template: extra-config keys (including ALLOY_MOTHERLODE first; see [§1.4](#14-alloy_motherlode)), and an ordered list of source entries (per nugget in topology order, then per package with a `Config.in`: path and nugget name for comments). Each Kconfig block is: `config VAR_NAME`, `string`, `option env="VAR_NAME"` so Buildroot accepts these when passed as make parameters.
2. For each nugget in topology order: read `buildroot` metadata; if `{packages, Path}` is present, resolve Path relative to nugget directory; list package subdirectories that have a `Config.in`; add each as a source entry with motherlode-relative path and nugget name. Order within a nugget can be deterministic (e.g. alphabetical by package name).
3. Render the **Config.in template** with the extra-config keys and source list; write the result to the **open output** provided by the caller.

**Output:**

- **Config.in content:** Kconfig source (extra-config declarations plus source lines for nugget packages). Written to the open output provided by the caller (file or stdout).
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.2](#a2-example-configin).

---

### 4.10 Generating external.mk

**Purpose:** Generate the top-level makefile that includes each nugget’s package `.mk` files.

**Inputs:**

- **External.mk template:** used for the top-level makefile include layout.
- **Overridden topology order** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides) (nugget dirs and `buildroot` metadata).
- **Open output:** An open file or output stream provided by the caller (e.g. path from `--output-external-mk`, or stdout when `-`). The process writes to it and does not open or close it; the caller decides file vs stdout. If the caller did not request this artefact, the process is not invoked.

**Process:**

1. Use the **external.mk template** so that comments and layout are defined in the template rather than in code. Build the data for the template: an ordered list of include entries (per nugget in topology order, then per package: path to the `.mk` file using motherlode-relative convention, and nugget name for comments). Paths must use the same motherlode-relative convention as Config.in so that the same ALLOY_MOTHERLODE can be set at build time.
2. For each nugget in topology order: resolve `{packages, Path}`; list package subdirectories; for each package, find the `.mk` file (typically `PACKAGE_NAME.mk`) and add an entry with `include $(ALLOY_MOTHERLODE)/.../PACKAGE_NAME.mk` and nugget name.
3. Render the **external.mk template** with the include list; write the result to the **open output** provided by the caller.

**Output:**

- **external.mk content:** Top-level makefile including nugget package `.mk` files. Written to the open output provided by the caller (file or stdout).
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.3](#a3-example-externalmk).

---

### 4.11 Generating defconfig

**Purpose:** Build a deterministic merged defconfig model from all nuggets (plan-time) and render it for one selected target (generate-time). The set of **cumulative Buildroot keys** is defined in a list under **priv** (e.g. `priv/defconfig-keys.spec` as an Erlang term file). That list is generated (e.g. from Buildroot documentation or inspection) and stored in the tool as configuration. Each entry specifies the key name and whether values are **paths**: path values are converted from relative (to the nugget) to `"${ALLOY_MOTHERLODE}/<nugget_relative_path>/<specified_value>"`, where `<nugget_relative_path>` is the path from the motherlode root to the nugget directory (e.g. `repo/nugget_dir`); absolute values are kept as-is.

**Inputs:**

- **Defconfig key spec:** list of cumulative Buildroot keys (key name + whether values are paths).
- **Overridden topology order** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides) (nugget dir, metadata for defconfig_fragment and flavor).
- **Consolidated config** (global and per-nugget) from [§4.7 Consolidating Nugget Configuration](#47-consolidating-nugget-configuration) for `[[ALLOY_CONFIG_*]]` substitution.
- **Extra-config** from plan (`--extra-config` captured by `plan`; e.g. `ALLOY_BUILD_DIR`, `ALLOY_CACHE_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_MOTHERLODE`).
- **Selected target identifier** from the loaded plan (`main` or `AuxId`), used for deterministic wrapper script injection.
- **Defconfig template:** used for the merged defconfig layout (header, regular/cumulative key lines, hook entries).
- **Open output:** An open file or output stream provided by the caller (e.g. path from `--output-defconfig`, or stdout when `-`). The process writes to it and does not open or close it; the caller decides file vs stdout. If the caller did not request this artefact, the process is not invoked.

**Process:**

1. **Plan-time merge:** For each nugget in topology order:
   - Resolve defconfig fragment path: if metadata has `defconfig_fragment` as a path, use it; if `{flavor_map, [...]}`, select path by nugget’s resolved flavor. Load fragment content.
   - Substitute all `[[KEY]]` markers in the fragment (keys and values) with: consolidated config (ALLOY_CONFIG_*), plan-carried extra-config (ALLOY_*), product metadata (ALLOY_PRODUCT*, etc.). The replacement is **literal**: whatever string was passed as the value for KEY during `plan` (e.g. via `--extra-config 'ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}'`) is written into the defconfig unchanged. So passing a value like `${ALLOY_CACHE_DIR}` (using single quotes when invoking smelterl so the shell does not expand it) causes the generated defconfig to contain that variable reference, which is then expanded from the environment when the defconfig is used at runtime. Single-pass, non-recursive; unresolved marker are errors.
   - Parse the fragment using buildroot defconfig format.
   - Classify each line: **regular** key (last-wins) or **cumulative** key (from the key spec). For cumulative keys, collect values; for regular, keep last value.
2. **Plan-time cumulative keys:** Accumulate values from all nuggets, then one line per key using the key spec (key name + whether values are paths). For each value that is a **path** (per that list): if relative, resolve to `"${ALLOY_MOTHERLODE}/<nugget_relative_path>/<specified_value>"`; if absolute, keep. For non-path cumulative values, use as-is. Concatenate all resolved values with space.
3. **Plan-time regular keys:** Keep one line per key; last value wins. Optionally keep source nugget info for comments and diagnostics.
4. **Target wrapper hook entries:** Append target-local wrapper scripts to cumulative hook keys:
   - `BR2_ROOTFS_POST_BUILD_SCRIPT += $(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-build.sh`
   - `BR2_ROOTFS_POST_IMAGE_SCRIPT += $(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-image.sh`
   - `BR2_ROOTFS_POST_FAKEROOT_SCRIPT += $(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-fakeroot.sh`
5. **Generate-time render:** Use the **defconfig template** for layout so header comments and section structure are template-defined. Read the selected target’s precomputed defconfig model from the plan, render the template, and write to the **open output** provided by the caller.

**Output:**

- **defconfig content:** Merged defconfig from nugget fragments (with substitution and auto-injected target-local wrapper hook entries). Written to the open output provided by the caller (file or stdout).
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.4](#a4-example-defconfig).

---

### 4.12 Generating alloy_context.sh

**Purpose:** Produce a **selected-target** shell context (`alloy_context.sh`) that exports target metadata, consolidated config, hook arrays, and sdk output metadata. Main context additionally carries firmware capability and embedding/fs-priority arrays; auxiliary contexts do not.

**Inputs:**

- **Selected target** from `generate` selector (`main` or one `AuxId`).
- **Target topology order** from [§4.5](#45-applying-overrides).
- **Target consolidated config** from [§4.7](#47-consolidating-nugget-configuration).
- **Overridden motherlode** from [§4.5](#45-applying-overrides).
- **Target capabilities** from [§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters).
- **Alloy context template:** used for the context script (exports, arrays, helpers).
- **Open output:** An open file or output stream provided by the caller (e.g. path from `--output-context`, or stdout when `-`). The process writes to it and does not open or close it; the caller decides file vs stdout. If the caller did not request this artefact, the process is not invoked.

**Process:**

1. Use the **alloy context template** with placeholders for selected-target data: target/product metadata, nugget metadata, per-nugget and global config, nugget order, hook arrays, sdk outputs metadata, and (for main only) embed/fs-priority arrays plus firmware capability variables. Comments and layout stay in the template so formatting changes do not require Erlang code changes.
2. Export target identity and product metadata variables:
   - `ALLOY_PRODUCT=<target_id>`
   - `ALLOY_IS_AUXILIARY=true|false`
   - `ALLOY_AUXILIARY=<AuxId|empty>`
   - `ALLOY_PRODUCT_NAME`, `ALLOY_PRODUCT_DESC`, `ALLOY_PRODUCT_VERSION`.
3. Export selected-target nugget/config metadata:
   - Per nugget: `ALLOY_NUGGET_<NAME>`, `_DIR`, `_NAME`, `_DESC`, `_VERSION`, `_FLAVOR`, and per-key `ALLOY_NUGGET_<NAME>_CONFIG_<KEY>`.
   - Global config: `ALLOY_CONFIG_<KEY>`.
4. Build non-exported orchestration arrays for the selected target:
   - `ALLOY_NUGGET_ORDER` from selected-target topology order.
   - SDK-time hook arrays (`ALLOY_PRE_BUILD_HOOKS`, `ALLOY_POST_BUILD_HOOKS`, `ALLOY_POST_IMAGE_HOOKS`, `ALLOY_POST_FAKEROOT_HOOKS`) with scope filtering (`main | auxiliary | all | <AuxId>`):
     - `main` only in main context.
     - `auxiliary` in all auxiliary contexts.
     - `<AuxId>` only in that auxiliary context.
     - `all` in every context.
   - Firmware-time hook arrays are generated **only in main context** and are variant-specific: `ALLOY_PRE_FIRMWARE_HOOKS_<VARIANT>`, `ALLOY_FIRMWARE_BUILD_HOOKS_<VARIANT>`, `ALLOY_POST_FIRMWARE_HOOKS_<VARIANT>`.
     - Variants come from [§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters) (no hardcoded list).
     - For each variant, include hooks from variant-less nuggets plus nuggets declaring that variant, in topological order.
     - Hook ordering is strictly topological; there is no special-case bootflow ordering beyond dependency constraints.
   - These orchestration arrays are defined for the process that sources `alloy_context.sh` and are not exported to child hook processes.
5. Build embedding arrays **only in main context**:
   - `ALLOY_EMBED_IMAGES`, `ALLOY_EMBED_HOST`, `ALLOY_EMBED_NUGGETS` from main-target metadata.
   - Apply auto-embed into `ALLOY_EMBED_NUGGETS`: firmware-time hook scripts (`pre_firmware`, `firmware_build`, `post_firmware`) and `fs_priorities` files.
   - Deduplicate combined embed entries (same nugget + same path emitted once).
   - Auxiliary contexts do not emit `ALLOY_EMBED_*`; auxiliary artefact transfer uses `sdk_outputs`.
6. Build filesystem-priority metadata **only in main context**:
   - Per-nugget variables when present: `ALLOY_NUGGET_<NAME>_FS_PRIORITIES`.
   - `ALLOY_FS_PRIORITIES_FRAGMENTS` with entries `<NUGGET_IDENTIFIER>:<RESOLVED_PATH>` in topological order.
   - Auxiliary contexts do not emit `ALLOY_FS_PRIORITIES_FRAGMENTS`.
7. Emit exported firmware capability variables **only in main context**:
   - `ALLOY_FIRMWARE_VARIANTS`.
   - `ALLOY_FIRMWARE_OUTPUTS` plus per-output `ALLOY_FIRMWARE_OUT_<ID>_*`.
   - `ALLOY_OUTPUT_SELECTABLE`.
   - `ALLOY_FIRMWARE_PARAMETERS` plus per-parameter `ALLOY_FIRMWARE_PARAM_<ID>_*`.
8. Emit sdk output metadata:
   - Target-declared sdk outputs for the selected target in both main and auxiliary contexts:
     - `ALLOY_SDK_OUTPUTS` (ordered output-id array),
     - per-output metadata variables `ALLOY_SDK_OUTPUT_<ID>_NAME` and `ALLOY_SDK_OUTPUT_<ID>_DESCRIPTION`.
   - Main-context consumption variables prepared by orchestrator after auxiliary builds (e.g. `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` and optional unique alias) in main context only; these are available to both SDK-time and firmware-time consumers when the main context is sourced.
9. Emit helper functions for stable access without manual variable-name construction:
   - `alloy_nugget_dir`, `alloy_nugget_name`, `alloy_nugget_desc`, `alloy_nugget_version`, `alloy_nugget_flavor`, `alloy_config`, and sdk lookup helpers expected by alloy.
10. Do not define runtime mode variables from plan-carried extra-config in the script (`ALLOY_BUILD_DIR`, `ALLOY_CACHE_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_MOTHERLODE`, etc. are caller-supplied at runtime).
11. Write the rendered script to the output stream.

**Output:**

- **alloy_context.sh content:** Rendered shell script (product/nugget metadata, config, nugget order, hook arrays, sdk output metadata, helpers; with embed/fs-priority/firmware capability sections only in main context). Written to the open output provided by the caller (file or stdout).
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.5](#a5-example-alloy_contextsh).

**References:** [Data Design](01_DATA_DESIGN.md) Environment Variables and Functions.


---

### 4.13 Collecting Legal Info and Export

**Purpose:** On the main-target generate pass, parse legal-info for one or more targets and export a single merged legal-info tree (no per-target subtrees in final SDK export).

**Inputs:**

- **Selected target id:** `main` (this process is main-pass only).
- **Buildroot legal directories:** zero or more target-local `legal-info/` paths from repeatable `--buildroot-legal` (main and/or auxiliaries).
- **Export root path:** the root directory from which relative paths are derived; from the directory of the file written to `--output-manifest`.
- **Export legal path:** the relative path from the export root. From `--export-legal` when that option is set.
- **Include sources flag:** whether to include Buildroot sources/ and host-sources/ and alloy-sources/ in the export. From `--include-sources`.
- **Selected target tree** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Overridden motherlode** from [§4.5 Applying Overrides](#45-applying-overrides).
- **Consolidated config** from [§4.7 Consolidating Nugget Configuration](#47-consolidating-nugget-configuration) (for scripts environment).
- **Extra-config** from plan (`--extra-config` captured by `plan`) for scripts environment.
- **Legal README template:** used for merged top-level legal README (when export is performed).

**Process:**

Export produces one merged legal-info tree. Behavior depends on whether parsed Buildroot legal-info inputs are present: with inputs, merge Buildroot + alloy legal data; without inputs, export alloy legal data only.

1. For each provided `--buildroot-legal` path, parse Buildroot legal files (`manifest.csv`, `host-manifest.csv`) and keep package/source/license metadata for merge.
2. Resolve the export directory from `--output-manifest` parent + `--export-legal` (relative path). Fail if the final export directory already exists, to prevent mixing incompatible legal datasets across runs.
3. Build merged Buildroot legal content (when Buildroot legal inputs are present):
   - merge `manifest.csv` and `host-manifest.csv` package records across targets (deduplicated, deterministic),
   - merge/copy `licenses/` and `host-licenses/`,
   - when `--include-sources` is set, merge/copy `sources/` and `host-sources/`.
4. Generate `alloy-manifest.csv` from nugget and external component metadata (name, version, license, license path, source path when included). Paths in this file are relative to the legal export root.
5. Create `alloy-licenses/` and copy nugget/external-component license files into deterministic per-component directories (for example `<NAME>-<VERSION>/...`), keeping manifest paths relative to export root.
6. If `--include-sources` is set, create `alloy-sources/` and export nugget/external sources. Resolve external component source fields (`source_dir`, `source_archive`) at export time:
   - **plain path / computed:** resolve using the same config+extra-config inputs and `[[KEY]]` substitution model as [§4.7](#47-consolidating-nugget-configuration),
   - **exec:** run the referenced script (relative to nugget dir) with consolidated config and plan extra-config in the script environment; trimmed stdout is the raw result,
   - **final path concretization:** evaluate variable references in the raw result against the smelterl runtime environment to obtain a concrete filesystem path required for copy/archive operations.
7. Generate merged `legal-info/README` from the legal README template:
   - include Buildroot README content when Buildroot inputs were provided, preserving each input README block as-is (main and auxiliaries) in deterministic target order,
   - do not drop per-target Buildroot warnings; warnings from each input README remain visible in the merged top-level README under that target's section,
   - include alloy-specific section describing `alloy-manifest.csv`, `alloy-licenses/`, and optional `alloy-sources/`,
   - describe that the export is a single merged tree (main + auxiliaries), without per-target legal subtrees.
8. Generate `legal-info.sha256` for exported files using the Buildroot-compatible checksum format.
9. Do not keep per-target legal README/files in final SDK export; temporary per-target intermediates are allowed during merge but must not leak into final output.

**Output:**

- **Parsed target legal-info:** package list + Buildroot version for each provided `--buildroot-legal` path.
- **Merged export tree:** single `legal-info/` tree with merged package/source/license content and one top-level README.
- **Used by:** [§4.14 Generating Manifest](#414-generating-manifest) (Buildroot package list and paths when `--buildroot-legal` was used); Caller (export tree when `--export-legal` is set).
- **Examples:** alloy-manifest.csv [Appendix A.7](#a7-example-alloy-manifestcsv); README [Appendix A.8](#a8-example-legal-export-readme).

---

### 4.14 Generating Manifest

**Purpose:** Build the main ALLOY_SDK_MANIFEST including auxiliary products, firmware capabilities, sdk output metadata section, and merged legal-info-derived package/license data.

**Inputs:**

- **Main target** id/metadata/tree/topology/config from [§4.5](#45-applying-overrides) and [§4.7](#47-consolidating-nugget-configuration).
- **Auxiliary target metadata** from plan (`AuxId`, root nugget, resolved constraints).
- **Capabilities/discovery output** from [§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters): main-target firmware capabilities and per-target `sdk_outputs` declarations.
- **Merged legal-info data** from [§4.13](#413-collecting-legal-info-and-export).
- **Smelterl build-info:** Self-contained structure (name, relpath, repo as vcs_info) for the smelterl source; produced at escript build time by the build script. Used to add the generator repository to the manifest and to set `build_environment.smelterl_repository`.
- Optional: **Buildroot package list**, **Buildroot version** (from legal-info host-manifest `buildroot` row), and license paths from [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export) when `--buildroot-legal` is set.
- Optional: **Export dir** so manifest paths are relative to manifest file location (e.g. relative to export legal dir).
- **Open output:** An open file or output stream provided by the caller (e.g. path from `--output-manifest`, or stdout when `-`). The process writes to it and does not open or close it; the caller decides file vs stdout. If the caller did not request this artefact, the process is not invoked.

**Process:**

Manifest generation is split into two stages so plan-time deterministic computation is testable independently from generate-time runtime/legal/path-dependent finalization.

### 4.14.A Plan-stage: Build manifest seed (run by `plan`)

This stage prepares and stores a deterministic manifest seed in `build_plan.term` (no I/O-path-specific relativization, no Buildroot legal merge, no integrity hash yet):

1. **Product static metadata and target architecture:**
   - Read main product id and metadata (`name`, `description`, `version`) from the main target inputs.
   - Read well-known export key `target_arch_triplet` from consolidated config (see [Well-Known Export Keys](#well-known-export-keys)); fail validation if absent.
   - Store as seed fields (`product`, `product_name`, `product_description`, `product_version`, `target_arch`).
2. **Repository index and deduplication:**
   - Seed repository set with Smelterl generator repository from build-info (`repo`), including optional `path_in_repo` from `build_info.relpath`.
   - Traverse nuggets in main topology and collect supplying repository identities when present (nuggets from non-repository directories have no `RepoId`).
   - Deduplicate repositories by canonical URL/path; if a nugget repository equals the Smelterl repository, reuse that entry.
   - Assign stable `RepoId` atoms with collision-safe suffixing (`name`, `name2`, `name3`, ...).
   - Store:
     - ordered `repositories` seed entries (`name`, `url`, `commit`, `describe`, `dirty`, optional `path_in_repo`),
     - nugget-id -> optional `RepoId` mapping,
     - Smelterl repository `RepoId` for later `build_environment.smelterl_repository`.
3. **Nuggets seed:**
   - Iterate nuggets in overridden main topology order.
   - For each nugget, prepare nugget fields (`version`, optional `repository`, `category`, optional `flavor`, optional `provides`, `license`, `license_files` source paths).
   - Validate that every referenced repository id exists in the seed `repositories`.
4. **Auxiliary products seed:**
   - Prepare `auxiliary_products` seed entries from planned auxiliary metadata (`AuxId`, root nugget, resolved version/flavor/constraint summary per schema).
5. **Firmware capabilities seed:**
   - Copy main-target firmware capabilities from [§4.6](#46-discovering-firmware-variants-selectable-outputs-and-parameters):
     - `firmware_variants`, `selectable_outputs`, `firmware_parameters`.
6. **SDK outputs seed:**
   - Prepare top-level `sdk_outputs` seed entries from per-target sdk output declarations discovered in [§4.6] (mapping `TargetId -> OutputId -> metadata`).
7. **External components seed:**
   - Collect `external_components` declarations from nugget metadata.
   - Prepare component entries with version/license/license_files source paths and optional display fields.
   - Validate uniqueness of component ids (conflicting duplicates are errors).
8. **Persist seed into plan:**
   - Store the resulting manifest seed as part of plan output for main-target manifest finalization in `generate`.

### 4.14.B Generate-stage: Finalize manifest from plan seed (run by `generate` on main target)

This stage consumes plan seed + generate-time inputs and writes `ALLOY_SDK_MANIFEST`:

1. **Load main manifest seed from plan** and validate seed shape/version compatibility.
2. **Build environment runtime fields:**
   - Capture `host_os`, `host_arch`, and `smelterl_version` (from application metadata/runtime).
   - Set `smelterl_repository` from seed repository id.
   - If Buildroot version is available from legal parsing (`host-manifest` `buildroot` row), set `buildroot_version`.
   - Compute `build_date` as ISO 8601 UTC timestamp.
3. **Relativize path-bearing seed fields to manifest base path:**
   - For nuggets: `license_files`.
   - For external components: `license_files`.
   - Base path is derived from `--output-manifest` location.
4. **Add Buildroot package sections (optional):**
   - When parsed legal data is available from [§4.13](#413-collecting-legal-info-and-export), emit `buildroot_packages` and `buildroot_host_packages`.
   - Relativize package license paths to manifest base.
   - If unavailable, omit (or emit empty lists where allowed by [Data Design](01_DATA_DESIGN.md)).
5. **Assemble full manifest term in section order** per [Data Design](01_DATA_DESIGN.md) (product/build, build_environment, repositories, nuggets, auxiliary_products, capabilities, sdk_outputs, optional Buildroot package sections, external_components).
6. **Integrity:**
   - Build manifest term in memory without `integrity`.
   - Canonicalize using `basic_term_canon` and compute SHA-256 hex digest.
   - Add `integrity` with `{digest_algorithm, sha256}`, `{canonical_form, basic_term_canon}`, `{digest, HexHash}`.
7. **Serialization and write:**
   - Serialize as Erlang term file per [Overview](00_OVERVIEW.md) conventions (UTF-8, one term, period-terminated).
   - Write to the open output stream supplied by caller.

**Output:**

- **ALLOY_SDK_MANIFEST content:** Erlang term file including auxiliary products, firmware capabilities, and top-level `sdk_outputs`, with Buildroot/legal-derived package and license path data when provided.
- **Used by:** Caller only (receives content via the stream it provided).
- **Example:** See [Appendix A.6](#a6-example-alloy_sdk_manifest).

[Data Design](01_DATA_DESIGN.md) Manifest Specification (root format, sections, repositories, nuggets, auxiliary products, capabilities, sdk_outputs, buildroot packages, external components, integrity).

---

## 5. Implementation Details

### 5.1 Project Structure

The smelterl application lives under a single root directory with the following layout. **Application env** (e.g. `command_modules`, version) is read **only in smelterl**; smelterl builds a config map from it and passes (argv, Config) to smelterl_cli, which does not read app env (see [§5.7.2](#572-smelterl-entry-point) and [§5.7.3](#573-smelterl_cli)).

```
smelterl/
├── rebar.config
├── src/
│   ├── smelterl.app.src          # Application metadata; version; env (e.g. command_modules)
│   ├── smelterl.erl              # Escript entry point: gather app env into config, call smelterl_cli(argv, Config)
│   ├── smelterl_cli.erl          # CLI: receives (argv, Config); parses and dispatches to command modules
│   ├── smelterl_command.erl      # Behaviour for command modules (run/2, help/2, actions/0)
│   ├── smelterl_cmd_plan.erl     # plan command handler
│   ├── smelterl_cmd_generate.erl # generate command handler
│   ├── smelterl_plan.erl         # Build-plan construction and serialization
│   ├── smelterl_motherlode.erl   # Load motherlode
│   ├── smelterl_tree.erl         # Build target trees from product + motherlode (§4.2)
│   ├── smelterl_topology.erl     # Topological sort from dependency graph (§4.4)
│   ├── smelterl_validate.erl     # Validate tree: category, capability, version/flavor (§4.3)
│   ├── smelterl_overrides.erl    # Apply nugget and config overrides (§4.5)
│   ├── smelterl_config.erl       # Consolidate config/exports; paths, computed, exec, flavor_map
│   ├── smelterl_script.erl       # Script execution and variable resolution from environment
│   ├── smelterl_gen_external_desc.erl  # external.desc via smelterl_template
│   ├── smelterl_gen_external_mk.erl    # external.mk via smelterl_template
│   ├── smelterl_gen_config_in.erl      # Config.in via smelterl_template
│   ├── smelterl_gen_defconfig.erl      # Merged defconfig via smelterl_template (substitute + template)
│   ├── smelterl_gen_context.erl        # alloy_context.sh via smelterl_template
│   ├── smelterl_gen_manifest.erl       # Manifest term build and write
│   ├── smelterl_legal.erl      # Parse BR legal-info; export legal tree; README via smelterl_template
│   ├── smelterl_template.erl     # [[KEY]] substitution + template engine (Mustache)
│   ├── smelterl_file.erl         # Files, directories and path manipulation utilities
│   ├── smelterl_vcs.erl          # VCS utility functions (commit, describe, dirty)
│   └── smelterl_log.erl          # Logging / stderr
├── scripts/
│   └── generate_build_info.escript   # Build-time script: writes priv/build_info.term (see below)
└── priv/
    ├── defconfig-keys.spec             # List of cumulative key in defconfig fragments, with value type expectation
    ├── build_info.term                 # VCS info of smelterl source; generated by scripts/generate_build_info.escript
    └── templates/
        ├── external.desc.mustache      # Buildroot external tree descriptor
        ├── Config.in.mustache          # Kconfig extra-config and source lines
        ├── external.mk.mustache        # Top-level makefile include lines
        ├── defconfig.mustache          # Merged defconfig layout
        ├── alloy_context.sh.mustache   # Context script layout
        └── README.mustache             # Legal-info export README
```

**build-info.term** is generated at build time and contains smelterl source repository VCS state into. The build must run **scripts/generate_build_info.escript** during the escript packaging so that `priv/build_info.term` exists and is included in the escript. 

**scripts/** is the standard place for build and helper scripts. Scripts here are not part of the compiled application but are run during the build or by developers.

The script’s requirements are specified in [§5.7.1 Build-time script: generate_build_info](#571-build-time-script-generate_build_info).

**Build output:** Escript built as `_build/default/bin/smelterl`

---

### 5.2 General Principles

- **Self-contained escript:** The smelterl escript must be self-contained: it embeds its dependencies (including **erts** and the **priv** directory where Mustache templates are defined) so that a single executable can be distributed and run without requiring a separate Erlang installation or unpacked release.
- **Input/output:** All inputs come from CLI options and the filesystem (motherlode). All outputs are written only to paths specified by the relevant options (`--output-*` and `--export-legal`).
- **Error handling:** On validation or I/O error, report a clear message to stderr and exit with non-zero status. No partial writes for the same run (either all requested outputs are written or none).
- **Encoding:** All Erlang term files (including generated manifest) follow the [Overview](00_OVERVIEW.md): UTF-8, binaries for strings, one term per file, period at end.
- **Templating:** Use **Mustache** for all processes that generate text files: external.desc, Config.in, external.mk, defconfig, alloy_context.sh, README. Templates live in `priv/templates/` and receive a data structure (keys, source list, nugget list, config maps, etc.). They may also receive extra information used to generate better comments and headers-e.g. nugget identifier and name, product name and version, smelterl version, etc. Comments, headers, and layout are defined in the templates so that changes do not require Erlang code edits. The manifest is serialized as an Erlang term (not Mustache).
- **Plan-first generators:** For file-generation modules, split logic into two layers: (1) compute a deterministic Erlang term/map representing the output content (suitable for persistence in `build_plan.term`), and (2) render/write that term to text. `plan` should run the compute layer; `generate` should only select plan data and render it.
- **Testability:** Keep modules as pure as possible: functions take explicit inputs (motherlode map, tree, topology, config map) and return content or updated state. Functions that write output data take an open output (e.g. file descriptor or IO device) as an argument so that output can be sent to a file or to stdout as needed.
- **Determinism:** Topological order and merge order (config, defconfig) must be deterministic for the same inputs so that builds are reproducible.

---

### 5.3 Documentation

The project follows systematic documentation guidelines so that APIs and behaviour are clear and tooling (IDE, ExDoc, `code:get_doc/1`, `h/1`) can use them. For a full example module illustrating all of the below, see [Appendix B - Format and Documentation](#appendix-b-format-and-documentation).

- **Erlang inline documentation:** Use the [Erlang system documentation](https://www.erlang.org/doc/system/documentation.html) attributes. Every module must have **`-moduledoc`** describing its purpose and usage. Every **exported function** must have a **`-doc`** attribute (short description; add details or examples if needed). Document user-defined types and behaviour callbacks with `-doc` as well. Prefer Markdown format (default); use a short first paragraph for the entity, then detail.
- **SPDX license headers:** Every source and script file must include an [SPDX short-form license identifier](https://spdx.dev/learn/handling-license-info/) in a comment at the top (e.g. `%% SPDX-License-Identifier: Apache-2.0` for Erlang, or the appropriate comment style for escripts). This ensures license information is machine-readable and stays with the file.
- **REUSE compliance:** The project must pass the [REUSE](https://reuse.software/) compliance check (`reuse lint`). REUSE builds on SPDX and requires copyright and licensing information in each file; passing `reuse lint` confirms the repo is machine-readable and unambiguous for licensing.
- **Consistency:** Keep `-spec` and `-doc` in sync with behaviour; when changing a function’s contract, update both.

---

### 5.4 Testing

The project uses a test-first, disciplined testing approach so that behaviour is well covered and regressions are caught early.

- **Test-first:** Write tests before or alongside implementation; tests define the expected behaviour.
- **Coverage:** Every Erlang module has a corresponding test module (e.g. `smelterl_config` -> `smelterl_config_tests`) under a `test/`. All exported behaviour that can be tested in isolation should have tests.
- **Common Test with eunit assertions:** Use **Common Test** as the test framework. Use **eunit assertions** (e.g. `?assertEqual(Expected, Actual)`, `?assertMatch(Pattern, Expr)`) within test cases so that failures are clear and local.
- **Custom assertions:** Define **custom assertion helpers** (e.g. macros or functions that wrap `?assertEqual` / `?assertMatch` with domain-specific checks) when they simplify the expressiveness of the core tests; use them in test cases so that intent is clear and failures remain local.
- **Local helper functions:** Each test suite should define **simple local helper functions** (e.g. to build minimal motherlode, build a small tree, build a config map) and use them inside test cases. This keeps individual tests short and readable and avoids duplication.
- **Mocking:** When a module depends on external resources (filesystem, VCS, subprocesses) or other modules that are hard to exercise in a test, use **meck** to mock the dependency. Mock only what is necessary; prefer pure functions and explicit inputs so that most code can be tested without mocks.
- **Dialyzer:** The project must pass **Dialyzer** checks without warnings. Run Dialyzer (e.g. `rebar3 dialyzer`) and fix or suppress only with justified `-dialyzer` attributes; the default is zero warnings.

---

### 5.5 Build

**Compiling:**

```
rebar3 compile
```

**Produce self-contained escript:**

```
rebar3 escriptize
```

The escript output is be `_build/default/bin/smelterl`.

**Notes:**
- **Default profile dependencies:** 
  - **mustache** - for rendering Mustache templates (external.desc, Config.in, external.mk, defconfig, alloy_context.sh, README); see §4.8-§4.11 and §5.7 generator modules.
- **Test profile defpendencies:**
  - **meck** - for mockups in unit tests.
- **Self-contained escript:** rebar3 **must** be configured so that the generated escript **includes ERTS** and the **priv directory** (templates, defconfig-keys.spec, and the generated `build_info.term`). - - **generate_build_info.escript:** The build **must** invoke **scripts/generate_build_info.escript** during **compile** and **escriptiz** commands so that `priv/build_info.term` is created (or updated). Use a rebar3 hook that runs the script from the project root and writes into `priv/build_info.term`.

---

### 5.6 Shared Data Structures

This section defines the **implementation** representation of all data structures passed between modules. It is the **reference for input and output types** of the modules described in §5.7: every function that takes or returns one of these structures must use the types defined here. Data formats (nugget metadata, manifest on disk) are specified in [Data Design](01_DATA_DESIGN.md); this section specifies how the implementation models them in Erlang.

The following types use Erlang `-type` and `-spec` notation. All shared data type specifications are defined in the **smelterl** module (`smelterl.erl`); other modules reference these types for their function specs. The implementation may use records, maps, or proplists as long as the effective shape matches these definitions.

#### 5.6.1 Identifiers and primitives

```erlang
-type alloy_id()          :: atom(). % [a-z][a-z0-9_]*

%% Semantic ID aliases - all share the alloy_id() format.
-type nugget_id()         :: alloy_id().
-type component_id()      :: alloy_id().
-type repo_id()           :: alloy_id().
-type config_key()        :: alloy_id().

%% Domain-specific identifiers - same format, distinct semantics.
-type capability()        :: atom(). % [a-z][a-z0-9_]*
-type flavor()            :: atom(). % [a-z][a-z0-9_]*
-type variant()           :: atom(). % [a-z][a-z0-9_]*

-type category()          :: builder | toolchain | platform | system | bootflow | feature.
-type file_path()         :: binary().
-type version()           :: binary().
-type config_value()      :: binary() | integer() | atom() | path_value() | compute_value() | exec_value().
-type path_value()        :: {path, file_path()}.
-type compute_value()     :: {compute, Template :: binary()}.
-type exec_value()        :: {exec, ScriptPath :: file_path()}.
-type flavor_map_value()  :: {flavor_map, [{flavor(), config_value()}]}.
```

**Notes:**
- `alloy_id()` is the single canonical format for atom identifiers - `[a-z][a-z0-9_]*` per [Data Design](01_DATA_DESIGN.md); this keeps generated env vars and shell usage safe. Semantic ID aliases (`nugget_id()`, `component_id()`, `repo_id()`, `config_key()`) are provided for readability.
- `capability()`, `flavor()`, and `variant()` share the same format but are defined as their own types because they carry distinct domain semantics (a capability is not interchangeable with a flavor or variant).
- `config_value()`: plain (binary/atom/integer) is used as-is.
- `path_value()` is resolved to absolute using the declaring nugget’s dir.
- `compute_value()` has `[[KEY]]` replaced from consolidated config and extra config.
- `exec_value()` runs script with config in env, stdout is value.
- `flavor_map_value()` is resolved by selecting the branch for the nugget’s flavor.

#### 5.6.2 Motherlode

Produced by §4.1 (smelterl_motherlode). Input to §4.2, §4.3, §4.5.

```erlang
-type config_entry()      :: {config_key(), config_value(), DeclaringNugget :: nugget_id()}.
-type export_entry()      :: {config_key(), config_value()}.
-type override_scope()    :: main | all | nugget_id(). % nugget_id used as AuxId selector
-type override_spec()     :: {config, config_key(), config_value()}
                           | {config, override_scope(), config_key(), config_value()}
                           | {nugget, Target :: nugget_id(), Replacement :: nugget_id()}
                           | {auxiliary_product, TargetAuxId :: nugget_id(), ReplacementAuxId :: nugget_id()}.
-type constraint_type()   :: required | optional | one_of | any_of | conflicts_with.
-type constraint_kind() :: nugget | category | capability.
-type constraint_value_property() :: {version, version()} | {flavor, flavor()}.
-type constraint_value()  :: {nugget_id(), [constraint_value_property()]}.
-type depends_on_constraint() :: {constraint_type(), constraint_kind(), term()}.
-type defconfig_fragment_spec() :: file_path() | {flavor_map, [{flavor(), file_path()}]}.
-type buildroot_spec()    :: {defconfig_fragment, defconfig_fragment_spec()}
                           | {packages, file_path()}.
-type hook_type()         :: pre_build | post_build | post_image | post_fakeroot | pre_firmware | firmware_build | post_firmware.
-type hook_scope()        :: main | auxiliary | all | nugget_id(). % nugget_id used as AuxId selector
-type hook_spec()         :: {hook_type(), file_path(), hook_scope()}.
-type embed_source_type() :: images | host | nugget.
-type embed_spec()        :: {embed_source_type(), file_path()}.
-type value_source()      :: registry | nugget.

-type auxiliary_constraint_prop() :: {version, version()} | {flavor, flavor()}.
-type auxiliary_target_spec() :: {AuxId :: nugget_id(), RootNugget :: nugget_id(), [auxiliary_constraint_prop()]}.

-type firmware_output_spec() :: #{
    id                    := alloy_id(),
    selectable            => boolean(),
    default               => boolean(),
    display_name          => binary(),
    description           => binary()
}.

-type sdk_output_spec() :: #{
    id                    := alloy_id(),
    display_name          => binary(),
    description           => binary()
}.

-type param_type() :: string | integer | boolean.

-type firmware_parameter_spec() :: #{
    id                    := alloy_id(),
    type                  := param_type(),
    name                  => binary(),
    description           => binary(),
    required              => boolean(),          %% default false
    default               => binary() | integer() | boolean()
}.

-type external_component_spec() :: #{
    id                    := component_id(),
    name                  => binary(),
    description           => binary(),
    version               => binary(),
    license               => binary(),
    license_files         => [file_path()],
    source_dir            => binary() | path_value() | compute_value() | exec_value(),
    source_archive        => binary() | path_value() | compute_value() | exec_value(),
}.

-type nugget() :: #{
    id                    := nugget_id(),
    version               => binary(),
    name                  => binary(),
    description           => binary(),
    category              := category(),
    flavors               => [flavor()],
    provides              => [capability()],
    depends_on            => [depends_on_constraint()],
    auxiliary_products    => [auxiliary_target_spec()],
    config                => [config_entry()],
    exports               => [config_entry()],
    overrides             => [override_spec()],
    buildroot             => [buildroot_spec()],
    hooks                 => [hook_spec()],
    embed                 => [embed_spec()],
    firmware_variant      => [variant()],
    firmware_outputs      => [firmware_output_spec()],
    sdk_outputs           => [sdk_output_spec()],
    firmware_parameters   => [firmware_parameter_spec()],
    fs_priorities         => file_path(),
    license               => {value_source(), binary()},
    license_files         => {value_source(), [file_path()]},
    author                => {value_source(), binary()},
    maintainer            => {value_source(), binary()},
    homepage              => {value_source(), binary()},
    security_contact      => {value_source(), binary()},
    external_components   => [external_component_spec()],
    repo_path             := file_path(),
    nugget_relpath        := file_path(),
    repository            => repo_id()
}.

% VCS repository information (commit, describe, dirty); from smelterl_vcs or generate_build_info.
-type vcs_info() :: #{
    name     := binary(),
    url      := binary(),
    commit   := binary(),
    describe := binary(),
    dirty    := boolean()
}.

% Motherlode: map of nugget_id -> nugget; map of repo_id -> vcs_info for repositories.
-type motherlode() :: #{
    nuggets       := #{nugget_id() => nugget()},
    repositories  := #{repo_id() => vcs_info()}
}.
```

**Notes:**
- **Config declaring nugget:** The third element of `config_entry()` is the nugget that declared the key. When resolving path values, use that nugget's directory as the base. It is set to the declaring nugget at load time and can change when the config value is overridden by another nugget.
- **SBOM fields and value_source:** Fields that can have defaults from the registry and overriden in the nugget metadata have a source marker: `{value_source(), Value}`; `registry` means the value came from the `.nuggets` defaults block; `nugget` means it came from the `.nugget` file (or overrode a registry default). For path resolution of path-bearing fields (e.g. `license_files`), if the source is `registry`, resolve paths relative to `repo_path` (directory containing `.nuggets`); if `nugget`, resolve relative to `repo_path` joined with `nugget_relpath`.

#### 5.6.3 Nugget tree and topology

Built by §4.2 (smelterl_tree). The tree is represented by a **root** (the product nugget) and **edges**: for each nugget, the **ordered** list of its direct nugget dependencies, in the same order as in that nugget’s `depends_on` metadata. After §4.5 the same shape is used with replacement nuggets swapped in (overridden tree). Used by §4.6-§4.14.

```erlang
-type nugget_topology_order() :: [nugget_id()].

-type nugget_tree() :: #{
    root  := nugget_id(),
    edges := #{ nugget_id() => [nugget_id()] }
}.
```

**Notes:**
- Preserve the **order** of each nugget’s direct dependencies when building `edges` (same order as in `depends_on`); that order is the tie-breaker for a stable, deterministic topological sort (§4.4).

#### 5.6.4 Build plan and targets

Produced by `smelterl plan`. Consumed by `smelterl generate`.

```erlang
-type target_kind() :: main | auxiliary.

-type defconfig_model() :: #{
    regular    := [{binary(), binary()}],
    cumulative := [{binary(), binary()}]
}.

-type build_target() :: #{
    id            := nugget_id(), % main or AuxId
    kind          := target_kind(),
    aux_root      => nugget_id(),
    tree          := nugget_tree(),
    topology      := nugget_topology_order(),
    config        := config(),
    defconfig     := defconfig_model(),
    capabilities  := map()
}.

-type manifest_seed() :: #{
    product            := nugget_id(),
    target_arch        := binary(),
    product_fields     := map(),                 % name/description/version
    repositories       := [{repo_id(), map()}],  % deduplicated repository entries
    nugget_repo_map    := #{nugget_id() => repo_id() | undefined},
    nuggets            := [map()],               % nugget entries before base-path relativization
    auxiliary_products := [map()],
    capabilities       := map(),                 % firmware-only capabilities section
    sdk_outputs        := [map()],               % top-level sdk_outputs section entries
    external_components := [map()],              % component entries before base-path relativization
    smelterl_repository := repo_id()
}.

-type build_plan() :: #{
    product        := nugget_id(),
    targets        := #{nugget_id() => build_target()},
    auxiliary_ids  := [nugget_id()],
    manifest_seed  := manifest_seed()            % main-target seed prepared at plan-time
}.
```

**Notes:**
- `defconfig` in each target is a precomputed render model built during `plan` (including auto-injected target-local wrapper hook entries). `generate` renders this model and writes the selected target defconfig file.
- `manifest_seed` is a precomputed main-target manifest model built during `plan`. `generate` finalizes it with runtime/buildroot-legal/path-dependent data and writes `ALLOY_SDK_MANIFEST`.

#### 5.6.5 Firmware capabilities and sdk output declarations

Output of §4.6. Contains firmware variants, variant-to-nugget mapping, selectable outputs, firmware parameters, and per-target `sdk_outputs` declarations. Used by §4.12 (ALLOY_FIRMWARE_VARIANTS, per-variant hook arrays, ALLOY_FIRMWARE_OUTPUTS and per-output ALLOY_FIRMWARE_OUT_<ID>_* variables, ALLOY_OUTPUT_SELECTABLE, ALLOY_FIRMWARE_PARAMETERS and per-parameter ALLOY_FIRMWARE_PARAM_<ID>_* variables) and §4.14 (`capabilities` section for firmware fields, and top-level `sdk_outputs` section for sdk output declarations).

```erlang
-type firmware_capabilities() :: #{
    firmware_variants    := [variant()],        %% ordered variant atoms; plain always present
    variant_nuggets      := #{variant() => [nugget_id()]},  %% which nuggets per variant
    selectable_outputs   := [firmware_output_spec()],   %% output records with selectable=true (id, default, name, description)
    firmware_parameters  := [firmware_parameter_spec()],  %% merged params from all nuggets
    sdk_outputs_by_target := #{nugget_id() => [sdk_output_spec()]}
}.
```

**Notes:**
- `firmware_variants` always contains `plain` (prepended if not declared by any nugget).
- `variant_nuggets` maps each variant atom to the list of nuggets that declare it via `firmware_variant` metadata.
- `selectable_outputs` contains the full output records for outputs with `selectable=true`; each record carries `id`, `default`, `display_name`, and `description`. Used to generate `ALLOY_FIRMWARE_OUT_<ID>_*` variables including `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT`. The orchestrator reads `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` at runtime to determine the default selection - no separate default list is generated.
- `firmware_parameters` contains the merged, deduplicated parameter declarations. Each entry is a `firmware_parameter_spec()` with fields resolved by the cross-nugget merge rules (see [Data Design - Firmware Parameters Metadata](01_DATA_DESIGN.md#firmware-parameters-metadata)). Order is first-occurrence from topological order.
- `sdk_outputs_by_target` maps target id (`main` or `AuxId`) to declared `sdk_outputs` for that target.

#### 5.6.6 Consolidated configuration and extra config

Output of §4.7 (smelterl_config). Both consolidated and extra config use the same map shape: key = full environment variable name (binary), value = `{Kind, NuggetId, Value}`. **Kind** identifies the source; **NuggetId** is set only for per-nugget entries; **Value** is the resolved string. Path values use `"${ALLOY_MOTHERLODE}/<nugget_relpath>/path"` unless absolute. The caller is responsible for injecting `ALLOY_MOTHERLODE` into ExtraConfig before calling smelterl_config:consolidate/4 so it is available in templates and exec.

```erlang
-type config_entry_kind() :: extra   % caller-supplied
                           | nugget  % from nugget metadata
                           | global. % from nugget metadata; last-win in topological order
-type config_entry() :: {config_entry_kind(), nugget_id() | undefined, Value :: binary()}.
-type config() :: #{ binary() => config_entry() }.
```

**Notes:**
- **Unified shape:** Consolidated config (output of §4.7) contains entries with kind `nugget` or `global`; `nugget` entries have the declaring nugget as second element, `global` entries have `undefined`. Extra config contains only kind `extra` with `undefined` as second element. When merging for context or exec, the result is one `config()` with all three kinds.
- **Context generator:** Group by kind and second element. Emit in order: (1) for each nugget in `nugget_topology_order()`, emit all entries with kind `nugget` and that nugget_id (e.g. sorted by key); (2) emit all entries with kind `global` sorted by key; extra config keys are not emmited.
- **Templating and exec env:** Use only the third element (resolved value) when substituting or building the exec environment.
- Resolved values are strings/binaries. Path values that refer to nugget resources must be stored as `"${ALLOY_MOTHERLODE}/<nugget_relpath>/path"` so generated files stay relocatable; only originally absolute paths remain as-is.
- **ALLOY_MOTHERLODE:** Smelterl always injects it as `ALLOY_MOTHERLODE="${ALLOY_MOTHERLODE}"` so it is available in templates; the caller cannot override it with extra config parameter.

#### 5.6.7 Parsed Buildroot legal-info

When `--buildroot-legal` is set: parsed from Buildroot manifest.csv and host-manifest.csv. Paths relative to legal-info dir.

```erlang
-type br_package_entry() :: #{
    name          := binary(),
    version       := binary(),
    license       := binary(),
    license_files := [file_path()]
}.

-type br_legal_info() :: #{
    path              := file_path(), % Absolute path buildroot legal-info directory
    br_version        := binary(),
    packages          := [br_package_entry()],
    host_packages     := [br_package_entry()]
}.
```

**Notes:**
- All paths in `license_files` are relative to the legal-info directory.

#### 5.6.8 Smelterl build-info

Read from `priv/build_info.term`. Input to §4.14.

**Self-contained:** Smelterl build-info carries the VCS info for the smelterl source repository in a single structure. It contains a [vcs_info()](#562-motherlode) under `repo` plus `name` (e.g. the generator name) and `relpath` (path of the smelterl app within the repo, or `<<>>` if at repository root). §4.14 uses this value to create and add the generator as a repository entry to the manifest.

```erlang
-type smelterl_build_info() :: #{
    name     := binary(),
    relpath  := binary(), % <<>> if in the root of the repository
    repo     := vcs_info()
}.
```

**Notes:**
- Written at escript build time by `scripts/generate_build_info.escript`; read at runtime by manifest generation (§4.14).
- **Smelterl version** is not part of build-info: it is read from **application metadata** (e.g. `smelterl.app.src`) in §4.14 step 3 for `build_environment.smelterl_version`.


---

### 5.7 Erlang Modules

Each module’s role, inputs, and outputs are specified so that implementation can stay self-contained and testable.

**Module subsection structure (uniform):** Except for the build-time escript (§5.7.1) and the behaviour (§5.7.4), each module subsection follows: **Role:** (general role and responsibilities). **Exported functions:** for relevent functions - description; **Processes:** (§4.x) when relevant; `-spec`; **Error reasons:** (one bullet per error tuple) only when the function can return documented errors. Omit **Processes** or **Error reasons** when they would not add information (e.g. “(none)” or “(none documented)”). **Testing highlights:** at end (what to test, mocks, helpers, when to mock this module).

**Generator pattern:** For modules that generate output files (e.g. `smelterl_gen_*`), prefer a two-layer API: one function computes a deterministic Erlang term/data model, and another function renders/writes that model to an output device. `plan` should call compute functions; `generate` should call render/write with plan data.

**Scope and maintenance:** The following subsections are **not exhaustive**. Implementation may require additional exported functions; the listed functions are the **most representative** ones for each module’s role. Adding new exported functions during implementation **does not** require documenting each of them here; this design doc need only be updated when **changing** a function already documented here or when adding a **crucial** export that belongs in the design. The **reference for function documentation** is the **inline documentation in the modules** (e.g. `-doc` attributes); this section is a design overview, not the source of truth for every export.

#### 5.7.1 Build-time script: generate_build_info

**scripts/generate_build_info.escript** is not an Erlang module but a build-time escript. It must:

- Run from the smelterl project directory (the directory containing the smelterl application, which may be the repository root or a subdirectory such as `smelterl/`).
- **Detect the VCS repository root:** If smelterl lives in a subdirectory of a larger repository (e.g. `grisp_alloy/smelterl/`), walk up from the current directory to find the repository root (e.g. the directory containing `.git`). Use that root for all VCS queries.
- **Capture from the repository root:** `url` (remote URL, e.g. from `git config remote.origin.url`), `commit` (full commit hash), `describe` (e.g. `git describe --always`), `dirty` (boolean: uncommitted changes).
- **Relpath:** Compute the path of the smelterl application directory relative to the repository root (e.g. `smelterl/` or `apps/smelterl/`); use empty binary if smelterl is at the repo root. Store as `relpath` in the build-info.
- **Write** an Erlang term file to `priv/build_info.term` (path relative to the smelterl app root). Term format per [§5.6.8 Smelterl build-info](#568-smelterl-build-info), serialization per [Erlang Term File Format Conventions](00_OVERVIEW.md#erlang-term-file-format-conventions) (UTF-8, one term, period-terminated).
- **Failure:** If the directory is not a VCS checkout (e.g. tarball with no `.git`), the script fails.

#### 5.7.2 smelterl (entry point)

**Role:**
Escript entry point and central place for all shared type specifications (§5.6 types are defined here; other modules reference them for their function specs). Gathers all configuration from application env (e.g. command module list) into a single config map; passes argv and this config to smelterl_cli. This is the only place that reads application env-smelterl_cli receives explicit (argv, Config) and does not read app env. Invokes smelterl_cli and returns the exit code; all CLI handling (parsing, dispatch, help) is done inside smelterl_cli. Input: argv (from escript). Output: exit code.

**Types:**

```erlang
-type smelterl_config() :: #{
    command_handlers := #{CommandName :: atom() => Handler :: module()}
}
```

**Exported functions:**

- **`main/1`**:

    Escript entry point. Reads application env, builds a config map (e.g. `#{command_handlers => #{plan => smelterl_cmd_plan, generate => smelterl_cmd_generate, ...}}`), calls smelterl_cli with (argv, Config), and returns exit code (0 = success, non-zero = failure). All option parsing and command dispatch are done inside smelterl_cli; this module only gathers config and invokes the CLI.

    ```erlang
    -spec main(Argv) -> Result
        when Argv    :: [string()],
             Result  :: non_neg_integer().
    ```

#### 5.7.3 smelterl_cli

**Role:**
All CLI handling with a two-phase parse (see [§3.0](#30-cli-parsing-flow-overview)):

- **First pass:** parse with a minimal global spec (`--help`, `--version`) and determine the command (first non-option token, if any).
- **Second pass:** when a command is present, look up the handler in the config map (Config is passed by the caller; this module does not read application env), get option spec via `options_spec(Action)`, parse the remaining argv with that spec.
- **Dispatch:** if `--version` or global `--help` (no command), handle and exit; if command `--help`, call handler’s `help(Action)`; otherwise call `Module:run(Action, ParsedOpts)`.

The config map is the single source of command names and handlers; the CLI does not ask handlers for their name.  

**Exported functions:**

- **`run/2`**:

    Two-phase parse and dispatch:

    - **First pass:** parse global options (`--help`, `--version`) and find command (first non-option token).
    - If no command and `--help`/`--version`: print global help or version and return.
    - If command present: look up module from Config, get `options_spec(Action)` from handler, parse rest of argv with that spec.
    - If `--help` was seen for command: call `Module:help(Action)`; else call `Module:run(Action, ParsedOpts)`.

    Returns status code. Does not read application env.

    ```erlang
    -spec run(Argv, Config) -> StatusCode.
        when Argv    :: [string()],
             Config  :: smelterl:smelterl_config(),
             StatusCode  :: integer().
    ```

**Testing highlights:**
- Pass an explicit config map; no need to set application env. Stub command modules with meck; assert that the correct command module run/2 or help is called for given argv; assert CLI obtains option spec from command module and parses with it.
- Local helpers: build argv and config map; assert exit code and that stubbed modules were called with expected (Argv, Config) and options.

#### 5.7.4 smelterl_command (behaviour)

**Role:**
Contract for all command modules. The **command name** (e.g. `generate`) is **not** a callback-it is the key in the config map that maps to this module; the entry point builds that map from application env. The CLI uses **first-pass** parsing to find the command token, looks up the module in the config map, then calls **`options_spec(Action)`** to get the spec for the **second parse** (remaining argv). After parsing, the CLI either calls **`help(Action)`** (when `--help` was given for this command) or **`run(Action, ParsedOpts)`**. Each command module **defines** its options via `options_spec/1`; the CLI only **parses** with that spec and passes the resulting option map to `run/2`.

**Callback type specs:**

The type `option_spec()` is the format required by the chosen CLI parser (e.g. getopt); the implementation may use a type alias to the parser library's option record/tuple.

- **`run/2`**:

    Execute the command for Action with the option map produced by the **second parse**. Called when no `--help` or `--version` is pending for this command. Returns an integer status code (0 success, non-zero failure). Command handlers print user-facing error messages to stderr before returning non-zero.

    ```erlang
    -callback run(Action, Opts) -> StatusCode
        when Action :: atom(),
             Opts   :: map(),
             StatusCode :: integer().
    ```

- **`help/1`**:

    Return help text for the given Action. Called by the CLI when the user requested help for **this** command (e.g. `smelterl generate --help`). Used for command-specific help only; global help (no command) is produced by the CLI from the config map.

    ```erlang
    -callback help(Action) -> Result
        when Action :: atom(),
             Result :: iodata().
    ```

- **`actions/0`**:

    Return the list of action atoms this command supports (e.g. [generate]). Used by the CLI to resolve Action (e.g. when the command has a single action, Action may equal the command name).

    ```erlang
    -callback actions() -> Result
        when Result :: [atom()].
    ```

- **`options_spec/1`**:

    Return the option specification for Action for use in the **second parse**. The CLI parses the remaining argv (after the command token) with this spec and passes the resulting option map to `run/2`. Format depends on the chosen getopt/parser library.

    ```erlang
    -callback options_spec(Action) -> Result
        when Action :: atom(),
             Result :: [option_spec()].
    ```

#### 5.7.5 smelterl_cmd_plan

**Role:**
Implements the **`plan`** command (registered under key `plan` in the command-module config map). Implements the **smelterl_command** behaviour.

**Required parameters and errors:**

- Required options: `--product`, `--motherlode`, `--output-plan`.
- Missing required option: print descriptive error to stderr; return non-zero; do not execute planning steps.

**Process flow:**

1. Load motherlode (§4.1) from `--motherlode` via `smelterl_motherlode`.
2. Construct target trees (§4.2) from `--product` + motherlode via `smelterl_tree`.
3. Validate target trees (§4.3) via `smelterl_validate`.
4. Compute per-target topology (§4.4) via `smelterl_topology`.
5. Capture and validate `--extra-config` key/value pairs (plan-only option input).
6. Apply overrides (§4.5) with auxiliary/scoped semantics via `smelterl_overrides`.
7. Discover capabilities (§4.6) from overridden trees via `smelterl_capabilities`.
8. Consolidate config per target (§4.7) via `smelterl_config` (with plan-carried extra-config).
9. Build per-target defconfig models (§4.11 plan stage) via `smelterl_gen_defconfig:build_model/5`.
10. Build main-target manifest seed (§4.14.A) via `smelterl_gen_manifest:prepare_seed/7`.
11. Serialize/write full plan (`--output-plan`) and optional env summary (`--output-plan-env`) via `smelterl_plan`.
12. On first error at any step: print message to stderr, return non-zero, stop remaining steps.

**Exported functions:**

- Implements `smelterl_command` callbacks (`actions/0`, `options_spec/1`, `help/1`, `run/2`).
- `run/2` orchestrates the flow above and returns status code (no structured error return to CLI).

**Testing highlights:**
- Assert deterministic plan output for same inputs.
- Assert required-option failures (`--product`, `--motherlode`, `--output-plan`) print to stderr and return non-zero.
- Assert deterministic injection of target-local wrapper hook entries in defconfig models.
- Assert auxiliary and scope validation failures are reported at plan time.

#### 5.7.6 smelterl_cmd_generate

**Role:**
Implements the **`generate`** command (registered under key `generate` in the command-module config map). Implements the **smelterl_command** behaviour. Consumes a precomputed plan and renders artefacts for one selected target.

**Required parameters and errors:**

- Required option: `--plan <PATH>`.
- Missing `--plan`: print descriptive error to stderr; return non-zero; do not execute generation steps.
- `generate` rejects `--extra-config` (plan-only): print error to stderr; return non-zero.
- Main-only option misuse (`--output-manifest`, `--buildroot-legal`, `--export-legal`, `--include-sources` with `--auxiliary`) is an error: print to stderr; return non-zero.
- Invalid auxiliary selector (`--auxiliary <AuxId>` not in plan) is an error: print to stderr; return non-zero.

**Process flow:**

1. Load build plan from `--plan` via `smelterl_plan`; resolve selected target (main by default, or `--auxiliary <AuxId>`).
2. Generate requested Buildroot files for selected target:
   - external.desc (§4.8) via `smelterl_gen_external_desc` when `--output-external-desc` is set.
   - Config.in (§4.9) via `smelterl_gen_config_in` when `--output-config-in` is set (using plan-carried extra-config keys).
   - external.mk (§4.10) via `smelterl_gen_external_mk` when `--output-external-mk` is set.
   - defconfig (§4.11 render stage) via `smelterl_gen_defconfig:render/*` when `--output-defconfig` is set (from selected-target precomputed model).
3. Generate selected-target context (§4.12) via `smelterl_gen_context` when `--output-context` is set.
4. For main target only, when relevant options are set:
   - Parse optional repeatable `--buildroot-legal` inputs and optionally export merged legal tree (§4.13) via `smelterl_legal`.
   - Finalize/write manifest from plan-carried seed (§4.14.B) via `smelterl_gen_manifest` when `--output-manifest` is set.
5. On first error at any step: print message to stderr, return non-zero, stop remaining steps.

**Exported functions:**

- Implements `smelterl_command` callbacks (`actions/0`, `options_spec/1`, `help/1`, `run/2`).
- `run/2` orchestrates the flow above and returns status code (no structured error return to CLI).

**Testing highlights:**
- Assert no dependency re-resolution in `generate`.
- Assert `generate` rejects `--extra-config`.
- Assert auxiliary selector validation and main-only manifest/legal rules.
- Mock generators and legal/manifest modules; assert option-gated call order and early stop on first error.

#### 5.7.7 smelterl_motherlode

**Role:**
Load motherlode directory: list repos, read .nuggets and .nugget files, merge defaults + per-nugget, resolve license paths; optionally attach VCS info.

**Exported functions:**

- **`load/1`**:

    Load the motherlode directory:

    - List repos, read .nuggets and .nugget files.
    - Merge defaults and per-nugget metadata; resolve license paths.
    - Attach VCS info when available.

    Return motherlode map or `{error, Reason}`. The caller is responsible for printing a user-friendly message from Reason (see error reasons below).

    **Processes:** §4.1 Loading the Motherlode.

    ```erlang
    -spec load(MotherlodePath) -> Result
        when MotherlodePath   :: smelterl:file_path() | string(),
             Result :: {ok, smelterl:motherlode()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{invalid_path, Path, Posix}`** - Motherlode path invalid or inaccessible. `Path` is the path passed to `load/1`. `Posix` is a POSIX atom (e.g. `enoent`, `enotdir`, `eacces`).
    - **`{invalid_registry, RepoPath, Detail}`** - Failed to parse a `.nuggets` registry file (e.g. not `{nugget_registry, Version, Fields}` or malformed term). `RepoPath` is the repository directory path; `Detail` may be a parse error or term validation error.
    - **`{missing_metadata, RepoPath, NuggetRelPath}`** - A path listed in a registry’s `nuggets` does not exist. `RepoPath` is the repo dir; `NuggetRelPath` is the relative path to the `.nugget` file.
    - **`{invalid_metadata, RepoPath, NuggetRelPath, Detail}`** - Failed to parse or validate a `.nugget` file (e.g. not `{nugget, Version, Fields}`, missing `id` field, or malformed term). `RepoPath` and `NuggetPath` identify the file; `Detail` describes the error.
    - **`{duplicated_nugget_id, NuggetId, RepoPath1, RepoPath2}`** - The same nugget identifier appears in two repositories.
    - **`{missing_file, RepoPath, NuggetRelPath, FileRelPath, Detail}`** - A file referenced by the metadata is missing (licence, script, fragment, etc).

**Testing highlights:**
- Use a fixture directory tree (minimal .nuggets + .nugget files) under test priv; load and assert shape of motherlode (keys, presence of config, license paths resolved).
- **Mock smelterl_vcs** so that repository info extraction (e.g. URL, commit, describe, dirty) can be tested without real VCS repositories; the motherlode fixture can be plain directories and the mock returns the expected VCS data per path.
- Helper: create a minimal motherlode dir (one repo, one nugget) and assert merged defaults and per-nugget metadata.

#### 5.7.8 smelterl_tree

**Role:**
From a root nugget id (main product or auxiliary root) and motherlode, build a dependency subtree (nugget dependencies only) and detect cycles. Does not perform validation (§4.3), topological sort (§4.4), overrides (§4.5), or auxiliary effective-tree composition with the main backbone (§4.2)-those are handled by command-level orchestration plus smelterl_validate/smelterl_topology/smelterl_overrides.

**Exported functions:**

- **`build/2`**:

    Build dependency tree from product id and motherlode:

    - Build tree (root + edges); detect cycles.
    - Return tree or `{error, Reason}`.

    The caller is responsible for printing a user-friendly message from Reason (see error reasons below).

    **Processes:** §4.2 Constructing Target Trees.

    ```erlang
    -spec build(ProductId, Motherlode) -> Result
        when ProductId :: smelterl:nugget_id(),
             Motherlode :: smelterl:motherlode(),
             Result     :: {ok, smelterl:nugget_tree()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{product_not_found, ProductId}`** - The product nugget is not in the motherlode. `ProductId` is the value passed as `--product`.
    - **`{circular_dependency, Cycle}`** - A circular dependency was detected. `Cycle` is a list of nugget identifiers in order (e.g. `[a, b, c, a]`) so the caller can display the loop.
    - **`{dependency_not_found, RequesterId, MissingId, Constraint}`** - A required (or one_of/any_of-required) dependency could not be found in the motherlode. `RequesterId` is the nugget that declared the dependency; `MissingId` is the nugget id that is missing; `Constraint` indicates the constraint type (e.g. `required`, `one_of`, `any_of`).

**Testing highlights:**
- Build minimal motherlode (fixture or in-memory) and product id; assert tree shape and edges; test cycle detection and missing-product error.
- Helpers: small motherlode with 2-3 nuggets and dependencies; assert dependency order in tree.

#### 5.7.9 smelterl_validate

**Role:**
Validate nugget tree: category cardinality (§4.3), category/capability constraints, version/flavor constraints, conflicts. Single responsibility so validation rules can be tested in isolation with a pre-built tree and motherlode. Also exposes single-nugget validation for use by smelterl_overrides when applying a nugget replacement (so the replacement can be checked before the tree is updated).

**Exported functions:**

- **`validate_tree/2`**:

    Validate full tree:

    - Category cardinality (builder, toolchain, platform, system exactly one).
    - Category/capability constraints, version/flavor, conflicts.

    Return ok or `{error, Reason}`; caller prints message and returns status. See error reasons below.

    **Processes:** §4.3 Validating Target Trees.

    ```erlang
    -spec validate_tree(Tree, Motherlode) -> Result
        when Tree      :: smelterl:nugget_tree(),
             Motherlode :: smelterl:motherlode(),
             Result    :: ok | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{bad_category_cardinality, Category, Count, NuggetIds}`** - For `builder`, `toolchain`, `platform`, or `system`, count in tree is not 1. `Count` is the actual count; `NuggetIds` lists nuggets with that category.
    - **`{missing_category_dependency, NuggetId, Category, Constraint}`** - A nugget requires a category (e.g. `{required, category, platform}`) that the tree does not satisfy.
    - **`{missing_capability_dependency, NuggetId, Capability}`** - A nugget requires a capability that no nugget in the tree provides.
    - **`{nugget_conflict, NuggetIdA, NuggetIdB}`** -  A conflicts_with nugget constraint is violated.
    - **`{capability_conflict, NuggetId, capability, Cap}`** - A conflicts_with capability constraint is violated.
    - **`{incompatible_version, RequesterId, TargetId, Required, Actual}`** - Version constraint not satisfied.
    - **`{invalid_flavor, NuggetId, Flavor}`** - Flavor not in nugget's flavors list.
    - **`{flavor_mismatch, NuggetId, Flavor}`** - Dependents disagree on flavor.

- **`validate_replacement/4`**:

    Validate a single nugget replacement for use when applying overrides: check that replacing `ReplacedNuggetId` with `NewNuggetId` in the given tree keeps the tree valid:

    - Category cardinality preserved; capability/category deps; version/flavor; conflicts.

    smelterl_overrides calls this before applying each nugget override. Tree and Motherlode are the current state (before this replacement). Return ok or `{error, Reason}`; caller prints message and returns status. See error reasons below.

    **Processes:** §4.5 Applying Overrides (called during override application).

    ```erlang
    -spec validate_replacement(NewNuggetId, ReplacedNuggetId, Tree, Motherlode) -> Result
        when NewNuggetId    :: smelterl:nugget_id(),
             ReplacedNuggetId :: smelterl:nugget_id(),
             Tree           :: smelterl:nugget_tree(),
             Motherlode     :: smelterl:motherlode(),
             Result         :: ok | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - Same as for `validate_tree/2`.
    - **`{category_mismatch, NewNuggetId, ReplacedNuggetId, Category}`** - Replacement has a different category than the replaced nugget, so category cardinality would be broken.

**Testing highlights:**
- Pass minimal pre-built tree and motherlode; assert validation passes or fails (e.g. missing category, duplicate category, version mismatch, conflict).
- For `validate_replacement/4`: assert that replacing a nugget with one of the same category succeeds; replacing with a different category fails (cardinality); test version/flavor and conflict rules for the replacement.
- Helpers: build small tree + motherlode with known category/capability/version; test each validation rule in isolation.

#### 5.7.10 smelterl_overrides

**Role:**
Apply nugget and config overrides from metadata in topology order (§4.5); return overridden tree, topology order, and overridden motherlode.

**Exported functions:**

- **`apply_overrides/3`**:

    Apply nugget and config overrides from metadata in topology order:

    - For each nugget replacement: call smelterl_validate:validate_replacement/4 before applying; on validation failure return that error.
    - Return overridden tree, order, and motherlode.

    Caller prints error and returns status on `{error, Reason}`. See error reasons below.

    **Processes:** §4.5 Applying Overrides.

    ```erlang
    -spec apply_overrides(Tree, TopOrder, Motherlode) -> Result
        when Tree      :: smelterl:nugget_tree(),
             TopOrder  :: smelterl:nugget_topology_order(),
             Motherlode :: smelterl:motherlode(),
             Result    :: {ok, smelterl:nugget_tree(), smelterl:nugget_topology_order(), smelterl:motherlode()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{validation_failed, Reason}`** - **smelterl_validate:validate_replacement/4** returned an error for a nugget replacement. `Reason` is the same as validate_replacement’s Reason.
    - **`{replacement_not_found, ReplacedNuggetId, NewNuggetId}`** - Override_spec references a replacement nugget `NewNuggetId` that is not in the motherlode.
    - **`{override_target_missing, NuggetId, TargetId}`** - The nugget to be replaced (`TargetId`) is not in the tree.

**Testing highlights:**
- Pass minimal tree + topology + motherlode with override_spec and config overrides; assert overridden tree and motherlode (nugget replacement, config last-wins).
- Helpers: small fixture with one replacement and one config override; assert result shape.

#### 5.7.11 smelterl_topology

**Role:** Given a nugget tree, return a topological order (list of nugget ids) with stable tie-breaking so that dependencies appear before dependents.

**Exported functions:**

- **`topology_order/1`**:

    Topological sort of the nugget tree:

    - Take `nugget_tree()` (root + edges).
    - Return an ordered list of nugget ids with stable tie-break using declaration order.
    - Return error if the tree contains a cycle.

    **Processes:** §4.4 Topological Order (used by the command flow after smelterl_tree:build/2 to obtain the order for validation and overrides).

    ```erlang
    -spec topology_order(Tree) -> Result
        when Tree   :: smelterl:nugget_tree(),
             Result :: {ok, smelterl:nugget_topology_order()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{cycle_detected, Path}`** - The graph contains a cycle (e.g. a -> b -> c -> a); path is a list of nugget ids.

**Testing highlights:**
- Pure function: pass a nugget tree (from build/2 or fixture); assert result is a valid topological order (all nodes, deps before dependents); test stable tie-breaking with multiple valid orders.
- Helper: build a small tree (e.g. a -> b, a -> c, b -> c) and assert order; test cycle returns error.

#### 5.7.12 smelterl_capabilities (or equivalent)

**Role:**
Discover firmware variants, selectable outputs, and firmware parameters per [§4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters](#46-discovering-firmware-variants-selectable-outputs-and-parameters): firmware_variants (ordered list of variant atoms - the union of all nuggets' `firmware_variant` lists, with `plain` always present), variant_nuggets (map from each variant atom to the list of nuggets that declare it), selectable_outputs (ordered list of output identifier atoms from nuggets' `firmware_outputs` metadata where `selectable` is `true`), and firmware_parameters (ordered list of merged parameter declarations from all nuggets' `firmware_parameters` metadata).

**Exported functions:**

- **`discover/3`**:

    From overridden tree, topology, and motherlode compute firmware_variants (ordered list of variant atoms - the union of all nuggets' `firmware_variant` lists, with `plain` always present), variant_nuggets (map from each variant atom to the list of nuggets that declare it), selectable_outputs (ordered list of output identifier atoms from `firmware_outputs` metadata with `selectable` = `true`), and firmware_parameters (ordered list of merged parameter declarations from all nuggets' `firmware_parameters` metadata, with cross-nugget validation for type consistency and default consistency). Validates that each variant atom within a single nugget's list is unique, that output IDs are unique across the tree, that parameter types are consistent across nuggets, and ensures `plain` is always in the variant list.

    **Processes:** §4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters.

    ```erlang
    -spec discover(Tree, TopOrder, Motherlode) -> Result
        when Tree      :: smelterl:nugget_tree(),
             TopOrder  :: smelterl:nugget_topology_order(),
             Motherlode :: smelterl:motherlode(),
             Result    :: smelterl:firmware_capabilities().
    ```

**Testing highlights:**
- Pass overridden tree, topology, motherlode with nuggets declaring `firmware_variant`; assert firmware_variants list preserves first-occurrence order from topology, contains the correct variant atoms, and always includes `plain`; assert variant_nuggets maps each variant to the correct nuggets; assert selectable_outputs are collected correctly and output ID uniqueness is enforced.
- Helper: minimal tree with one bootflow nugget declaring `firmware_variant`; assert capabilities map and bootflow coverage validation.
- Test: multiple nuggets sharing the same variant atom; assert variant_nuggets lists all participating nuggets.
- Error case: duplicate variant atom within a single nugget's firmware_variant list; assert error.
- Pass nuggets declaring `firmware_parameters` with same `ParamId`; assert merged parameters have correct type, OR-ed `required`, first non-empty `name`/`description`, consistent `default`.
- Error case: two nuggets declare the same parameter with conflicting types; assert error.
- Error case: two nuggets declare the same parameter with conflicting defaults; assert error.

#### 5.7.13 smelterl_config

**Role:**
Consolidate config: iterate nuggets in topology order, merge config and exports, apply overrides, resolve flavor_map, paths, computed, exec. Produces per-nugget and global config map (unified shape §5.6.5). ALLOY_MOTHERLODE is not injected by this module; the command handler must add it to ExtraConfig before calling consolidate.

**Exported functions:**

- **`consolidate/4`**:

    Merge config and exports in topology order:

    - Resolve path, flavor_map, computed, exec (ExtraConfig supplies env keys for exec scripts and `[[KEY]]` substitution).
    - Return single config map (per §5.6.5) or error.

    **Processes:** §4.7 Consolidating Nugget Configuration.

    ```erlang
    -spec consolidate(Tree, TopOrder, Motherlode, ExtraConfig) -> Result
        when Tree        :: smelterl:nugget_tree(),
             TopOrder    :: smelterl:nugget_topology_order(),
             Motherlode  :: smelterl:motherlode(),
             ExtraConfig :: #{binary() => binary()},
             Result      :: {ok, smelterl:config()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{duplicate_export, Key, NuggetId1, NuggetId2}`** - Two nuggets both export the same key.
    - **`{export_config_conflict, Key, ExportNuggetId, ConfigNuggetId}`** - A key exported by one nugget appears in another nugget's `config`. Exports reserve the key across the entire tree.
    - **`{config_export_conflict, NuggetId, Key}`** - Within one nugget, the same key appears in both `config` and `exports`.
    - **`{path_resolution_failed, NuggetId, Path, Detail}`** - A path (e.g. from config or exports) could not be resolved relative to the nugget or motherlode.
    - **`{exec_failed, NuggetId, Key, Reason}`** - smelterl_script returned an error for an exec value. `Reason` is from smelterl_script.
    - **`{invalid_flavor, NuggetId, Detail}`** - flavor_map lookup or selection failed for a nugget.
    - **`{template_error, NuggetId, Key, Detail}`** - smelterl_template returned an error for a computed value (e.g. substitute). `Detail` is from smelterl_template.

**Testing highlights:**
- Mock smelterl_script for exec; pass overridden tree, topology, motherlode, extra_config (caller adds ALLOY_MOTHERLODE); assert consolidated config shape (per-nugget, global) and path resolution.
- Helpers: minimal tree + motherlode with one nugget and a few config keys (plain, path, flavor_map); assert merge order and last-wins.

#### 5.7.14 smelterl_script

**Role:**
Abstract **script execution** and **variable resolution from environment**. Provides: (1) run a script (relative path, working dir, env map) and return stdout (trimmed); (2) expand shell variable references in a string using the current process environment and return the fully expanded string. This module does not use other smelterl modules.

**Exported functions:**

- **`run_script/4`**:

    Run the script at the given path (relative to working dir) with the given working dir and env map; optional first argument passed to the script. Return {ok, Stdout} (trimmed) or {error, Reason}. Exit code must be 0 for success.

    **Processes:** §4.7 (config consolidation, exec values); §4.13 (legal export: exec scripts for source_dir/source_archive).

    ```erlang
    -spec run_script(ScriptPath, WorkingDir, Env, Arg) -> Result
        when ScriptPath :: smelterl:file_path(),
             WorkingDir :: smelterl:file_path(),
             Env        :: smelterl:config(),
             Arg        :: binary() | undefined,
             Result     :: {ok, binary()} | {error, term()}.
    ```

    **Error reasons:**
    - **`{script_not_found, Path}`** - Script path does not exist or is not executable.
    - **`{exit_non_zero, ExitCode, Stdout, Stderr}`** - Script exited with non-zero code.
    - **`{posix, Path, Posix}`** - File or system error (e.g. `eacces`, `enoent`).

- **`resolve_env/1`**:

    Expand shell variable references (e.g. `${ALLOY_CACHE_DIR}`) in the string using the current process environment; return the fully expanded string.

    **Processes:** §4.13 (legal export: variable resolution for concrete paths when exporting alloy-sources).

    ```erlang
    -spec resolve_env(Str) -> Result
        when Str    :: binary(),
             Result :: binary() | {error, term()}.
    ```

    **Error reasons:**
    - **`{unresolved_variable, VarName}`** - A variable in the string is not set in the environment.
    - **`{invalid_syntax, Detail}`** - String has invalid or unsupported variable syntax.

**Testing highlights:**
- run_script/4: use a small script in a fixture dir (e.g. echo a value); pass working dir and env map; assert stdout and exit 0; test non-zero exit returns error. Mock os:cmd or port if needed to avoid real shell.
- resolve_env/1: set env in process, call resolve with a string containing `${VAR}`; assert expanded result. Helpers to set/get test env and clean up.
- Mock this module in smelterl_config and smelterl_legal tests to avoid executing real scripts.

#### 5.7.15 smelterl_template

**Role:**
Single module for all templating: (1) **[[KEY]] substitution** - given a string and consolidated config, replace every `[[KEY]]` with the value for KEY from config; (2) **Template engine** - given a template key and a data structure, render to a string or write to a file. This module is the only one that knows where templates live (e.g. `priv/templates/`) and which engine is used (e.g. Mustache). Callers use template keys only; they do not reference paths or the engine. Reads template files from application priv; does not use §5.6 structures (callers pass config or data map).

**Exported functions:**

- **`substitute/2`**:

    Replace every `[[KEY]]` in the string with the value for KEY from the consolidated config. Single pass, no recursion. Unresolved keys are an error.

    **Processes:** §4.7 (computed values in config); §4.11 ([[KEY]] in defconfig fragments).

    ```erlang
    -spec substitute(String, Config) -> Result
        when String :: binary() | string(),
             Config :: smelterl:config(),
             Result :: {ok, binary()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{unresolved_key, Key}`** - A `[[KEY]]` marker has no corresponding value in Config.

- **`render/2`**:

    Render a template by key with the given data structure. Resolves the key to a path under priv/templates and uses the configured engine (e.g. Mustache). Returns the rendered content as iodata.

    **Processes:** §4.8-§4.12 (external.desc, Config.in, external.mk, defconfig, alloy_context.sh); §4.13 (README for legal export).

    ```erlang
    -spec render(TemplateKey, Data) -> Result
        when TemplateKey :: atom() | binary(),
             Data       :: map() | term(),
             Result     :: {ok, iodata()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{template_not_found, TemplateKey}`** - No template file for the given key.
    - **`{template_load_failed, TemplateKey, Detail}`** - Template file could not be read or parsed.
    - **`{render_failed, TemplateKey, Detail}`** - Engine failed to render (e.g. missing variable, syntax).

- **`render_to_file/3`**:

    Same as render/2 but write the result to the given path or IO device. Renders then writes; no engine-specific write API.

    **Processes:** §4.8-§4.12; §4.13 (README for legal export).

    ```erlang
    -spec render_to_file(TemplateKey, Data, PathOrDevice) -> Result
        when TemplateKey   :: atom() | binary(),
             Data         :: map() | term(),
             PathOrDevice :: smelterl:file_path() | file:io_device(),
             Result       :: ok | {error, Reason :: term()}.
    ```

    **Error reasons:** Same as render/2; additionally
    - **`{write_failed, PathOrDevice, Detail}`** - writing to path or device failed.

**Testing highlights:**
- Mock smelterl_template in gen_* and defconfig tests when no no real template files or engine is needed.
- Unit-test substitute/2 with a small config map and a string containing `[[KEY]]`; assert output and that unresolved key returns error.
- Unit-test render/2 with a fixture template in test priv or a mock engine; assert render_to_file writes the same content as render.

#### 5.7.16 smelterl_gen_external_desc

**Role:**
Build external.desc content (two lines: name, desc) from product metadata. Uses smelterl_template (template key `external_desc`). Input: product id, product metadata. Output: IO list or binary. Does not modify shared structures.

**Exported functions:**

- **`generate/2`**:

    Build external.desc content (name line, desc line) from product id and motherlode (product nugget metadata). Return iodata or binary.

    **Processes:** §4.8 Generating external.desc.

    ```erlang
    -spec generate(Product, Motherlode) -> Result
        when Product   :: smelterl:nugget_id(),
             Motherlode :: smelterl:motherlode(),
             Result    :: iodata().
    ```

- **`generate/3`**:

    Build external.desc content and write to the open output device Out.

    **Processes:** §4.8 Generating external.desc.

    ```erlang
    -spec generate(Product, Motherlode, Out) -> Result
        when Product   :: smelterl:nugget_id(),
             Motherlode :: smelterl:motherlode(),
             Out       :: file:io_device(),
             Result    :: ok.
    ```

**Testing highlights:**
- **Template-based generation:** (1) Test render parameters: mock smelterl_template and assert template key and data passed to render. (2) When possible: use a custom template in the test context and assert on the rendered output (e.g. two lines, name then desc).
- Helper: minimal product_metadata() map; assert format matches Buildroot external.desc expectation.

#### 5.7.17 smelterl_gen_config_in

**Role:**
Build Config.in: extra-config Kconfig blocks, then source lines for each nugget's packages (with Config.in) in topology order. Uses smelterl_template (template key `config_in`). Input: topology order, motherlode, plan-carried extra-config keys. Output: IO list or binary. Does not modify shared structures.

**Exported functions:**

- **`generate/3`**:

    Build Config.in: extra-config Kconfig blocks (including ALLOY_MOTHERLODE first), then source lines for each nugget package Config.in in topology order. Third argument: extra-config key list. Return iodata or binary.

    **Processes:** §4.9 Generating Config.in.

    ```erlang
    -spec generate(TopOrder, Motherlode, ExtraConfigKeys) -> Result
        when TopOrder        :: smelterl:nugget_topology_order(),
             Motherlode      :: smelterl:motherlode(),
             ExtraConfigKeys :: [binary()],
             Result          :: iodata().
    ```

- **`generate/4`**:

    Build Config.in and write to the open output device Out.

    **Processes:** §4.9 Generating Config.in.

    ```erlang
    -spec generate(TopOrder, Motherlode, ExtraConfigKeys, Out) -> Result
        when TopOrder        :: smelterl:nugget_topology_order(),
             Motherlode      :: smelterl:motherlode(),
             ExtraConfigKeys :: [binary()],
             Out             :: file:io_device(),
             Result          :: ok.
    ```

**Testing highlights:**
- **Template-based generation:** (1) Test render parameters: mock smelterl_template and assert template key and data. (2) When possible: use a custom template in the test context and assert on the rendered output (Kconfig blocks, source lines in order).
- Helper: minimal motherlode with one nugget and a packages entry; assert source line format and order.

#### 5.7.18 smelterl_gen_external_mk

**Role:**
Build external.mk: include lines for each nugget's package .mk files in topology order. Uses smelterl_template (template key `external_mk`). Input: topology order, motherlode. Output: IO list or binary. Does not modify shared structures.

**Exported functions:**

- **`generate/2`**:

    Build external.mk: include lines for each nugget package .mk file in topology order; paths use $(ALLOY_MOTHERLODE)/... . Return iodata or binary.

    **Processes:** §4.10 Generating external.mk.

    ```erlang
    -spec generate(TopOrder, Motherlode) -> Result
        when TopOrder   :: smelterl:nugget_topology_order(),
             Motherlode :: smelterl:motherlode(),
             Result     :: iodata().
    ```

- **`generate/3`**:

    Build external.mk and write to the open output device Out.

    **Processes:** §4.10 Generating external.mk.

    ```erlang
    -spec generate(TopOrder, Motherlode, Out) -> Result
        when TopOrder   :: smelterl:nugget_topology_order(),
             Motherlode :: smelterl:motherlode(),
             Out        :: file:io_device(),
             Result     :: ok.
    ```

**Testing highlights:**
- **Template-based generation:** (1) Test render parameters: mock smelterl_template and assert template key and data. (2) When possible: use a custom template in the test context and assert on the rendered output (include lines in topology order).
- Helper: two-nugget motherlode; assert two includes in dependency order.

#### 5.7.19 smelterl_gen_defconfig

**Role:**
Build and render defconfig data in two phases. Plan phase merges defconfig fragments into a deterministic `defconfig_model()` (regular + cumulative key/value lines, including automatic target-local wrapper hook entries). Generate phase renders that model via smelterl_template and writes output. Reads defconfig-keys.spec from priv. Does not modify shared structures.

**Exported functions:**

- **`build_model/5`**:

    Build plan-storable defconfig model from topology inputs:

    - Substitute [[KEY]] via smelterl_template using the given config and product metadata (from ProductId and motherlode).
    - Merge regular (last-wins) and cumulative keys.
    - Append deterministic target-local wrapper scripts (`$(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-*.sh`) to cumulative hook keys.

    Return `defconfig_model()`.

    **Processes:** §4.11 Generating defconfig.

    ```erlang
    -spec build_model(TargetId, TopOrder, Motherlode, Config, ProductId) -> Result
        when TargetId    :: smelterl:nugget_id(),
             TopOrder    :: smelterl:nugget_topology_order(),
             Motherlode  :: smelterl:motherlode(),
             Config      :: smelterl:config(),
             ProductId   :: smelterl:nugget_id(),
             Result      :: smelterl:defconfig_model().
    ```

- **`render/1`**:

    Render a defconfig model to iodata via smelterl_template.

    **Processes:** §4.11 Generating defconfig.

    ```erlang
    -spec render(DefconfigModel) -> Result
        when DefconfigModel :: smelterl:defconfig_model(),
             Result         :: iodata().
    ```

- **`render/2`**:

    Render a defconfig model and write to the open output device Out.

    **Processes:** §4.11 Generating defconfig.

    ```erlang
    -spec render(DefconfigModel, Out) -> Result
        when DefconfigModel :: smelterl:defconfig_model(),
             Out         :: file:io_device(),
             Result      :: ok.
    ```

**Testing highlights:**
- **Model build:** Use fixture defconfig fragments (one per nugget) and minimal topology/motherlode/consolidated config; assert model content: last-wins for regular keys, concatenation for cumulative keys, [[KEY]] substituted, and target-local wrapper scripts appended to hook keys.
- **Template-based render:** (1) Test render parameters: mock smelterl_template and assert template key/data. (2) When possible: use a minimal template in test context and assert rendered output from a fixed model.
- Helper: small fragment files and config map; assert path resolution and flavor_map selection when flavor differs.

#### 5.7.20 smelterl_gen_context

**Role:**
Render target-scoped `alloy_context.sh` from template via smelterl_template (template key `alloy_context`): target identity (`ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, `ALLOY_AUXILIARY`), nugget metadata/config, target hook arrays with scope filtering, embed/fs-priority arrays, and capabilities. For main target, also emit firmware arrays (`ALLOY_FIRMWARE_*`) and sdk-output consumption metadata (`ALLOY_SDK_OUTPUT_*` vars prepared by orchestrator). Input: target id/kind, topology order, motherlode, config, target capabilities. Output: rendered script. Does not modify shared structures.

**Exported functions:**

- **`generate/6`**:

    Render alloy_context.sh for one selected target. Return iodata or binary.

    **Processes:** §4.12 Generating alloy_context.sh.

    ```erlang
    -spec generate(TargetId, TargetKind, TopOrder, Motherlode, Config, Capabilities) -> Result
        when TargetId    :: smelterl:nugget_id(),
             TargetKind  :: smelterl:target_kind(),
             TopOrder    :: smelterl:nugget_topology_order(),
             Motherlode  :: smelterl:motherlode(),
             Config      :: smelterl:config(),
             Capabilities :: map(),
             Result      :: iodata().
    ```

- **`generate/7`**:

    Render alloy_context.sh and write to the open output device Out.

    **Processes:** §4.12 Generating alloy_context.sh.

    ```erlang
    -spec generate(TargetId, TargetKind, TopOrder, Motherlode, Config, Capabilities, Out) -> Result
        when TargetId    :: smelterl:nugget_id(),
             TargetKind  :: smelterl:target_kind(),
             TopOrder    :: smelterl:nugget_topology_order(),
             Motherlode  :: smelterl:motherlode(),
             Config      :: smelterl:config(),
             Capabilities :: map(),
             Out         :: file:io_device(),
             Result      :: ok.
    ```

**Testing highlights:**
- Assert exported target identity variables for main vs auxiliary.
- Assert hook scope filtering (`main|auxiliary|all|AuxId`) and firmware arrays only in main contexts.
- Assert sdk output metadata vars are present in main context when provided by orchestrator data.

#### 5.7.21 smelterl_legal

**Role:**
Parse target Buildroot legal-info and export one merged multi-target legal tree. `parse_legal/1` parses one target legal directory. `export_legal/*` merges all selected targets into one top-level legal-info structure (no per-target subtree in final export) and generates merged README content. Alloy-only export mode remains valid when Buildroot legal input is not supplied.

**Exported functions:**

- **`parse_legal/1`**:

    Parse Buildroot legal-info directory (manifest.csv, host-manifest.csv); return br_legal_info() with path, packages, host_packages, br_version. Use when the caller only needs parsed data (e.g. for manifest, without exporting).

    **Processes:** §4.13 Collecting Legal Info and Export.

    ```erlang
    -spec parse_legal(Path) -> Result
        when Path   :: smelterl:file_path(),
             Result :: {ok, smelterl:br_legal_info()} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{invalid_path, Path, Posix}`** - Path does not exist, is not a directory, or not readable.
    - **`{missing_manifest, Path, Detail}`** - manifest.csv (or host-manifest.csv) missing, unreadable, or malformed.

- **`export_legal/6`**:

    Export the full legal-info tree in one call. Takes **BuildrootLegal** :: `smelterl:br_legal_info() | undefined` (handler passes result of parse_legal or undefined). When **undefined**: skip Buildroot copy, export only alloy legal info (alloy-manifest.csv, alloy-licenses/, optionally alloy-sources/, README, legal-info.sha256). When BuildrootLegal is given: copy from BuildrootLegal.path, then write the same alloy artefacts. Returns {ok, BuildrootLegal} (pass-through for §4.14).

    **Processes:** §4.13 Collecting Legal Info and Export.

    ```erlang
    -spec export_legal(ExportDir, TopOrder, Motherlode, Config, BuildrootLegal, IncludeSources) -> Result
        when ExportDir      :: smelterl:file_path(),
             TopOrder       :: smelterl:nugget_topology_order(),
             Motherlode     :: smelterl:motherlode(),
             Config         :: smelterl:config(),
             BuildrootLegal :: smelterl:br_legal_info() | undefined,
             IncludeSources :: boolean(),
             Result         :: {ok, smelterl:br_legal_info() | undefined} | {error, Reason :: term()}.
    ```

    **Error reasons:**
    - **`{dir_error, Path, Posix}`** - Could not create export directory.
    - **`{copy_failed, Source, Dest, Detail}`** - Copy of legal-info file or tree failed.
    - **`{script_failed, Reason}`** - smelterl_script (exec or resolve) failed during alloy-sources export. `Reason` is from smelterl_script.

**Testing highlights:**
- **README (template):** (1) Test render parameters: mock smelterl_template and assert template key and data for the README. (2) When possible: use a custom template in the test context and assert on the rendered README output.
- Use fixture buildroot_legal dir (manifest.csv, host-manifest.csv) and optionally export_legal to a tmp dir; mock smelterl_script for exec/resolve if testing alloy-sources; assert parsed package list, Buildroot version, and on-disk layout (alloy-manifest.csv, alloy-licenses/, README).
- Helper: minimal legal-info tree; assert parsing and that export copies and relativizes paths correctly.

#### 5.7.22 smelterl_gen_manifest

**Role:**
Two-stage manifest generator:
- **plan stage** computes a deterministic main-target `manifest_seed` to store in `build_plan.term`;
- **generate stage** finalizes `ALLOY_SDK_MANIFEST` from that seed using runtime/buildroot-legal/path-dependent inputs.
This split mirrors [§4.14](#414-generating-manifest) and keeps both stages independently testable.

**Exported functions:**

- **`prepare_seed/7`**:

    Plan-stage function. Build the deterministic manifest seed from plan-time inputs (main target metadata/config/topology/motherlode/discovery output including firmware capabilities + sdk output declarations/auxiliary metadata + smelterl build-info). Does not consume Buildroot legal data, does not relativize to output path, and does not compute integrity.

    **Processes:** §4.14.A Plan-stage.

    ```erlang
    -spec prepare_seed(Product, Topology, Motherlode, Config, Capabilities, AuxiliaryMeta, BuildInfo) -> Result
        when Product        :: smelterl:nugget_id(),
             Topology       :: smelterl:nugget_topology_order(),
             Motherlode     :: smelterl:motherlode(),
             Config         :: smelterl:config(),
             Capabilities   :: map(),
             AuxiliaryMeta  :: [map()],
             BuildInfo      :: smelterl:smelterl_build_info(),
             Result         :: {ok, smelterl:manifest_seed()} | {error, term()}.
    ```

    **Error reasons:**
    - **`{invalid_build_info, Detail}`** - Smelterl build-info is missing or malformed.
    - **`{missing_target_arch_triplet, Product}`** - Required well-known export key absent from consolidated config.
    - **`{invalid_seed_input, Detail}`** - Repository/nugget/capability data cannot produce a valid deterministic seed.

- **`build_from_seed/4`**:

    Generate-stage function. Finalize manifest term from a plan-carried seed plus generate-time inputs:
    - Buildroot legal data (optional),
    - manifest base path for relativization,
    - runtime environment fields (`host_os`, `host_arch`, `smelterl_version`, `build_date`, optional buildroot version).
    Produces in-memory manifest term including integrity.

    **Processes:** §4.14.B Generate-stage.

    ```erlang
    -spec build_from_seed(Seed, BuildrootLegal, BasePath, RuntimeEnv) -> Result
        when Seed           :: smelterl:manifest_seed(),
             BuildrootLegal :: smelterl:br_legal_info() | undefined,
             BasePath       :: smelterl:file_path(),
             RuntimeEnv     :: map(),
             Result         :: {ok, term()} | {error, term()}.
    ```

    **Error reasons:**
    - **`{invalid_manifest_seed, Detail}`** - Seed missing required fields or has incompatible version.
    - **`{relativize_failed, Path, BasePath}`** - Path could not be relativized to manifest base.
    - **`{integrity_failed, Detail}`** - Canonicalization or digest generation failed.

- **`generate/3`**:

    Convenience wrapper: `build_from_seed/4` + `smelterl_file:format_term/1`.

    **Processes:** §4.14.B Generate-stage.

    ```erlang
    -spec generate(Seed, BuildrootLegal, BasePath) -> Result
        when Seed           :: smelterl:manifest_seed(),
             BuildrootLegal :: smelterl:br_legal_info() | undefined,
             BasePath       :: smelterl:file_path(),
             Result         :: {ok, iodata()} | {error, term()}.
    ```

    **Error reasons:** Same as `build_from_seed/4`.

- **`generate/4`**:

    Convenience wrapper: `generate/3` + `smelterl_file:write_term/2`.

    **Processes:** §4.14.B Generate-stage.

    ```erlang
    -spec generate(Seed, BuildrootLegal, BasePath, PathOrDevice) -> Result
        when Seed           :: smelterl:manifest_seed(),
             BuildrootLegal :: smelterl:br_legal_info() | undefined,
             BasePath       :: smelterl:file_path(),
             PathOrDevice   :: smelterl:file_path() | file:io_device(),
             Result         :: ok | {error, term()}.
    ```

    **Error reasons:** Same as `generate/3`; plus errors from `smelterl_file:write_term/2`.

**Testing highlights:**
- `prepare_seed/7`: deterministic tests for product/repository dedup/nuggets/auxiliary/capability/component seed structures; assert stable `RepoId` assignment and nugget->repo mapping.
- `build_from_seed/4`: tests for runtime-field injection, path relativization to manifest base, optional Buildroot package merge, optional legal references, and integrity hash generation.
- wrappers `generate/3` and `generate/4`: serialization/write behavior only (term file format, UTF-8, period-terminated), with heavy logic mocked or covered by core-stage tests.

#### 5.7.23 smelterl_file

**Role:**
Generic file and path utilities: path manipulation (resolve, relativize; use **filename:join** for segment joining) and **Erlang term file**  per [00_OVERVIEW.md](00_OVERVIEW.md#erlang-term-file-format-conventions). Used by any module that needs consistent term-file output (e.g. smelterl_gen_manifest, build_info), operates on path strings and optional metadata.

**Exported functions:**

- **`format_term/1`**:

    Serialize a term to Erlang term file format per [00_OVERVIEW.md](00_OVERVIEW.md#erlang-term-file-format-conventions): UTF-8 encoded output, optional `%% coding: utf-8` header, one term, period-terminated. Return iodata. Used by smelterl_gen_manifest:generate/7 and by write_term/2.

    ```erlang
    -spec format_term(Term) -> iodata()
        when Term :: term().
    ```

- **`write_term/2`**:

    Serialize term per the same conventions (via format_term/1) and write to path or device. Ensures encoding, header, and period are applied consistently for all generated term files (manifest, build_info, etc.). smelterl_gen_manifest uses format_term/1 for generate/7 and write_term/2 for generate/8.

    **Processes:** §4.14 (manifest write); any other term-file output.

    ```erlang
    -spec write_term(PathOrDevice, Term) -> Result
        when Term         :: term(),
             PathOrDevice :: smelterl:file_path() | file:io_device(),
             Result       :: ok | {error, term()}.
    ```

    **Error reasons:**
    - **`{open_failed, Path, Posix}`** - Could not open path for writing.
    - **`{write_failed, Detail}`** - I/O error while writing.

- **`resolve_path/2`**:

    Resolve Path against Base: when Path is relative, join Base and Path (equivalent to `filename:join/2` for that case); when Path is absolute, return Path. Result is normalized (resolve `.` and `..`, collapse redundant slashes)-beyond plain join.
    Example:
     - `resolve_path("nugget/license.txt", "/motherlode/repo")` -> `"/motherlode/repo/nugget/license.txt"`.
     - `resolve_path("/opt/nugget/license.txt", "/motherlode/repo")`-> `"/opt/nugget/license.txt"`.

    **Processes:** Used by multiple modules across §4.1, §4.11, §4.13, §4.14 (path resolution for motherlode, defconfig, legal export, manifest license paths).

    ```erlang
    -spec resolve_path(Path, Base) -> Result
        when Path   :: smelterl:file_path() | string(),
             Base   :: smelterl:file_path() | string(),
             Result :: smelterl:file_path().
    ```

- **`relativize/2`**:

    Make path relative to base; return path relative to base.

    ```erlang
    -spec relativize(Path, Base) -> Result
        when Path   :: smelterl:file_path(),
             Base   :: smelterl:file_path(),
             Result :: smelterl:file_path().
    ```

**Testing highlights:**
- Pure or mostly pure: test resolve (relative to base), relativize (path relative to base); use filename:join where segment joining is needed; use tmp dir or fixture paths; assert correct path strings and handling of absolute vs relative.
- **Term file:** Test format_term/1 and write_term/2: assert output includes `%% coding: utf-8` (or equivalent), term ends with `.`, and encoding is UTF-8; parse written file as Erlang term and assert round-trip.

#### 5.7.24 smelterl_vcs

**Role:**
Given a repository path, return VCS info (name, url, commit, describe, dirty) for use when building motherlode and when filling manifest repositories. Implemented so that **either** a precomputed `.alloy_repo_info` file **or** a real VCS checkout (e.g. `.git`) supplies the data; the rest of the code always calls `info/1` and receives `vcs_info() | undefined`, so the source is transparent.

**Lookup order for `info/1`:**

1. **`.alloy_repo_info`:** Starting from the given path, look for a file named `.alloy_repo_info` in that directory. If not found, walk up to the parent directory and repeat until the file is found or the filesystem root is reached. If found, parse the file per [Data Design - Alloy repository info file](01_DATA_DESIGN.md#alloy-repository-info-file-alloy_repo_info). If the file is valid (all required keys present with non-empty values), return a `vcs_info()` map with the same fields (name, url, commit, describe, dirty; `dirty` parsed from the string `true`/`false`). If the file is missing, invalid, or unreadable, continue to step 2.
2. **VCS checkout:** If the path (or a parent used when walking up) is a VCS checkout (e.g. contains `.git`), run the usual VCS commands and return `vcs_info()` (name, url, commit, describe, dirty). Otherwise return `undefined`.

This order ensures that when the orchestrator has written `.alloy_repo_info` at the repository root (e.g. before delegating to a Vagrant VM that has no `.git`), smelterl obtains correct provenance without touching git; when the file is absent, behaviour is unchanged (git is used when available).

**Exported functions:**

- **`info/1`**:

    Given a path (repository root or a subdirectory of it), return `vcs_info()` (name, url, commit, describe, dirty) if info can be obtained from `.alloy_repo_info` (in the path or a parent directory) or from a VCS checkout; otherwise `undefined`. Callers do not need to know which source was used.

    **Processes:** §4.1 (motherlode load: attach VCS to repos); §4.14 (manifest repositories: VCS info per repo); also generate_build_info.escript.

    ```erlang
    -spec info(Path) -> Result
        when Path   :: smelterl:file_path() | string(),
             Result :: smelterl:vcs_info() | undefined.
    ```

**Testing highlights:**
- Use a real git repo under test (e.g. tmp dir, git init, one commit) or mock os:cmd/port that runs git; assert returned shape (commit, describe, dirty) and that non-repo or missing dir returns empty or error.
- **`.alloy_repo_info`:** Create a directory with a valid `.alloy_repo_info` file (all five keys); call `info/1` with that path or a subpath; assert returned `vcs_info()` matches the file. Test with file in parent directory (path is subdir of repo root). Test invalid file (missing key, bad DIRTY value) falls back to git or undefined.
- Helper: create minimal git repo in tmp; assert describe and dirty (e.g. after touching a file).

#### 5.7.25 smelterl_log

**Role:**
Stderr logging; no shared state. Used by any module that reports errors or diagnostic messages (e.g. motherlode load, tree validation, CLI). Side effect only (writes to stderr).

**Exported functions:**

- **`error/2`**:

    Format and write error message to stderr (io:format(standard_error, Format, Args)).

    ```erlang
    -spec error(Fmt, Args) -> Result
        when Fmt    :: string(),
             Args   :: [term()],
             Result :: ok.
    ```

- **`warning/2`**:

    Format and write warning message to stderr.

    ```erlang
    -spec warning(Fmt, Args) -> Result
        when Fmt    :: string(),
             Args   :: [term()],
             Result :: ok.
    ```

- **`info/2`**:

    Format and write info message to stderr (when verbose/debug).

    ```erlang
    -spec info(Fmt, Args) -> Result
        when Fmt    :: string(),
             Args   :: [term()],
             Result :: ok.
    ```

- **`debug/2`**:

    Format and write debug message to stderr when debug mode enabled.

    ```erlang
    -spec debug(Fmt, Args) -> Result
        when Fmt    :: string(),
             Args   :: [term()],
             Result :: ok.
    ```

**Testing highlights:**
- Assert that log functions are called (capture side effect with meck or by redirecting standard_io); test format and args; avoid depending on exact stderr output in CI.
- Helper: capture group leader or mock io; assert one or two log calls with expected level and format string.

---

## Appendix A - Examples of Generated Files

This appendix shows example content for each file generated by smelterl. The process that produces each file is referenced at the start of its subsection.

---

### A.1 Example external.desc

**Generated by:** [§4.8 Generating external.desc](#48-generating-externaldesc).

Buildroot external tree descriptor: two lines (name, description). The name is the product identifier in uppercase; the description comes from the product nugget metadata.

```
name: ACME_APP
desc: Acme application BSP - Version 1.0.0
```

---

### A.2 Example Config.in

**Generated by:** [§4.9 Generating Config.in](#49-generating-configin).

Kconfig file that declares extra-config variables (so Buildroot accepts them as make parameters) and sources each nugget package’s Config.in in topological order.

```
# Generated by smelterl 1.0.0 - do not edit
# Product: acme_app 1.0.0
# Nuggets:
# - platform_imx6 1.0.1: NXP i.MX6 BSP
# - toolchain_ctng 2.3.4: Crosstool-NG Toolchain
# - acme_app 1.0.0: ACME Application BSP

## Extra Buildroot Envornment ##

config ALLOY_MOTHERLODE
	string
	option env="ALLOY_MOTHERLODE"

config ALLOY_CACHE_DIR
	string
	option env="ALLOY_CACHE_DIR"

config ALLOY_BUILD_DIR
	string
	option env="ALLOY_BUILD_DIR"

## Nugget Packages ##

# platform_imx6: NXP i.MX6 BSP
source "$(ALLOY_MOTHERLODE)/builtin/platform_imx6/buildroot/Config.in"
# toolchain_ctng: Crosstool-NG Toolchain
source "$(ALLOY_MOTHERLODE)/builtin/toolchain_ctng/buildroot/Config.in"
# acme_app: ACME Application BSP
source "$(ALLOY_MOTHERLODE)/acme_nuggets/acme_app/buildroot/Config.in"
```

---

### A.3 Example external.mk

**Generated by:** [§4.10 Generating external.mk](#410-generating-externalmk).

Top-level makefile that includes each nugget package’s `.mk` file. Paths use `$(ALLOY_MOTHERLODE)` so the tree is relocatable.

```
# Generated by smelterl 1.0.0 - do not edit
# Product: acme_app 1.0.0
# Nuggets:
# - platform_imx6 1.0.1: NXP i.MX6 BSP
# - toolchain_ctng 2.3.4: Crosstool-NG Toolchain
# - acme_app 1.0.0: ACME Application BSP

## Nugget Packages ##

# platform_imx6: NXP i.MX6 BSP
include $(ALLOY_MOTHERLODE)/builtin/platform_imx6/buildroot/platform_imx6.mk
# toolchain_ctng: Crosstool-NG Toolchain
include $(ALLOY_MOTHERLODE)/builtin/toolchain_ctng/buildroot/crosstool-ng.mk
# acme_app: ACME Application BSP
include $(ALLOY_MOTHERLODE)/acme_nuggets/acme_app/buildroot/acme_app.mk
```

---

### A.4 Example defconfig

**Generated by:** [§4.11 Generating defconfig](#411-generating-defconfig).

Merged defconfig from nugget fragments in topological order. Regular keys: last value wins; when a later nugget overrides a key, the previous nugget’s section can note it in a comment. Cumulative keys: path-type values are resolved to `${ALLOY_MOTHERLODE}/<nugget_path>/<value>`; non-path cumulative keys concatenate literal values (no path resolution). Template markers `[[KEY]]` are replaced by consolidated config and plan-carried extra-config. Target-local wrapper scripts (`$(BR2_EXTERNAL)/board/<TARGET_ID>/scripts/post-*.sh`) are always appended to the corresponding cumulative hook keys.

```ini
# Generated by smelterl 1.0.0 - do not edit
# Product: acme_app 1.0.0
# Nuggets:
# - platform_imx6 1.0.1: NXP i.MX6 BSP
# - toolchain_ctng 2.3.4: Crosstool-NG Toolchain
# - security_habv4 0.1.0: HAB v4 Security
# - acme_app 1.0.0: ACME Application BSP

## Nugget Configuration ##

# platform_imx6: NXP i.MX6 BSP
BR2_LINUX_KERNEL_USE_DEFCONFIG=y
BR2_LINUX_KERNEL_DEFCONFIG="imx_v6_v7"
BR2_TARGET_GENERIC_HOSTNAME="imx6-dev"
# BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y  # Overridden by system_grisp2

# system_grisp2 (system)
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y
BR2_PACKAGE_EUDEV=y
BR2_PACKAGE_UTIL_LINUX=y
# BR2_TARGET_GENERIC_HOSTNAME  # Overridden by acme_app

# toolchain_ctng: Crosstool-NG Toolchain
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_GCC_ENABLE_LTO=y
BR2_GCC_VERSION_10_X=y

# security_habv4: HAB v4 Security
BR2_PACKAGE_OPTEE_OS=y
BR2_ALLOY_SECURE_BOOT=y

# acme_app: ACME Application BSP
BR2_TARGET_GENERIC_HOSTNAME="acme_device"
BR2_TARGET_GENERIC_ISSUE="Acme Application 1.0"
BR2_PACKAGE_ACME_APP=y

## Cumulative Configuration ##

# platform_imx6, acme_app
BR2_ROOTFS_OVERLAY="${ALLOY_MOTHERLODE}/builtin/platform_imx6/rootfs-overlay ${ALLOY_MOTHERLODE}/acme_nuggets/acme_app/board/acme_app/rootfs-overlay"

# platform_imx6, auto target wrapper
BR2_ROOTFS_POST_BUILD_SCRIPT="${ALLOY_MOTHERLODE}/builtin/platform_imx6/scripts/custom-post-build.sh $(BR2_EXTERNAL)/board/acme_app/scripts/post-build.sh"

# acme_app, auto target wrapper
BR2_ROOTFS_POST_IMAGE_SCRIPT="$(BR2_EXTERNAL)/board/acme_app/scripts/post-image.sh"

# platform_imx6, security_habv4, acme_app
BR2_LINUX_KERNEL_EXT_CONFIG_FRAGMENT_FILES="${ALLOY_MOTHERLODE}/builtin/platform_imx6/configs/imx6_secure.kernel.fragment ${ALLOY_MOTHERLODE}/acme_nuggets/security_habv4/configs/habv4.kernel.fragment ${ALLOY_MOTHERLODE}/acme_nuggets/acme_app/configs/acme_app.kernel.fragment"

# system_grisp2, acme_app
BR2_ENABLE_LOCALE_WHITELIST="C en_US.utf8 de_DE.utf8"
```

---

### A.5 Example alloy_context.sh

**Generated by:** [§4.12 Generating alloy_context.sh](#412-generating-alloy_contextsh).

Shell script to be sourced by the build environment. It exports target identity (`ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, `ALLOY_AUXILIARY`), product/nugget metadata, consolidated config, capability flags, and defines arrays for nugget order, hooks, embed lists, and sdk output metadata. Paths use `${ALLOY_MOTHERLODE}`; that variable is not set by the script (caller sets it before sourcing).

```bash
# Generated by smelterl 1.0.0 - do not edit
# Product: acme_app 1.0.0
# Nuggets:
# - platform_imx6 1.0.1: NXP i.MX6 Platform
# - toolchain_ctng 2.3.4: Crosstool-NG Toolchain
# - security_habv4 0.1.0: HAB v4 Security
# - acme_app 1.0.0: ACME Application BSP

# ALLOY_MOTHERLODE is required
: "${ALLOY_MOTHERLODE:?ALLOY_MOTHERLODE must be set}"

## Product ##

export ALLOY_PRODUCT=acme_app
export ALLOY_IS_AUXILIARY=false
export ALLOY_AUXILIARY=""
export ALLOY_PRODUCT_NAME="Acme Application BSP"
export ALLOY_PRODUCT_DESC="Board support for Acme hardware"
export ALLOY_PRODUCT_VERSION="1.0.0"

## Firmware Variants (discovered from nugget metadata; plain always present) ##

export ALLOY_FIRMWARE_VARIANTS=("plain" "secure")

## Nugget Metadata ##

# platform_imx6: NXP i.MX6 BSP
export ALLOY_NUGGET_PLATFORM_IMX6=platform_imx6
export ALLOY_NUGGET_PLATFORM_IMX6_DIR="${ALLOY_MOTHERLODE}/grisp_alloy/platform_imx6"
export ALLOY_NUGGET_PLATFORM_IMX6_NAME="NXP i.MX6 Platform"
export ALLOY_NUGGET_PLATFORM_IMX6_DESC="i.MX6ULL/i.MX6UL BSP and rootfs"
export ALLOY_NUGGET_PLATFORM_IMX6_VERSION="1.0.0"
export ALLOY_NUGGET_PLATFORM_IMX6_FLAVOR=imx6ull

# toolchain_ctng: Crosstool-NG Toolchain
export ALLOY_NUGGET_TOOLCHAIN_CTNG=toolchain_ctng
export ALLOY_NUGGET_TOOLCHAIN_CTNG_DIR="${ALLOY_MOTHERLODE}/grisp_alloy/toolchain_ctng"
export ALLOY_NUGGET_TOOLCHAIN_CTNG_NAME="Crosstool-NG Toolchain"
export ALLOY_NUGGET_TOOLCHAIN_CTNG_DESC="External toolchain definition"
export ALLOY_NUGGET_TOOLCHAIN_CTNG_VERSION="1.0.0"

# security_habv4: HAB v4 Security
export ALLOY_NUGGET_SECURITY_HABV4=security_habv4
export ALLOY_NUGGET_SECURITY_HABV4_DIR="${ALLOY_MOTHERLODE}/acme_nuggets/security_habv4"
export ALLOY_NUGGET_SECURITY_HABV4_NAME="HAB v4 Security"
export ALLOY_NUGGET_SECURITY_HABV4_DESC="i.MX HAB v4 signing and CST"
export ALLOY_NUGGET_SECURITY_HABV4_VERSION="1.0.0"

# acme_app: ACME Application BSP
export ALLOY_NUGGET_ACME_APP=acme_app
export ALLOY_NUGGET_ACME_APP_DIR="${ALLOY_MOTHERLODE}/acme_nuggets/acme_app"
export ALLOY_NUGGET_ACME_APP_NAME="ACME Application BSP"
export ALLOY_NUGGET_ACME_APP_DESC="Board support for ACME hardware"
export ALLOY_NUGGET_ACME_APP_VERSION="1.0.0"

## Configuration ##

# platform_imx6: NXP i.MX6 BSP
export ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_KERNEL_VERSION="5.13.0"
export ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_DTB_NAME="imx6ull-acme-eval"
export ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_DEBUG_LEVEL="0"

# toolchain_ctng: Crosstool-NG Toolchain
export ALLOY_NUGGET_TOOLCHAIN_CTNG_CONFIG_TOOLCHAIN_TUPLE="armv7l-acme-linux-gnueabihf"

# acme_app: ACME Application BSP
export ALLOY_NUGGET_ACME_APP_CONFIG_KERNEL_VERSION="5.13.0"
export ALLOY_NUGGET_ACME_APP_CONFIG_DTB_NAME="imx6ull-acme-eval"
export ALLOY_NUGGET_ACME_APP_CONFIG_DEBUG_LEVEL="2"

# Consolidated configuration
export ALLOY_CONFIG_KERNEL_VERSION="5.13.0"
export ALLOY_CONFIG_DTB_NAME="imx6ull-acme-eval"
export ALLOY_CONFIG_TOOLCHAIN_TUPLE="armv7l-acme-linux-gnueabihf"
export ALLOY_CONFIG_DEBUG_LEVEL="2"

## Registries ##

# Nugget order
ALLOY_NUGGET_ORDER=("platform_imx6" "toolchain_ctng" "system_grisp2" "bootflow_grisp2_plain" "feature_squashfs" "feature_fwup" "feature_image" "acme_app")

# Hook post-build script chain (run in order after Buildroot rootfs build)
ALLOY_PRE_BUILD_HOOKS=()
ALLOY_POST_BUILD_HOOKS=("platform_imx6:scripts/post-build.sh" "acme_app:board/scripts/post-build.sh")
# Hook post-image script chain (run after image generation)
ALLOY_POST_IMAGE_HOOKS=("acme_app:board/scripts/post-image.sh")
ALLOY_POST_FAKEROOT_HOOKS=()
# Firmware-time hook arrays (variant-specific, dynamically generated)
ALLOY_PRE_FIRMWARE_HOOKS_PLAIN=("feature_squashfs:scripts/pre-firmware.sh")
ALLOY_FIRMWARE_BUILD_HOOKS_PLAIN=("bootflow_grisp2_plain:scripts/build_firmware.sh")
ALLOY_POST_FIRMWARE_HOOKS_PLAIN=("feature_fwup:scripts/post-firmware.sh" "feature_image:scripts/post-firmware.sh")

ALLOY_PRE_FIRMWARE_HOOKS_SECURE=("feature_squashfs:scripts/pre-firmware.sh")
ALLOY_FIRMWARE_BUILD_HOOKS_SECURE=("bootflow_grisp2_signed:scripts/build_firmware.sh")
ALLOY_POST_FIRMWARE_HOOKS_SECURE=("feature_fwup:scripts/post-firmware.sh" "feature_image:scripts/post-firmware.sh")

## Filesystem Priorities ##

ALLOY_FS_PRIORITIES_FRAGMENTS=("platform_imx6:${ALLOY_MOTHERLODE}/grisp_alloy/platform_imx6/board/fs.priorities")
export ALLOY_NUGGET_PLATFORM_IMX6_FS_PRIORITIES="${ALLOY_MOTHERLODE}/grisp_alloy/platform_imx6/board/fs.priorities"

## Embedding ##

# From Buildroot images (e.g. rootfs, kernel, DTB to embed in SDK)
ALLOY_EMBED_IMAGES=("rootfs/rootfs.ext4" "images/zImage" "images/imx6ull-acme-eval.dtb")
# From Buildroot host (e.g. host tarball)
ALLOY_EMBED_HOST=("host/sdk-host.tar")
# From nuggets (nugget_id:path_or_glob relative to nugget dir)
ALLOY_EMBED_NUGGETS=("platform_imx6:board/acme/overlay" "security_habv4:scripts/sign-image.sh")

## Outputs - declared artefacts (from nuggets' firmware_outputs metadata) ##

export ALLOY_FIRMWARE_OUTPUTS=("fwup_firmware" "image" "signed_boot_image")

# Per-output metadata
export ALLOY_FIRMWARE_OUT_FWUP_FIRMWARE_NUGGET=feature_fwup
export ALLOY_FIRMWARE_OUT_FWUP_FIRMWARE_SELECTABLE=true
export ALLOY_FIRMWARE_OUT_FWUP_FIRMWARE_DEFAULT=true
export ALLOY_FIRMWARE_OUT_FWUP_FIRMWARE_NAME="Firmware update package"
export ALLOY_FIRMWARE_OUT_FWUP_FIRMWARE_DESCRIPTION="fwup firmware update package for OTA deployment"

export ALLOY_FIRMWARE_OUT_IMAGE_NUGGET=feature_image
export ALLOY_FIRMWARE_OUT_IMAGE_SELECTABLE=true
export ALLOY_FIRMWARE_OUT_IMAGE_DEFAULT=false
export ALLOY_FIRMWARE_OUT_IMAGE_NAME="Raw disk image"
export ALLOY_FIRMWARE_OUT_IMAGE_DESCRIPTION="Complete disk image for initial flashing via dd. Not built by default; use --output-image to request it."

export ALLOY_FIRMWARE_OUT_SIGNED_BOOT_IMAGE_NUGGET=security_habv4
export ALLOY_FIRMWARE_OUT_SIGNED_BOOT_IMAGE_SELECTABLE=false
export ALLOY_FIRMWARE_OUT_SIGNED_BOOT_IMAGE_DEFAULT=false
export ALLOY_FIRMWARE_OUT_SIGNED_BOOT_IMAGE_NAME="Signed boot image"
export ALLOY_FIRMWARE_OUT_SIGNED_BOOT_IMAGE_DESCRIPTION="HABv4-signed boot image for secure boot"

## Selectable outputs - derived from ALLOY_FIRMWARE_OUT_<ID>_SELECTABLE
## The orchestrator reads ALLOY_FIRMWARE_OUT_<ID>_DEFAULT per entry to determine the default selection.

export ALLOY_OUTPUT_SELECTABLE=("fwup_firmware" "image")

## Firmware parameters - declared build-time parameters (from nuggets' firmware_parameters metadata) ##

export ALLOY_FIRMWARE_PARAMETERS=("serial_number" "batch_id" "factory_mode")

# Per-parameter metadata
export ALLOY_FIRMWARE_PARAM_SERIAL_NUMBER_TYPE=string
export ALLOY_FIRMWARE_PARAM_SERIAL_NUMBER_REQUIRED=true
export ALLOY_FIRMWARE_PARAM_SERIAL_NUMBER_NAME="Serial number"
export ALLOY_FIRMWARE_PARAM_SERIAL_NUMBER_DESCRIPTION="Unique device serial number for factory provisioning"

export ALLOY_FIRMWARE_PARAM_BATCH_ID_TYPE=string
export ALLOY_FIRMWARE_PARAM_BATCH_ID_REQUIRED=false
export ALLOY_FIRMWARE_PARAM_BATCH_ID_DEFAULT="default-batch"
export ALLOY_FIRMWARE_PARAM_BATCH_ID_NAME="Batch ID"
export ALLOY_FIRMWARE_PARAM_BATCH_ID_DESCRIPTION="Production batch identifier for traceability"

export ALLOY_FIRMWARE_PARAM_FACTORY_MODE_TYPE=boolean
export ALLOY_FIRMWARE_PARAM_FACTORY_MODE_REQUIRED=false
export ALLOY_FIRMWARE_PARAM_FACTORY_MODE_DEFAULT=false
export ALLOY_FIRMWARE_PARAM_FACTORY_MODE_NAME="Factory mode"
export ALLOY_FIRMWARE_PARAM_FACTORY_MODE_DESCRIPTION="Enable factory test mode with extended diagnostics"

## SDK outputs (target-declared metadata + main-context auxiliary consumption vars) ##

# sdk_outputs declared in the selected target tree (here: main)
export ALLOY_SDK_OUTPUTS=("debug_symbols")
export ALLOY_SDK_OUTPUT_DEBUG_SYMBOLS_NAME="Debug symbols archive"
export ALLOY_SDK_OUTPUT_DEBUG_SYMBOLS_DESCRIPTION="Main-target symbol bundle for offline debugging"

# Added by orchestrator in main context after auxiliary builds
export ALLOY_SDK_OUTPUT_ENCRYPTED_INITRAMFS_INITRAMFS="/build/sdk/auxiliary/encrypted_initramfs/outputs/initramfs/initramfs.cpio.gz"
# Optional uniqueness alias (present only when OUTPUT_ID is unique across auxiliaries)
export ALLOY_SDK_OUTPUT_INITRAMFS="/build/sdk/auxiliary/encrypted_initramfs/outputs/initramfs/initramfs.cpio.gz"

## Helper Functions ##
alloy_nugget_dir() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_DIR}"; }
alloy_nugget_name() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_NAME}"; }
alloy_nugget_desc() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_DESC}"; }
alloy_nugget_version() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_VERSION}"; }
alloy_nugget_flavor() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_FLAVOR}"; }
alloy_config() { local k="${1^^}"; k="${k//-/_}"; eval "echo \${ALLOY_CONFIG_${k}}"; }
alloy_sdk_output_from_aux() {
  local aux="${1^^}" out="${2^^}"
  aux="${aux//-/_}"; out="${out//-/_}"
  eval "echo \${ALLOY_SDK_OUTPUT_${aux}_${out}}"
}
alloy_sdk_output() {
  local out="${1^^}"
  out="${out//-/_}"
  eval "echo \${ALLOY_SDK_OUTPUT_${out}}"
}
export -f alloy_nugget_dir alloy_nugget_name alloy_nugget_desc alloy_nugget_version alloy_nugget_flavor alloy_config
export -f alloy_sdk_output_from_aux alloy_sdk_output
```

Full auxiliary context example (same template, selected target is an auxiliary):

```bash
# Generated by smelterl 1.0.0 - do not edit
# Target: encrypted_initramfs (auxiliary)
# Nuggets:
# - platform_imx6 1.0.1: NXP i.MX6 Platform
# - toolchain_ctng 2.3.4: Crosstool-NG Toolchain
# - auxiliary_initramfs 1.0.0: Auxiliary initramfs

# ALLOY_MOTHERLODE is required
: "${ALLOY_MOTHERLODE:?ALLOY_MOTHERLODE must be set}"

## Product ##

export ALLOY_PRODUCT=encrypted_initramfs
export ALLOY_IS_AUXILIARY=true
export ALLOY_AUXILIARY=encrypted_initramfs
export ALLOY_PRODUCT_NAME="Encrypted initramfs"
export ALLOY_PRODUCT_DESC="Auxiliary target for encrypted initramfs image"
export ALLOY_PRODUCT_VERSION="1.0.0"

## Nugget Metadata ##

export ALLOY_NUGGET_PLATFORM_IMX6=platform_imx6
export ALLOY_NUGGET_PLATFORM_IMX6_DIR="${ALLOY_MOTHERLODE}/grisp_alloy/platform_imx6"
export ALLOY_NUGGET_PLATFORM_IMX6_NAME="NXP i.MX6 Platform"
export ALLOY_NUGGET_PLATFORM_IMX6_VERSION="1.0.0"

export ALLOY_NUGGET_TOOLCHAIN_CTNG=toolchain_ctng
export ALLOY_NUGGET_TOOLCHAIN_CTNG_DIR="${ALLOY_MOTHERLODE}/grisp_alloy/toolchain_ctng"
export ALLOY_NUGGET_TOOLCHAIN_CTNG_NAME="Crosstool-NG Toolchain"
export ALLOY_NUGGET_TOOLCHAIN_CTNG_VERSION="1.0.0"

export ALLOY_NUGGET_AUXILIARY_INITRAMFS=auxiliary_initramfs
export ALLOY_NUGGET_AUXILIARY_INITRAMFS_DIR="${ALLOY_MOTHERLODE}/acme_nuggets/auxiliary_initramfs"
export ALLOY_NUGGET_AUXILIARY_INITRAMFS_NAME="Auxiliary initramfs"
export ALLOY_NUGGET_AUXILIARY_INITRAMFS_VERSION="1.0.0"

## Configuration ##

export ALLOY_NUGGET_AUXILIARY_INITRAMFS_CONFIG_INITRAMFS_COMPRESSION="gzip"
export ALLOY_NUGGET_AUXILIARY_INITRAMFS_CONFIG_INITRAMFS_ENCRYPTION="aes256"
export ALLOY_CONFIG_INITRAMFS_COMPRESSION="gzip"
export ALLOY_CONFIG_INITRAMFS_ENCRYPTION="aes256"

## Registries ##

ALLOY_NUGGET_ORDER=("platform_imx6" "toolchain_ctng" "auxiliary_initramfs")
ALLOY_PRE_BUILD_HOOKS=("auxiliary_initramfs:scripts/pre-build.sh")
ALLOY_POST_BUILD_HOOKS=("auxiliary_initramfs:scripts/post-build.sh")
ALLOY_POST_IMAGE_HOOKS=("auxiliary_initramfs:scripts/post-image.sh")
ALLOY_POST_FAKEROOT_HOOKS=()

## SDK outputs ##

# Auxiliary target declares what it produces for main-target consumption
export ALLOY_SDK_OUTPUTS=("initramfs")
export ALLOY_SDK_OUTPUT_INITRAMFS_NAME="Encrypted initramfs image"
export ALLOY_SDK_OUTPUT_INITRAMFS_DESCRIPTION="initramfs artefact consumed by main target"

## Helper Functions ##
alloy_nugget_dir() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_DIR}"; }
alloy_nugget_name() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_NAME}"; }
alloy_nugget_desc() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_DESC}"; }
alloy_nugget_version() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_VERSION}"; }
alloy_nugget_flavor() { local n="${1^^}"; n="${n//-/_}"; eval "echo \${ALLOY_NUGGET_${n}_FLAVOR}"; }
alloy_config() { local k="${1^^}"; k="${k//-/_}"; eval "echo \${ALLOY_CONFIG_${k}}"; }
export -f alloy_nugget_dir alloy_nugget_name alloy_nugget_desc alloy_nugget_version alloy_nugget_flavor alloy_config
```

---

### A.6 Example ALLOY_SDK_MANIFEST

**Generated by:** [§4.14 Generating Manifest](#414-generating-manifest).

Erlang term file (UTF-8, one term, period-terminated). Contains product, build_environment, repositories, nuggets (topological order), auxiliary_products, firmware capabilities, sdk_outputs, and optionally buildroot_packages, buildroot_host_packages, external_components, integrity.

```erlang
%% -*- coding: utf-8 -*-
{sdk_manifest, <<"1.0">>, [
    {product, <<"acme_app">>},
    {product_name, <<"Acme application BSP">>},
    {product_description, <<"Board support for Acme hardware">>},
    {product_version, <<"1.0.0">>},
    {target_arch, <<"arm-buildroot-linux-gnueabihf">>},
    {build_date, <<"2026-02-09T14:00:00Z">>},

    {build_environment, [
        {host_os, <<"Linux">>},
        {host_arch, <<"x86_64">>},
        {smelterl_version, <<"2.0.0">>},
        {smelterl_repository, grisp_alloy},
        {buildroot_version, <<"2024.02.1">>}
    ]},

    {repositories, [
        {grisp_alloy, [
            {name, <<"grisp_alloy">>},
            {url, <<"https://github.com/grisp/grisp_alloy.git">>},
            {commit, <<"abc123">>},
            {describe, <<"v2.0.0">>},
            {dirty, false}
        ]},
        {acme_nuggets, [
            {name, <<"acme_nuggets">>},
            {url, <<"https://github.com/acme/acme_nuggets.git">>},
            {commit, <<"def456">>},
            {describe, <<"v1.0.0">>},
            {dirty, false}
        ]}
    ]},

    {nuggets, [
        {nugget, <<"platform_imx6">>, [
            {version, <<"1.0.0">>},
            {repository, grisp_alloy},
            {category, platform},
            {flavor, imx6ull},
            {license, <<"Apache-2.0">>},
            {license_files, [<<"legal-info/alloy-licenses/platform_imx6-1.0.0/LICENSE">>]}
        ]},
        {nugget, <<"acme_app">>, [
            {version, <<"1.0.0">>},
            {repository, acme_nuggets},
            {category, feature},
            {license, <<"Proprietary">>},
            {license_files, [<<"legal-info/alloy-licenses/acme_app-1.0.0/LICENSE">>]}
        ]}
    ]},

    {auxiliary_products, [
        {auxiliary, encrypted_initramfs, [
            {root_nugget, auxiliary_initramfs},
            {constraints, [{flavor, encrypted}]}
        ]}
    ]},

    {capabilities, [
        {firmware_variants, [plain, secure]},
        {selectable_outputs, [fwup_firmware, image]}
    ]},

    {sdk_outputs, [
        {target, main, [
            {output, debug_symbols, [
                {nugget, feature_debug_symbols},
                {name, <<"Debug symbols archive">>},
                {description, <<"Main-target symbol bundle for offline debugging">>}
            ]}
        ]},
        {target, encrypted_initramfs, [
            {output, initramfs, [
                {nugget, auxiliary_initramfs},
                {name, <<"Encrypted initramfs image">>},
                {description, <<"Initramfs artefact consumed by main target">>}
            ]}
        ]}
    ]},

    {buildroot_packages, [
        {package, <<"busybox">>, [
            {version, <<"1.33.1">>},
            {license, <<"GPL-2.0">>},
            {license_files, [<<"legal-info/licenses/busybox-1.33.1/LICENSE">>]}
        ]},
        {package, <<"erlang">>, [
            {version, <<"24.0.5">>},
            {license, <<"Apache-2.0">>},
            {license_files, [<<"legal-info/licenses/erlang-24.0.5/LICENSE.txt">>]}
        ]}
    ]},

    {buildroot_host_packages, [
        {package, <<"host-gcc">>, [
            {version, <<"10.3.0">>},
            {license, <<"GPL-3.0">>},
            {license_files, [<<"legal-info/host-licenses/host-gcc-10.3.0/COPYING">>]}
        ]}
    ]},

    {external_components, [
        {component, crosstool_ng, [
            {name, <<"Crosstool-NG">>},
            {description, <<"Crosstool-NG toolchain">>},
            {version, <<"1.24.0">>},
            {license, <<"GPL-2.0">>},
            {license_files, [<<"legal-info/alloy-licenses/toolchain_ctng-1.0.0/crosstool_ng-1.24.0/COPYING">>]}
        ]}
    ]},

    {integrity, [
        {digest_algorithm, sha256},
        {canonical_form, basic_term_canon},
        {digest, <<"a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456">>}
    ]}
]}.
```

---

### A.7 Example alloy-manifest.csv

**Generated by:** [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export) (when `--export-legal` is set).

CSV listing nugget and external component metadata for the legal-info export tree. Paths are relative to the export directory. Nuggets and external components (e.g. Crosstool-NG from a toolchain nugget) share the same columns.

```csv
PACKAGE,VERSION,LICENSE,LICENSE FILES,SOURCE ARCHIVE,SOURCE SITE
platform_imx6,1.0.0,Apache-2.0,alloy-licenses/platform_imx6-1.0.0/LICENSE,,
acme_app,1.0.0,Proprietary,alloy-licenses/acme_app-1.0.0/LICENSE,,
crosstool_ng,1.24.0,GPL-2.0,alloy-licenses/toolchain_ctng-1.0.0/crosstool_ng-1.24.0/COPYING,,
```

---

### A.8 Example legal export README

**Generated by:** [§4.13 Collecting Legal Info and Export](#413-collecting-legal-info-and-export) (when `--export-legal` is set).

Top-level merged README in the legal-info export directory.

```
Grisp Alloy legal-info export (multi-target, merged)

This directory contains one merged legal-info dataset built from all targets
(main + auxiliaries). Buildroot package/license/source files are merged and
deduplicated in this tree, while Buildroot README text is preserved per input
target below.

--- From Buildroot (main) ---

Most of the packages that were used by Buildroot to produce the image files,
including Buildroot itself, have open-source licenses. It is your
responsibility to comply to the requirements of these licenses.
To make this easier for you, Buildroot collected in this directory some
material you may need to get it done.

This material is composed of the following items.
 * The scripts used to control compilation of the packages and the generation
   of image files, i.e. the Buildroot sources.
   Note: this has not been saved due to technical limitations, you must
   collect it manually.
 * The Buildroot configuration file; this has been saved in buildroot.config.
 * The toolchain (cross-compiler and related tools) used to generate all the
   compiled programs.
   Note: this may have not been saved due to technical limitations, you may
   need to collect it manually.
 * The original source code for target packages in the 'sources/'
   subdirectory and for host packages in the 'host-sources/' subdirectory
   (except for the non-redistributable packages, which have not been
   saved). Patches that were applied are also saved, along with a file
   named 'series' that lists the patches in the order they were
   applied. Patches are under the same license as the files that they
   modify in the original package.
   Note: Buildroot applies additional patches to Libtool scripts of
   autotools-based packages. These patches can be found under
   support/libtool in the Buildroot source and, due to technical
   limitations, are not saved with the package sources. You may need
   to collect them manually.
 * Two manifest files listing the configured packages and related
   information: 'manifest.csv' for target packages and 'host-manifest.csv'
   for host packages.
 * The license text of the packages, in the 'licenses/' and
   'host-licenses/' subdirectories for target and host packages
   respectively.

Due to technical limitations or lack of license definition in the package
makefile, some of the material listed above could not been saved, as the
following list details.

WARNING: the Buildroot source code has not been saved
WARNING: linux-headers-168ca6166204bd24090dffe5d4047d0c202e8d30: cannot save license (LINUX_HEADERS_LICENSE_FILES not defined)
WARNING: linux-168ca6166204bd24090dffe5d4047d0c202e8d30: cannot save license (LINUX_LICENSE_FILES not defined)

--- From Buildroot (auxiliary: encrypted_initramfs) ---

Most of the packages that were used by Buildroot to produce the image files,
including Buildroot itself, have open-source licenses. It is your
responsibility to comply to the requirements of these licenses.
To make this easier for you, Buildroot collected in this directory some
material you may need to get it done.

WARNING: arm-trusted-firmware-lf_v2.10_6.6.52-2.2.0_var01: cannot save license (ARM_TRUSTED_FIRMWARE_LICENSE_FILES not defined)

--- From Grisp Alloy ---

This directory contains legal and source material for the build:
- Buildroot: merged manifest.csv, host-manifest.csv, licenses/, host-licenses/, sources/, host-sources/
- Alloy nuggets and external components:
  - alloy-manifest.csv - list of nugget and external component packages with version and license
  - alloy-licenses/ - license texts for each nugget/component
  - alloy-sources/ - copies of nugget/external sources when enabled

Paths in alloy-manifest.csv are relative to this directory. See legal-info.sha256 for checksums.
```

---

## Appendix B - Format and Documentation

This appendix shows a single example Erlang module that illustrates every documentation requirement from [§5.3 Documentation](#53-documentation): SPDX/REUSE headers, `-moduledoc`, `-doc` and `-spec` on exported functions, documented user-defined types, and a behaviour with documented callbacks. The documentation text is written in a **meta** style (it describes what should be there as if it were real documentation). Function bodies are replaced by `...` to keep the example compact.

**Formatting and documentation rules:**

- **SPDX header:** Every source file starts with SPDX-FileCopyrightText and SPDX-License-Identifier (REUSE-compliant).
- **Module documentation:** `-moduledoc` before the first `-doc` or function; short description then optional detail; max line length 80.
- **Section order and headers:** Respect the following order; each non-empty section starts with the corresponding `%=== SECTION NAME ===` (padded to 80 characters) header; empty sections do not need headers:
  1. INCLUDES: For include_lib and include
  2. EXPORTS: For -export lines
  3. TYPES: For type specs and record definition
  4. MACROS: For -define lines
  5. BEHAVIOUR (callback definitions, only in behaviour modules)
  6. API FUNCTIONS
  7. BEHAVIOUR <NAME> CALLBACKS (callback implementations)
  8. INTERNAL FUNCTIONS
- **Pattern matching in function heads:** Prefer `Arg = #{key1 := A, key2 := B}` (assign then match) over `#{key1 := A, key2 := B} = Arg` in function argument pattern matching.
- **`maybe` for linear fallible flows:** Prefer Erlang `maybe` syntax when it
  materially improves readability of a linear sequence of fallible steps (for
  example repeated `{ok, Value}` / `{error, Reason}` propagation). Do not use
  it mechanically when an explicit `case` expresses the branching intent more
  clearly.
- **Nested `case` depth:** Treat more than three nested `case` expressions in
  one flow as a readability smell. When the depth would exceed that threshold,
  refactor to `maybe`, helper functions, or both, unless the explicit nested
  branching is still demonstrably clearer.
- **Guard indentation:** When a function head wraps and the `when` guard moves to
  the next line, indent `when` by two spaces so it reads as a continuation of
  the function head.
  Preferred:
  ```erlang
  normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, license, Value)
    when is_binary(Value) ->
  ```
  Not preferred:
  ```erlang
  normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, license, Value)
  when is_binary(Value) ->
  ```
- **Exports:** One `-export([...])` per function name per line (repeat `-export` for each function); use a single `-export([name/1, name/2])` when one function has multiple arities.
- No spec or documentation needed for bahviour callback implementations.

**Example:**

```erlang
%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(example).
-moduledoc """
Module documentation: short one-line description of the module purpose.

Detailed description of the module with maximum line length 80 characters.
Explain what the module does, when to use it, and how it fits with other
modules. Add a second paragraph if needed. Keep `-moduledoc` before the
first `-doc` or function.
""".

-behaviour(used_behaviour).

%=== INCLUDES ==================================================================

-include_lib("kernel/include/logger.hrl").
-include("my_include.hrl").


%=== EXPORTS ===================================================================

% API functions
-export([run/1]).
-export([parse/2]).
% Behaviour used_behaviour callbacks
-export([init/1]).
-export([terminate/1]).


%=== TYPES =====================================================================

-doc """
User-defined type: describe the type and when to use it.

For opaque types, document the abstract representation and valid values.
Refer to other types with `t:result/0` if needed.
""".
-type options() :: #{key => value}.

-doc "Another type used as argument or return; single line if possible."
-type result() :: ok | {error, term()}.


%=== MACROS ====================================================================

-define(SIMPLE_CONSTANT, 123) % Describe the constant
-define(COMPLEX_MAP_CONSTANT, #{
    foo => #{
        field1 => <<"value1">>,
        field2 => <<"value2">>
    },
    bar => [<<"if">>, <<"it">>, <<"fits,">>, <<"single">>, <<"line">>],
    buz => [
      <<"Long list of values that do not fit in a single line">>,
      <<"So instead, put one per line">>
    ]
}).
-define(FUNCTION_ENCAPSULATION_FOR_ASSERTS(A, B), (fun(A, B) ->
    Temp1 = some_function(A),
    Temp2 = other_function(B),
    ?assertEqual(Temp1, Temp2)
)()).

%=== BEHAVIOUR =================================================================

-doc """
Short description of what the callback does.

Detail when it is called, what the options map may contain, and what
the implementation must return. Keep in sync with the behaviour spec.
Refer to other callbacks with `c:parse/2` if needed.
""".
-callback run(options()) -> result().

-doc "Use single line for simple documentation"
-callback parse(binary(), options()) -> {ok, term()} | {error, term()}.


%=== API FUNCTIONS =============================================================

-doc "For basic documentation, use single lines".
-spec run(options()) -> result().
run(_Opts) -> ...

-doc """
Short description of run/1: what it does in one line.

Optional second paragraph with details, examples in code blocks, or
notes. The first paragraph is used as summary by tools. Keep `-spec`
and `-doc` in sync when changing the contract.
Detail arguments (Binary, Options), return value, and possible errors.
Use Markdown (e.g. **bold**, `code`) as needed. Max line length 80.
""".
-spec parse(binary(), options()) -> {ok, term()} | {error, term()}.
parse(_Binary, _Opts = #{foo := _Foo, bar := _Bar}) -> ...


%=== BEHAVIOUR used_behaviour CALLBACKS ========================================

init(_Opts) -> ...

terminate(_Reason) -> ...


%=== INTERNAL FUNCTIONS ========================================================

internal_fun1(Foo, Bar) -> ...

%-- function group separator ---------------------------------------------------

internal_fun2(Foo, Bar) -> ...
```
