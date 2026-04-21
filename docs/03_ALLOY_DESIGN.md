# GRiSP Alloy - Alloy Orchestrator Design

**Version:** 2.0 (Draft)  
**Status:** Design Document  
**Last Updated:** 2026-02-13

This document specifies the **alloy** bash orchestrator: its role, responsibilities, commands, processes, and implementation. It covers how alloy uses smelterl and Buildroot, SDK and project generation, Vagrant abstraction, security pack concepts, and all operational details. Data formats (nugget metadata, manifest) are defined in [Data Design](01_DATA_DESIGN.md). Smelterl behavior and CLI are defined in [Smelterl Design](02_SMELTERL_DESIGN.md), the local checkout [smelterl/docs/DESIGN.md](../smelterl/docs/DESIGN.md), and the web view [github.com/grisp/smelterl/docs/DESIGN.md](https://github.com/grisp/smelterl/blob/main/docs/DESIGN.md). For overview and glossary see [Overview](00_OVERVIEW.md).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Responsibilities](#2-responsibilities)
3. [Commands](#3-commands)
   - [alloy build sdk](#31-alloy-build-sdk)
   - [alloy build project](#32-alloy-build-project)
   - [alloy build firmware](#33-alloy-build-firmware)
   - [alloy prepare sdk](#34-alloy-prepare-sdk)
   - [alloy serve artefacts](#35-alloy-serve-artefacts)
   - [alloy grispio](#36-alloy-grispio)
4. [Concepts](#4-concepts)
   - [Self-Contained SDK](#41-self-contained-sdk)
   - [Projects](#42-projects)
   - [Firmware](#43-firmware)
   - [Nugget System](#44-nugget-system)
     - [Bootflows](#bootflows)
   - [Integration with Buildroot](#45-integration-with-buildroot)
   - [Security Pack](#46-security-pack)
   - [Output Selection](#47-output-selection)
   - [Firmware Build Parameters](#48-firmware-build-parameters)
   - [Logging and Debugging](#49-logging-and-debugging)
   - [Error Handling](#410-error-handling)
   - [Caching](#411-caching)
   - [Reproducibility and Traceability](#412-reproducibility-and-traceability)
   - [Testing](#413-testing)
   - [Plugin System](#414-plugin-system)
5. [Processes](#5-processes)
   - [Command Dispatch Flow](#51-command-dispatch-flow)
   - [Mode Detection](#52-mode-detection)
   - [Vagrant Abstraction Flow](#53-vagrant-abstraction-flow)
   - [Nugget Staging Flow](#54-nugget-staging-flow)
   - [SDK Build Flow](#55-sdk-build-flow)
   - [Project Build Flow](#56-project-build-flow)
   - [Firmware Build Flow](#57-firmware-build-flow)
   - [Hook Invocation Flow](#58-hook-invocation-flow)
   - [Firmware Hook API](#59-firmware-hook-api)
   - [SDK Packing Flow](#510-sdk-packing-flow)
   - [Smelterl Management Flow](#511-smelterl-management-flow)
6. [Nugget Categories](#6-nugget-categories)
   - [Category Overview](#61-category-overview)
   - [builder](#62-builder)
   - [toolchain](#63-toolchain)
   - [platform](#64-platform)
   - [system](#65-system)
   - [bootflow](#66-bootflow)
   - [feature](#67-feature)
   - [Function Export Convention and Contracts](#68-function-export-convention-and-contracts)
7. [Builtin Nuggets](#7-builtin-nuggets)
   - [builder_buildroot](#71-builderbuildroot)
   - [toolchain_ctng](#72-toolchainctng)
   - [common_base](#73-commonbase)
   - [bootflow_grisp2_plain](#74-bootflowgrisp2plain)
   - [bootflow_imx8_fit_plain](#75-bootflowimx8fitplain)
   - [platform_imx6](#76-platformimx6)
   - [platform_imx8](#77-platformimx8)
   - [system_grisp2](#78-systemgrisp2)
   - [system_kontron-albl-imx8mm](#79-systemkontron-albl-imx8mm)
   - [feature_erlinit](#710-featureerlinit)
   - [feature_erlang](#711-featureerlang)
   - [feature_elixir](#712-featureelixir)
   - [feature_squashfs](#713-featuresquashfs)
   - [feature_fwup](#714-featurefwup)
   - [feature_image](#715-featureimage)
   - [feature_grisp_updater](#716-featuregrispupdater)
   - [grisp2_vanilla](#717-grisp2vanilla)
   - [kontron-albl-imx8mm_vanilla](#718-kontron-albl-imx8mmvanilla)
8. [Implementation Details](#8-implementation-details)
   - [Project Structure](#81-project-structure)
   - [General Principles](#82-general-principles)
   - [Documentation](#83-documentation)
   - [Testing](#84-testing)
   - [Shared Variables and Data Structures](#85-shared-variables-and-data-structures)
   - [Shared Utilities](#86-shared-utilities)
   - [Commands Handling](#87-commands-handling)
   - [Project Plugins](#88-project-plugins)
   - [Buildroot Integration](#89-buildroot-integration)

---

## 1. Overview

### 1.1 Role

**alloy** is the main entry point and bash orchestrator for the GRiSP Alloy build system. It:

- Parses user commands and dispatches them to the appropriate command script.
- Detects operating mode (repository or SDK) and adapts available commands accordingly.
- Manages the Vagrant VM lifecycle for cross-platform builds (macOS, Windows).
- Stages nugget sources (builtin, local, VCS) into a motherlode directory.
- Invokes smelterl for code generation and Buildroot for compilation.
- Runs hook scripts in topological nugget order at each build stage.
- Packs the SDK from build artefacts, context, and manifest.
- Builds Erlang/Elixir project releases using SDK host tools.
- Assembles firmware images from SDK base images and project artefacts.

The orchestrator does **not** parse nugget metadata, resolve dependencies, or generate Buildroot configuration. Those tasks belong to smelterl (see [Smelterl Design](02_SMELTERL_DESIGN.md), the local checkout [smelterl/docs/DESIGN.md](../smelterl/docs/DESIGN.md), and the web view [github.com/grisp/smelterl/docs/DESIGN.md](https://github.com/grisp/smelterl/blob/main/docs/DESIGN.md)).

### 1.2 Invocation Model

- **Entry point:** Single script `alloy` at repository root (or SDK root).
- **Command syntax:** `alloy [OPTIONS] verb [noun] [ARGS]`.
- **Dual mode:** The same `alloy` script operates in **repository mode** (full command set) and **SDK mode** (firmware, project, prepare, serve, and grispio commands). Mode is detected by the presence of `ALLOY_SDK_MANIFEST` in the script's directory.
- **Platform:** Bash (4.0+). On non-Linux hosts (macOS, Windows), the orchestrator delegates to a Vagrant-managed Linux VM.

### 1.3 Design Principles

1. **Bash-first orchestration** - alloy handles orchestration, Vagrant, mode detection, and command dispatch.
2. **Erlang for code generation** - smelterl focuses on parsing, dependency resolution, and file generation.
3. **Single script, dual modes** - Same alloy script in repository (full commands) and SDK (project/firmware/serve/grispio subset).
4. **Buildroot as build engine** - Orchestrate from above; treat Buildroot as lower-level build system.
5. **Target-scoped context generation** - One generated context per build target (`alloy_context.sh`) gives hooks and pack step target-local order, paths, metadata, and identity (`ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, `ALLOY_AUXILIARY`). Nugget metadata is parsed once at plan time; later stages consume generated contexts.
6. **Self-contained, relocatable SDK** - Images, host tools, scripts, context; no grisp_alloy checkout required. The SDK can be unpacked anywhere and automatically relocates hardcoded paths on first use.
7. **Composability and reusability** - Nuggets are composable building blocks; mix and match platform, system, and features; reuse across products.
8. **Separation of concerns** - Clear boundaries: orchestration (alloy), code generation (smelterl), build execution (Buildroot).
9. **Security abstraction** - Security-related material (keys, certs, signing) lives in an external security pack or remote service; not in the repo or SDK; enables secure CI and customer-specific deployment.
10. **Manifest and legal-info for SBOM** - Manifest and legal-information tracking meet modern SBOM and compliance requirements.
11. **Main-target firmware ownership** - Auxiliary targets are integrated SDK-build targets that produce Buildroot-driven artefacts (`sdk_outputs`) for main-target consumption. They do not participate in firmware build orchestration, firmware output declaration, firmware parameter contracts, or SDK embedding control arrays.

---

## 2. Responsibilities

Each responsibility is implemented by one or more processes; the section reference points to the detailed process description.

| # | Responsibility | Summary | See |
|---|----------------|---------|-----|
| 1 | **Argument parsing** | Parse command-line flags, validate required arguments, accumulate repeatable flags (`-n`). | [§5.1](#51-command-dispatch-flow) |
| 2 | **Mode detection** | Check for `ALLOY_SDK_MANIFEST` in script directory; select repository or SDK mode. | [§5.2](#52-mode-detection) |
| 3 | **Command validation** | Verify command is valid for current mode; provide helpful error if unavailable. | [§5.1](#51-command-dispatch-flow) |
| 4 | **Command dispatch** | Map `verb noun` to `scripts/commands/verb-noun.sh`; pass arguments and environment. | [§5.1](#51-command-dispatch-flow) |
| 5 | **Vagrant orchestration** | Detect host OS; on non-Linux: start VM, sync external paths, rewrite arguments, delegate to VM. | [§5.3](#53-vagrant-abstraction-flow) |
| 6 | **Nugget staging** | Stage all nugget sources (builtin, local, VCS) into the motherlode directory before calling smelterl. | [§5.4](#54-nugget-staging-flow) |
| 7 | **Smelterl management** | Build or cache the smelterl escript; invoke it with correct parameters. | [§5.11](#511-smelterl-management-flow) |
| 8 | **SDK build** | Orchestrate plan + per-target generate/build loop (auxiliaries first, then main), merge legal-info, regenerate main manifest, and pack SDK. | [§5.5](#55-sdk-build-flow) |
| 9 | **Project build** | Build an Erlang/Elixir project release using SDK host tools and sysroot. | [§5.6](#56-project-build-flow) |
| 10 | **Firmware build** | Assemble firmware from SDK base images, one or more project artefacts, and optional security pack. | [§5.7](#57-firmware-build-flow) |
| 11 | **Hook invocation** | Source target context, apply scope-filtered hook chains, execute per-nugget hooks with per-target environment, and enforce pre_build once-per-nugget semantics across targets. | [§5.8](#58-hook-invocation-flow) |
| 12 | **SDK packing** | Embed images, host tools, and nugget content into SDK tarball using embed lists from alloy_context.sh. | [§5.10](#510-sdk-packing-flow) |
| 13 | **Error handling** | Trap errors, clean up on exit, provide context-aware error messages, exit with appropriate status codes. | [§4.10](#410-error-handling) |
| 14 | **Environment setup** | Source common utilities, set `ALLOY_*` environment variables, validate required dependencies. | [§5.1](#51-command-dispatch-flow) |

---

## 3. Commands

### 3.0 Command Syntax

```
alloy [GLOBAL_OPTIONS] verb [noun] [COMMAND_OPTIONS] [ARGUMENTS]
```

**Global options** (apply to all commands):

| Option | Description |
|--------|-------------|
| `--debug[=N]` / `-d[N]` / `-ddd` | Set log verbosity level. `--debug` or `-d` alone implies level 1 (informational progress). `--debug=2` or `-dd` shows developer debug messages. `--debug=3`, `-d3`, or `-ddd` additionally enables Buildroot verbose output. Sets `ALLOY_DEBUG=N`. See [§4.9](#49-logging-and-debugging). |
| `--trace` | Enable bash `set -x` execution tracing in the orchestrator and all hook wrappers. Sets `ALLOY_TRACE=true`. Independent of `--debug` - can be combined freely with any debug level. Intended for debugging the bash scripts themselves. See [§4.9](#49-logging-and-debugging). |
| `--dev` | Development mode; sets `ALLOY_DEV_MODE=true`. Enables behaviours useful during alloy/smelterl development (e.g. force rebuild of smelterl from source). |
| `--force-vagrant` / `-F` | Force Vagrant VM usage even on Linux. |
| `--keep-vagrant` / `-K` | Keep Vagrant VM running after command completes. |
| `--provision` / `-P` | Force Vagrant VM provisioning before command execution (system upgrade, dependency installation, cache disk mount). This is **not** required for picking up changes to `scripts/` or `nuggets/` during development - repository files are synced into the VM for each delegated command (see [§5.3](#53-vagrant-abstraction-flow)). |
| `--init-deps` | Explicitly initialize required repository dependencies before command execution. Currently used by repository-mode `alloy build sdk` to initialize the local `smelterl/` checkout via `git submodule sync --recursive smelterl` followed by `git submodule update --init --recursive smelterl` when it is missing. Never implied automatically. |
| `--forward-env PATTERN` | Forward additional environment variables to the Vagrant VM. `PATTERN` is a variable name (e.g. `SIGNING_TOKEN`) or a prefix pattern ending with `*` (e.g. `SIGNING_*`). Repeatable. Only effective when the build runs in a Vagrant VM; ignored on native Linux builds. Can also be specified via the `ALLOY_FORWARD_ENV` environment variable (comma-separated list of patterns). **Forwarded variables are passed as-is** (no path rewriting). They must **not** be used for paths to files or directories that must exist in the VM: such paths are not synced and will not be available in the Vagrant VM. For the security pack path use `--security-pack` or `ALLOY_SECURITY_PACK`, which are synced and rewritten. See [§5.3 Vagrant Abstraction Flow - Environment Forwarding](#environment-forwarding). |
| `--help` / `-h` | Display help for the command. |
| `--version` / `-v` | Display alloy version. |

**Global option placement:** The canonical form shows global options before the verb, but the parser accepts them at any position on the command line - before, between, or after the verb and its arguments. Since global option names are distinct from all command-specific option names, there is no parsing ambiguity. For example, the following are all equivalent:

```bash
alloy -d build firmware my_project
alloy build -d firmware my_project
alloy build firmware -d my_project
alloy build firmware my_project -d
```

The alloy entry-point script extracts all recognized global options in a first pass, regardless of position, then dispatches the remaining tokens to the command handler.

**Mode-dependent command availability:**

| Command | Repository Mode | SDK Mode |
|---------|:--------------:|:--------:|
| `alloy build sdk` | Yes | No |
| `alloy build project` | Yes | Yes |
| `alloy build firmware` | Yes | Yes |
| `alloy prepare sdk` | No | Yes |
| `alloy serve artefacts` | Yes | Yes |
| `alloy grispio` | Yes | Yes |

### Artefact Resolution

Several commands accept an artefact reference (project tarball, SDK tarball, update package) as a positional argument or option value. Alloy resolves these references using a common algorithm:

1. **Explicit path** - If the value ends with a known artefact extension (`.tgz`, `.tar.gz`, `.tar`) and the file exists, use it directly.
2. **Prefix match** - If the value contains no `/` and does not end with an artefact extension, treat it as a name prefix. The artefact type prefix is prepended to form the glob pattern: `${ARTEFACT_SUBDIR}/${TYPE_PREFIX}-${PREFIX}*`. This accounts for the fact that all artefact filenames begin with their type prefix:
   - **Project:** `project-${PREFIX}*.tgz` in `${ALLOY_ARTEFACT_DIR}/projects/`
   - **SDK:** `sdk-${PREFIX}*.tar.gz` in `${ALLOY_ARTEFACT_DIR}/sdk/`
   - **GRiSP update package:** `${PREFIX}*.tar` in `${ALLOY_ARTEFACT_DIR}/grisp_updates/` (no type prefix - the subdirectory provides disambiguation)
3. **Manifest filtering** - When the prefix match returns multiple candidates, filter them using metadata from the artefact's embedded manifest. For project artefacts, the target architecture from the project manifest is compared against the current SDK's `target_arch`; only artefacts built for the matching target are retained.
4. **Final selection:**
   - **One match** (after filtering): Use it.
   - **Zero matches:** Fail with `"No artefact matching prefix '<PREFIX>'. Build the project/SDK first."`.
   - **Multiple matches:** Fail listing the candidates: `"Multiple artefacts found for prefix '<PREFIX>': ..."`.
5. **Path with `/`** - If the value contains `/` but does not end with an artefact extension, fail with a usage error (ambiguous: not a prefix, not a tarball).

**Examples** (given artefact naming conventions `project-NAME-VERSION-ARCH.tgz`, `sdk-PRODUCT-VERSION-HOST_ARCH.tar.gz`, `PROJECT-PROJECT_VERSION-PRODUCT-PRODUCT_VERSION.tar` for GRiSP updates):

| User types | Glob executed |
|---|---|
| `alloy build firmware my_app` | `artefacts/projects/project-my_app*.tgz` |
| `alloy build firmware --sdk grisp2_vanilla` | `artefacts/sdk/sdk-grisp2_vanilla*.tar.gz` |
| `alloy grispio upload my_app` | `artefacts/grisp_updates/my_app*.tar` |

---

### 3.1 alloy build sdk

**Purpose:** Generate a self-contained SDK from nuggets using smelterl and Buildroot.

**Availability:** Repository mode only.

**Synopsis:**

```bash
alloy build sdk PRODUCT_NUGGET [OPTIONS]
```

`PRODUCT_NUGGET` (required): Identifier of the top-level (product) nugget to build.

**Options:**

| Option | Description |
|--------|-------------|
| `-n PATH`, `--nugget-path PATH` | Additional nugget source (local directory or VCS URL). Repeatable. |
| `--allow-dirty` | Allow nugget sources that are VCS checkouts (local or cloned) to have uncommitted changes. By default, the orchestrator fails if a repository has a dirty working tree. Use for local development when you have uncommitted edits. Can also be enabled by setting `ALLOY_ALLOW_DIRTY=true`; the command-line flag takes precedence. See [Nugget staging](#54-nugget-staging-flow) (VCS URL / working tree cleanliness). |
| `--include-sources` | Include redistributable source code in SDK legal-info. |
| `--clean` / `-c` | Remove the entire build directory before building, redoing everything from scratch (Buildroot, smelterl generation, hooks). |
| `--clean-package PKG` | Remove a specific Buildroot package and rebuild it. Use when a single package needs rebuilding without cleaning the whole tree. This option is intentionally long-only so `-c` remains reserved for `--clean`. **Expert option:** Buildroot does not track inter-package dependencies, so incorrect use may produce inconsistent results. |

**Nugget path specification:**

Nuggets can be loaded from multiple sources:

1. **Default path** - `./nuggets` relative to repository root (always included).
2. **Environment variable** - `ALLOY_NUGGET_PATH` (colon-separated, cumulative).
3. **Command-line flags** - `-n` / `--nugget-path` (repeatable, in order specified).

**Path types:**

- **Local directories:** Absolute or relative filesystem paths.
- **VCS URLs:** `git+https://...#ref` or `git+ssh://...#ref`. The `#ref` fragment specifies the branch, tag, or commit to check out.

**Examples:**

```bash
# Build SDK for the grisp2_vanilla product using only builtin nuggets
alloy build sdk grisp2_vanilla

# Build SDK with additional local and VCS nugget sources
alloy build sdk acme_product \
    -n ../acme_nuggets \
    -n git+https://example.com/security.git#v1.2.3

# Build SDK in development mode (rebuilds smelterl from source)
alloy --dev build sdk grisp2_vanilla

# Build SDK with source in legal-info
alloy build sdk grisp2_vanilla --include-sources
```

**Output:** SDK tarball in `artefacts/sdk/sdk-PRODUCT-VERSION-HOST_ARCH.tar.gz`.

**Execution model:** Internally this command runs a multi-target pipeline:
1. `smelterl plan` once.
2. `smelterl generate` + Buildroot build for each auxiliary target.
3. `smelterl generate` + Buildroot build for main target.
4. merged legal-info + final main manifest generation.

---

### 3.2 alloy build project

**Purpose:** Build an Erlang or Elixir project release using SDK host tools. No smelterl or Buildroot involved.

**Availability:** Repository mode and SDK mode.

**Synopsis:**

```bash
alloy build project PROJECT_SOURCE [OPTIONS]
```

**Required arguments:**

| Argument | Description |
|----------|-------------|
| `PROJECT_SOURCE` | Path to project directory or VCS URL (`git+https://...#ref`). |

**Optional options:**

| Option | Description |
|--------|-------------|
| `--allow-dirty` | Allow the project source (when it is a local directory that is a VCS checkout or when cloned from a VCS URL) to have uncommitted changes. By default, the orchestrator fails if the repository has a dirty working tree. Use for local development when you have uncommitted edits. Can also be enabled by setting `ALLOY_ALLOW_DIRTY=true`; the command-line flag takes precedence. |
| `--profile PROFILE` | Build profile name. Repeatable for multi-profile builds (e.g. `--profile prod --profile debug`). Default: `default`. |
| `--sdk SDK_REF` | SDK reference: name prefix, path to `.tar.gz`, or directory. Resolved via [artefact resolution](#artefact-resolution) (repository mode only; required if no SDK installed). |

**Examples:**

```bash
# From SDK directory: build project from local path
./alloy build project /path/to/my_app

# From SDK directory: build project from VCS URL
./alloy build project git+https://github.com/acme/my_app.git#v1.0.0

# From repository: build project using SDK prefix (resolves in artefacts/sdk/)
./alloy build project /path/to/my_app --sdk grisp2_vanilla

# From repository: build project using explicit SDK path
./alloy build project /path/to/my_app --sdk artefacts/sdk/sdk-grisp2_vanilla-1.0.0-x86_64.tar.gz
```

**Output:** Project tarball in `artefacts/projects/project-NAME-VERSION-TARGET-ARCH.tgz`.

---

### 3.3 alloy build firmware

**Purpose:** Assemble a flashable firmware image from SDK base images and one or more project artefacts.

Auxiliary products are **not built** by this command. It consumes auxiliary-produced artefacts that were already built and embedded during `alloy build sdk`.
Firmware capability variables (`ALLOY_FIRMWARE_*`, `ALLOY_OUTPUT_SELECTABLE`) come from the SDK's main-target context; auxiliary contexts do not provide them.

**Availability:** Repository mode and SDK mode.

**Synopsis:**

```
alloy build firmware [OPTIONS] PROJECT_SPEC [PROJECT_SPEC ...] [OPTIONS]

PROJECT_SPEC = PROJECT_REF [--name NAME]
```

One or more `PROJECT_SPEC` entries are required. Each `PROJECT_SPEC` consists of a `PROJECT_REF` (positional argument) optionally followed by `--name NAME` to assign an installation name to that project. Command options can appear anywhere on the command line - before, between, or after project specs - because they are parsed independently from project specs (see [Argument Parsing](#argument-parsing) below). Alloy-level global options (`--debug`, `--force-vagrant`, etc.) are also accepted anywhere, as described in [§3.0](#30-command-syntax).

**Project arguments:**

| Argument | Description |
|----------|-------------|
| `PROJECT_REF` | Project artefact reference: name prefix, path to `.tgz`, or VCS URL. Resolved via [artefact resolution](#artefact-resolution). One or more required. Each `PROJECT_REF` is a positional argument; the parser collects them left-to-right. |

**Per-project options:**

These options are positionally bound to the immediately preceding `PROJECT_REF`.

| Option | Description |
|--------|-------------|
| `--name NAME` | Assign an installation name to the preceding `PROJECT_REF`. The project's OTP release is staged under `/srv/alloy/<NAME>/` in the firmware rootfs. If omitted, defaults to the project's `id` field from its `ALLOY_PROJECT_MANIFEST`. When multiple projects are included, each must have a distinct name (whether explicit or defaulted). |

**Command options:**

These options apply to the firmware build as a whole and can appear at any position on the command line.

| Option | Description |
|--------|-------------|
| `--sdk SDK_REF` | SDK reference: name prefix, path to `.tar.gz`, or directory. Resolved via [artefact resolution](#artefact-resolution) (repository mode only). |
| `--variant VARIANT` | Select a firmware variant by name (e.g. `plain`, `secure`, `encrypted`). Available variants are discovered from nuggets' `firmware_variant` metadata and listed in `ALLOY_FIRMWARE_VARIANTS`. Defaults to `plain`. Use `--list-variants` to see available variants. |
| `--list-variants` | List available firmware variants for this SDK and exit. |
| `--security-pack PATH` / `-S PATH` | Path to the security pack - either a path to an executable file or a path to a directory containing a `secpack` executable at its root (see [§4.6 Security Pack](#46-security-pack)). The orchestrator resolves, validates, and canonicalizes the pack using `security_resolve_pack` from `security_utils.sh` (see [§8.6.14](#8614-securityutilssh)), then exports `ALLOY_SECURITY_PACK` as the resolved absolute path to the entry point executable. Overrides the `ALLOY_SECURITY_PACK` environment variable if both are set. When the build runs via Vagrant, the security pack is automatically synced to the VM (see [§5.3](#53-vagrant-abstraction-flow)). Required when the selected variant's hooks need security services (signing, credential export). If a security pack is expected but not provided, the hooks will fail with a clear error via `alloy_security_available` checks. Implementation-specific configuration (API tokens, service URLs, HSM PINs) is provided via environment variables set by the user before invoking alloy. |
| `--overlay PATH` | Additional overlay directory to merge into the firmware rootfs. Repeatable. Merged after project overlays and security pack overlay (see [Overlay Consolidation](#overlay-consolidation)). Each `--overlay` directory may contain an `ALLOY_FS_PRIORITIES` file at its root for [filesystem priority consolidation](#filesystem-priority-consolidation). |
| `--firmware-name NAME` | Override the firmware name recorded in the firmware manifest and used in artefact naming. Does **not** replace project metadata (app name/version, release name/version) in the embedded project manifests. |
| `--firmware-version VERSION` | Override the firmware version recorded in the firmware manifest and used in artefact naming. Does **not** replace project metadata in the embedded project manifests. |
| `--param KEY=VALUE` | Inject a build-time parameter. Validated against declared `firmware_parameters` metadata (type, required). Exported to hooks as `ALLOY_PARAM_<KEY>` (key uppercased). Repeatable. Recorded in the firmware manifest `{parameters, [...]}` section. Use `--list-params` to see available parameters. See [Firmware Build Parameters](#48-firmware-build-parameters). |
| `--list-params` | List available firmware build parameters for this SDK and exit. Shows parameter ID, type, required/optional, default (if any), display name, and description. |
| `--output-<ID>` | Enable a specific firmware output (e.g. `--output-fwup-firmware`, `--output-image`). If no `--output-*` flags are given, only default outputs are built (selectable outputs with `{default, true}`). If one or more `--output-*` flags are given, only the specified outputs are built. Available outputs (including opt-in ones) are derived from nuggets' `firmware_outputs` metadata where `selectable` is `true`; use `--list-outputs` to see them. |
| `--list-outputs` | List available firmware output types for this SDK and exit. Shows output ID, display name, description, and whether the output is built by default (`[default]`) or must be explicitly requested (`[opt-in]`). |
| `--include-legal[=VALUE]` | Include SDK legal-info in the firmware rootfs so the firmware manifest's `license_files` paths can resolve on device (SBOM/compliance). Controlled by the **orchestrator** (this command). If **omitted**: do not include legal-info (default). If **`--include-legal`** (no value): include as a compressed tarball. If **`--include-legal=VALUE`**: `tarball` – single compressed tarball at root of rootfs (e.g. `/legal-info.tgz`), same content as SDK `legal-info/`; extracting to `/` yields `/legal-info/` so manifest paths resolve; `full` – copy the full `legal-info/` tree at `/legal-info/` (larger); `none` – do not include. See [Legal-info in firmware](#legal-info-in-firmware). |

**Capability validation:** `--variant` and `--output-*` are validated against capabilities declared by nuggets in the SDK (variants from `firmware_variant`, outputs from `firmware_outputs`). Use `--list-variants` and `--list-outputs` to inspect what the SDK supports. Implementation details of discovery and validation are defined in [§4.7 Output Selection](#47-output-selection) and [§5.7 Firmware Build Flow](#57-firmware-build-flow).


#### Argument Parsing

The `alloy build firmware` command uses a **two-phase argument parsing** strategy that cleanly separates command options from project specifications. (Alloy-level global options like `--debug` and `--force-vagrant` are already extracted by the alloy entry-point script before the command handler runs - see [§3.0](#30-command-syntax).)

**Phase 1 - Command option extraction:** The argument parser scans the command's token stream and extracts all recognized command options (`--sdk`, `--variant`, `--overlay`, `--firmware-name`, `--firmware-version`, `--param`, `--security-pack`, `--output-*`, `--include-legal`, `--list-*`) and their values regardless of their position. Command options are consumed and removed from the token stream. All remaining tokens (positional arguments and `--name` with its value) are collected into a positional token list.

**Phase 2 - Project spec parsing:** The positional token list is parsed left-to-right to build the project list:

1. A bare token (not starting with `--`) is a `PROJECT_REF`. It starts a new project entry with that reference. The project's name is initially unset.
2. `--name NAME` assigns `NAME` to the most recently seen project entry. If `--name` appears before any `PROJECT_REF`, abort with: `"--name must be used after a project reference"`. If `--name` appears twice for the same project, the last value wins.
3. Any other `--*` token in the positional list is an error: `"Unknown option: <token>"`.
4. After parsing, for each project without an explicit `--name`, the name is defaulted to the project's `id` field read from its `ALLOY_PROJECT_MANIFEST` (after artefact resolution and manifest validation).
5. Validate uniqueness: if two projects resolve to the same installation name (whether explicit or defaulted), abort with a clear error.

If no `PROJECT_REF` is found after phase 2 and no `--list-*` flag was specified, abort with: `"Missing project artefact reference"`.

**Examples:**

```bash
# Single project (common case) - simplest form
./alloy build firmware my_project

# Single project with global options - options can go anywhere
./alloy build firmware my_project --output-fwup-firmware
./alloy build firmware --variant secure my_project --security-pack ../keys

# Multi-project with explicit installation names
./alloy build firmware my_project --name alpha other_project --name beta

# Multi-project with defaulted names (names come from project manifests)
./alloy build firmware projA projB

# Multi-project with mix of explicit and defaulted names
./alloy build firmware projA --name alpha projB

# Command options interleaved with project specs (all equivalent)
./alloy build firmware --variant secure projA --name alpha projB --overlay ../extra
./alloy build firmware projA --name alpha --variant secure projB --overlay ../extra
./alloy build firmware projA --name alpha projB --variant secure --overlay ../extra

# Firmware with custom overlay directory
./alloy build firmware my_project --overlay ../my_overlay

# Firmware with multiple overlays (merged in order)
./alloy build firmware my_project \
    --overlay ../base_overlay \
    --overlay ../customer_overlay

# Firmware with secure boot variant and security pack
./alloy build firmware my_project \
    --variant secure \
    --security-pack ../acme_security_pack

# List available firmware variants, output types, and parameters
./alloy build firmware --list-variants
./alloy build firmware --list-outputs
./alloy build firmware --list-params

# From repository: firmware using SDK prefix (resolves in artefacts/sdk/)
./alloy build firmware --sdk grisp2_vanilla my_app

# From repository: firmware using explicit SDK path
./alloy build firmware \
    --sdk artefacts/sdk/sdk-grisp2_vanilla-1.0.0-x86_64.tar.gz \
    my_app

# Firmware with device-specific parameters
./alloy build firmware my_project \
    --param serial_number=SN-2026-00042 \
    --param batch_id=B2026-02

# Firmware with explicit name/version (independent from project metadata)
./alloy build firmware projA projB \
    --firmware-name toto \
    --firmware-version 1.0
```

#### Legal-info in firmware

**Who controls it:** The **orchestrator** (`alloy build firmware`) controls whether legal-info is included in the firmware. The SDK already contains `legal-info/` (from the SDK build); the firmware build decides whether to copy that content into the firmware rootfs and in what form.

**Option:** `--include-legal[=VALUE]`. If the flag is **omitted**: do not include legal-info in the firmware (default). If **`--include-legal`** is given without a value: include legal-info as a compressed tarball. If **`--include-legal=VALUE`** is given: `tarball` (compressed tarball, e.g. `/legal-info.tgz`), `full` (full `legal-info/` tree at `/legal-info/`; paths resolve directly; larger image), or `none` (do not include). The orchestrator adds the chosen artefact to the rootfs overlay during the [Firmware Build Flow](#57-firmware-build-flow) (e.g. after generating the manifest), so it appears in the final image at a fixed path (e.g. `/legal-info.tgz` or `/legal-info/`). The firmware manifest's `license_files` paths are relative to the manifest; with the manifest at `/ALLOY_FIRMWARE_MANIFEST`, extracting `legal-info.tgz` to `/` or including the full tree at `/legal-info/` makes those paths resolve on device.

**Output:** Firmware artefacts in `artefacts/firmware/` and `artefacts/images/` depending on the selected outputs. By default, all outputs supported by the SDK are produced. The default firmware filename is derived from the firmware name/version and the product/version (e.g. `firmware-<name>-<version>-<product>-<product_version>.fw`). When `--firmware-name` and/or `--firmware-version` are provided, the overrides are used both in the firmware manifest (`firmware_name`, `firmware_version`) and in the artefact filename.

---

### 3.4 alloy prepare sdk

**Purpose:** Explicitly perform text-based path relocation on a relocated SDK. This is needed when the SDK directory is not writable by the user running `alloy build` commands (e.g. system-wide installations under `/opt/`).

**Availability:** SDK mode only.

**Synopsis:**

```bash
alloy prepare sdk
```

**Behavior:**

1. Read the recorded path from `.alloy_sdk_dir` (either the placeholder `@@ALLOY_SDK_DIR@@` for a fresh SDK, or a real path from a previous relocation).
2. Compare with the current SDK root path.
3. If paths differ: replace the recorded path with the current SDK root path in all files listed in `.alloy_relocation_manifest` via `sed`, then update `.alloy_sdk_dir` to the current real path.
4. If paths match: print `"SDK is already prepared."` and exit successfully.

**Notes:**
- This command modifies files inside the SDK directory. If the SDK is installed system-wide, run with elevated privileges: `sudo alloy prepare sdk`.
- For most users who unpack the SDK into a writable directory, this command is never needed - relocation happens automatically on the first `alloy build` invocation.
- The command is idempotent: running it multiple times is safe.

**Examples:**

```bash
# After extracting SDK to a system directory
sudo tar -xf sdk-grisp2_vanilla-1.0.0-x86_64.tar.gz -C /opt/grisp/
sudo /opt/grisp/sdk-grisp2_vanilla-1.0.0-x86_64/alloy prepare sdk
```

---

### 3.5 alloy serve artefacts

**Purpose:** Start an HTTP/HTTPS server that serves built artefacts (SDKs, project packages, firmware images) for download by devices or CI pipelines.

**Availability:** Repository mode and SDK mode.

**Synopsis:**

```bash
alloy serve artefacts [OPTIONS]
```

The server supports three TLS modes:

1. **Plain HTTP** (default) - No TLS. Suitable for local development and trusted networks.
2. **Manual TLS** (`--tls --cert FILE --key FILE`) - User provides their own certificate and private key files. Optionally, `--ca-cert FILE` enables mutual TLS (mTLS) with client certificate verification.
3. **Security-pack TLS** (`--security-pack PATH`) - TLS materials are obtained from the security pack using the security pack command contract (see [§4.6 Security Pack Command Contract](#security-pack-command-contract)). `PATH` is a path to either an executable file or a directory containing a `secpack` executable at its root. The pack is resolved and validated using `security_resolve_pack` from `security_utils.sh` (see [§8.6.14](#8614-securityutilssh)). Can also be specified via the `ALLOY_SECURITY_PACK` environment variable (`--security-pack` overrides it). If the pack supports the `tls` capability and can export both server credentials and device CA material, mTLS is automatically enabled. If only server credentials are available, one-way TLS is used.

**Options:**

| Option | Description |
|--------|-------------|
| `--port PORT` | Port to listen on. Default: `8080` (HTTP) or `8443` (HTTPS when `--tls` or `--security-pack` is used). |
| `--tls` | Enable HTTPS with manually provided certificate and key (requires `--cert` and `--key`). |
| `--cert FILE` | TLS certificate file or certificate chain (required with `--tls`). |
| `--key FILE` | TLS private key file (required with `--tls`). |
| `--ca-cert FILE` | CA certificate bundle for client verification (optional with `--tls`; enables mTLS). |
| `--security-pack PATH` / `-S PATH` | Path to the security pack - either an executable file or a directory containing a `secpack` executable at its root. Enables HTTPS using TLS materials obtained from the pack. Mutually exclusive with `--tls`. Can also be specified via the `ALLOY_SECURITY_PACK` environment variable (`--security-pack` overrides it). See [§4.6 Security Pack](#46-security-pack) for the pack contract. |
| `--identity IDENTITY` | Server identity name when using `--security-pack` (optional; defaults to `artefact-server`). Passed as the `--identity` argument to the pack's `tls` command. Ignored without `--security-pack`. |
| `--verbose` | Log each HTTP request (method, status code, path). |

**Security-pack TLS mode details:**

When a security pack is specified (via `--security-pack` or `ALLOY_SECURITY_PACK` environment variable), the artefact-server escript interacts with the security pack directly using the security pack command contract (see [§4.6](#security-pack-command-contract)):

1. Resolves and validates the security pack using the same `security_resolve_pack` logic described in [§8.6.14](#8614-securityutilssh) (the escript performs equivalent validation from Erlang).
2. Calls `secpack capabilities` to check for `tls`. If not supported (exit 2), fails with:
   `"The security pack does not support TLS material export (tls capability not available). To serve over HTTPS, provide your own certificate and key with --tls --cert FILE --key FILE, or omit TLS options to use plain HTTP."`
3. Calls `secpack tls --role server --identity IDENTITY --type key --output TMPDIR/server.key.pem` and `secpack tls --role server --identity IDENTITY --type chain --output TMPDIR/server.chain.pem` to obtain the server key and certificate chain (`IDENTITY` defaults to `artefact-server`). If either call returns exit 3 (key not exportable), fails with:
   `"The security pack cannot export the TLS server private key (likely HSM-backed). To serve over HTTPS, provide your own certificate and key with --tls --cert FILE --key FILE, or omit TLS options to use plain HTTP."`
4. Attempts to obtain a device CA bundle for mTLS: calls `secpack tls --role ca --identity device --type ca --output TMPDIR/device-ca.pem`. If this succeeds, enables mTLS. If it returns exit 2 (not supported), proceeds with one-way TLS only.
5. Starts the HTTPS listener using the obtained TLS materials.

**Examples:**

```bash
# Plain HTTP on default port
alloy serve artefacts

# Manual HTTPS with own cert/key
alloy serve artefacts --tls --cert server.pem --key server.key

# Manual HTTPS with mTLS (client certificate required)
alloy serve artefacts --tls --cert server.pem --key server.key --ca-cert devices-ca.pem

# HTTPS via security pack (mTLS if pack supports device CA export)
alloy serve artefacts --security-pack ../my_security_pack

# HTTPS via security pack specified by environment variable
ALLOY_SECURITY_PACK=acme-secpack alloy serve artefacts

# HTTPS via security pack with custom server identity and port
alloy serve artefacts --security-pack ../my_security_pack --identity prod-server --port 4443
```

**Implementation:** The `serve-artefacts.sh` script validates options and invokes the `scripts/tools/artefact-server` Erlang escript. The escript is a self-contained HTTP/HTTPS server that serves files from the artefact directory. When a security pack is configured, the escript interacts with the security pack directly using the security pack command contract (see [§4.6](#security-pack-command-contract)). See [§8.7.6 serve-artefacts.sh](#876-serve-artefactssh) and [§8.7.8 Scripts Tools - artefact-server](#878-scripts-tools) for implementation details.

---

### 3.6 alloy grispio

**Purpose:** Interface to the grisp.io cloud platform for software update package management and device deployment.

**Availability:** Repository mode and SDK mode.

**Software update packages:** The grisp.io platform manages **software update packages** - `.tar` archives containing firmware data and a `MANIFEST` file at their root. These packages are produced during the firmware build by the `feature_grisp_updater` nugget's `post_firmware` hook (see [§7.15](#715-featuregrispupdater)) and stored in `${ALLOY_ARTEFACT_DIR}/grisp_updates/`. They are distinct from raw firmware images (`.fw`, `.img`); grispio commands operate exclusively on update packages.

**Common options (apply to all actions):**

| Option | Description |
|--------|-------------|
| `-H HOST`, `--host HOST` | grisp.io host. Default: `app.grisp.io:443`. Can also be set via the `GRISPIO_HOST` environment variable. The command-line option takes precedence over the environment variable. |
| `--no-tls-verify` | Disable TLS certificate verification (useful for development/testing against local instances). |

**Update package resolution:** The `upload` action accepts a `PACKAGE_REF` that refers to a **local** update package. It uses the same [artefact resolution](#artefact-resolution) mechanism as other alloy commands. The `grispio.sh` orchestrator script resolves the reference to a full filesystem path before invoking the grispio escript - the escript only receives a resolved absolute path. Resolution searches `${ALLOY_ARTEFACT_DIR}/updates/`:

- **Name prefix:** `alloy grispio upload my_app` - globbed against `artefacts/grisp_updates/my_app*`. If multiple matches, fail with candidate list.
- **Explicit path:** `alloy grispio upload artefacts/grisp_updates/my_app-1.2.0-grisp2_vanilla-1.0.0.tar` - used directly.

For `delete`, `deploy`, and other remote actions, `PACKAGE_REF` is a **remote** identifier (the package name as known by grisp.io) and is passed through to the escript without local resolution.

#### Actions

**`alloy grispio authenticate [OPTIONS]`**

Authenticate with grisp.io and store an encrypted API token locally.

```bash
alloy grispio authenticate
alloy grispio authenticate --host my-grisp-instance.example.com:443
```

The user is prompted to enter their grisp.io credentials. Upon successful authentication, the API token is encrypted and stored locally (see Token Storage below).

No additional options beyond the common options.

**`alloy grispio upload [OPTIONS] PACKAGE_REF`**

Upload a software update package to grisp.io.

```bash
alloy grispio upload PACKAGE_REF
```

| Argument / Option | Description |
|---|---|
| `PACKAGE_REF` | Update package reference: name prefix or explicit path to a `.tar` update package. Resolved by the orchestrator to a full path before passing to the escript. Required. |

The orchestrator validates that the resolved file is a `.tar` archive containing a `MANIFEST` at its root before uploading.

```bash
# Upload by name prefix (resolved from artefacts/grisp_updates/)
alloy grispio upload my_app

# Upload by explicit path
alloy grispio upload ./artefacts/grisp_updates/my_app-1.2.0-grisp2_vanilla-1.0.0.tar

# Upload to a custom grisp.io instance
alloy grispio upload my_app --host staging.grisp.io:443
```

**`alloy grispio delete [OPTIONS] PACKAGE_REF`**

Delete a software update package from grisp.io. The `PACKAGE_REF` identifies the package on the remote platform (same identifier used during upload).

```bash
alloy grispio delete PACKAGE_REF
```

| Argument / Option | Description |
|---|---|
| `PACKAGE_REF` | Package identifier on grisp.io. Required. |

```bash
alloy grispio delete my_app-1.2.0-grisp2_vanilla-1.0.0
```

**`alloy grispio deploy [OPTIONS] PACKAGE_REF`**

Deploy a software update package to a device or device group on grisp.io.

```bash
alloy grispio deploy PACKAGE_REF --device DEVICE
```

| Argument / Option | Description |
|---|---|
| `PACKAGE_REF` | Package identifier on grisp.io (as uploaded). Required. |
| `-D DEVICE`, `--device DEVICE` | Target device identifier or device group. Required. |

```bash
# Deploy to a single device
alloy grispio deploy my_app-1.2.0-grisp2_vanilla-1.0.0 \
    --device my-device-serial

# Deploy to a device using GRISPIO_HOST env var
GRISPIO_HOST=staging.grisp.io:443 \
    alloy grispio deploy my_app --device test-device-001
```

**`alloy grispio validate [OPTIONS]`**

Validate a deployed software update on a device (confirm that the device is running the expected firmware and it is healthy).

```bash
alloy grispio validate --device DEVICE
```

| Argument / Option | Description |
|---|---|
| `-D DEVICE`, `--device DEVICE` | Target device identifier. Required. |

```bash
alloy grispio validate --device my-device-serial
```

**`alloy grispio reboot [OPTIONS]`**

Reboot a device via grisp.io.

```bash
alloy grispio reboot --device DEVICE
```

| Argument / Option | Description |
|---|---|
| `-D DEVICE`, `--device DEVICE` | Target device identifier. Required. |

```bash
alloy grispio reboot --device my-device-serial
```

#### Token Storage

The API token is encrypted with AES-256-CBC (PBKDF2 key derivation) and stored at:
- **Repository mode:** `${REPO_ROOT}/.grispio.token`
- **SDK mode:** `~/.grisp_alloy/.grispio.token`

The user is prompted for a passphrase on first use. Subsequent commands decrypt the token automatically (prompting for the passphrase again if needed).

---

## 4. Concepts

### 4.1 Self-Contained SDK

An SDK is a self-contained kit that includes everything needed to build firmware images without a grisp_alloy repository checkout. It is produced by `alloy build sdk` and consumed by `alloy build project` and `alloy build firmware`.

**Contents:**

- `alloy` - Orchestrator script (SDK mode).
- `ALLOY_SDK_MANIFEST` - Build manifest with product, target architecture, nuggets, auxiliary products, firmware capabilities, sdk output declarations, and Buildroot package/license metadata.
- `legal-info/` - Buildroot legal-info plus alloy-manifest.csv, alloy-licenses/, and optionally alloy-sources/.
- `scripts/` - Command scripts, utilities, build context, plugins, the artefact server, and the manifest-tool escript. Test scripts are excluded.
- `images/` - Buildroot output images (rootfs, kernel, bootloader) explicitly embedded by nuggets.
- `host/` - Host tools explicitly embedded by nuggets, plus auto-resolved shared libraries. This includes the cross-compilation toolchain (from `toolchain_ctng`), the host Erlang/OTP runtime and rebar3 (from `feature_erlang`), optional Elixir tools (from `feature_elixir`), and other host tools like fwup, mksquashfs.
- `staging/` - Buildroot's target staging directory (complete copy). Contains all target packages installed with `STAGING=YES`, including cross-compiled target Erlang/OTP (`staging/usr/lib/erlang/`). The target ERTS and OTP applications from this directory are bundled into project releases at build time (via `--include-erts` / `--system_libs`). The staging directory is copied unconditionally (not selectively embedded) because it acts as a coherent target sysroot - selectively picking files would require tracking transitive C library dependencies, which Buildroot already manages. See [§5.10 SDK Packing Flow](#510-sdk-packing-flow).
- `motherlode/` - Embedded nugget content (scripts, templates, keys, priority fragments), same structure as the build-time motherlode. Includes both explicitly declared `{nugget, ...}` embed entries and auto-embedded files (firmware-time hook scripts and `fs_priorities` fragments).
- `auxiliary/` - Auxiliary target outputs embedded during SDK build under `auxiliary/<AUX_ID>/outputs/<OUTPUT_ID>/...`, consumable by main-target hooks and firmware-time flows.

**Not included:** Buildroot source, build output directory, br2_external, smelterl, script tests, build logs. Note: the cross-compilation toolchain and host Erlang/OTP are always embedded (by `toolchain_ctng` and `feature_erlang` respectively), so the SDK requires no language runtimes or cross-compilers on the host system.

**Mode detection:** The presence of `ALLOY_SDK_MANIFEST` in the alloy script's directory indicates SDK mode. In SDK mode, only `build project`, `build firmware`, `prepare sdk`, `serve artefacts`, and `grispio` commands are available.

**Relocatability:** SDKs work at any filesystem location without a fixed install path. ELF binaries use `$ORIGIN`-relative RPATHs (set by Buildroot's `fix-rpath` during the build, verified at pack time across all embedded trees). Text-based paths (`.la`, `.pc`, GCC specs, wrapper scripts, nugget-embedded scripts) contain a canonical placeholder (`@@ALLOY_SDK_DIR@@`) in the distributed tarball - the builder's real filesystem path is never shipped. The placeholder is replaced with the actual SDK root path automatically on first use. All script-level paths are resolved at runtime relative to the alloy script's location. Embedded symlinks use relative paths. Artefact output goes to a writable location (default `~/.grisp_alloy/artefacts/`).

**Automatic relocation flow:** When any SDK command is invoked (`build project`, `build firmware`, etc.), the orchestrator checks whether the SDK needs relocation by comparing `.alloy_sdk_dir` against the current SDK root path. For a freshly unpacked SDK, `.alloy_sdk_dir` contains the placeholder `@@ALLOY_SDK_DIR@@`, so relocation always triggers on first use:

1. **Paths match** - No action needed; proceed normally (this is the case after a successful relocation).
2. **Paths differ (or placeholder), SDK is writable** - Perform text-based path fixup automatically. Log: `Relocating SDK to <new-path>...`. Update `.alloy_sdk_dir`. Proceed normally.
3. **Paths differ (or placeholder), SDK is not writable** - Abort with a clear error message:
   ```
   Error: SDK needs relocation but the SDK directory is not writable.
   Run: alloy prepare sdk
   Or, if the SDK is installed system-wide: sudo alloy prepare sdk
   ```

**`alloy prepare sdk` command** (SDK mode only): Explicitly triggers the text-based path relocation. Useful when:
- The SDK is installed in a system-wide location writable only by root.
- The user wants to pre-relocate before making the SDK read-only.
- Automation/CI scripts need an explicit preparation step.

See [Data Design - Relocatability](01_DATA_DESIGN.md#relocatability) for the technical details of the two-phase relocation strategy and [§5.10 SDK Packing Flow](#510-sdk-packing-flow) for the pack-time steps.

See [Data Design - SDK Directory](01_DATA_DESIGN.md#sdk-directory) for the complete directory structure.

### 4.2 Projects

A project is an Erlang or Elixir application (typically an OTP release) that is compiled and packaged using SDK host tools. Projects are built by `alloy build project` and consumed by `alloy build firmware`.

**Project sources:**

- **Local directory:** Path to a directory containing `rebar.config` (Erlang) or `mix.exs` (Elixir).
- **VCS URL:** `git+https://...#ref` - cloned and built.

**Project type detection:** The orchestrator uses a plugin system (see [§4.14 Plugin System](#414-plugin-system)) to detect the project type. Plugins inspect the project directory (e.g. presence of `mix.exs` for Elixir, `rebar.config` for Erlang) and provide type-specific build, info extraction, and staging functions.

**Cross-compilation environment:** Before invoking any project plugin, the orchestrator sets up the full cross-compilation environment via `env_utils.sh` (see [§8.6.7](#867-envutilssh)). This gives every plugin access to the cross-compiler toolchain (`CC`, `CXX`, `CFLAGS`, `LDFLAGS`), the host Erlang/OTP runtime (`HOST_ERLANG`, `HOST_REBAR3`), the target Erlang/OTP runtime (`TARGET_ERLANG`), and all other variables needed for building native extensions and OTP releases for the target architecture. Plugins do not set up the cross-compilation environment themselves - they receive it fully configured.

**Project artefact contents:**

- `ALLOY_PROJECT_MANIFEST` - Project manifest (Erlang term file: release name, release version, main OTP application name and version, type, profile, SDK provenance, dependencies). See [Data Design - Project Manifest](01_DATA_DESIGN.md#project-manifest-specification).
- `release/` - OTP release directory, written by the plugin into the orchestrator-provided staging path during `project_build`. Staged under `/srv/alloy/<name>/` during firmware build. It may optionally contain `ALLOY_FS_PRIORITIES` at its root (paths relative to the release root). At firmware build time the orchestrator relocates those paths with base `/srv/alloy/<name>/`. See [Data Design - Filesystem Priority](01_DATA_DESIGN.md#filesystem-priority-specification).
- `overlay/` - Optional project-specific rootfs overlay directory, written by the plugin into the orchestrator-provided staging path during `project_build`. The plugin may leave it empty. Merged into the firmware rootfs overlay during firmware build (after nugget overlays, before security pack overlay). Use for project-specific files that live outside the release tree (e.g. `etc/my_app.conf`, `etc/systemd/system/my_app.service`). The overlay directory may contain `ALLOY_FS_PRIORITIES` at its root; paths in that file are relative to the overlay root (rootfs `/`). During firmware build, the orchestrator relocates each path by prepending `/`. See [Data Design - Filesystem Priority](01_DATA_DESIGN.md#filesystem-priority-specification).

### 4.3 Firmware

Firmware is a flashable image assembled from the SDK's base images, host tools, and one or more project artefacts. Built by `alloy build firmware`.

**Main vs auxiliary responsibility boundary:** The firmware flow is owned by the main product context. Auxiliary products contribute prebuilt SDK artefacts via `sdk_outputs` during SDK build, then stop. They do not run firmware-time hooks, do not contribute firmware parameters or firmware outputs at runtime, and do not control SDK embed lists.

**Firmware assembly combines:**

1. **SDK base rootfs** - A single rootfs image from the SDK (e.g. SquashFS or ext4). **Which file is the base rootfs is defined by nugget configuration**, not hardcoded: a nugget (e.g. platform or the filesystem-builder feature) declares a config or exports key `base_rootfs` with value in the form `${ALLOY_SDK_DIR}/images/rootfs.squashfs` so it resolves when `ALLOY_SDK_DIR` is set at firmware build time. The firmware build command sets `ALLOY_FIRMWARE_BASE_ROOTFS` from that when setting the hook environment (see [Base rootfs path](#base-rootfs-path) in step 13).
2. **Project releases** - One or more project artefacts staged under `/srv/alloy/<name>` in the root filesystem, with `/srv/erlang` as a symlink to the primary project.
3. **Rootfs overlay** - Consolidated overlay from multiple sources (see below).
4. **Bootloader, kernel, and device tree** - From SDK images.
5. **Security material** - Optional: signed bootloader, encrypted partitions (via security pack).

**Multi-project firmware:** Multiple projects can be installed in a single firmware image. Each is staged under `/srv/alloy/<name>`, where `<name>` is either the project name (default) or a user-specified name via `--name`.

#### Overlay Consolidation

The firmware rootfs overlay is assembled from multiple sources, merged in a defined order where later sources override earlier files:

1. **Nugget firmware overlays** - Each nugget may declare a `firmware_overlay` config key pointing to a directory of files to merge at firmware build time. These are static overlays baked into the nugget (as opposed to Buildroot overlays applied at SDK build time). Merged in topological nugget order.
2. **Project releases** - OTP releases staged under `/srv/alloy/<name>/`.
3. **Project overlays** - Each project artefact may include an `overlay/` directory containing files with absolute paths (e.g. `/etc/my_app.conf`). These are merged after the project releases.
4. **Security pack overlay** - If a security pack is provided, the orchestrator calls `security_generate_overlay` (see [§8.6.14](#8614-securityutilssh)). If the pack supports overlay generation, the generated files are merged. Used for security-specific files (certificates, CA bundles, security configuration).
5. **Command-line overlays** - Directories passed via `--overlay` on the firmware build command.
6. **Dynamic hook overlays** - `pre_firmware` hooks may add files to the overlay directory dynamically (e.g. generated configuration, initramfs).

#### Filesystem Priority Consolidation

**Convention:** Multiple sources can optionally provide **filesystem priority fragments** - files listing `path weight` pairs that control file ordering in the final firmware filesystem for boot-time performance optimization. Paths in each fragment are always **relative** to the directory tree containing the `ALLOY_FS_PRIORITIES` file (no leading `/`). The orchestrator relocates each path by prepending the tree's installation base in the rootfs (`${INSTALL_BASE}/${PATH}`), producing absolute rootfs paths. See [Data Design - Filesystem Priority Specification](01_DATA_DESIGN.md#filesystem-priority-specification) for the full format description, relocation table, and examples.

The orchestrator collects all relocated priority fragments and consolidates them into a single file before firmware hooks run. The consolidated file (with absolute rootfs paths) is passed to the filesystem builder feature nugget (e.g. `feature_squashfs`), which adapts it to the target filesystem. For SquashFS this is a direct `mksquashfs -sort` file; other filesystem builders may ignore it or map it to their own ordering mechanism.

**Priority sources (in consolidation order):**

1. **Nugget priorities** - Each nugget may declare a `{fs_priorities, Path}` metadata field pointing to a priority fragment file (see [Data Design - Filesystem Priority Metadata](01_DATA_DESIGN.md#filesystem-priority-metadata)). Paths are relative to the rootfs root (installation base `/`). Smelterl generates per-nugget `ALLOY_NUGGET_<NAME>_FS_PRIORITIES` variables and an `ALLOY_FS_PRIORITIES_FRAGMENTS` array in the **main target context** for the orchestrator to iterate.
2. **Project release priorities** - Each project artefact may include a `release/ALLOY_FS_PRIORITIES` file at the release root (the plugin may write it when populating the release staging directory). Paths are relative to the release root; at firmware build time the release is staged under `/srv/alloy/<name>/`, so the installation base is `/srv/alloy/<name>/`.
3. **Project overlay priorities** - Each project artefact may include an `overlay/ALLOY_FS_PRIORITIES` file at the overlay root (the plugin may write it when populating the overlay staging directory). Paths are relative to the overlay root (installation base `/`).
4. **Security pack priorities** - If the security pack's generated overlay (from `security_generate_overlay`) contains an `ALLOY_FS_PRIORITIES` file at its root. Paths are relative to the overlay root (installation base `/`).
5. **Command-line overlay priorities** - Each directory passed via `--overlay` may contain an `ALLOY_FS_PRIORITIES` file at its root. Paths are relative to the overlay root (installation base `/`).
6. **`pre_firmware` hook contributions** - Hooks may append entries directly to the consolidated priorities file in `ALLOY_FIRMWARE_WORK_DIR`. These entries must use absolute rootfs paths (they bypass the relocation step since they are written directly to the final file).

**Consolidation algorithm:** For each source in the order above, the orchestrator reads the fragment, prepends the source's installation base to each path, and appends the relocated entries to the consolidated file. After all sources are processed: **last** occurrence of a path wins (consistent with the overlay last-wins convention - later sources can override earlier priorities), and the final list is sorted by weight descending.

### 4.4 Nugget System

Nuggets are the composable building blocks of GRiSP Alloy. Each nugget is a self-contained component that provides a specific function (platform support, system integration, firmware assembly orchestration, features, build backend, or toolchain). Nuggets declare dependencies, configuration, Buildroot integration, hooks, and SDK embedding metadata.

**Nugget discovery:** The orchestrator discovers nuggets from multiple sources (default `./nuggets`, environment variable paths, command-line paths). It stages all nugget sources into a **motherlode** directory. Smelterl then scans the motherlode, parses `.nuggets` registries and `.nugget` files, and resolves dependencies.

**Nugget categories and metadata:** See [Data Design - Nugget Specification](01_DATA_DESIGN.md#nugget-specification).

**Nugget lifecycle in alloy:**

1. **Staging** - alloy copies or clones nugget sources into the motherlode directory.
2. **Generation** - smelterl scans the motherlode, resolves dependencies, generates Buildroot integration, context, and manifest.
3. **Hook execution** - alloy invokes nugget hook scripts at each build stage in topological order.
4. **Embedding** - alloy packs nugget content into the SDK based on embed lists from the **main** `alloy_context.sh`.

**Auxiliary products:** Nuggets may declare `auxiliary_products` to request additional SDK-time targets. These are planned by smelterl, built before main target, and do not participate in firmware-time hook execution.

**Firmware-time hooks and variants:**

Firmware-time hooks are split into three phases. All three phases are variant-filtered using `firmware_variant`:

| Phase | Hook Type | Purpose |
|-------|-----------|---------|
| 1 | `pre_firmware` | Rootfs merge, dm-verity, encryption prep, initramfs prep |
| 2 | `firmware_build` | Boot component build/sign/encrypt and boot image assembly (bootflow orchestrator runs here) |
| 3 | `post_firmware` | Firmware packaging (fwup, raw image, RAUC, update packages) |

See [§5.7 Firmware Build Flow](#57-firmware-build-flow) for the complete process.

#### Bootflows

An SDK can support multiple firmware variants (e.g. `plain`, `secure`, `encrypted`). Variant participation is declared by nuggets through the `firmware_variant` metadata field (see [Data Design - Firmware Variant Metadata](01_DATA_DESIGN.md#firmware-variant-metadata)). Nuggets that do not declare `firmware_variant` participate in all variants. Bootflow nuggets always declare `firmware_variant` (there are no variant-less bootflows).

**Key design principle:** A **bootflow** nugget is the **firmware assembly orchestrator**. The assembly recipe is expressed through the normal nugget mechanisms - topologically ordered hook execution plus consolidated configuration (`ALLOY_CONFIG_*`, `ALLOY_PARAM_*`, and `ALLOY_SECURITY_*`). The bootflow hook composes platform, system, and feature contributions and (when needed) invokes the security pack through `security_tools.sh`.

**Bootflow-driven model:** Platform and system define Buildroot variables and packages, device tree, and board-level config. **Bootflow** drives how the bootloader and kernel are **packaged** and how **security** is applied. Each bootflow declares compatibility with a specific platform or set of platforms. The system depends on a set of bootflows (one per supported variant). Bootflows are frozen definitions: a new *type* of flow requires a new bootflow nugget; a new system with a similar flow can reuse an existing bootflow. Platform **may optionally** export `fun_` helper scripts; a bootflow **may** use them when the platform provides them, or it may implement the full flow itself using Buildroot outputs and config from platform/system. Using `fun_` is not required—it is a pattern for reuse when convenient.

**How bootflows work:**

1. **Bootflow nuggets provide the firmware assembly recipe** via a `firmware_build` hook. The hook:
   - Builds the required unsigned components (by calling platform `fun_` helpers when the platform exports them and the bootflow chooses to use them, or by running its own scripts using Buildroot outputs and config).
   - When a variant requires signing or encryption, interleaves cryptographic operations via `security_tools.sh` (`alloy_security_sign`, `alloy_security_get_credential`, `alloy_security_check_capability`).
   - Assembles the final boot artefact(s) and declares their path(s) via the nugget’s **exports** (e.g. `firmware_boot_image`) so they appear as `ALLOY_CONFIG_*` for downstream nuggets. Hooks run in a subshell and cannot export shell variables; paths are provided through nugget metadata exports, not from the hook.

   See [§6.8 Function Export Convention and Contracts](#68-function-export-convention-and-contracts) for the optional `fun_` contract and recommended patterns when a bootflow uses platform helpers.

2. **Variant selection and bootflow uniqueness:** The orchestrator selects a variant at firmware build time using `--variant` (default `plain`) and runs the corresponding hook arrays generated by smelterl. For each firmware variant, the SDK contains **exactly one bootflow** nugget participating in that variant, ensuring there is a single, well-defined assembly orchestrator.

**Why bootflow drives assembly (not platform):**

- Platform scripts are pure “builders”: they construct unsigned artefacts and perform platform-specific assembly steps.
- Bootflow scripts own the sequencing and interleaving needed for secure variants (build -> sign -> wrap -> sign), while keeping cryptographic backend logic in the security pack.
- Multiple variants can be supported by providing multiple bootflow nuggets (one per variant), all consuming the same platform/system primitives and feature hooks.

### 4.5 Integration with Buildroot

Buildroot is the underlying build system that compiles packages, kernels, bootloaders, and root filesystems. Alloy treats Buildroot as a lower-level build engine and orchestrates it from above.

**How alloy uses Buildroot:**

1. **Smelterl generates Buildroot integration files** - `external.desc`, `Config.in`, `external.mk`, and a merged defconfig. These are written to the `br2_external/` directory in the build tree.
2. **alloy sets up symlinks** - Hook script symlinks in `br2_external/board/PRODUCT/scripts/` point to `scripts/buildroot/script_hook.sh` and `alloy_context.sh`.
3. **alloy invokes Buildroot** - `make -C BUILDROOT_PATH O=WORKSPACE BR2_EXTERNAL=BR2_EXT_PATH [ALLOY_*=...]` with:
   - `O=` pointing to the workspace (build output directory).
   - `BR2_EXTERNAL=` pointing to the generated br2_external tree.
   - `ALLOY_*` variables passed as make parameters (exported to hook scripts).
   Buildroot generates its output layout in the workspace directory, including a **Makefile** that forwards to the Buildroot source. Developers can therefore use the workspace for **manual Buildroot invocations** (e.g. `cd _build/sdk/PRODUCT/workspace && make menuconfig`, `make linux-menuconfig`, `make V=1`) to debug Buildroot behaviour, adjust configuration, or inspect the build without going through the full alloy SDK build.
4. **Buildroot calls hook scripts** - During the build, Buildroot invokes `post-build.sh`, `post-image.sh`, and `post-fakeroot.sh` (symlinks to `script_hook.sh`). The wrapper sources `alloy_context.sh` and dispatches to nugget-specific hooks.
5. **alloy runs `make legal-info`** - After the main build, Buildroot generates license information and package manifests.

**Builder nugget:** The builder nugget (`builder_buildroot`) provides Buildroot version, source URL, placement path, ccache configuration, and the download-cache symlink. Its `pre_build` hook downloads and extracts Buildroot. See [§7.1](#71-builderbuildroot).

**Motherlode placement:** The motherlode (consolidated nugget repositories) is staged at `ALLOY_BUILD_DIR/motherlode/`. It is separate from `br2_external/` and referenced via the `ALLOY_MOTHERLODE` variable.

### 4.6 Security Pack

#### Security Pack

A security pack is an external component that provides security services to the alloy build system. It may wrap local key material, a Hardware Security Module (HSM), or a remote signing service. A security pack implements the [security pack command contract](#security-pack-command-contract) and can be provided in two forms:

1. **A single executable file** - A self-contained script or binary that implements the command contract. The file itself is the security pack.
2. **A directory** containing an executable named `secpack` at its root, alongside any supporting files (keys, certificates, templates, configuration). The `secpack` executable at the directory root is the entry point.

In both cases, the entry point executable may be a bash script, a compiled binary, a Python script, or any other executable program.

**Design principles:**

- **Not stored in the repository or SDK** - Security materials live outside the version-controlled source and the distributed SDK.
- **External to the build** - The security pack is provided at firmware build time via the `--security-pack` option or the `ALLOY_SECURITY_PACK` environment variable, and at artefact-serve time via the same mechanisms.
- **The executable is the sole entry point** - All interaction with the security pack goes through the entry point executable (`secpack` for directory packs, or the file itself for single-file packs). Consumers never access the pack's internal files directly.
- **Supports local keys, HSMs, and remote signing** - The security pack abstracts the underlying security backend. A simple pack may wrap local PEM files; an advanced pack may talk to a YubiHSM via PKCS#11 or to a remote signing server (e.g. digsigserver). Hooks and tools are unaware of the backend.
- **Per-customer deployment** - Different customers can use different security packs with the same SDK.
- **Environment-driven configuration** - Pack-specific configuration (API tokens, service URLs, HSM PINs) is provided via user-set environment variables, not via alloy command-line options. This keeps sensitive values out of the firmware manifest and aligns with CI/CD secret management practices (GitHub Actions secrets, GitLab CI masked variables, etc.). The pack documents which environment variables it expects.
- **Relocatable and self-contained** - The security pack (whether a single executable or a directory) MUST be relocatable: it MUST NOT depend on absolute paths and MUST NOT contain symbolic links pointing outside its own directory tree. A single-file pack must be entirely self-contained (or rely solely on environment variables for external configuration). A directory pack must locate supporting files relative to its own location (e.g. `$(dirname "$0")/keys/`). This requirement ensures the pack works correctly when copied to a Vagrant VM or other build environment.
- **Linux-compatible** - Because builds may run inside a Linux Vagrant VM (even when the host is macOS or Windows), the security pack executable MUST be Linux-compatible. Scripts (bash, Python, etc.) are inherently portable; compiled binaries must be Linux ELF binaries or a multi-platform wrapper that detects the OS.

**How the security pack is specified:**

The security pack can be specified via:
- **CLI option:** `--security-pack PATH` (on `alloy build firmware` or `alloy serve artefacts`).
- **Environment variable:** `ALLOY_SECURITY_PACK=PATH` (set before invoking alloy).
- The CLI option takes precedence over the environment variable.

The value MUST be a path (absolute or relative) pointing to either an executable file or a directory. Bare command names resolved via `$PATH` are **not** supported - the path must explicitly point to the pack on disk. This avoids host/VM architecture mismatches (a macOS binary in `$PATH` would not work inside a Linux VM) and ensures the Vagrant flow can reliably copy the pack to the VM.

**How it works:**

1. The user provides the security pack via `--security-pack` or the `ALLOY_SECURITY_PACK` environment variable.
2. The orchestrator calls `security_resolve_pack` from `security_utils.sh` (see [§8.6.14 security_utils.sh](#8614-securityutilssh)) to resolve, validate, and canonicalize the security pack:
   - If the value is a **directory**: verify a file named `secpack` exists at its root and is executable. The resolved executable is `<directory>/secpack`.
   - If the value is a **file**: verify it exists and is executable. The resolved executable is the file itself.
   - If the value is neither a file nor a directory, fail with: `"Security pack not found: <path>"`.
   - Call `<executable> capabilities` to verify it is a valid security pack (exits 0 and produces output). If this fails, fail with: `"'<path>' does not appear to be a valid security pack (capabilities command failed)."`.
   - Convert to an absolute path (via `realpath`) and export `ALLOY_SECURITY_PACK` with the resolved absolute path.
3. All interaction with the security pack goes through `security_tools.sh` functions (see [§8.6.12 security_tools.sh](#8612-securitytoolssh)), which invoke the security pack executable internally. Hooks never call the security pack directly.
4. The security pack inherits the full process environment, including `ALLOY_*` context variables and any implementation-specific environment variables the user has set (API tokens, HSM PINs, service URLs - these are documented by the pack, not by alloy).

**Vagrant VM considerations:** When the build runs inside a Vagrant VM, the security pack is automatically synced from the host to the VM by the Vagrant abstraction flow (see [§5.3](#53-vagrant-abstraction-flow)). Single-file packs are copied as individual files; directory packs are rsynced as directories. The `--security-pack` argument and `ALLOY_SECURITY_PACK` are rewritten to point to the VM copy. This is why the relocatability and Linux-compatibility requirements above are essential. Implementation-specific configuration (tokens, URLs, PINs) that the pack needs must be forwarded via `--forward-env`; **forwarded variables are passed as-is and must not contain paths to files or directories**, because those paths are not synced and will not be available in the VM (see [Environment Forwarding](#environment-forwarding)).

**Sample security pack:** The `samples/` directory in the grisp_alloy repository includes a reference directory-based security pack for local development. It implements the full command contract using local key files and OpenSSL, and provides additional convenience commands to generate development keys, CA chains, and device credentials. Generated key material is local to the sample directory and excluded from version control via `.gitignore`. This sample is intended as a starting point for pack authors and for development/testing workflows that do not require HSM or remote signing.

#### Security Pack Command Contract

The security pack entry point is the executable that implements the subcommands defined in this section. For a single-file security pack, this is the file itself. For a directory-based security pack, this is the file named `secpack` at the directory root. The executable may be a bash script, a compiled binary, a Python script, or any other program.

##### Common Conventions

| Convention | Detail |
|---|---|
| **stdout** | Machine-parseable output: key=value pairs (one per line) or capability identifiers. |
| **stderr** | Human-readable error messages and diagnostics. |
| **Exit 0** | Success. |
| **Exit 1** | General error (misconfiguration, missing dependency, runtime failure). stderr has details. |
| **Exit 2** | Capability not supported - this security pack does not implement the requested operation. |
| **Exit 3** | Operation refused - sensitive material is not exportable (e.g. HSM-backed private key cannot be written to disk). stderr should explain what cannot be exported. |

**Key=value output format:** Commands that produce key=value output (`info`, `env`, and file-reporting outputs like `tls`) MUST follow these rules:
- One key=value pair per line. The first `=` on the line is the delimiter (values may contain `=`).
- Keys MUST match `[a-z][a-z0-9_]*` - a lowercase ASCII letter followed by zero or more lowercase ASCII letters, digits, or underscores.
- Values MUST be valid UTF-8. Values MUST NOT contain newlines (the format is line-delimited).
- Empty lines are ignored.

The orchestrator (`security_utils.sh`) validates all key=value output against these rules. Invalid keys cause a build error: `"Security pack error: invalid key '<key>' in '<command>' output - keys must match [a-z][a-z0-9_]*."`.

**All defined subcommands must be accepted:** A security pack MUST accept every subcommand defined in this contract. If a subcommand corresponds to a capability the pack does not support, it MUST return exit code 2 ("not supported") - it MUST NOT fail with an "unknown command" error. This enables the orchestrator and hooks to call any command without first checking capabilities, and gracefully handle unsupported operations via exit code 2.

**Forward compatibility:** If a security pack receives a subcommand it does not recognize (e.g. a command added in a later version of the contract), it MUST return exit code 2 and print a diagnostic to stderr. This ensures older packs degrade gracefully when used with newer versions of alloy.

##### Commands

**`secpack info`** - Report pack identity metadata.

Output (stdout): key=value pairs, one per line (see [key=value output format](#common-conventions) above). All fields are optional and pack-defined. Common fields include `name`, `version`, `provider`, `hash`, but the pack may include any metadata it considers relevant for traceability.

The orchestrator stores the output **opaquely** in the firmware manifest's `{security_pack, [...]}` field - it does not interpret, validate, or filter the reported metadata beyond key format validation. The pack is solely responsible for ensuring that no sensitive information (tokens, credentials, passwords) appears in the `info` output. See [Firmware Manifest - security_pack field](#firmware-manifest-specification) in Data Design.

Example output:
```
name=acme_secure_v1
version=2.1.0
provider=acme_security_service
hash=a1b2c3d4e5f6...
```

When no security pack is used, the firmware manifest contains `{security_pack, none}`.

**`secpack capabilities`** - List supported capabilities.

Output (stdout): one capability identifier per line (lowercase, hyphen-separated).

Defined capability identifiers:

| Capability | Meaning |
|---|---|
| `generate-overlay` | Can generate firmware rootfs overlay files (certificates, config, etc.). |
| `env` | Can export hook environment configuration (key=value pairs). |
| `tls` | Can export TLS materials (keys, certificates, CA bundles) for server or client roles. |
| `sign-boot` | Can sign secure-boot chain components (boot images, boot containers, FIT authentication regions, CSF blobs). |
| `sign-update` | Can sign OTA update packages (grisp_updater, RAUC, swupdate). |
| `sign-kernel` | Can sign kernel FIT images (may use HABv4, RSA, or other method). |
| `get-credential` | Can export credential files (certificates, public keys, SRK tables). |

The list is extensible - packs may report additional capabilities. The orchestrator and `security_tools.sh` use `capabilities` output to provide early failure with clear messages when a required capability is missing. Capability identifiers use lowercase hyphen-separated naming (e.g. `sign-boot`), distinct from the key=value key format used by other commands.

**`secpack generate-overlay OUTPUT_DIR [EXTRA_ARGS...]`** - Generate security overlay files for the firmware rootfs.

Arguments:
- `OUTPUT_DIR` - Directory to write overlay files into (created by the caller). Files are written relative to the rootfs root (e.g. `OUTPUT_DIR/etc/ssl/device.pem`).
- Extra arguments are forwarded from `security_tools.sh` - the pack defines their meaning.

The generated overlay directory may optionally contain an `ALLOY_FS_PRIORITIES` file at its root, following the same convention as project and command-line overlays. The orchestrator collects it during [filesystem priority consolidation](#filesystem-priority-consolidation).

Exit code 2 if the pack does not generate overlays.

**`secpack env`** - Export hook environment configuration.

Output (stdout): key=value pairs, one per line (see [key=value output format](#common-conventions) above). Each key is exported by the orchestrator as `ALLOY_SECURITY_<KEY>` (key uppercased), available to all firmware hooks. Because keys are uppercased for export, the pack MUST use the `[a-z][a-z0-9_]*` format defined in Common Conventions.

This command reports **all** configuration the security pack wants to communicate to hooks, including but not limited to:

| Category | Example keys | Purpose |
|---|---|---|
| Overlay file locations | `device_cert_path=/etc/ssl/device.pem`, `ca_bundle_path=/etc/ssl/ca-bundle.pem` | Tell hooks where security files are in the rootfs (exported as `ALLOY_SECURITY_DEVICE_CERT_PATH`, etc.). |
| Signing configuration | `signing_algorithm=hab4`, `srk_index=0` | Configure signing behavior for `firmware_build` hooks. |
| Feature flags | `encrypt_rootfs=true`, `enable_verity=true` | Enable/disable security features. |
| Key identifiers | `signing_key_id=SRK1`, `update_signing_key_id=update_prod` | Identify which keys to use (without exposing key material). |

The `secpack env` command is called **once** by the orchestrator (at step 13 of the [Firmware Build Flow](#57-firmware-build-flow)) after overlay generation and priority consolidation, but before any hooks run. This ensures hooks receive a complete and consistent environment. The command receives the full `ALLOY_*` environment, so it can adapt its output based on the selected variant, platform, product, etc.

Exit code 2 if the pack has no environment to export (the orchestrator treats this as a no-op).

**`secpack tls --role ROLE --identity IDENTITY --type TYPE --output FILE`** - Export a TLS material file.

This is a generic TLS material export command. It replaces use-case-specific commands by parameterizing the role, identity, and material type. All exported files use **PEM format** - the pack handles any internal format conversion.

Arguments:
- `--role ROLE` - TLS role: `server` (server-side credentials), `client` (client-side credentials), or `ca` (CA trust chain).
- `--identity IDENTITY` - A name identifying the entity (e.g. `artefact-server`, `device`, `mqtt-broker`). The pack defines which identities it supports.
- `--type TYPE` - Material type to export: `key` (private key), `cert` (certificate), `chain` (full certificate chain including intermediates), or `ca` (CA bundle / trust anchors).
- `--output FILE` - Exact file path to write the material to (the caller controls the output location and filename).

Exit code 0 on success. Exit code 2 if the requested role/identity/type combination is not supported by this pack. Exit code 3 if the requested material is non-exportable (e.g. HSM-backed private key). stderr should explain: e.g. `"Private key for 'artefact-server' is stored on HSM and cannot be exported to disk."`.

Examples:
```bash
# Server key and certificate for the artefact server
secpack tls --role server --identity artefact-server --type key --output /tmp/tls/server.key.pem
secpack tls --role server --identity artefact-server --type chain --output /tmp/tls/server.chain.pem

# Device CA bundle for mTLS client verification
secpack tls --role ca --identity device --type ca --output /tmp/tls/device-ca.pem

# Device client certificate and key
secpack tls --role client --identity device --type cert --output /tmp/tls/device.cert.pem
secpack tls --role client --identity device --type key --output /tmp/tls/device.key.pem
```

**`secpack sign --purpose PURPOSE --input FILE --output FILE [EXTRA_ARGS...]`** - Sign a file.

The security pack handles signing internally using whatever backend it supports (local keys + OpenSSL, PKCS#11/HSM, remote signing service via HTTP). The caller does not know or care about the backend.

Arguments:
- `--purpose PURPOSE` - Signing purpose identifier. Defined purposes:
  - `boot` - Sign a secure-boot chain component (e.g. SPL, boot container, U-Boot FIT authentication region). Typically uses HABv4/AHAB CST.
  - `kernel` - Sign a kernel image (typically a kernel FIT). May use HABv4 (same chain as boot) or RSA signature verification by U-Boot (different mechanism, different key).
  - `update` - Sign an OTA update package (grisp_updater bundle).
  - `verity` - Sign a dm-verity hash tree root.
  - Custom purposes may be defined by packs.
- `--input FILE` - File to sign.
- `--output FILE` - Where to write the signed output or signature blob.
- Extra key=value arguments are forwarded from `security_tools.sh` (see [§8.6.12](#8612-securitytoolssh)) - the pack defines their meaning (e.g. `format=hab4-csf`, `srk_index=0`, `csf_template=/path/to/template.csf`, `blocks=/path/to/blocks.txt`).

Exit code 0 on success. Exit code 1 on signing failure. Exit code 2 if the requested purpose is not supported.

**Standardized signing formats (recommended):** The `sign` command is intentionally generic, but to make bootflows portable across backends (local keys, PKCS#11/HSM, remote signing services) packs SHOULD support the following standardized `format=...` extra arguments and associated parameters.

**Design rule:** File layout and packaging operations (creating i.MX boot containers, creating IVT headers, inserting CSF blobs with `dd`, building FIT images) belong in hooks. The security pack is responsible for cryptographic operations and producing the **signing outputs** (signed file or signature/CSF blob). This separation keeps the pack backend-agnostic and suitable for remote signing services.

**`--purpose boot` formats:**

- **`format=hab4-csf`** - Generate a HABv4 CSF binary blob for an input image.
  - **`--input`**: The unsigned image/container to authenticate (boot container, SPL image, or a FIT image region).
  - **`--output`**: Path where the pack writes the generated CSF binary blob (e.g. `csf.bin`).
  - **Extra args (required):**
    - `csf_template=PATH` - Path to a CSF text template file provided by the caller. This file is typically supplied by the bootflow/system nuggets as platform/layout data but MAY also be obtained from the pack via `get-credential` if the template is backend-specific. The template may contain placeholders that the pack replaces.
    - `blocks=PATH` - Path to a “CSF blocks” description file defining which byte ranges are authenticated.
  - **Extra args (optional):**
    - `srk_index=N` - SRK index to use (0-3) when applicable.
  - **Blocks file format:** UTF-8 text. Empty lines and lines beginning with `#` are ignored. Each non-empty line MUST contain exactly these fields as `key=value` pairs separated by spaces:
    - `offset=0x...` - Start offset (in bytes) within the `--input` file.
    - `length=0x...` - Length (in bytes) of the authenticated region.
    - `load_addr=0x...` - Target load address for the region (SoC-dependent; used by HAB).
    Example:
    ```
    # Authenticate SPL
    offset=0x0 length=0x1a000 load_addr=0x920000
    # Authenticate U-Boot FIT header+IVT region
    offset=0x58000 length=0x1020 load_addr=0x40200000
    ```
  - **Expected caller behavior:** The hook inserts the resulting CSF blob into the final image at the appropriate offset (e.g. the IVT `csf_ptr` location for i.MX boot containers) and performs any required alignment/padding.

**`--purpose kernel` formats:**

- **`format=fit-rsa`** - Sign a U-Boot FIT image using FIT signature nodes (RSA).
  - **`--input`**: Unsigned FIT image (e.g. `kernel.itb`).
  - **`--output`**: Signed FIT image (e.g. `kernel.itb.signed`).
  - **Extra args (optional):**
    - `key_id=ID` - Select which signing key/certificate to use (pack-defined).
    - `algo=sha256,rsa4096` - Requested algorithm/profile (pack-defined; defaults are pack-defined).

- **`format=hab4-csf`** - Generate a HABv4 CSF binary blob to authenticate a kernel image (typically a kernel FIT) as part of a HAB boot chain.
  - **`--input`**: The unsigned kernel image/FIT file.
  - **`--output`**: Path where the pack writes the generated CSF binary blob (e.g. `kernel.csf.bin`).
  - **Extra args (required):**
    - `csf_template=PATH` - Path to a CSF text template file provided by the caller (typically supplied by the bootflow/system nuggets). Packs MAY also expose templates via `get-credential` with a suitable `profile=` when templates are backend-specific.
    - `blocks=PATH` - Path to a “CSF blocks” description file defining which byte ranges are authenticated (same format as `format=hab4-csf` under `--purpose boot`).
  - **Extra args (optional):**
    - `srk_index=N` - SRK index to use (0-3) when applicable.
  - **Expected caller behavior:** The hook is responsible for any IVT/header creation and for placing the CSF blob into the final bootable layout (e.g. appending IVT+CSF to a FIT image, or inserting CSF into a container at an IVT `csf_ptr` offset). The pack does not perform `dd`/offset insertion.

**`--purpose verity` formats:**

- **`format=detached`** - Produce a detached signature over a dm-verity root hash value.
  - **`--input`**: File containing the dm-verity root hash (typically a single line of ASCII hex).
  - **`--output`**: Signature output file (raw or armored; pack-defined unless overridden).
  - **Extra args (optional):**
    - `key_id=ID` - Key selection (pack-defined).
    - `encoding=raw|base64` - Output encoding (pack-defined).

**`secpack get-credential --purpose PURPOSE --type TYPE OUTPUT_DIR [EXTRA_ARGS...]`** - Export a credential file.

Used when a tool or hook needs a file (certificate, public key, SRK table) on disk. This is distinct from `sign` - `get-credential` exports material, `sign` performs a cryptographic operation.

Arguments:
- `--purpose PURPOSE` - Credential purpose (e.g. `boot-signing`, `update-signing`, `device-identity`).
- `--type TYPE` - Credential type: `certificate`, `public-key`, `private-key`, `ca-bundle`, `srk-table`, `csf-template`, or custom.
- `OUTPUT_DIR` - Directory where the credential file is written.
- Extra arguments forwarded from `security_tools.sh` (see [§8.6.12](#8612-securitytoolssh)).

Output (stdout): `path=OUTPUT_DIR/<filename>`

Exit code 2 if the purpose/type combination is not available. Exit code 3 if the material is non-exportable (typical for `private-key` with HSM-backed packs).

**Standardized credential exports (recommended):** To support HAB-based secure boot workflows without exposing private key material to hooks, packs SHOULD support the following exports:

- **`--purpose boot-signing --type srk-table`** - Export the SRK table binary blob used for fuse programming and/or boot image validation.
- **`--purpose boot-signing --type srk-fuse`** - Export the SRK fuse hash binary blob (the value that would be programmed into fuses).
- **`--purpose boot-signing --type csf-template`** - OPTIONAL. Export a CSF template file. Use `profile=...` (extra arg) to select a template variant (pack-defined; e.g. `profile=imx8mp_spl_container`, `profile=imx8mp_uboot_fit`). This is useful when the template is backend-specific (e.g. it embeds PKCS#11 URIs or remote-service identifiers). If the template is purely platform/layout data, bootflow/system nuggets can provide it and the pack can omit this export (return exit code 2 for unsupported type).

Packs MAY also export public credentials needed for verification (e.g. `certificate`, `public-key`) but MUST return exit code 3 for private-key exports when backing keys are non-exportable (HSM).

##### Guaranteed Context Environment

The orchestrator sets the following `ALLOY_*` variables before invoking any `secpack` command. The security pack can rely on these being present:

| Variable | Content |
|---|---|
| `ALLOY_SECURITY_PACK` | Absolute path to the resolved security pack executable. |
| `ALLOY_PRODUCT` | Product identifier (from SDK metadata). |
| `ALLOY_PRODUCT_VERSION` | Product version string. |
| `ALLOY_FIRMWARE_VARIANT` | Selected firmware variant (e.g. `plain`, `secure`, `encrypted`). Only set during firmware builds. |
| `ALLOY_CONFIG_TARGET_ARCH_TRIPLET` | Target architecture triplet (e.g. `aarch64-buildroot-linux-gnu`). |

In addition to the variables above, `secpack` commands run with the same consolidated build context as hooks:

- **Consolidated nugget configuration** - All resolved configuration keys are available in the `ALLOY_CONFIG_*` namespace (and, where applicable, in per-nugget namespaces). This allows a pack to adapt behavior to the selected platform/product/variant without inventing a parallel configuration mechanism.
- **Firmware parameters** - During firmware builds, each resolved `--param KEY=VALUE` is exported as `ALLOY_PARAM_<KEY>` (uppercased), so a pack can incorporate per-device/per-deployment values (e.g. serial numbers) into its behavior. See [§4.8 Firmware Build Parameters](#48-firmware-build-parameters).

In addition, the process environment includes any variables set by the user before invoking `alloy`. When the build runs inside a Vagrant VM, **user-provided pack configuration variables are not automatically available in the VM** - they must be explicitly forwarded using `--forward-env` (repeatable) or `ALLOY_FORWARD_ENV` (comma-separated patterns), otherwise the in-VM `secpack` process will not see them. Implementation-specific configuration (API tokens, service URLs, HSM PINs, signing profiles) should be documented by the pack and set by the user in their environment or CI configuration:

```bash
# Example: CI job configuring a remote signing pack (directory-based)
export ALLOY_SECURITY_PACK="/opt/acme/security-pack/"
export SIGNING_SERVICE_URL="https://signing.internal:9999"
export SIGNING_TOKEN="${CI_SIGNING_SECRET}"  # GitLab CI masked variable
alloy build firmware --variant secure my_project

# If the build runs in a Vagrant VM (macOS/Windows), pack-specific variables must be forwarded:
export ALLOY_SECURITY_PACK="./company_secpack/"
export SIGNING_SERVICE_URL="https://signing.internal:9999"
export SIGNING_TOKEN="${CI_SIGNING_SECRET}"
export ALLOY_FORWARD_ENV="SIGNING_*"   # or: alloy --forward-env 'SIGNING_*' build firmware ...
alloy build firmware --variant secure my_project

# Or with a single-file pack:
export ALLOY_SECURITY_PACK="/opt/acme/bin/acme-secpack"
alloy build firmware --variant secure my_project

# Or with --security-pack overriding the environment variable:
alloy build firmware --security-pack ./local_signing_pack/ --variant secure my_project
```

##### Security Pack Use Cases

The security pack interface is designed to cover the following use cases. Bootflow nuggets and hooks interact with these capabilities exclusively through `security_tools.sh` functions (see [§8.6.12](#8612-securitytoolssh)).

**Firmware build - overlay generation:**
1. **Device certificates** - Per-device or per-product X.509 certificates for the firmware rootfs.
2. **CA bundles** - Trusted CA certificate chains for device identity verification.
3. **Security configuration files** - Runtime config for on-device security services.
4. **Overlay file location reporting** - Via `secpack env`, the pack declares where important files land in the rootfs (e.g. `device_cert_path=/etc/ssl/device.pem`, exported as `ALLOY_SECURITY_DEVICE_CERT_PATH`), so hooks can find them without hardcoding paths.

**Firmware build - signing:**
5. **Bootloader signing (HABv4/AHAB)** - Sign SPL, U-Boot FIT, or boot containers using NXP CST. The pack handles CST invocation with the correct backend (OpenSSL for local keys, PKCS#11 for HSM).
6. **Kernel FIT signing** - May use HABv4 (same key chain as bootloader) or RSA signature verification by U-Boot (different mechanism, different key). **The bootflow / firmware build configuration decides the signing method** and communicates it via the consolidated config and/or firmware parameters (e.g. `ALLOY_CONFIG_KERNEL_SIGNING_METHOD` or `ALLOY_PARAM_KERNEL_SIGNING_METHOD`). Hooks pass the chosen method to the security pack in the `sign` request (e.g. as `--purpose kernel` plus extra args) and fail if the pack does not support it.
7. **SRK table and CSF template provision** - HABv4 requires the SRK table binary embedded in the signed image and CSF templates for the signing tool. Exported via `secpack get-credential --purpose boot-signing --type srk-table` and `--type csf-template`.
8. **SRK index / key revocation** - HABv4 supports up to 4 Super Root Keys. The pack reports which index to use via `secpack env` (`srk_index=0`, exported as `ALLOY_SECURITY_SRK_INDEX`), enabling key rotation and revocation.

**Example - HABv4 signing split between hook and pack (recommended):**

For HAB-based secure boot on NXP i.MX devices, the hook owns **image layout** and the pack owns **cryptography**:

1. The hook assembles the unsigned boot container / FIT image and determines:
   - The CSF insertion offset (e.g. from the IVT `csf_ptr` field for containers).
   - The authenticated regions (offset/length/load address) and writes a blocks file.
2. The hook obtains a CSF template (if needed) via `alloy_security_get_credential boot-signing csf-template ... profile=...`.
3. The hook requests a CSF blob from the pack:

```bash
alloy_security_sign boot "${unsigned_image}" "${csf_blob}" \
  format=hab4-csf \
  csf_template="${csf_template}" \
  blocks="${csf_blocks}" \
  srk_index="${ALLOY_SECURITY_SRK_INDEX:-0}"
```

4. The hook inserts the CSF blob into the image at the correct offset and performs any alignment/padding.

**Firmware build - encryption:**
9. **Disk encryption keys** - For encrypted filesystem variants (dm-crypt, LUKS).
10. **dm-verity signing** - Sign the hash tree root for verified boot.

**Firmware build - update packages:**
11. **Update package signing** - Sign grisp_updater / RAUC / swupdate bundles via `secpack sign --purpose update`.

**Development / deployment:**
12. **TLS material export** - Provide server certificates and keys for HTTPS (e.g. artefact server), device CA bundles for mTLS client verification, and client credentials for device identity. The generic `tls` command supports any role/identity combination. See [§3.5 alloy serve artefacts](#35-alloy-serve-artefacts).

Firmware assembly orchestration is defined by the bootflow nugget. See [§4.4 Nugget System - Bootflows](#bootflows).

### 4.7 Output Selection

Feature nuggets that produce firmware artefacts declare them via `firmware_outputs` metadata with an optional `{selectable, true}` field (see [Data Design - Firmware Outputs Metadata](01_DATA_DESIGN.md#firmware-outputs-metadata)). Selectable outputs get CLI flag support, allowing the user to choose which outputs to build at firmware build time. All output metadata - IDs, display names, selectability - is derived from a single source: the `firmware_outputs` metadata in `.nugget` files.

**How it works:**

1. **Discovery:** The orchestrator reads `ALLOY_OUTPUT_SELECTABLE` (populated by smelterl from `firmware_outputs` entries where `selectable` is `true`) to know which output types this SDK supports and can be user-selected. For each entry, `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` carries whether that output is included in the default selection.
2. **CLI validation:** If the user passes `--output-<id>`, the orchestrator validates that `<id>` (with hyphens converted to underscores) exists in `ALLOY_OUTPUT_SELECTABLE`. Unknown output types cause an immediate error listing available options.
3. **Selection logic:**
   - If **no** `--output-*` flags are given, enable the **default** selectable outputs: for each entry in `ALLOY_OUTPUT_SELECTABLE`, read `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` and export `ALLOY_OUTPUT_<ID>=true` if `true`, `false` otherwise. Outputs with `{default, false}` are therefore not built unless explicitly requested.
   - If **one or more** `--output-*` flags are given, **only** the specified outputs are enabled: export `ALLOY_OUTPUT_<ID>=true` for the requested ones, `ALLOY_OUTPUT_<ID>=false` for all others in `ALLOY_OUTPUT_SELECTABLE`.
4. **Environment export:** For each entry in `ALLOY_OUTPUT_SELECTABLE`, the orchestrator exports `ALLOY_OUTPUT_<ID>=true` or `ALLOY_OUTPUT_<ID>=false` depending on the selection.
5. **Hook checking:** Each hook that produces a selectable output checks its corresponding `ALLOY_OUTPUT_*` variable and skips its work if set to `false`:

```bash
# In feature_fwup's post_firmware hook:
if [[ "${ALLOY_OUTPUT_FWUP_FIRMWARE}" != "true" ]]; then
    alloy_log_info "Skipping fwup firmware (not selected)"
    return 0
fi
# ... build the .fw file ...
alloy_firmware_add_output fwup_firmware "${output_path}"
```

6. **Runtime registration:** When a hook produces an output, it calls `alloy_firmware_add_output OUTPUT_ID FILE_PATH` (see [Firmware Hook API](#59-firmware-hook-api)). This records the artefact path in `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/<ID>` so the orchestrator can discover what was produced (build summary, verification). Hooks run in separate processes, so no environment export is performed; a downstream hook that needs another hook's output path reads it from the `.outputs/<ID>` file.

**Listing available outputs:** The `--list-outputs` flag iterates `ALLOY_OUTPUT_SELECTABLE` and reads per-output variables (`ALLOY_FIRMWARE_OUT_<ID>_NAME`, `ALLOY_FIRMWARE_OUT_<ID>_DESCRIPTION`, `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT`) to print selectable outputs with display names, descriptions, and default status:

```bash
$ alloy build firmware --list-outputs
Available firmware outputs:
  fwup_firmware    Firmware update package     [default]
                   fwup firmware update package for OTA deployment
  image            Raw disk image              [opt-in]
                   Complete disk image for initial flashing via dd. Not built by default; use --output-image to request it.
```

**Selectable vs non-selectable outputs:** Outputs with `{selectable, true}` are user-controllable via CLI flags. Outputs without this field (default `false`) are not exposed as CLI flags - they are produced unconditionally when their hook runs (e.g. a signed boot image produced only in the `secure` firmware variant). Both types participate in the build summary if `alloy_firmware_add_output` was called.

**Default vs opt-in selectable outputs:** Among selectable outputs, those with `{default, true}` (the default) are built automatically in a default run. Those with `{default, false}` are opt-in: they are listed in `--list-outputs` and accepted via `--output-<id>`, but they are never built unless explicitly requested. Use `{default, false}` for expensive or rarely-needed outputs such as raw disk images.

See [§5.7 Firmware Build Flow](#57-firmware-build-flow) step 5 for the full output selection process.

### 4.8 Firmware Build Parameters

The `--param KEY=VALUE` option allows injecting key-value pairs at firmware build time. Parameters are designed for device-specific or deployment-specific values that do not exist in the SDK or project configuration - they are **new information**, not overrides.

**Use cases:**

- Device identity: serial numbers, MAC addresses, device certificates.
- Deployment metadata: batch IDs, customer labels, factory identifiers.
- CI/CD context: pipeline ID, build agent, release channel.
- Build-time toggles: factory mode, debug console enable.

**Declaration:** Nuggets declare expected parameters via `firmware_parameters` metadata (see [Data Design - Firmware Parameters Metadata](01_DATA_DESIGN.md#firmware-parameters-metadata)). Each declaration specifies the parameter ID, type (`string`, `integer`, or `boolean`), and optional name, description, required flag, and default value. Multiple nuggets may declare the same parameter ID (e.g. both a platform nugget and a provisioning nugget use `serial_number`); smelterl validates type consistency and merges the declarations. The merged parameter list is embedded in the SDK manifest's `capabilities` section and in `alloy_context.sh` as the `ALLOY_FIRMWARE_PARAMETERS` ID array plus per-parameter `ALLOY_FIRMWARE_PARAM_<ID>_*` metadata variables (see the Smelterl design section on generating `alloy_context.sh`:
local checkout [smelterl/docs/DESIGN.md#412-generating-alloy_contextsh](../smelterl/docs/DESIGN.md#412-generating-alloy_contextsh),
web view [github.com/grisp/smelterl/docs/DESIGN.md#412-generating-alloy_contextsh](https://github.com/grisp/smelterl/blob/main/docs/DESIGN.md#412-generating-alloy_contextsh)).

**Validation at firmware build time:** The orchestrator iterates the `ALLOY_FIRMWARE_PARAMETERS` array and reads each parameter's metadata from `ALLOY_FIRMWARE_PARAM_<ID>_TYPE`, `_REQUIRED`, `_DEFAULT`, and `_NAME` variables:
- Unknown parameter keys produce an error listing available parameters.
- Type checking: `integer` params must be valid integers; `boolean` params must be `true`/`false`/`yes`/`no`/`1`/`0`.
- Required parameters (declared with `{required, true}` by any nugget) must be provided - if missing, the build fails before any hook runs.
- Default values: if a parameter has a declared `{default, Value}` and the user does not provide it via `--param`, the default is applied automatically.

**Discoverability:** `alloy build firmware --list-params` iterates `ALLOY_FIRMWARE_PARAMETERS` and reads the per-parameter metadata variables (`ALLOY_FIRMWARE_PARAM_<ID>_TYPE`, `_REQUIRED`, `_DEFAULT`, `_NAME`, `_DESCRIPTION`) to display each parameter's type, required/optional status, default, display name, and description.

**Environment convention:** Each resolved parameter is exported as `ALLOY_PARAM_<KEY>` (key uppercased) before any firmware hook runs. Hook scripts that need parameters read them from the `ALLOY_PARAM_*` namespace. Hooks that do not consume parameters simply ignore them.

**Manifest traceability:** All parameters (user-provided and defaults) are recorded in the firmware manifest's `{parameters, [...]}` section (see [Data Design - Firmware Manifest](01_DATA_DESIGN.md#firmware-manifest-specification)). Each entry carries the typed value (binary for strings, integer for integers, atom for booleans). This provides full traceability: the firmware manifest is a complete record of the SDK, projects, variant, security pack, *and* any device-specific values that were injected at build time.

**Design rationale - why parameters, not config overrides:**

Parameters live in a dedicated `ALLOY_PARAM_*` namespace that is disjoint from `ALLOY_CONFIG_*` (nugget configuration) and `ALLOY_EXPORT_*` (nugget exports). This separation is intentional:

1. **Safety:** Parameters cannot accidentally override SDK or nugget configuration. Most `ALLOY_CONFIG_*` values were consumed during SDK build (e.g. Buildroot version, toolchain settings); overriding them at firmware time would create a phantom inconsistency between compiled binaries and hook assumptions.
2. **No ambiguity:** The `ALLOY_PARAM_*` prefix unambiguously identifies values injected at firmware build time, both in the shell environment and in the manifest.
3. **Declared contract:** Nuggets explicitly declare what parameters they expect. The orchestrator validates against these declarations, catching typos and missing values before hooks run - rather than silently passing through arbitrary key-value pairs.

### 4.9 Logging and Debugging

#### Orchestrator observability (design principle)

As a **project-wide design rule**, the orchestrator (and all code that is part of it, including hook wrappers) must use **debug logging** to make its behaviour observable. Developers implementing or extending the orchestrator should add debug logging so that someone investigating issues can see:

- **Flow control** - which steps and phases run, in what order, and when they start or finish.
- **Delegation** - which subprocesses, scripts, or tools are invoked (e.g. smelterl, Buildroot, hook scripts) and with what role.
- **Parameters and variable flow** - which arguments, options, and environment variables are passed into delegations (at a level appropriate to sensitivity; see [Bash trace](#bash-trace-set--x) and `alloy_enter_hidden` for hiding secrets).

Debug output is gated by the debug level (see [Log verbosity levels](#log-verbosity-levels) below): at appropriate levels the orchestrator should log which hooks are invoked (nugget name, script path, hook type), which build steps run, and other information that helps debug flow control, delegation, and parameter flow. This applies across all build flows (SDK build, firmware build, hook invocation, etc.). Implementation details (where to call `log_debug`, exact message format) are in [§8 Implementation Details](#8-implementation-details) and in the individual flow descriptions.

#### Log verbosity levels

`ALLOY_DEBUG` is an integer that controls structured log output. It is independent of bash execution tracing (see [Bash trace](#bash-trace-set--x) below).

| Level | Flag | What is shown |
|-------|------|--------------|
| `0` | *(default)* | `log_error`, `log_warn`, `die` - errors and warnings only |
| `1` | `--debug` | + `log_info` - informational progress messages; smelterl progress |
| `2` | `--debug=2` | + `log_debug` - detailed developer debug messages |
| `3` | `--debug=3` | + Buildroot verbose output (`V=1` make parameter) |

`--debug` without a value is equivalent to `--debug=1`. Setting `ALLOY_TRACE=true` (see below) is independent and can be combined with any level.

#### Log functions

**Orchestrator:** Command scripts source `common.sh` (which sources `console_utils.sh` and `debug_utils.sh`; `debug_utils.sh` also sources `console_utils.sh` directly) and use the internal names `log_info`, `log_debug`, `log_warn`, `log_error`, `die`, `enter_hidden`, `leave_hidden` plus user-facing print helpers `print_result`, `print_note`, `print_hint` (see [§8.6.1](#861-commonsh), [§8.6.1a](#861a-debugutilssh)).

**Hook scripts:** Hooks source [hook_common.sh](#860-hookcommonsh-hook-entry-point) at the top to get the **`alloy_`-prefixed** API (from `debug_tools.sh` and other _tools.sh) and tracing. They must use only that API; if they do not source the entry point, they cannot expect any `alloy_*` functions (see [§8.6.1b](#861b-debugtoolssh)).

| Function (hook API) | Output stream | Minimum `ALLOY_DEBUG` |
|---------------------|--------------|----------------------|
| `alloy_log_error MESSAGE` | stderr | 0 (always) |
| `alloy_log_warn MESSAGE` | stderr | 0 (always) |
| `alloy_die [EXIT_CODE] MESSAGE` | stderr | 0 (always); exits |
| `alloy_log_info MESSAGE` | stdout | 1 |
| `alloy_log_debug MESSAGE` | stderr | 2 |

Color output is supported for interactive terminals; auto-disabled when not connected to a terminal or when `NO_COLOR` is set.

Hook scripts MUST use the `alloy_log_*` and `alloy_die` functions instead of bare `echo` for all diagnostic output. This ensures messages are suppressed at the right level and output is uniformly formatted across all hook scripts.

#### Bash trace (`set -x`)

Bash execution tracing is controlled separately via `--trace` / `ALLOY_TRACE=true`. When enabled, the orchestrator calls the `set_trace true` function provided by `common.sh` immediately after argument parsing (so tracing reflects the parsed command arguments). That function enables `set -x` for the current process and exports `ALLOY_TRACE=true` for child processes. This is intended for debugging the bash scripts themselves - it is far more verbose than `log_debug` and orthogonal to log verbosity.

`--trace` can be combined freely with any `--debug` level:
- `--trace` alone: script tracing with no extra log messages
- `--debug=2 --trace`: full debug messages plus script tracing
- `--debug=3 --trace`: maximum verbosity

**Suppressing trace around sensitive operations:** Two functions in the hook API allow temporarily disabling the trace so that keys, credentials, or tokens are not echoed in build logs:

- **`alloy_enter_hidden`** - disables `set -x` if it is active.
- **`alloy_leave_hidden`** - re-enables `set -x` if it was active when `alloy_enter_hidden` was called.

```bash
alloy_enter_hidden
secret_key=$(cat "${ALLOY_SECURITY_PACK_KEYS_DIR}/signing.key")
alloy_leave_hidden
```

Hook scripts that handle sensitive material (crypto, signing, credential access) MUST use `alloy_enter_hidden` / `alloy_leave_hidden` around those sections.

#### Debug propagation chain

`ALLOY_DEBUG` and `ALLOY_TRACE` propagate through the full build chain when set:

1. **CLI -> orchestrator:** The command script sources `common.sh` early, then parses arguments. After parsing, it calls `set_debug_level N` when `--debug[=N]` was passed and `set_trace true` when `--trace` was passed (both functions are provided by common.sh). So the debug level and tracing are applied from the parsed command arguments; `common.sh` also applies any existing `ALLOY_DEBUG` / `ALLOY_TRACE` from the environment when sourced (e.g. for the Buildroot wrapper).
2. **Orchestrator -> Vagrant VM:** `--debug=N` and `--trace` are forwarded in the re-invocation argument list; `ALLOY_DEBUG` and `ALLOY_TRACE` are forwarded as environment variables (see [§5.3](#53-vagrant-vm-abstraction-layer)).
3. **Orchestrator -> Buildroot:** `ALLOY_DEBUG` and `ALLOY_TRACE` are passed as Buildroot make parameters (exported to hook scripts). `V=1` is additionally appended to the make invocation when `ALLOY_DEBUG >= 3`.
4. **Orchestrator -> smelterl:** `--debug` is passed to the smelterl escript when `ALLOY_DEBUG >= 1`.
5. **Buildroot -> hook scripts:** `ALLOY_DEBUG` and `ALLOY_TRACE` arrive in the environment of `script_hook.sh` via Buildroot make parameters. The wrapper sources `common.sh`, which enables tracing for the **wrapper** when `ALLOY_TRACE=true`. Each hook script sources [hook_common.sh](#860-hookcommonsh-hook-entry-point) at the top, which enables `set -x` for the **hook** when `ALLOY_TRACE=true` (see [§5.8](#58-hook-invocation-flow)).

#### Hook logging availability

Hook scripts run in two distinct contexts. The **hook API** (`alloy_log_*`, `alloy_die`, `alloy_enter_hidden`, `alloy_leave_hidden` from `debug_tools.sh`) must be available in both:

- **Buildroot-invoked hooks** (`post_build`, `post_image`, `post_fakeroot`): The wrapper executes each hook script. The hook must **source** [hook_common.sh](#860-hookcommonsh-hook-entry-point) at the top to get the `alloy_*` API and tracing. See [§5.8](#58-hook-invocation-flow) and [§8.6](#86-shared-utilities).

- **Orchestrator-invoked hooks** (`pre_build`, `pre_firmware`, `firmware_build`, `post_firmware`): Same rule - the wrapper executes each hook; the hook must source hook_common.sh at the top to get the API and tracing.

In all cases, the **wrapper** does not source _tools.sh and does not export functions. Hooks get the API by **sourcing** the single entry point [hook_common.sh](#860-hookcommonsh-hook-entry-point). If a hook does not source it, it cannot expect any `alloy_*` functions.

#### Build logs

- Buildroot build logs are retained in the build workspace directory (`_build/sdk/PRODUCT/workspace/build/`). Each package build produces a `build.log` in its package directory. These logs are not removed after a successful build.
- Smelterl output goes to stderr when `--debug` is passed, interleaved with the orchestrator's output.

### 4.10 Error Handling

**Principles:**

- **Fail early:** Validate inputs and prerequisites before starting expensive operations.
- **Clear messages:** Every error message includes what failed, why, and what the user can do.
- **Appropriate exit codes:** Non-zero exit on failure; specific codes for different failure modes where useful.
- **Cleanup on exit:** Use bash traps to clean up temporary files and directories on any exit (success or failure).
- **No silent failures:** Every external command is checked for success; `set -e` and `set -o pipefail` are used in command scripts.

**Error categories:**

| Category | Example | Behavior |
|----------|---------|----------|
| Invalid arguments | Missing PRODUCT_NUGGET | Immediate exit with usage hint |
| Mode mismatch | `build sdk` from SDK | Immediate exit with explanation |
| Missing dependency | smelterl not built, Buildroot missing | Attempt auto-recovery or fail with instructions |
| Build failure | Buildroot make fails | Exit with error; build log preserved |
| Hook failure | Nugget script exits non-zero | Abort build; report which nugget and hook failed |
| Unknown variant | `--variant <name>` not in `ALLOY_FIRMWARE_VARIANTS` | Immediate exit listing available firmware variants |
| Unknown parameter | `--param foo=bar` where `foo` not in `ALLOY_FIRMWARE_PARAMETERS` | Immediate exit listing available parameters |
| Invalid parameter value | `--param count=abc` where `count` is declared `integer` | Immediate exit with type hint |
| Missing required parameter | Declared `{required, true}` but not provided via `--param` | Immediate exit listing missing required parameters |
| Unknown output | `--output-<id>` not in `ALLOY_OUTPUT_SELECTABLE` | Immediate exit listing available output types |
| Missing output | Selectable output selected but `alloy_firmware_add_output` not called | Build error listing the missing output |
| Output file missing | `alloy_firmware_add_output` called but file does not exist | Build error with the registered path |

### 4.11 Caching

The build system uses caching at multiple levels to speed up repeated builds.

**Cache directory:** `ALLOY_CACHE_DIR` (`_cache/` in repository mode; `~/.grisp_alloy/cache/` in SDK mode). Fixed by mode, not user-configurable. When running SDK commands (e.g. `build firmware`) from the repository with `--sdk`, mode remains repository so the repo's `_cache/` is used; no separate configurable cache path is required.

**Cache structure:**

| Path | Purpose | Shared Across |
|------|---------|---------------|
| `buildroot/downloads/` | Buildroot package source tarballs | All SDK builds |
| `buildroot/ccache/` | Compiler cache | All SDK builds |
| `toolchain/` | Toolchain source tarballs | All toolchain builds |
| `toolchain/downloads/` | Toolchain component sources (GCC, binutils, glibc) | All toolchain builds |

**SDK mode:** In SDK mode the SDK does not run Buildroot and does not build the toolchain, so most of the typical cache entries above (Buildroot downloads, ccache, toolchain) are not used. The cache directory is still set (`ALLOY_CACHE_DIR`) and available for any nuggets (e.g. firmware hooks or project plugins) that want to use it.

**How caching works:**

- **Buildroot downloads:** The builder nugget's `pre_build` hook creates a symlink from the Buildroot source tree's `dl/` directory to `${ALLOY_CACHE_DIR}/buildroot/downloads`. Buildroot uses this symlink for package downloads.
- **Ccache:** The builder nugget's defconfig fragment enables ccache and points it at `${ALLOY_CACHE_DIR}/buildroot/ccache`.
- **Toolchain:** Toolchain nuggets use `${ALLOY_CACHE_DIR}/toolchain/` for component downloads.
- **Smelterl artefact:** Smelterl is built once and cached at `artefacts/tools/smelterl-VERSION`; reused across builds unless `--dev` is specified.

**Artefacts vs cache:** Artefacts (SDKs, firmware, projects) are build outputs in `ALLOY_ARTEFACT_DIR`. Cache is long-lived intermediate data in `ALLOY_CACHE_DIR`. Artefacts can be relocated or cleaned without affecting cache.

### 4.12 Reproducibility and Traceability

**Reproducibility goals:**

- **Deterministic builds:** Same inputs (nuggets, product, flags) produce the same SDK and firmware.
- **Pinned dependencies:** Nuggets declare version constraints; VCS sources are pinned to specific refs (branches, tags, commit hashes).
- **Always regenerate:** smelterl outputs are regenerated on every `build sdk` run (not cached); this avoids subtle desynchronization bugs.

**Traceability features:**

- **SDK manifest (`ALLOY_SDK_MANIFEST`):** Records product identity, main nugget tree (topological order with versions), planned auxiliary products, firmware capabilities, sdk output declarations by target, repository provenance (URL, commit, git describe, dirty status), Buildroot package versions/licenses, build environment (host OS, smelterl version, Buildroot version), and cryptographic integrity hash.
- **Project manifest (`ALLOY_PROJECT_MANIFEST`):** Records project name, version, type, profile, SDK provenance, build date, and dependency information with versions and repository URLs.
- **Firmware manifest (`ALLOY_FIRMWARE_MANIFEST`):** Wraps the SDK manifest plus all project manifests into a single firmware-level manifest, adding firmware build metadata, security flags, and integrity hash. The orchestrator adds this file at the **root of the firmware rootfs** during overlay creation (see [Firmware Build Flow](#57-firmware-build-flow)), so it appears as `/ALLOY_FIRMWARE_MANIFEST` in the final firmware image.
- **VCS provenance:** For every nugget source from a VCS repository, the manifest records the URL, commit hash, `git describe` output, and dirty flag.
- **Legal-info:** Buildroot's `make legal-info` plus smelterl's alloy-manifest.csv and alloy-licenses/ provide a complete SBOM-ready inventory.

### 4.13 Testing

**Bash script tests:** Scripts are tested with [bash_unit](https://github.com/bash-unit/bash_unit). Tests live in `scripts/tests/`, one file per tested script or utility (e.g. `test_common.sh`, `test_file_utils.sh`).

**Test execution:**

- **Locally:** Run `./scripts/tests/run_tests.sh` from the repository root. The wrapper checks for `bash_unit` on `PATH`; if missing, exits with a clear message and non-zero status.
- **CI:** CI installs bash_unit, then runs the same wrapper.

**Test structure:**

- `run_tests.sh` - Wrapper that discovers and runs all `test_*.sh` files.
- `test_*.sh` - One file per tested script. Test cases are functions named `test_*`; each file sources the code under test and uses bash_unit assertions.

**Not shipped in SDK:** The SDK pack step excludes `scripts/tests/` when copying `scripts/` into the SDK.

### 4.14 Plugin System

**Purpose:** Provide an extensible mechanism for supporting different project types (Erlang, Elixir, and potentially Rust, C, Python, or other languages in the future) without modifying the core orchestrator. The plugin system is designed as a category-agnostic framework - while the only category today is "project", the framework can be extended to other categories (e.g. deployment, packaging) without architectural changes.

**Design principles:**

1. **Key=value stdout for data exchange** - When a plugin needs to return structured data to the orchestrator (e.g. project name, version, runtime information), it writes `key=value` pairs to stdout, one per line. This is a simple, universal, language-agnostic contract that avoids complex serialization. The framework parses the output into a Bash associative array for the caller.

2. **Environment for context** - Plugins receive their context through environment variables set by the orchestrator (cross-compilation toolchain, SDK paths, Erlang/OTP locations). Plugins never discover these paths themselves; the environment is their sole input for build context.

3. **Detect-once** - Plugin detection (identifying the project type) runs once. After detection, the orchestrator records the type and dispatches all subsequent calls to the identified plugin without re-running detection. This avoids redundant filesystem checks and makes the build deterministic.

4. **Standardized staging output** - All project plugins produce the same directory structure as output (`staging/release/`, `staging/overlay/`, `ALLOY_PROJECT_MANIFEST`). The orchestrator does not need type-specific knowledge to package the result.

5. **Exit codes for status** - Plugins use exit code 0 for success and non-zero for failure. The framework enforces this: if a required plugin function fails, the build aborts with a clear error message identifying the plugin, the function, and the exit code.

6. **Optional functions** - Plugin functions are either required or optional. Required functions must exist and succeed. Optional functions are silently skipped if not defined, allowing plugins to only implement the capabilities they need.

**Plugin categories:**

Currently, the only category is **project** (see [§8.8 Project Plugins](#88-project-plugins)). The project plugin category provides type-specific logic for detecting, building, and extracting metadata from projects. Each project type (Erlang, Elixir) is implemented as a separate plugin file.

**Plugin loading:** Plugins are Bash scripts located in a category-specific directory (`scripts/plugins/<category>/`). The plugin framework loads all `*.sh` files from the directory, making their functions available for dispatch. Plugin files follow a naming convention: `<type>.sh` (e.g. `erlang.sh`, `elixir.sh`). Functions within a plugin follow the pattern `<category>_<type>_<action>` (e.g. `project_erlang_build`, `project_elixir_detect`).

**Plugin dispatch:** The framework provides generic dispatch functions that the orchestrator uses without knowledge of the underlying plugin type. For example, `plugin_call project erlang build "$@"` invokes `project_erlang_build` with the given arguments. The framework validates that the function exists before calling it and handles error reporting.

**Data exchange:** When a plugin needs to return structured data, the caller uses `plugin_read`, which captures the plugin function's stdout, checks its exit code, and parses the `key=value` output into a named Bash associative array. This ensures the caller never processes partial or corrupt data from a failed plugin.

See [§8.6.13 plugin_utils.sh](#8613-pluginutilssh) for the framework implementation and [§8.8 Project Plugins](#88-project-plugins) for the project plugin contract, including detailed function signatures and the cross-compilation environment available to plugins.

---

## 5. Processes

### 5.1 Command Dispatch Flow

**Purpose:** Parse user input and route to the appropriate command script.

**Steps:**

1. **Parse global options** - Scan the entire argument list and extract all recognized global options (`--debug`, `--dev`, `--force-vagrant`, `--keep-vagrant`, `--provision`, `--init-deps`, `--forward-env`, `--help`, `--version`) regardless of their position. Global options are consumed and removed from the token stream; the remaining tokens are passed to subsequent steps. This allows users to place global options before, between, or after the verb and command arguments (e.g. `alloy -d build firmware my_app` and `alloy build firmware -d my_app` are equivalent).
2. **Extract command** - Identify the verb (and optional noun) from the remaining arguments. Examples: `build sdk`, `build firmware`, `serve artefacts`, `grispio`.
3. **Source common utilities** - Load `scripts/utils/common.sh` (error handling, logging). Set up `ALLOY_*` environment variables.
4. **Detect mode** - See [§5.2](#52-mode-detection). Determine repository or SDK mode.
5. **Validate command for mode** - Check that the extracted command is available in the current mode. If not, exit with a clear error (e.g. "The `build sdk` command is only available in repository mode").
6. **Validate required runtime commands for the selected execution path** - Check only the host commands required before the next phase of execution. Example: when Vagrant delegation is required (non-Linux host or `--force-vagrant`), validate host-side sync prerequisites such as `rsync` via `require_commands` from `common.sh`. If `--init-deps` is set, also require `git` because dependency initialization mutates the local checkout. Fail fast with a clear error if a required command is missing.
7. **Validate repository-local dependencies for the selected command** - Before dispatching repository-mode `build sdk`, ensure the local `smelterl/` checkout is present and structurally valid. If it is missing and `--init-deps` was provided, initialize it with `git submodule sync --recursive smelterl` followed by `git submodule update --init --recursive smelterl`; otherwise fail with a clear message that tells the user to initialize the submodule or rerun with `--init-deps`.
8. **Check if Vagrant is needed** - Detect host OS. If not Linux (or if `--force-vagrant` is set), set `ALLOY_MODE` to the detected mode (`repo` or `sdk`). In SDK mode, also set `VAGRANT_DOTFILE_PATH=~/.grisp_alloy/vagrant/.vagrant` to relocate Vagrant state out of the potentially read-only SDK directory. Then enter the Vagrant flow (see [§5.3](#53-vagrant-abstraction-flow)). If Linux, continue to direct execution.
9. **Dispatch to command script** - Map command to script path: `verb noun` -> `scripts/commands/verb-noun.sh`; single-word command `verb` -> `scripts/commands/verb.sh`. Source the script or execute it with all remaining arguments and environment.
10. **Handle errors and cleanup** - Trap errors (`ERR`, `EXIT`). Clean up temporary files. Exit with the command script's exit code.

### 5.2 Mode Detection

**Purpose:** Determine whether alloy is running from a repository checkout or from an extracted SDK.

**Algorithm:**

1. Resolve the directory containing the `alloy` script (follow symlinks).
2. Check for the existence of `ALLOY_SDK_MANIFEST` in that directory.
3. If `ALLOY_SDK_MANIFEST` exists -> **SDK mode**.
4. If `ALLOY_SDK_MANIFEST` does not exist -> **Repository mode**.

**Effects:**

- **Repository mode:** All commands available. Build directory is `_build/`, artefact directory is `artefacts/`, cache directory is `_cache/` (all relative to the alloy root). Vagrant state (`.vagrant/`, `.vagrant.cache.vmdk`) also lives in the alloy root.
- **SDK mode:** Only `build project`, `build firmware`, `prepare sdk`, `serve artefacts`, and `grispio` available. Build directory is `~/.grisp_alloy/build/`, artefact directory is `~/.grisp_alloy/artefacts/`, cache directory is `~/.grisp_alloy/cache/`. Vagrant state lives under `~/.grisp_alloy/vagrant/` (`.vagrant/`, `cache.vmdk`, `ssh_config`), because the SDK directory may be read-only.

These paths are **fixed conventions** determined solely by the mode - they are not user-configurable. The corresponding environment variables (`ALLOY_BUILD_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_CACHE_DIR`) are set by the orchestrator based on the detected mode and must not be overridden by the user.

**Running SDK commands from the repository:** It is possible to run SDK-only commands (`build firmware`, `build project`, etc.) from the repository by invoking the repository's alloy script and passing `--sdk SDK_REF`. In that case mode is still **repository** (the script lives in the repo), so `ALLOY_CACHE_DIR` and `ALLOY_ARTEFACT_DIR` are the repository's (`_cache/`, `artefacts/`). The `--sdk` parameter only selects which SDK tree to use for build context (scripts, base images, `alloy_context.sh`); it does not change mode or path conventions. Thus firmware and project builds run from the repo automatically use the repo's cache and artefacts without any explicit custom cache or artefact directory options. This keeps behaviour consistent with Vagrant sync (repo content, including _cache and artefacts, is what gets synced) while allowing "run from repo, delegate to a given SDK" for consistency.

### 5.3 Vagrant Abstraction Flow

**Purpose:** Enable cross-platform builds by delegating to a Linux VM on non-Linux hosts.

**When triggered:** Host OS is macOS or Windows, or `--force-vagrant` is set.

**Steps:**

1. **Source `scripts/utils/vagrant_utils.sh`** - Load VM management functions (including environment forwarding helpers).
2. **Start VM** - Call `vagrant_start()`. If `--provision` is set, force provisioning. Provisioning is only for VM setup (packages, cache disk mount, etc.), not for syncing alloy repository content.
3. **Obtain Vagrant SSH config** - Run `vagrant ssh-config` and write the output to a file so that rsync and SSH can connect to the VM. **Repository mode:** write to `.vagrant.ssh_config` at the repository root (the directory containing the Vagrantfile). **SDK mode:** write to `~/.grisp_alloy/vagrant/ssh_config`; the SDK directory may be read-only and Vagrant state is already under `~/.grisp_alloy/vagrant/` (see [§5.2 Mode Detection](#52-mode-detection)). All subsequent rsync and SSH invocations that target the VM (steps 4 and 6 syncs, and any remote command execution that uses `ssh` rather than `vagrant ssh`) use this file via `ssh -F <path>` (e.g. `rsync -e "ssh -F <path>"`).
4. **Sync orchestrator content into `/home/vagrant/`** - The VM must have the `alloy` script and `scripts/` (and in repository mode, `nuggets/`) so that the delegated command can run. The source is always the **directory containing the alloy script** (the repository root in repository mode, or the SDK root in SDK mode). Rsync uses the SSH config from step 3 (`ssh -F <path>`). Use **`--delete`** so that files deleted on the host are removed in the VM. Only the following content is synced (all other paths are excluded):
   - **Repository mode:** Sync exactly: `alloy`, `scripts/`, `nuggets/`. Before sync, the orchestrator calls a function from `vcs_utils.sh` (see [§8.6.4](#864-vcsutilssh)) to write `.alloy_repo_info` at the repository root when the host tree is a VCS checkout (see [Repository provenance when delegating to Vagrant](#repository-provenance-when-delegating-to-vagrant)); that file is included in the synced content. The orchestrator does not need to know VCS details. Exclude at least: `.git/`, `.vagrant/`, `_build/`, `_cache/`, `artefacts/`. Do **not** sync `.git/`.
   - **SDK mode:** Sync exactly: `alloy`, `scripts/`, `motherlode/`, `images/`, `host/`, `staging/`, `ALLOY_SDK_MANIFEST`, `legal-info/`. The scripts and entry point in the VM therefore come from the SDK that the user is running from on the host; no separate `--sdk` path is involved.
5. **Identify external paths** - Parse the command arguments **and** relevant host environment variables to find local paths that must be made available in the VM:
   - **From arguments:** `-n`, `--nugget-path`, `--project`, `--sdk`, `--security-pack` flags.
   - **From environment:** `ALLOY_SECURITY_PACK` (if set and `--security-pack` is not on the command line). When the security pack is specified by env var only (no `--security-pack` on the command line), it is still synced to the VM in step 6 and `ALLOY_SECURITY_PACK` is rewritten to the VM path when the environment is forwarded (step 8), so the in-VM command sees the path where the pack was synced.
   - **Paths under the artefact directory:** If a path is under the host artefact directory (`ALLOY_ARTEFACT_DIR`), it is **not** synced to `/home/vagrant/_sync/`. Instead it is translated to the corresponding path under the in-VM artefact directory (where the artefact directory is mounted in the VM, e.g. `/home/vagrant/artefacts`). Record that mapping in the path map so argument and environment rewriting use the VM artefact path; no separate sync is needed because the artefact directory is already mounted in the VM.
6. **Sync external paths to VM** - For each external local path that is **not** under the artefact directory:
   - Generate a unique VM path: `/home/vagrant/_sync/<type>_<basename>/` (with numeric suffix for conflicts).
   - **Directory paths** (nugget paths, project dirs, SDK dirs, security pack directories): Rsync the host directory to the VM path over SSH, using the SSH config from step 3 (`rsync -e "ssh -F <path>"`). Use **`--delete`** so that files deleted on the host are removed in the VM.
   - **Single-file security pack** (`--security-pack` or `ALLOY_SECURITY_PACK` pointing to a file, not a directory): Copy only the file to the VM path. The VM path in this case is `/home/vagrant/_sync/secpack_<basename>` (the file itself, not a directory).
   - Record the mapping (host path -> VM path) in a path map.
   - VCS URLs are not synced (they are cloned directly in the VM).
7. **Rewrite arguments** - Walk the argument list. For each path-accepting flag, replace the host path with the corresponding VM path from the path map. Keep VCS URLs and other arguments unchanged.
8. **Collect forwarded environment** - Build the set of environment variables to forward to the VM (see [Environment Forwarding](#environment-forwarding) below). Rewrite path-bearing variables using the path map.
9. **Execute in VM** - Run the alloy command inside the VM with the forwarded environment injected. The command is executed as: `env VAR1=val1 VAR2=val2 ... /home/vagrant/alloy <rewritten_args>`. This ensures only the explicitly selected variables are set in the VM process, avoiding clashes with the VM's own system environment. Capture output and exit code.
10. **Cleanup** - If `--keep-vagrant` is not set, run `vagrant halt` (registered as a trap).
11. **Exit** - Exit with the VM command's exit code.

#### Repository provenance when delegating to Vagrant

In repository mode, the SDK manifest records repository provenance (URL, commit, `git describe`, dirty flag) for the grisp_alloy (alloy) repository.The orchestrator does **not** sync `.git/` into the VM (to keep sync small and fast), so the synced tree has no VCS metadata; the orchestrator therefore arranges for `.alloy_repo_info` to be written and synced so that smelterl can still get the correct provenance when it runs in the VM.

**Designed behaviour:** Before delegating to the VM (in repository mode), the orchestrator calls a function in `vcs_utils.sh` (`write_alloy_repo_info`) with the repository root. That function, when the directory is a VCS checkout, captures the repository's VCS state (URL, commit, describe, dirty) and writes `.alloy_repo_info` at the repository root per [Data Design - Alloy repository info file](01_DATA_DESIGN.md#alloy-repository-info-file-alloy_repo_info). The orchestrator does not need to know anything about VCS; it only invokes the utility. The file is synced to the VM as part of the orchestrator content in step 4. Smelterl still uses `smelterl_vcs` to get that repository's provenance; how `smelterl_vcs` does so (e.g. using `.alloy_repo_info` when present) is an internal detail of smelterl. If the host tree is not a VCS checkout (e.g. tarball), the utility does not write the file and smelterl gets no or partial provenance for that repo.

#### Environment Forwarding

When the build is delegated to a Vagrant VM, host environment variables are **not** automatically inherited by the in-VM process. The Vagrant flow selectively forwards a defined set of variables to avoid clashing with the VM's own system environment (`PATH`, `HOME`, `USER`, `SHELL`, `LANG`, etc.).

**What is forwarded:**

1. **All `ALLOY_*` variables** - Every environment variable matching the `ALLOY_*` prefix that is set in the host environment is forwarded to the VM. This includes user-set variables like `ALLOY_SECURITY_PACK`, `ALLOY_DEBUG`, and `ALLOY_DEV_MODE`. The only path-bearing variable that needs rewriting is:
   - `ALLOY_SECURITY_PACK`: rewritten to the VM path where the security pack was synced.
   - `ALLOY_BUILD_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_CACHE_DIR` are **not** forwarded from the host - they are fixed conventions set by the orchestrator inside the VM based on the in-VM directory layout. The host values are irrelevant to the VM.
   - All other `ALLOY_*` variables (non-path values like `ALLOY_DEBUG=2` or `ALLOY_TRACE=true`) are forwarded as-is.

2. **User-declared variables** - Additional variables are forwarded based on patterns from:
   - The `--forward-env PATTERN` global option (repeatable).
   - The `ALLOY_FORWARD_ENV` environment variable (comma-separated list of patterns).
   - Both sources are merged. Each pattern is either an **exact variable name** (e.g. `SIGNING_TOKEN`) or a **prefix pattern** ending with `*` (e.g. `SIGNING_*`, `ACME_*`).
   - For each pattern, all matching host environment variables are collected and forwarded **as-is** (no path rewriting). Use forwarded variables only for **non-path values** (tokens, URLs, PINs, etc.). **Do not use them for paths to files or directories:** forwarded variable values are not synced to the VM and are not rewritten; if a value is a host path, that path will not exist inside the VM and the in-VM process will see an invalid path. For any path that must be available in the VM (e.g. the security pack), use the dedicated mechanism (`--security-pack` or `ALLOY_SECURITY_PACK`), which is synced and rewritten.

**What is never forwarded:**

System variables are excluded from forwarding even if they match a pattern. The blocklist includes: `PATH`, `HOME`, `USER`, `SHELL`, `TERM`, `LANG`, `LC_*`, `SSH_*`, `DISPLAY`, `HOSTNAME`, `LOGNAME`, `MAIL`, `PWD`, `OLDPWD`, `SHLVL`, `TMPDIR`, `XDG_*`, `LD_*`, `DYLD_*`.

**What is consumed (not forwarded):**

- `ALLOY_FORWARD_ENV` itself is consumed by the Vagrant flow and is **not** forwarded to the VM (it is a host-side directive, not a build variable).
- Vagrant-specific global options (`--force-vagrant`, `--keep-vagrant`, `--provision`, `--forward-env`) are consumed by the entry-point script and are not passed as arguments to the in-VM command.

**Example:**

```bash
# CI pipeline: remote signing pack with custom env vars
export ALLOY_SECURITY_PACK="./company_secpack/"
export SIGNING_SERVICE_URL="https://signing.internal:9999"
export SIGNING_TOKEN="${CI_SIGNING_SECRET}"
export ALLOY_FORWARD_ENV="SIGNING_*"
export ALLOY_DEBUG="2"

# On macOS, alloy detects non-Linux and enters Vagrant flow:
# - ./company_secpack/ is synced to /home/vagrant/_sync/secpack_company_secpack/
# - ALLOY_SECURITY_PACK is rewritten to /home/vagrant/_sync/secpack_company_secpack/
# - SIGNING_SERVICE_URL and SIGNING_TOKEN are forwarded as-is (match SIGNING_*)
# - ALLOY_FORWARD_ENV is consumed, not forwarded
alloy build firmware --variant secure my_project
```

**Implementation detail:** The environment is injected using the `env` command prefix:

```bash
vagrant ssh -c "env ALLOY_SECURITY_PACK='/home/vagrant/_sync/secpack_company_secpack/' \
  ALLOY_DEBUG='2' \
  SIGNING_SERVICE_URL='https://signing.internal:9999' \
  SIGNING_TOKEN='s3cr3t' \
  /home/vagrant/alloy build firmware --security-pack /home/vagrant/_sync/secpack_company_secpack/ \
  --variant secure my_project"
```

Values are shell-escaped to prevent injection. If the number of forwarded variables is large, the Vagrant flow writes them to a temporary file on the VM and sources it instead (to avoid exceeding shell command-line length limits).

#### Vagrantfile Specification

The Vagrantfile is a single file, parameterized by host environment variables, that configures the build VM for both repository and SDK modes.

##### 1. Input environment variables (host-side)

The Vagrantfile reads these environment variables at parse time. **`VM_MEMORY`, `VM_CORES`, `VM_CACHE_DISK_SIZE`, and `VM_PRIMARY_DISK_SIZE`** can be exported when calling the alloy command on the host (e.g. `export VM_MEMORY=8192; alloy build firmware my_project`). They may only take effect the first time the VM is created or when provisioning is run (`--provision`); changing them after the VM exists does not automatically resize or reconfigure the VM until the next create or provision.

| Variable | Description | Default |
|----------|-------------|---------|
| `ALLOY_MODE` | `repo` or `sdk`. Determines host-side paths for shared folders, cache disk, and state directory. Set by the alloy entry-point before invoking Vagrant. | `repo` |
| `VM_MEMORY` | VM RAM in MB. | `16384` (16 GB) |
| `VM_CORES` | VM CPU count. | `8` |
| `VM_CACHE_DISK_SIZE` | Persistent cache disk size in MB. | `10240` (10 GB) |
| `VM_PRIMARY_DISK_SIZE` | Optional. Resize the VM primary disk (e.g. `96GB`). Format: `<number><KB\|MB\|GB\|TB>`. If unset, the box default is used. | unset |
| `VAGRANT_DOTFILE_PATH` | In SDK mode, set by the alloy entry-point to `~/.grisp_alloy/vagrant/.vagrant` to relocate Vagrant state out of the SDK directory. | unset (Vagrant default: `.vagrant/` in Vagrantfile directory) |

##### 2. Base box and required plugins

- **Box:** `bento/ubuntu-24.04` (Ubuntu LTS).
- **Required plugins:** `vagrant-scp`, `vagrant-exec`. For VirtualBox: `vagrant-vbguest` (guest additions).

##### 3. State directory layout (host-side)

Depends on `ALLOY_MODE`:

- **Repository mode (`repo`):** Vagrant state lives in the alloy root (the Vagrantfile's directory):
  - `.vagrant/` - Vagrant machine state (default location).
  - `.vagrant.cache.vmdk` - Persistent cache disk image.
  - `.vagrant.ssh_config` - SSH config generated by the Vagrant abstraction flow (`vagrant ssh-config` output).
- **SDK mode (`sdk`):** Vagrant state lives under `~/.grisp_alloy/vagrant/`:
  - `.vagrant/` - Via `VAGRANT_DOTFILE_PATH`.
  - `cache.vmdk` - Persistent cache disk image.
  - `ssh_config` - SSH config generated by the Vagrant abstraction flow (`vagrant ssh-config` output).

The Vagrantfile computes the cache disk base directory from `ALLOY_MODE`: if `sdk`, use `File.expand_path("~/.grisp_alloy/vagrant/")`; if `repo` (or unset), use `__dir__` (the Vagrantfile's own directory, i.e. the alloy root).

##### 4. Persistent cache disk creation

The cache disk is a VMDK file created on first use and reused across VM restarts. Creation is platform-dependent:

- **Linux host:** Create with `qemu-img create -f vmdk <path> <size>M`, then format with `mkfs.ext4 -L VAGRANT_CACHE <path>`.
- **macOS host:** Cannot format ext4 directly. Create a raw image with `dd`, attach via `hdiutil`, format as FAT32 dummy (`newfs_msdos -F 32 -v TMPCACHE`), detach, convert to VMDK with `qemu-img convert`. The in-VM provisioning script detects the FAT32 dummy label and reformats to ext4.

If the VMDK file already exists, skip creation entirely.

##### 5. VirtualBox-specific: VMDK registration

VirtualBox requires VMDK disks to be registered as media before attachment. The Vagrantfile calls `VBoxManage showmediuminfo <path>` to check if already registered, and `VBoxManage openmedium disk <path>` if not. This only runs when VirtualBox is the active provider.

##### 6. Provider configuration

Two providers are supported:

- **VMware Desktop:**
  - GUI disabled, no linked clones.
  - Network: `vmxnet3` adapter.
  - Memory and CPU from `VM_MEMORY` / `VM_CORES`.
  - Cache disk attachment: On ARM64 hosts, attach via NVMe controller (`nvme0:0`). On x86_64 hosts, attach via PVSCSI controller (`scsi1:0`). Both set `mode = persistent`.
- **VirtualBox:**
  - Memory and CPU from `VM_MEMORY` / `VM_CORES`.
  - Cache disk attachment: Add a SATA controller (`"SATAController"`), attach the registered VMDK to SATA port 1.

Both providers set a VM display name (e.g. `"GRiSP Alloy Builder"`).

##### 7. Primary disk resize (optional)

If `VM_PRIMARY_DISK_SIZE` is set, use `config.vm.disk :disk, size: "<value>", primary: true` to resize the boot disk.

##### 8. Provisioning

Two shell provisioners, both `privileged: true`, `run: 'once'`:

- **`upgrade_system`:**
  - Mount the cache disk: find the attached disk device by label (`VAGRANT_CACHE`); if not found, look for the FAT32 dummy label (`TMPCACHE`) and reformat to ext4 with the correct label. Mount at `/home/vagrant/_cache`. Add an fstab entry for persistence across reboots. Set ownership to `vagrant:vagrant`.
  - Force IPv4 for apt (`Acquire::ForceIPv4 "true"`), switch apt sources to HTTPS.
  - On ARM64 hosts: `dpkg --add-architecture arm64`. On x86_64 hosts: `dpkg --add-architecture amd64`.
  - Full system upgrade (`apt-get full-upgrade -y`), `apt-get autoremove -y`, `apt-get clean`.
- **`install_packages`:**
  - Remove snapd and lxd (`apt-get purge -y snapd lxd`).
  - Install build dependencies: `build-essential`, `bison`, `flex`, `gperf`, `libncurses5-dev`, `texinfo`, `help2man`, `libssl-dev`, `gawk`, `libtool-bin`, `automake`, `lzip`, `python3`, `wget`, `curl`, `ca-certificates`, `git`, `git-lfs`, `bzr`, `cvs`, `mercurial`, `subversion`, `unzip`, `bc`, `mtools`, `u-boot-tools`, `squashfs-tools`, `mc`, `pv`, `keyutils`, `qemu-user`, `qemu-user-static`, `gcc-x86-64-linux-gnu`, `binutils-x86-64-linux-gnu`.
  - On ARM64 hosts: also `libc6:arm64`.
  - Set locale: `LC_ALL=C`.
  - Create `/opt/grisp_alloy` owned by `vagrant` (used for SDK extraction when using the `--sdk` parameter in **repository mode**; in SDK mode the orchestrator content is rsynced from the host SDK into `/home/vagrant/`, not extracted here).

##### 9. File provisioning

- **Repository mode:** The alloy repository files (`alloy` script, `scripts/`, `nuggets/`, etc.) are synced into `/home/vagrant/` by the **Vagrant abstraction flow** (see steps 2-4 of [§5.3](#53-vagrant-abstraction-flow)) for every delegated command, using rsync of the repository root. This is what makes development edits immediately visible inside the VM. The Vagrantfile must not require reprovisioning just to refresh these files.
- **SDK mode:** The SDK root (the alloy script's directory) is synced into `/home/vagrant/` in step 4 of [§5.3](#53-vagrant-abstraction-flow), so the VM has `alloy`, `scripts/`, and the rest of the SDK from the host. The Vagrantfile does not provision alloy files in this case.

##### 10. Shared folders (artefact directory)

The artefact directory is synced bidirectionally between host and VM so build outputs are immediately visible on the host:

- **VMware Desktop:** Use GHFS (VMware guest-host filesystem): `synced_folder <host_artefact_dir>, "/home/vagrant/artefacts", create: true`.
- **VirtualBox:** Use NFS: `synced_folder <host_artefact_dir>, "/home/vagrant/artefacts", create: true, type: "nfs", nfs_version: 3, nfs_udp: false, mount_options: ['vers=3,tcp']`.

The host-side artefact path depends on mode:

- **Repository mode:** `artefacts/` (relative to alloy root, i.e. `File.join(__dir__, "artefacts")`).
- **SDK mode:** `~/.grisp_alloy/artefacts/` (absolute, i.e. `File.expand_path("~/.grisp_alloy/artefacts")`).

##### 11. SSH

- `config.ssh.forward_agent = true` - Allows the VM to use the host's SSH keys (for git clone over SSH, VCS URL nugget paths, etc.).

##### 12. In-VM directory layout

```
/home/vagrant/
├── (alloy repository or SDK files)  # Provisioned or synced
├── artefacts/                        # Shared folder (bidirectional)
├── _cache/                           # Persistent cache disk (ext4, survives VM restarts)
├── _build/                           # Ephemeral build directory
├── _sync/                            # External path syncs (created at runtime by vagrant_utils.sh)
│   ├── nuggets_custom/
│   ├── project_my_app/
│   ├── secpack_company_secpack/
│   └── secpack_sign-tool
└── .profile / .bashrc                # Standard vagrant user shell config
```

### 5.4 Nugget Staging Flow

**Purpose:** Stage all nugget sources into a single motherlode directory before invoking smelterl.

**Steps:**

1. **Create motherlode directory** - `${ALLOY_BUILD_DIR}/motherlode/`.
2. **Stage builtin nuggets** - Rsync `./nuggets/` to `${ALLOY_BUILD_DIR}/motherlode/builtin/` (using `--link-dest` for hardlink optimization).
3. **Process environment variable paths** - For each path in `ALLOY_NUGGET_PATH` (colon-separated): stage as described below.
4. **Process command-line paths** - For each `-n` / `--nugget-path` argument: stage as described below.

**Per-path staging:**

- **Local directory:** Rsync to `${ALLOY_BUILD_DIR}/motherlode/<dirname>/`. If multiple paths share the same basename, append a numeric suffix (`<dirname>_2`, `<dirname>_3`).
- **VCS URL:** Clone (or validate existing clone) to `${ALLOY_BUILD_DIR}/motherlode/<reponame>/` using `vcs_utils.sh`. Extract `reponame` from URL. Validate ref, URL match, and working tree cleanliness unless dirty repositories are explicitly allowed for the command (via `--allow-dirty` or `ALLOY_ALLOW_DIRTY=true`). If URL mismatch, reclone.

**Result:** All nugget repositories are available under a single directory (`motherlode/`). This directory is passed to smelterl as `--motherlode` and to Buildroot as `ALLOY_MOTHERLODE`.

### 5.5 SDK Build Flow

**Purpose:** Orchestrate the complete SDK build from nuggets to packed tarball.

**Precondition:** Repository mode.

**Steps:**

1. **Parse and validate arguments** - Require `PRODUCT_NUGGET`. Source utilities.
2. **Set up build directory** - `${ALLOY_BUILD_DIR}/sdk/${PRODUCT}/` with:
   - `plan/` for `build_plan.term` and `build_plan.env`,
   - `targets/<TARGET_ID>/` target-local build trees,
   - shared `staging/` for final SDK assembly inputs,
   - `motherlode/` staged nugget sources.
   Export `ALLOY_SDK_STAGING_DIR="${BUILD_DIR}/staging"` for manifest/legal and pack phases (see [Data Design - SDK build directory](01_DATA_DESIGN.md#sdk-build-directory)).
3. **Stage nuggets** - See [§5.4](#54-nugget-staging-flow). Result: `${BUILD_DIR}/motherlode` populated.
4. **Ensure smelterl** - See [§5.11](#511-smelterl-management-flow). Result: `smelterl-<VERSION>` executable available.
5. **Run `smelterl plan`** - Generate `build_plan.term` and optional `build_plan.env`; pass plan-time `--extra-config` inputs.
   - These extra-config values are used for configuration consolidation and defconfig model preparation at plan time (not for runtime hook identity variables).
   - `ALLOY_SDK_DIR` and `ALLOY_FIRMWARE_WORK_DIR` may be passed as placeholder/literal references so generated contexts can resolve them later at runtime.
   - Defconfig wrapper hook entries are injected automatically per target by smelterl defconfig model build.

   Example:
   ```bash
   smelterl plan \
     --product "${PRODUCT}" \
     --motherlode "${BUILD_DIR}/motherlode" \
     --extra-config 'ALLOY_ROOT_DIR=${ALLOY_ROOT_DIR}' \
     --extra-config 'ALLOY_ARTEFACT_DIR=${ALLOY_ARTEFACT_DIR}' \
     --extra-config 'ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}' \
     --extra-config 'ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}' \
     --extra-config 'ALLOY_SDK_DIR=${ALLOY_SDK_DIR}' \
     --extra-config 'ALLOY_FIRMWARE_WORK_DIR=${ALLOY_FIRMWARE_WORK_DIR}' \
     --extra-config 'ALLOY_DEBUG=${ALLOY_DEBUG}' \
     --extra-config 'ALLOY_TRACE=${ALLOY_TRACE}' \
     --output-plan "${BUILD_DIR}/plan/build_plan.term" \
     --output-plan-env "${BUILD_DIR}/plan/build_plan.env"
   ```
6. **Load target list from plan** - Main target plus auxiliary targets (`AuxId`s).
   - Authoritative source: `build_plan.term`.
   - Shell convenience: `build_plan.env` may be sourced by the orchestrator script to obtain target IDs and loop metadata without re-parsing the Erlang term.
7. **For each target in build order (all auxiliaries first, then main):**
   - Create target-local paths: `br2_external/`, `workspace/`, `alloy_context.sh`.
   - Create hook wrapper symlinks in `br2_external/board/<TARGET_ID>/scripts/`:
     - `post-build.sh`, `post-image.sh`, `post-fakeroot.sh` -> `scripts/buildroot/script_hook.sh`.
   - Create context symlink in the same directory:
     - `alloy_context.sh` -> target-local generated context.
   - Run `smelterl generate --plan ... --auxiliary <AuxId>` for auxiliaries; run `smelterl generate --plan ...` (no `--auxiliary`) for main.
   - Generate target-local Buildroot files and target context (`external.desc`, `Config.in`, `external.mk`, defconfig, `alloy_context.sh`).
   - Auxiliary contexts are SDK-build contexts and intentionally omit firmware/embed/fs-priority control arrays.

   Example (auxiliary target):
   ```bash
   smelterl generate \
     --plan "${BUILD_DIR}/plan/build_plan.term" \
     --auxiliary "${AUX_ID}" \
     --output-external-desc "${BUILD_DIR}/targets/${AUX_ID}/br2_external/external.desc" \
     --output-config-in "${BUILD_DIR}/targets/${AUX_ID}/br2_external/Config.in" \
     --output-external-mk "${BUILD_DIR}/targets/${AUX_ID}/br2_external/external.mk" \
     --output-defconfig "${BUILD_DIR}/targets/${AUX_ID}/br2_external/configs/${AUX_ID}_defconfig" \
     --output-context "${BUILD_DIR}/targets/${AUX_ID}/alloy_context.sh"
   ```

   Example (main target, generation-only pass before legal/manifest consolidation):
   ```bash
   smelterl generate \
     --plan "${BUILD_DIR}/plan/build_plan.term" \
     --output-external-desc "${BUILD_DIR}/targets/main/br2_external/external.desc" \
     --output-config-in "${BUILD_DIR}/targets/main/br2_external/Config.in" \
     --output-external-mk "${BUILD_DIR}/targets/main/br2_external/external.mk" \
     --output-defconfig "${BUILD_DIR}/targets/main/br2_external/configs/main_defconfig" \
     --output-context "${BUILD_DIR}/targets/main/alloy_context.sh"
   ```
8. **Run `pre_build` hooks once per nugget across all targets** - Traverse targets in build order (auxiliaries then main), and execute each nugget `pre_build` hook at most once globally.
   - Deduplication key is **nugget identifier** (not target). Keep a global "already-run" set for this SDK build.
   - If the same nugget appears in multiple targets (for example shared builder/toolchain/platform backbone), its `pre_build` hooks run only on first encounter and are skipped for later targets.
   - First encounter order is deterministic from target traversal order (all auxiliaries first, then main) and each target's topology order.
   - This phase typically performs Buildroot source setup (builder nugget) and cross-toolchain setup/validation (toolchain nugget).
   - Buildroot source path is provided via consolidated config (for example `ALLOY_CONFIG_BUILDROOT_PATH`) and used in step 9.
9. **Build each target with Buildroot** - For each target, run `make <target_defconfig>` then `make` with target-local `O=` and `BR2_EXTERNAL=`.
   - Pass runtime `ALLOY_*` values to `make` so `script_hook.sh` and SDK-time hooks receive them (for example `ALLOY_ROOT_DIR`, `ALLOY_SDK_STAGING_DIR`, `ALLOY_BUILD_DIR`, `ALLOY_MOTHERLODE`, debug/trace flags).
   - Append `V=1` only when debug verbosity requires full Buildroot command tracing.
   - Each target workspace (`O=` directory) remains usable for manual Buildroot debugging (`make menuconfig`, `make V=1`).
10. **Run `make legal-info` per target** - Capture target-local legal-info trees.
    - For each target workspace, run legal-info with the same target-local Buildroot `O=` and `BR2_EXTERNAL=` context.
    - Result per target: `targets/<TARGET_ID>/workspace/legal-info/`.
11. **Collect auxiliary sdk outputs** - Validate registrations from auxiliary targets, stage them under `${ALLOY_SDK_STAGING_DIR}/auxiliary/<AUX_ID>/outputs/<OUTPUT_ID>/...`, and prepare main-target consumption variables (`ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>`, optional unique alias `ALLOY_SDK_OUTPUT_<OUTPUT_ID>`). These variables are injected into main context for SDK-time and firmware-time consumers.
12. **Main-target manifest/legal pass** - Run one main-target generate call for legal/manifest consolidation:
   - Pass repeatable `--buildroot-legal` values (one per target legal tree: auxiliaries and main), plus `--output-manifest` (and optional `--export-legal` / `--include-sources`).
   - Smelterl merges legal data from all provided legal trees and emits final `legal-info/README` and `ALLOY_SDK_MANIFEST`, including auxiliary metadata and merged legal references.
   - Final SDK export keeps one merged `legal-info/` tree (no per-target legal subtrees).

   Example:
   ```bash
   smelterl generate \
     --plan "${BUILD_DIR}/plan/build_plan.term" \
     --buildroot-legal "${BUILD_DIR}/targets/encrypted_initramfs/workspace/legal-info" \
     --buildroot-legal "${BUILD_DIR}/targets/main/workspace/legal-info" \
     --export-legal "legal-info" \
     ${INCLUDE_SOURCES:+--include-sources} \
     --output-manifest "${ALLOY_SDK_STAGING_DIR}/ALLOY_SDK_MANIFEST"
   ```
13. **Pack SDK** - See [§5.10](#510-sdk-packing-flow). Result: SDK tarball in `artefacts/sdk/`.

### 5.6 Project Build Flow

**Purpose:** Build an Erlang/Elixir project release using SDK host tools.

**Precondition:** SDK must be available (either SDK mode or specified via `--sdk`).

**Steps:**

1. **Resolve SDK** - If in SDK mode, use current directory. If repository mode with `--sdk`, choose an extraction directory then extract the SDK (overwriting any existing content there): if `/opt/grisp_alloy` exists and is writable, use it and always overwrite any existing SDK there; if it does not exist, try to create it and use it if creation succeeds and the directory is writable; if creation fails (e.g. insufficient permissions) or the directory is not writable, use a temporary directory instead. When a temporary directory is used, the orchestrator must clean it in step 14; no cleanup is required when using `/opt/grisp_alloy`. Set `ALLOY_SDK_DIR` to the SDK root.
2. **Ensure SDK is relocated** - Source `scripts/utils/sdk_utils.sh` and call `ensure_sdk_relocated "${ALLOY_SDK_DIR}"`. No-op if the SDK is already at the recorded path; otherwise relocates (if writable) or aborts with instructions to run `alloy prepare sdk`. See [§8.6.6 sdk_utils.sh](#866-sdkutilssh).
3. **Source alloy_context.sh** - Set `ALLOY_MOTHERLODE="${ALLOY_SDK_DIR}/motherlode"`. Source `${ALLOY_SDK_DIR}/scripts/alloy_context.sh` to load `ALLOY_CONFIG_*` and `ALLOY_EXPORT_*` for use by `setup_cross_env` and plugins.
4. **Validate SDK directory** - Source `scripts/utils/env_utils.sh` and call `validate_sdk_dir "${ALLOY_SDK_DIR}"` to ensure `host/` and `images/` exist. Exit non-zero with a clear error if not.
5. **Resolve project source** - Target: `${BUILD_DIR}/project/${PROJECT_NAME}/workspace/`. If `PROJECT_SOURCE` is a VCS URL: if a repository already exists there, ensure the remote URL matches; if it does not, remove the existing directory and clone again; if the URL matches, ensure the required ref (commit, tag, or branch) is checked out by resetting (e.g. fetch then checkout or reset). If `PROJECT_SOURCE` is a local directory, rsync from it into the workspace with `--delete` so the workspace mirrors the source exactly (including removal of files that no longer exist in the source).
6. **Load plugins and detect project type** - Source `scripts/utils/plugin_utils.sh` and `scripts/plugins/project.sh`. The project plugin loader calls `plugin_load project "${ALLOY_SDK_DIR}/scripts/plugins/project"` to source all plugin files from the directory. Then call `project_detect "${PROJECT_DIR}"` which iterates loaded plugins and calls each `project_<type>_detect` function until one succeeds (returns 0). The detected type is recorded for all subsequent dispatch calls. See [§8.8 Project Plugins](#88-project-plugins).
7. **Set up cross-compilation environment** - Source `scripts/utils/env_utils.sh` and call `setup_cross_env "${ALLOY_SDK_DIR}"`. Preconditions (steps 2–4) have already been satisfied. This sets up the complete cross-compilation environment that all plugins rely on:
   - Cross-compiler toolchain: `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, `STRIP`, and related variables, all pointing to the SDK's embedded cross-compiler.
   - `PATH`: prepended with `${ALLOY_SDK_DIR}/host/bin` and `${ALLOY_SDK_DIR}/host/usr/bin`, making the SDK's rebar3, escript, mix, and cross-compiler binaries available.
   - Host Erlang/OTP: `HOST_ERLANG` (for running build tools), `HOST_REBAR3` (SDK's rebar3 path), `OTP_VERSION`.
   - Target Erlang/OTP: `TARGET_ERLANG` pointing to `${ALLOY_SDK_DIR}/staging/usr/lib/erlang` (cross-compiled ERTS and OTP applications for the target architecture).
   - NIF compilation: `ERL_CFLAGS`, `ERL_LDFLAGS`, `ERTS_INCLUDE_DIR`, `ERL_EI_INCLUDE_DIR`, `ERL_EI_LIBDIR`, `REBAR_TARGET_ARCH`.
   - pkg-config: `PKG_CONFIG`, `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR` pointing to the SDK's target sysroot.
   - Build-for-host tools: `CC_FOR_BUILD`, `CXX_FOR_BUILD`, etc. set to native system tools for host-only build steps.
   After this step, the SDK's embedded rebar3, escript, and mix (if `feature_elixir` is included) are available on `PATH`. See [§8.6.7](#867-envutilssh).
8. **Create staging and build** - Create the project artefact staging directory `${BUILD_DIR}/project/${PROJECT_NAME}/staging/` with `release/` and `overlay/` subdirectories. Call `project_build "${PROJECT_TYPE}" "${PROJECT_DIR}" "${PROFILE}" "${STAGING_DIR}/release" "${STAGING_DIR}/overlay"` which dispatches to `project_<type>_build` via `plugin_call`. The plugin builds the OTP release using host tools (bundling the **target** Erlang/OTP runtime from the SDK's `staging/usr/lib/erlang/`) and writes the release directly into the given release directory; it may optionally write overlay content (rootfs files, and optionally `ALLOY_FS_PRIORITIES` at the overlay root) into the given overlay directory. The orchestrator does not copy from a plugin-returned path - the plugin is free to write whatever it wants into the two staging directories. See [§8.8.3 erlang.sh](#883-erlangsh) and [§8.8.4 elixir.sh](#884-elixirsh) for type-specific build details.
9. **Scrub OTP release** - Source `scripts/utils/otp_utils.sh` and call `scrub_otp_release "${STAGING_DIR}/release"`. This strips debug symbols from ELF binaries and removes build-time-only files so the project artefact is minimal before packaging. The scrub detects whether the directory is an OTP release (e.g. `lib/` and `releases/` present); if not (e.g. non-OTP project type), it returns 0 without modifying. There is exactly one release directory per project build. See [OTP release scrubbing](#otp-release-scrubbing) and [§8.6.8 otp_utils.sh](#868-otputilssh).
10. **Validate target architecture of release and overlay** - Before packaging, validate that all ELF executables and shared libraries in the staging release directory and in the staging overlay directory are built for the **target** architecture. This detects cross-compilation mistakes early (e.g. host binaries or wrong-architecture NIFs ending up in the release or overlay).

   **Scope:** Scan `${STAGING_DIR}/release/` and `${STAGING_DIR}/overlay/` for regular files that are ELF (magic bytes `\x7fELF`). Include both executables (e.g. beam.smp, erl) and shared libraries (`.so`). Skip non-ELF files (scripts, BEAM files, data, symlinks). Optionally support excluding subtrees (e.g. a directory containing a marker file like `.noarchcheck`, or paths reported by the project plugin) for known host-only tools that are intended to run on the build host rather than on the target.

   **Expected architecture:** The expected ELF Machine (and optionally class) for the target is determined from the SDK's cross-compilation environment. One reliable method: compile a minimal C program (e.g. `int main() { return 0; }`) with the SDK's cross-compiler (from step 4), then run the SDK's `readelf -h` (or the cross-compiler-prefixed `readelf`) on the resulting binary and capture the "Machine:" and optionally "Class:" lines. That yields the canonical expected type for the target. Alternatively, read the SDK manifest's `target_arch` (GNU triplet, e.g. `aarch64-linux-gnu`) and use a fixed mapping from triplet to ELF machine type (e.g. aarch64 -> AArch64, x86_64 -> Advanced Micro Devices X86-64); the probe method is preferred when the toolchain is available so the mapping stays consistent with the actual compiler.

   **Per-file check:** For each ELF file in scope, run `readelf -h` (using the SDK's `readelf` or `$CROSSCOMPILE-readelf` so the tool matches the toolchain). Parse the "Machine:" (and if needed "Class:") output. Compare to the expected type. If they differ, fail the build immediately: print a clear error to stderr including the file path, the expected Machine (and Class), and the actual Machine (and Class), and state that the file was compiled for the host or a different target and will not work on the device. Non-zero exit so the orchestrator aborts.

   **Output:** On success, the step produces no artefact; it only validates. On failure, the script exits non-zero and the build stops. The project build command invokes this validation immediately after step 9 (Scrub OTP release). The validation may be implemented as a function (e.g. `validate_release_target_arch`) in the same utility that provides the cross-compilation environment, or as a dedicated script under `scripts/`; in either case it receives a directory (release and/or overlay paths), uses the already-configured cross-compiler and `readelf` from step 7, and follows the algorithm above.
11. **Extract project info** - Call `project_info "${PROJECT_TYPE}" "${STAGING_DIR}/release" "${PROJECT_DIR}"` which dispatches to `project_<type>_info` via `plugin_read`. The release directory is the one the plugin wrote in step 8 (and was scrubbed in step 9). The plugin writes key=value pairs to stdout; the framework parses them into an associative array. Required keys: `name` (release name), `version` (release version). Optional keys: `app_name` (main OTP application name), `app_version` (main OTP application version), `runtime`, `otp_version`. If `app_name` is not provided, it defaults to `name`. The release name and version come from the OTP release directory structure (`_build/<profile>/rel/<RELEASE_NAME>/releases/<RELEASE_VERSION>/`). The application name is extracted from the `.app.src` file (Erlang) or `mix.exs` `:app` key (Elixir) and validated against `lib/<app>-*` in the built release; the application version is extracted from the `lib/<app_name>-<version>/` directory. Derive the project `id` (atom) from the release name by lowercasing and replacing hyphens with underscores. Capture the project's own VCS information (URL, commit, describe, dirty) if the project source is a git repository. Collect dependency information from the project's lock files (`rebar.lock` or `mix.lock`). For each dependency, check whether a `_checkouts/dep_name/` directory exists in the project workspace:
   - If it does and is a git repository: record the checkout's actual VCS state (URL, commit, describe, dirty) and set `{checkout, true}` with `{type, git}`. The repository entry reflects the checkout's state, not the lock file's.
   - If it does but has no VCS: record as `{type, path}` with `{checkout, true}` and `{ref, <<"_checkouts/dep_name">>}`.
   - If it does not exist: use the lock file entry as-is (no `checkout` flag).
   - This ensures the manifest always reflects the **actual code used** at build time, with checkout overrides clearly marked for traceability.
12. **Write manifest** - Write `ALLOY_PROJECT_MANIFEST` at the staging root (`${STAGING_DIR}/`) using `write_project_manifest()` from `manifest_utils.sh` (delegates to `manifest-tool create-project`; produces an Erlang term file with integrity hash). See [Data Design - Project Manifest](01_DATA_DESIGN.md#project-manifest-specification). The staging directory already contains `release/` and `overlay/` as written by the plugin in step 8 and scrubbed in step 9.
13. **Create tarball** - Archive `staging/` to `artefacts/projects/project-NAME-VERSION-TARGET-ARCH.tgz`. `TARGET-ARCH` is sourced from the SDK's `target_arch` manifest field (the GNU architecture triplet).
14. **Cleanup** - If SDK was extracted to temp, remove it.

### 5.7 Firmware Build Flow

**Purpose:** Assemble a flashable firmware image from SDK base and project artefacts.

**Precondition:** SDK must be available.

**Steps:**

0. **Parse arguments** - Apply the [two-phase argument parsing](#argument-parsing) described in [§3.3](#33-alloy-build-firmware). Alloy-level global options (`--debug`, `--force-vagrant`, etc.) have already been extracted by the entry-point script (see [§3.0](#30-command-syntax)). Phase 1 extracts all command options (`--sdk`, `--variant`, `--overlay`, `--security-pack`, `--param`, `--output-*`, `--include-legal`, `--list-*`). Phase 2 parses the remaining positional tokens left-to-right into a project list: each bare token starts a new project entry, `--name` assigns an installation name to the preceding entry, and any other `--*` token is an error. The result is a list of `(PROJECT_REF, NAME)` pairs - `NAME` may be `unset` at this point (defaulted later in step 7) - plus the collected command options. If no `PROJECT_REF` is found and no `--list-*` flag is set, abort.
1. **Resolve SDK** - If SDK mode, continue in the current directory. If repository mode with `--sdk`, choose an extraction directory then extract the SDK (overwriting any existing content there) and delegate to the SDK's own `alloy` script (setting `ALLOY_ARTEFACT_DIR` to the repository's artefact directory so outputs land in the expected location): if `/opt/grisp_alloy` exists and is writable, use it and always overwrite any existing SDK there; if it does not exist, try to create it and use it if creation succeeds and the directory is writable; if creation fails (e.g. insufficient permissions) or the directory is not writable, use a temporary directory instead. When a temporary directory is used, the orchestrator must clean it in the cleanup step (step 20); no cleanup is required when using `/opt/grisp_alloy`.
2. **Ensure SDK is relocated and source alloy_context.sh** - Set `ALLOY_SDK_DIR` to the SDK root. Source `scripts/utils/sdk_utils.sh` and call `ensure_sdk_relocated "${ALLOY_SDK_DIR}"` (no-op if already at recorded path; otherwise relocates or aborts). Then set `ALLOY_MOTHERLODE="${ALLOY_SDK_DIR}/motherlode"` and source `${ALLOY_SDK_DIR}/scripts/alloy_context.sh`. Validate that this is a main context (`ALLOY_IS_AUXILIARY=false`) and that firmware capability variables are present; otherwise abort because firmware builds are defined only for the main product context.
2b. **Resolve security pack** - If `--security-pack` was specified, use that value. Otherwise, if the `ALLOY_SECURITY_PACK` environment variable is set, use that value. If a security pack value is present, call `security_resolve_pack` from `security_utils.sh` (see [§8.6.14](#8614-securityutilssh)) to resolve, validate, and canonicalize it. If the value is a directory, `security_resolve_pack` locates the `secpack` executable at its root; if it is a file, it uses the file directly. In both cases, the function verifies the executable exists and is valid (calls `capabilities`), converts to an absolute path, and exports `ALLOY_SECURITY_PACK`. If neither `--security-pack` nor `ALLOY_SECURITY_PACK` is set, no security pack is configured and `ALLOY_SECURITY_PACK` remains unset.
3. **Set up build directory** - `${ALLOY_BUILD_DIR}/firmware/`. Create `projects/`, `workspace/`, and `workspace/rootfs_overlay/` subdirectories. **Clear or remove any existing content in `projects/`** so that only projects unpacked in step 7 will be present when the firmware manifest is merged in step 11 (a glob over `projects/` must not match leftovers from a previous run). Export `ALLOY_FIRMWARE_WORK_DIR="${ALLOY_BUILD_DIR}/firmware/workspace"`.
4. **Resolve firmware variant** - Determine the target firmware variant:
   - If `--list-variants` is specified, print the contents of `ALLOY_FIRMWARE_VARIANTS` and exit.
   - If `--variant VARIANT` is specified, validate that `VARIANT` exists in `ALLOY_FIRMWARE_VARIANTS`. If not found, fail with a clear error listing available firmware variants.
   - If no `--variant` is specified, default to `plain`.
   - Export `ALLOY_FIRMWARE_VARIANT` with the selected variant name.
5. **Resolve output selection** - Determine which firmware outputs to build:
   - If `--list-outputs` is specified, iterate `ALLOY_OUTPUT_SELECTABLE` and for each `<ID>`, read `ALLOY_FIRMWARE_OUT_<ID>_NAME`, `ALLOY_FIRMWARE_OUT_<ID>_DESCRIPTION`, and `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` to print a summary table (showing `[default]` or `[opt-in]` for each output). Exit.
   - Validate any `--output-<id>` flags against `ALLOY_OUTPUT_SELECTABLE` (converting hyphens to underscores). If an unknown output is requested, fail with a clear error listing available outputs.
   - If no `--output-*` flags are given, enable the default selectable outputs: for each entry in `ALLOY_OUTPUT_SELECTABLE`, read `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` and export `ALLOY_OUTPUT_<ID>=true` if `true`, `false` otherwise (opt-in outputs are skipped unless explicitly requested).
   - If one or more `--output-*` flags are given, enable only the specified outputs: export `ALLOY_OUTPUT_<ID>=true` for requested ones, `ALLOY_OUTPUT_<ID>=false` for all others.
   - Create the output registration directory: `mkdir -p "${ALLOY_FIRMWARE_WORK_DIR}/.outputs"`. This directory is used by firmware hooks when they call `alloy_firmware_add_output OUTPUT_ID FILE_PATH` (see [§5.9 Firmware Hook API](#59-firmware-hook-api)): the function writes one file per output ID (e.g. `.outputs/fwup_firmware`) containing the artefact path. The orchestrator later reads `.outputs/` to discover which outputs were produced, verify the files exist, and build the summary; it also uses this to detect when a user-selected output was not produced (build error).
6. **Resolve build parameters** - Process `--param KEY=VALUE` options against the declared `ALLOY_FIRMWARE_PARAMETERS` array and `ALLOY_FIRMWARE_PARAM_<ID>_*` metadata variables:
   - If `--list-params` is specified, iterate `ALLOY_FIRMWARE_PARAMETERS` and for each `<ID>`, read `ALLOY_FIRMWARE_PARAM_<ID>_TYPE`, `_REQUIRED`, `_DEFAULT`, `_NAME`, `_DESCRIPTION` to print a summary table. Exit.
   - For each `--param KEY=VALUE` pair:
     - Validate that `KEY` (lowercased) exists in `ALLOY_FIRMWARE_PARAMETERS`. If not, fail: `"Unknown parameter '<KEY>'. Available parameters: ..."`.
     - Read the declared type from `ALLOY_FIRMWARE_PARAM_<KEY>_TYPE` (key uppercased). Validate `VALUE` against the type:
       - `string`: any non-empty value accepted.
       - `integer`: must be a valid integer (regex `^-?[0-9]+$`). Fail if not.
       - `boolean`: must be one of `true`, `false`, `yes`, `no`, `1`, `0` (case-insensitive). Normalize to `true` or `false`.
   - Apply defaults: for each ID in `ALLOY_FIRMWARE_PARAMETERS` not provided via `--param`, if `ALLOY_FIRMWARE_PARAM_<ID>_DEFAULT` is set, use that default.
   - Check required parameters: for each ID in `ALLOY_FIRMWARE_PARAMETERS` where `ALLOY_FIRMWARE_PARAM_<ID>_REQUIRED` is `true` and no value was resolved (neither from `--param` nor from a default), fail: `"Required parameter '<KEY>' not provided. Use --param <KEY>=<VALUE>."`.
   - Export each resolved parameter as `ALLOY_PARAM_<KEY>=<VALUE>` (key uppercased).
   - Collect all resolved parameter key-value pairs (with their declared types) into an associative array for later inclusion in the firmware manifest (step 11).
   - Log each parameter at `debug` level: `"Parameter: ALLOY_PARAM_<KEY>=<VALUE> (type=<TYPE>)"`.
7. **Unpack project artefacts** - For each `(PROJECT_REF, NAME)` pair from the project list built in step 0:
   - Resolve the artefact: prefix match in `artefacts/projects/`, or path to `.tgz` file. See [artefact resolution](#artefact-resolution).
   - Unpack to `${BUILD_DIR}/firmware/projects/${PROJECT_NAME}/`.
   - Validate `ALLOY_PROJECT_MANIFEST` (parse, check required fields, verify integrity).
   - If `NAME` was not specified via `--name` (left unset in step 0), default it to the project's `id` field from the manifest.
   - Collect each project's `id` field. If two projects share the same `id`, abort with an error (duplicate project identity in a single firmware build is not permitted).
   - Validate name uniqueness: if two projects resolve to the same installation name (whether explicit via `--name` or defaulted from `id`), abort with a clear error.
8. **Stage projects in rootfs overlay** - For each unpacked project:
   - Copy the project's `release/` contents to `workspace/rootfs_overlay/srv/alloy/${NAME}/`, excluding `release/ALLOY_FS_PRIORITIES` (that file is consumed only in step 10 for priority consolidation and must not appear as a file in the rootfs). `${NAME}` is either the project name (default) or the name specified via `--name`. Releases are already scrubbed at project build time (Project Build Flow step 9); the orchestrator does not scrub again. There may be **multiple OTP releases** (one per project) under `srv/alloy/`; each project artefact contains exactly one release directory, already minimal when unpacked.
   - Record the installation path `/srv/alloy/${NAME}` as the project's `project_root` for inclusion in the firmware manifest (step 11).
   - If the project artefact contains an `overlay/` directory, merge its contents into `workspace/rootfs_overlay/`, excluding `overlay/ALLOY_FS_PRIORITIES` (that file is consumed only in step 10 for priority consolidation and must not appear as a file in the rootfs). The overlay tree mirrors the rootfs structure and is merged directly.
   - Create `/srv/erlang` symlink to the first project's release directory.
9. **Consolidate overlays** - Merge overlay sources into `workspace/rootfs_overlay/` in the following order (later sources override earlier files):
   a. **Nugget firmware overlays** - For each nugget in topological order, if `ALLOY_NUGGET_<NAME>_CONFIG_FIRMWARE_OVERLAY` is set, merge the referenced overlay directory.
   b. **Project releases** - Already staged in step 8 (under `/srv/alloy/<name>/`).
   c. **Project overlays** - Already merged in step 8 (absolute-path files from `overlay/`).
   d. **Security pack overlay** - If a security pack is configured (i.e. `ALLOY_SECURITY_PACK` was resolved in step 2b), call `security_generate_overlay "${SECPACK_OVERLAY_DIR}"` (see [§8.6.14](#8614-securityutilssh)). If the call succeeds (exit 0), merge the generated overlay directory. If the pack does not support overlay generation (exit 2), skip silently. If the call fails (exit 1), abort the build with the error message from stderr.
   e. **Command-line overlays** - If `--overlay` is specified, merge those directories.
   f. The consolidated directory path is exported as `ALLOY_FIRMWARE_ROOTFS_OVERLAY` in step 13 (Set firmware hook environment).
10. **Consolidate filesystem priorities** - Build the final priority file `workspace/fs.priorities`. All `ALLOY_FS_PRIORITIES` fragments contain relative paths (see [Data Design - Filesystem Priority Specification](01_DATA_DESIGN.md#filesystem-priority-specification)). For each fragment, the orchestrator **relocates** every path by prepending the **rootfs destination prefix** for that source-i.e. the path prefix that the source's content will have in the final rootfs, not the path where the overlay or release tree lives on the build host. Relocation is `${ROOTFS_PREFIX}/${PATH}`; the result is an absolute path in rootfs space. Then appends the relocated entries to the consolidated file:
    a. **Nugget priorities** - Iterate `ALLOY_FS_PRIORITIES_FRAGMENTS` (topological order). For each entry (`<NUGGET>:<PATH>`), read the fragment and relocate with base `/`. These come from the `{fs_priorities, Path}` metadata field declared by nuggets (see [Data Design - Filesystem Priority Metadata](01_DATA_DESIGN.md#filesystem-priority-metadata)).
    b. **Project release priorities** - For each project, if `release/ALLOY_FS_PRIORITIES` exists in the unpacked project artefact, relocate with base `/srv/alloy/${NAME}/`. For example, if the project's installation name is `my_app` and the fragment contains `lib/my_app/ebin/my_app.beam 1000`, the relocated entry becomes `/srv/alloy/my_app/lib/my_app/ebin/my_app.beam 1000`.
    c. **Project overlay priorities** - For each project, if `overlay/ALLOY_FS_PRIORITIES` exists in the unpacked project artefact, relocate with base `/`.
    d. **Security pack priorities** - If a security pack overlay was generated in step 9d and the generated overlay directory contains an `ALLOY_FS_PRIORITIES` file at its root, relocate with base `/`.
    e. **Command-line overlay priorities** - For each `--overlay` directory, if an `ALLOY_FS_PRIORITIES` file exists at its root, relocate with base `/`.
    f. **Deduplication** - Last occurrence of a path wins (later sources override earlier ones). Final list sorted by weight descending.
    g. Export `ALLOY_FIRMWARE_FS_PRIORITIES` pointing to the consolidated file.
11. **Generate firmware manifest and add to rootfs overlay** - Build `ALLOY_FIRMWARE_MANIFEST` using `merge_firmware_manifest()` from `manifest_utils.sh` (delegates to `manifest-tool merge`). Write the result to `workspace/ALLOY_FIRMWARE_MANIFEST`. Then **copy the manifest into the root of the rootfs overlay** (`workspace/rootfs_overlay/ALLOY_FIRMWARE_MANIFEST`) so that when the overlay is merged with the base rootfs in the `pre_firmware` phase, the manifest appears at the **root of the firmware rootfs** (`/ALLOY_FIRMWARE_MANIFEST` in the final image).

    **Invocation:** The merge function has fixed argument roles so the variable number of projects is unambiguous: **1)** SDK manifest path, **2)** project manifests (see below), **3)** output path, **4)** firmware-info key=value pairs (variant, security pack, project roots, params). The tool expands the project-manifests argument internally (e.g. a glob or a list); it does not rely on the shell to expand a glob into multiple positional args, so the output path and firmware-info always start at known positions. The fourth argument is a **flat** list of key=value strings (the three arrays in the example are concatenated by the shell). The manifest-tool tells them apart by **key prefix**, not by position: `firmware_variant`, `security_pack_<key>`, `project_root_<id>`, and `param_<name>:<type>` each route to the right manifest section (see [§8.7.8 manifest-tool merge](#878-scripts-tools)).

    **Project manifests:** The orchestrator must pass only the manifests for projects unpacked in **this** run (step 7). Because `projects/` may contain directories from previous invocations if the build directory is reused, **do not** pass a bare glob like `projects/*/ALLOY_PROJECT_MANIFEST` unless step 3 has cleared `projects/` so that only this run's unpacked projects are present. Preferred: build an explicit list of paths by iterating the unpacked project list (one path per `${BUILD_DIR}/firmware/projects/${PROJECT_NAME}/ALLOY_PROJECT_MANIFEST`) and pass that list to the merge function (e.g. as a single glob that is safe because `projects/` was cleared in step 3, or as multiple `--project-manifests PATH` arguments if the tool supports it). See [§8.6.9 manifest_utils.sh](#869-manifestutilssh) for the function signature.

    Example (when step 3 clears `projects/`, a glob is safe and expands only to this run's projects):
    ```bash
    merge_firmware_manifest \
        "${ALLOY_SDK_DIR}/ALLOY_SDK_MANIFEST" \
        "${BUILD_DIR}/firmware/projects/*/ALLOY_PROJECT_MANIFEST" \
        "${BUILD_DIR}/firmware/workspace/ALLOY_FIRMWARE_MANIFEST" \
        "firmware_variant=${ALLOY_FIRMWARE_VARIANT}" \
        ${ALLOY_SECURITY_PACK_INFO_ARGS[@]} \
        ${ALLOY_PROJECT_ROOTS_ARGS[@]} \
        ${ALLOY_PARAMS_ARGS[@]}
    ```
    After writing to workspace, copy to `workspace/rootfs_overlay/ALLOY_FIRMWARE_MANIFEST`. **Firmware-info arrays:** `ALLOY_SECURITY_PACK_INFO_ARGS` - key=value pairs from `security_info` (secpack), each prefixed `security_pack_<key>=<value>`; built when a security pack is configured (see [§8.6.14](#8614-securityutilssh)). `ALLOY_PROJECT_ROOTS_ARGS` - one entry per project unpacked in step 7, of the form `project_root_<id>=/srv/alloy/<name>` where `<id>` is the project's manifest `id` and `<name>` is the installation name from step 8; built in step 8 when recording each project's installation path. `ALLOY_PARAMS_ARGS` - one entry per resolved `--param`, of the form `param_<key>:<type>=<value>`; built in step 6. See [Data Design - Firmware Manifest](01_DATA_DESIGN.md#firmware-manifest-specification) and [§8.7.8 Scripts Tools - manifest-tool](#878-scripts-tools) for the merge flow.
12. **Stage legal-info in rootfs overlay** - According to `--include-legal` (parsed in step 0): if omitted or `none`, do nothing. If `tarball` (or `--include-legal` without value): create a compressed tarball of `${ALLOY_SDK_DIR}/legal-info/` and place it at `workspace/rootfs_overlay/legal-info.tgz` so it appears at `/legal-info.tgz` in the rootfs. If `full`: copy the full `${ALLOY_SDK_DIR}/legal-info/` tree to `workspace/rootfs_overlay/legal-info/` so it appears at `/legal-info/` in the rootfs. This allows the firmware manifest's `license_files` paths to resolve on device (SBOM/compliance). See [Legal-info in firmware](#legal-info-in-firmware).
13. **Set firmware hook environment** - The orchestrator exports runtime-computed variables that hooks cannot know at SDK build time. At this point, overlay staging (steps 8-9), priority consolidation (step 10), manifest (step 11), and legal-info (step 12) are complete; the rootfs overlay is **final** and must not be modified once hooks run (step 15 onward), because hooks will merge, sign, or package from it and later changes would not appear in the final image. Hooks receive these fully assembled inputs:
    - `ALLOY_FIRMWARE_WORK_DIR` (from step 3) - all hook outputs are written here. Nugget config/exports can reference `${ALLOY_FIRMWARE_WORK_DIR}` so that paths resolve when hooks run (e.g. `ALLOY_CONFIG_SIGNED_ROOTFS="${ALLOY_FIRMWARE_WORK_DIR}/images/rootfs.signed.squashfs"`). Smelterl received `ALLOY_FIRMWARE_WORK_DIR` via `--extra-config` during `smelterl plan`, so generated contexts from that plan can contain such references.
    - `ALLOY_FIRMWARE_BASE_ROOTFS` - path to the SDK base rootfs image (see [Base rootfs path](#base-rootfs-path) below).
    - `ALLOY_FIRMWARE_ROOTFS_OVERLAY="${BUILD_DIR}/firmware/workspace/rootfs_overlay"` - the single consolidated overlay directory containing all overlays merged by the orchestrator (nuggets, projects, security pack, CLI). No hook needs to locate or merge individual overlay sources.
    - `ALLOY_FIRMWARE_FS_PRIORITIES` (from step 10) - the single consolidated priorities file (nuggets, projects, security pack, deduplicated). No hook needs to locate or merge individual priority files. (Legal-info, if staged in step 12, is already part of the overlay and does not require a separate export.)
    - `ALLOY_SECURITY_PACK` - Already resolved in step 2b (absolute path to the security pack executable, or unset if no pack is configured).
    - `ALLOY_SECURITY_*` variables - If a security pack is configured, the orchestrator calls `security_export_env` (see [§8.6.14](#8614-securityutilssh)), which invokes `secpack env`. Each key=value pair from the output is validated (keys must match `[a-z][a-z0-9_]*`) and exported as `ALLOY_SECURITY_<KEY>` (key uppercased). This provides hooks with security configuration such as signing algorithm, SRK index, overlay file locations, and feature flags - without hooks needing to call the security pack directly. If the pack returns exit 2 (no env to export), this step is a no-op.
    - `ALLOY_PARAM_*` variables (from step 6) - build-time parameters injected via `--param`. Available to all firmware hooks.

    #### Base rootfs path

    The build system does not hardcode which file in the SDK is the base rootfs. That path is defined by **nugget configuration** so that different products (different Buildroot rootfs formats or locations) can specify the correct image. At SDK build time, smelterl consolidates config and exports from all nuggets into `alloy_context.sh` (see [Data Design - Configuration consolidation](01_DATA_DESIGN.md#configuration-consolidation)). A nugget that contributes or consumes the rootfs image (e.g. the platform nugget or `feature_squashfs`) declares a key `base_rootfs` in its `config` or `exports` metadata, with value in the form **`${ALLOY_SDK_DIR}/images/rootfs.squashfs`** (or `${ALLOY_SDK_DIR}/images/rootfs/rootfs.ext4` etc.), so that it **resolves when `ALLOY_SDK_DIR` is set** (at firmware build time, in step 2). That becomes `ALLOY_CONFIG_BASE_ROOTFS` in the generated context. Smelterl receives `ALLOY_SDK_DIR` via `--extra-config` during `smelterl plan`, so the literal string is written into generated contexts from that plan. When the firmware build command runs, it sources `alloy_context.sh` in step 2 (setting `ALLOY_SDK_DIR` to the SDK root). In step 13, the orchestrator sets `ALLOY_FIRMWARE_BASE_ROOTFS` to the resolved value: if `ALLOY_CONFIG_BASE_ROOTFS` is set, evaluate it (so `${ALLOY_SDK_DIR}` expands to the actual path); otherwise default to `"${ALLOY_SDK_DIR}/images/rootfs.squashfs"`. Hooks then receive `ALLOY_FIRMWARE_BASE_ROOTFS` as the absolute path to the base rootfs image.

    **Data flow:** The orchestrator prepares the inputs (overlay + priorities) -> `pre_firmware` hooks consume them to produce the merged rootfs (e.g. `feature_squashfs` merges base rootfs + overlay + priorities into a SquashFS image; the path is available to other nuggets via config such as `ALLOY_CONFIG_ROOTFS` declared at SDK build time) -> `firmware_build` hooks consume the rootfs for boot image assembly and signing -> `post_firmware` hooks package the outputs.

    Output filenames are NOT hardcoded by the orchestrator. Each hook derives its output path from `ALLOY_FIRMWARE_WORK_DIR` and its own config key (e.g. `ALLOY_CONFIG_SQUASHFS_OUTPUT_NAME`, `ALLOY_CONFIG_FWUP_OUTPUT_NAME`). Because hooks run in separate processes, a hook cannot export variables for the next hook. Nuggets that produce intermediate artefacts (e.g. the merged rootfs) declare a config at SDK build time with a value like `${ALLOY_FIRMWARE_WORK_DIR}/...` so downstream hooks get the path from that config.

14. **Firmware manifest** - The firmware manifest **must** be in the rootfs overlay **before** any hooks are invoked (step 11 generates it and copies it to `workspace/rootfs_overlay/ALLOY_FIRMWARE_MANIFEST`; step 12 may add legal-info to the overlay). The overlay **cannot change after hooks start**: once step 15 runs, a hook (e.g. `feature_squashfs`) will merge the overlay into the rootfs, and later hooks may sign or package that result-any change to the overlay after that would not be reflected in the final image. So the manifest is fixed in the overlay by step 12 and is present at the root of the firmware rootfs in the final image (`/ALLOY_FIRMWARE_MANIFEST`). No further generation is done during hooks; step 19 copies the manifest from workspace to the artefact directory under a unique filename so it does not clash with other generated firmware (see step 19).
15. **Run pre_firmware hooks** - See [§5.8](#58-hook-invocation-flow). Select the variant-specific array `ALLOY_PRE_FIRMWARE_HOOKS_<VARIANT>` (variant uppercased) and iterate it in topological order. This phase prepares the rootfs:
    - `feature_squashfs` merges the base rootfs with the overlay and priorities into the output path (e.g. `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_SQUASHFS_OUTPUT_NAME}`). The nugget does not export variables for other hooks (hooks run in separate processes). Instead it declares a config at **SDK build time** (e.g. `ALLOY_CONFIG_ROOTFS`) set to a value like `${ALLOY_FIRMWARE_WORK_DIR}/rootfs.merged.squashfs`, so downstream hooks obtain the merged rootfs path from that config (it resolves when `ALLOY_FIRMWARE_WORK_DIR` is set).
    - System nuggets and feature nuggets may perform dm-verity, encryption, and initramfs preparation as required by the selected variant.
16. **Select firmware_build hook array** - Construct the variant-specific array name by uppercasing the selected variant: `ALLOY_FIRMWARE_BUILD_HOOKS_$(echo "${ALLOY_FIRMWARE_VARIANT}" | tr '[:lower:]' '[:upper:]')`. This array was dynamically generated by smelterl based on the `firmware_variant` metadata declared by nuggets (see the Smelterl design section on generating `alloy_context.sh`:
    local checkout [smelterl/docs/DESIGN.md#412-generating-alloy_contextsh](../smelterl/docs/DESIGN.md#412-generating-alloy_contextsh),
    web view [github.com/grisp/smelterl/docs/DESIGN.md#412-generating-alloy_contextsh](https://github.com/grisp/smelterl/blob/main/docs/DESIGN.md#412-generating-alloy_contextsh)). No variant names are hardcoded in the orchestrator.
17. **Run firmware_build hooks** - See [§5.8](#58-hook-invocation-flow). Iterate the selected hook array in topological order. **The bootflow nugget matching the selected variant is the firmware assembly orchestrator.** The bootflow may call platform-exported `fun_` helper scripts to build boot components, interleaves signing operations (for secure variants), and assembles the final boot image. It interacts with the security pack only through `security_tools.sh` functions (see [§4.6 Security Pack](#46-security-pack)).
18. **Run post_firmware hooks** - See [§5.8](#58-hook-invocation-flow). Select the variant-specific array `ALLOY_POST_FIRMWARE_HOOKS_<VARIANT>` (variant uppercased) and iterate it in topological order. This phase packages the firmware. Each hook that produces a selectable output checks its `ALLOY_OUTPUT_<ID>` variable and skips if `false`. Hooks that produce outputs call `alloy_firmware_add_output` (see [§5.9 Firmware Hook API](#59-firmware-hook-api)):
    - `feature_fwup` checks `ALLOY_OUTPUT_FWUP_FIRMWARE`; if `true`, builds the `.fw` package and calls `alloy_firmware_add_output fwup_firmware <path>`.
    - `feature_image` checks `ALLOY_OUTPUT_IMAGE`; if `true`, reads the fwup path from `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/fwup_firmware`, generates raw disk images, and calls `alloy_firmware_add_output image <path>`.
    - System nuggets may create update tools, UUU files, etc.
19. **Verify artefacts and display summary** - Execute the output verification described in [§5.9 Firmware Hook API - Orchestrator Output Verification](#orchestrator-output-verification). For each entry in `ALLOY_FIRMWARE_OUTPUTS`:
    - If selectable and not selected: skip.
    - If `alloy_firmware_add_output` was called (registration file exists in `.outputs/`): verify file exists, add to summary using `ALLOY_FIRMWARE_OUT_<ID>_NAME`.
    - If selectable, selected, but not registered: error - the user requested it but no hook produced it.
    - If not selectable and not registered: skip silently (variant-conditional).
    - Copy the firmware manifest from workspace to the artefact directory under a unique filename that does not clash with other generated firmware, e.g. `FIRMWARE_<PRODUCT>_<VERSION>_MANIFEST` (product and version from `ALLOY_PRODUCT` and `ALLOY_PRODUCT_VERSION`.

    Example build summary output:
    ```
    Firmware built successfully:
      Firmware update package:  artefacts/firmware/firmware-my_app-1.2.0-grisp2_vanilla-1.0.0.fw
      Raw disk image:           artefacts/images/firmware-my_app-1.2.0-grisp2_vanilla-1.0.0.img
      Software update package:  artefacts/grisp_updates/my_app-1.2.0-grisp2_vanilla-1.0.0.tar
    ```
20. **Cleanup** - If SDK was extracted to temp, remove it.

#### OTP release scrubbing

**When:** During the **Project Build Flow**, after the project plugin writes the release (step 8) and before architecture validation and packaging (steps 10–13). The orchestrator runs the scrub once on the staging release directory (`${STAGING_DIR}/release`). There is exactly **one release directory per project build**. The resulting project tarball therefore contains an already-scrubbed release; the Firmware Build Flow only unpacks and stages these releases (step 8) and does **not** run scrubbing again (releases under `srv/alloy/${NAME}/` are one per project; multiple projects yield multiple OTP releases in the image, each pre-scrubbed at project build time).

**Implementation:** Scrubbing is abstracted in `otp_utils.sh` (see [§8.6.8 otp_utils.sh](#868-otputilssh)). The project build command sources that utility and calls `scrub_otp_release "${STAGING_DIR}/release"` in step 9. The function **detects** whether the directory is an OTP release (e.g. by checking for the presence of `lib/` and `releases/`). If the directory is not an OTP release (e.g. a project type that produces a different layout), the scrub **does not fail**: it returns success and performs no OTP-specific cleanup, so non-OTP projects are unaffected.

**Purpose:** Reduce artefact and rootfs size and remove files that are not needed on the device. The release produced by the project plugin may contain debug symbols in ELF binaries and extra files (scripts, tarballs) that are only useful at build time. Scrubbing makes the release directory minimal before the project tarball is created, so the same minimal content is used both in the artefact and in the firmware image.

**What the scrub does (design specification):**

0. **Detect OTP release** - Before any stripping or cleanup, determine whether the directory is an OTP release (e.g. contains `lib/` and `releases/` as subdirectories). If not, exit successfully without modifying the directory; do not fail the build. This allows the same firmware flow to handle both OTP-based projects (Erlang/Elixir) and other project types that stage different content.

1. **Strip ELF binaries** - For each ELF executable and shared library under the release directory, run the SDK's cross-compiler `strip` (e.g. `$CROSSCOMPILE-strip` or `$READELF`/strip from the same toolchain) to remove debug symbols. This shrinks binaries. If `strip` fails for a file (e.g. some precompiled binaries), log a warning and continue; do not fail the build. Make the file writable before stripping if necessary (e.g. `chmod +w`). Skip non-ELF files (scripts, BEAM, data).

2. **Cleanup release directory** - Remove files that are not needed on the target:
   - Delete all empty directories (e.g. `find RELEASE_DIR -type d -empty -delete`).
   - In the release root (top level of the OTP release): delete any regular files. The release root should contain only directories (e.g. `bin/`, `lib/`, `releases/`); stray files here are typically build artefacts.
   - In the `releases/` subdirectory: delete script and archive files that are not used at runtime on the device, e.g. `*.sh`, `*.bat`, `*.ps1`, `*.script`, and `*gz` (release tarballs). Keep the release metadata and boot script that the ERTS needs; the exact list of patterns is implementation-defined but must not remove files required to boot the release.

**Prerequisites:** The cross-compilation environment must be available when the scrub runs (Project Build Flow sets it up in step 7), so that `otp_utils.sh` can use `STRIP` and `READELF` from the cross toolchain. The scrub runs in-place on the staging release directory before the project tarball is created.

**Architecture validation:** Target-architecture validation of the release is done at **project build** time (Project Build Flow step 10, immediately after scrubbing). The scrub does not perform architecture validation; that is a separate step.

**Exclusions:** Implementation may support excluding subtrees from stripping or from cleanup (e.g. a directory containing a `.noscrub` marker file) for files that must not be modified or that are intentionally host-only.

### 5.8 Hook Invocation Flow

**Purpose:** Execute nugget hook scripts at a specific build stage, in target order and nugget order, with scope-correct hook chains and environment.

**Precondition:** the **target-specific** `alloy_context.sh` has been sourced, providing `ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, `ALLOY_AUXILIARY`, `ALLOY_*` config vars, and hook arrays already filtered by hook scope.

**General contract for all wrappers:**

The wrapper is considered **part of the orchestrator** (even when it is invoked by Buildroot, as with `script_hook.sh`). It sources `common.sh` (which enables tracing for the wrapper when `ALLOY_TRACE=true`) and may source `*_utils.sh` as needed. It does **not** source any `*_tools.sh`; hooks get the hook API by sourcing [hook_common.sh](#860-hookcommonsh-hook-entry-point).

**Debug logging:** Hook wrappers follow the [orchestrator observability principle](#orchestrator-observability-design-principle) (§4.9): when the debug level enables debug output, the wrapper must log which hooks are invoked (nugget name, script path, hook type).

1. **Set context variables and source the context file** - The set of available variables is **hook-type dependent**. Variables that hooks can use **must be exported** so they are visible in the hook process when the wrapper executes each hook script. The wrapper sources `alloy_context.sh` (from the location appropriate to the hook type; see table below); variables defined there are exported automatically by that file. The **developer** (author of the wrapper or orchestrator) must ensure that all **other** variables listed below are exported before invoking hooks-most are typically already exported by the orchestrator. Then source `common.sh` (and any `*_utils.sh` the wrapper needs).

    **Common to all hook types (must be exported):** `ALLOY_MOTHERLODE`, `ALLOY_BUILD_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_CACHE_DIR`, `ALLOY_DEBUG`, `ALLOY_TRACE`, **`ALLOY_ROOT_DIR`** (root of the alloy installation: in SDK mode equals the SDK root; in repository mode equals the alloy repository root; used to locate `scripts/hook_common.sh`), plus target identity from sourced context (`ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, `ALLOY_AUXILIARY`).

    **Repository-mode hooks only** (`pre_build`, `post_build`, `post_image`, `post_fakeroot`): **`ALLOY_SDK_STAGING_DIR`** (SDK build staging directory for manifest and legal-info; set in SDK build flow step 2). When Buildroot invokes `script_hook.sh`, the orchestrator must pass or inherit this (exported) so post_build/post_image/post_fakeroot hooks have it.

    **Firmware hooks only** (`pre_firmware`, `firmware_build`, `post_firmware`): **`ALLOY_SDK_DIR`** (SDK root), **`ALLOY_FIRMWARE_WORK_DIR`** (firmware build workspace). In addition, the orchestrator sets and exports the firmware hook environment in step 13 of the [Firmware Build Flow](#57-firmware-build-flow) before invoking these hooks: `ALLOY_FIRMWARE_BASE_ROOTFS`, `ALLOY_FIRMWARE_ROOTFS_OVERLAY`, `ALLOY_FIRMWARE_FS_PRIORITIES`, `ALLOY_SECURITY_PACK`, `ALLOY_SECURITY_*` (from `secpack env`), `ALLOY_PARAM_*` (from `--param`), `ALLOY_FIRMWARE_VARIANT`, `ALLOY_OUTPUT_<ID>`, etc. The full list is in [Data Design - Environment Variables and Functions](01_DATA_DESIGN.md#environment-variables-and-functions).
2. **Export `ALLOY_HOOK_TYPE`** - Set to the appropriate value (`pre_build`, `post_build`, `post_image`, `post_fakeroot`, `pre_firmware`, `firmware_build`, or `post_firmware`) so that hook_common.sh can conditionally source the right _tools.sh.
3. **Select hook array** - Choose the bash array for this hook type. For firmware-time hooks, the array is variant-specific (variant uppercased): `ALLOY_PRE_FIRMWARE_HOOKS_<VARIANT>`, `ALLOY_FIRMWARE_BUILD_HOOKS_<VARIANT>`, `ALLOY_POST_FIRMWARE_HOOKS_<VARIANT>`. For SDK-time hooks, use non-variant arrays (`ALLOY_PRE_BUILD_HOOKS`, `ALLOY_POST_BUILD_HOOKS`, etc.). Scope filtering (`main|auxiliary|all|AuxId`) is done by smelterl during context generation, so wrappers do not re-filter.
4. **Iterate** - For each element in the array (format `NUGGET_NAME:SCRIPT_RELATIVE_PATH`):
   a. Parse the nugget name and script path (split on first `:`).
   b. Resolve the nugget directory from `ALLOY_NUGGET_<NUGGET_NAME>_DIR`.
   c. Export per-invocation variables:
      - `ALLOY_NUGGET` - nugget identifier
      - `ALLOY_NUGGET_DIR` - nugget directory
      - `ALLOY_NUGGET_NAME` - display name
      - `ALLOY_NUGGET_DESC` - description
      - `ALLOY_NUGGET_VERSION` - version
      - `ALLOY_NUGGET_FLAVOR` - flavor (empty if not set)
   d. Log which hook is being invoked (nugget name, script path, hook type) using the appropriate logging function; level management is handled by the logging layer.
   e. Invoke the script at `${ALLOY_NUGGET_DIR}/${SCRIPT_RELATIVE_PATH}` with the wrapper's original arguments (`$@`). The wrapper **executes** each hook (e.g. `bash "${ALLOY_NUGGET_DIR}/${SCRIPT_RELATIVE_PATH}" "$@"`). The wrapper does **not** source any _tools.sh and does **not** export functions. The hook script is responsible for **sourcing** [hook_common.sh](#860-hookcommonsh-hook-entry-point) at the top to get the `alloy_*` API and tracing; if it does not, it cannot expect any `alloy_*` functions. The wrapper must export `ALLOY_ROOT_DIR`, `ALLOY_TRACE`, and other required variables so the hook can resolve the entry point. See [§8.6](#86-shared-utilities).
   f. If the script does not exist, emit a warning and skip.
   g. If the script exits non-zero, abort the build.

**Scope behavior (context generation contract):**
- Hooks scoped to `main` appear only in main target context chains.
- Hooks scoped to `auxiliary` appear in all auxiliary target context chains.
- Hooks scoped to `all` appear in all target context chains.
- Hooks scoped to a concrete `AuxId` appear only in that auxiliary context chain.
- Firmware-time hooks are emitted only in main context chains.

**`pre_build` global semantic (SDK build):**
- `pre_build` hooks are executed across all involved targets exactly once per nugget.
- Target traversal order is auxiliary targets first, then main target.
- Within each target, nugget order is the target topological order.
- If a nugget appears in several targets, only its first encounter executes `pre_build`; later encounters are skipped.

**Hook-specific wrappers:**

| Hook Type | Wrapper | Context Source |
|-----------|---------|----------------|
| `pre_build` | `build-sdk.sh` | current target context `${ALLOY_BUILD_DIR}/sdk/${PRODUCT}/targets/<TARGET_ID>/alloy_context.sh` |
| `post_build`, `post_image`, `post_fakeroot` | `scripts/buildroot/script_hook.sh` | `alloy_context.sh` in the same directory as the symlink |
| `pre_firmware` | `build-firmware.sh` | `${ALLOY_SDK_DIR}/scripts/alloy_context.sh` |
| `firmware_build` | `build-firmware.sh` | `${ALLOY_SDK_DIR}/scripts/alloy_context.sh` |
| `post_firmware` | `build-firmware.sh` | `${ALLOY_SDK_DIR}/scripts/alloy_context.sh` |

**Buildroot hook wrapper (`script_hook.sh`):**

The wrapper is part of the orchestrator (even though Buildroot invokes it). It determines the hook type from its invocation name (symlink basename without `.sh`, with `-` normalized to `_`). It expects `ALLOY_MOTHERLODE`, `ALLOY_ROOT_DIR`, `ALLOY_DEBUG`, `ALLOY_TRACE`, `ALLOY_SDK_STAGING_DIR` (during SDK build), `ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, and `ALLOY_AUXILIARY` to already be available from the sourced target context, plus other required `ALLOY_*` make variables. Its startup sequence is:

1. Source `common.sh` - so the wrapper gets error handling, logging, and tracing (when `ALLOY_TRACE=true`, the wrapper’s own execution is traced). The wrapper may also source any `*_utils.sh` it needs.
2. Source `alloy_context.sh` from the same directory as the symlink - this provides nugget paths, hook arrays, and context variables.
3. Export `ALLOY_HOOK_TYPE` for the current hook type so that when each hook sources hook_common.sh, the entry point can conditionally source the right _tools.sh.
4. Select the appropriate hook array, then **iterate** as in the [general contract](#58-hook-invocation-flow) step 4: for each element (`NUGGET_NAME:SCRIPT_RELATIVE_PATH`), parse the nugget name and script path, resolve `ALLOY_NUGGET_<NUGGET_NAME>_DIR`, export per-invocation variables (`ALLOY_NUGGET`, `ALLOY_NUGGET_DIR`, `ALLOY_NUGGET_NAME`, `ALLOY_NUGGET_DESC`, `ALLOY_NUGGET_VERSION`, `ALLOY_NUGGET_FLAVOR`), log which hook is being invoked (using the appropriate logging function), then **execute** the script (e.g. `bash "${ALLOY_NUGGET_DIR}/${SCRIPT_RELATIVE_PATH}" "$@"`). If the script does not exist, emit a warning and skip; if it exits non-zero, abort the build. Each hook must source [hook_common.sh](#860-hookcommonsh-hook-entry-point) at the top to get the `alloy_*` API and tracing (hook_common.sh enables `set -x` when `ALLOY_TRACE=true` for the hook process).

### 5.9 Firmware Hook API

**Purpose:** Define a set of functions available to firmware hooks (`pre_firmware`, `firmware_build`, `post_firmware`) for structured communication with the orchestrator. These functions are defined in `firmware_tools.sh` (see [§8.6.15 firmware_tools.sh](#8615-firmwaretoolssh)), which is sourced by [hook_common.sh](#860-hookcommonsh-hook-entry-point); firmware hooks get them by sourcing the entry point at the top of their script. They are available to firmware hooks because the hook sources [hook_common.sh](#860-hookcommonsh-hook-entry-point), which sources `firmware_tools.sh`; the hook then has these functions in its process. They require `ALLOY_FIRMWARE_WORK_DIR` to be set (firmware build context only).

> **Note:** `alloy_context.sh` contains only data declarations and stateless accessor helpers (`alloy_nugget_dir`, `alloy_config`, etc.). Functions with side effects - like `alloy_firmware_add_output` - are part of the hook API defined in `firmware_tools.sh`.

#### `alloy_firmware_add_output`

**Synopsis:** `alloy_firmware_add_output OUTPUT_ID FILE_PATH`

**Purpose:** Register a produced firmware artefact with the orchestrator. This is the only supported way for hooks to declare "I produced this output." The orchestrator uses this information for build summary, artefact verification, and CI/CD integration.

**Parameters:**
- `OUTPUT_ID` - must match a declared output ID from a nugget's `firmware_outputs` metadata (see [Data Design - Firmware Outputs Metadata](01_DATA_DESIGN.md#firmware-outputs-metadata)). The function validates this against the `ALLOY_FIRMWARE_OUTPUTS` array.
- `FILE_PATH` - absolute path to the produced artefact file. Must exist at call time.

**Behavior:**
1. Validate `ALLOY_FIRMWARE_WORK_DIR` is set (firmware build context guard).
2. Validate `OUTPUT_ID` exists in the declared `ALLOY_FIRMWARE_OUTPUTS` array. If not, emit error and return non-zero.
3. Validate file at `FILE_PATH` exists. If not, emit error and return non-zero.
4. Record the registration in `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/${OUTPUT_ID}` (one file per output, containing the path). This is how the orchestrator discovers what was produced (build summary, verification). No environment variable is exported-hooks run in separate processes, so an export would not be visible to other hooks; a downstream hook that needs another hook's output path uses [alloy_firmware_get_output](#alloyfirmwaregetoutput) (or checks with [alloy_firmware_has_output](#alloyfirmwarehasoutput)) rather than reading the `.outputs/<ID>` file directly.
5. Log the registration at debug level.

**Error handling:** Returns non-zero on validation failure. If a hook calls `alloy_firmware_add_output` with an unknown output ID or a non-existent file, the build aborts (hooks must exit non-zero on function failure).

#### `alloy_firmware_has_output`

**Synopsis:** `alloy_firmware_has_output OUTPUT_ID`

**Purpose:** Check whether an output was produced by an earlier hook (i.e. whether a registration exists for that output ID). Allows downstream hooks to conditionally consume an output without depending on internal storage details.

**Parameters:**
- `OUTPUT_ID` - output identifier (e.g. `fwup_firmware`). Should match a declared output ID from `firmware_outputs` metadata; behaviour for unknown IDs is implementation-defined (e.g. return false).

**Behavior:** Returns exit code 0 if the output was registered (the `.outputs/<OUTPUT_ID>` file exists and contains a path to an existing file). Returns non-zero otherwise (not produced, or invalid). Does not write to stdout; use only for condition checks (e.g. `if alloy_firmware_has_output fwup_firmware; then ...`).

#### `alloy_firmware_get_output`

**Synopsis:** `alloy_firmware_get_output OUTPUT_ID` (path printed to stdout)

**Purpose:** Get the path of an output produced by an earlier hook. Provides an abstraction over the internal `.outputs/<ID>` storage so hooks do not need to know how outputs are stored.

**Parameters:**
- `OUTPUT_ID` - output identifier (e.g. `fwup_firmware`). Must match a declared output ID; the function should validate and fail clearly if the ID is unknown or the output was not produced.

**Behavior:** If the output was registered and the file exists, print its absolute path to stdout and return 0. If the output was not produced, the ID is unknown, or the registered file is missing, emit an error, return non-zero, and produce no path (downstream hooks should check with `alloy_firmware_has_output` first if the output is optional). The caller captures the path with e.g. `path=$(alloy_firmware_get_output fwup_firmware)`.

**Example:**

```bash
# In feature_fwup's post_firmware hook:
if [[ "${ALLOY_OUTPUT_FWUP_FIRMWARE}" != "true" ]]; then
    alloy_log_info "Skipping fwup firmware (not selected)"
    return 0
fi

# Build the firmware update package
fwup -c -f "${expanded_conf}" -o "${output_path}"

# Register the output
alloy_firmware_add_output fwup_firmware "${output_path}"

# In feature_image's post_firmware hook (downstream): use API to get path
if ! alloy_firmware_has_output fwup_firmware; then
    alloy_die 1 "fwup firmware output required but not produced"
fi
fwup_file=$(alloy_firmware_get_output fwup_firmware)
fwup -a -d "${image_path}" -t complete -i "${fwup_file}"
alloy_firmware_add_output image "${image_path}"
```

**Distinction from config:** Hook-to-hook intermediates that are not user-visible artefacts (e.g. the merged rootfs path from `feature_squashfs`) are not passed via runtime export (hooks run in separate processes). The producing nugget declares a **config at SDK build time** (e.g. `ALLOY_CONFIG_ROOTFS` with value `${ALLOY_FIRMWARE_WORK_DIR}/rootfs.merged.squashfs`) so downstream hooks read the path from that config. `alloy_firmware_add_output` is exclusively for declared outputs that appear in the build summary.

#### Orchestrator Output Verification

After all firmware hooks have completed, the orchestrator performs the following verification (step 19 of the [Firmware Build Flow](#57-firmware-build-flow)):

1. Initialize the build summary output.
2. For each entry in `ALLOY_FIRMWARE_OUTPUTS` (topological order), parse the output ID, nugget, selectability, default status, and display name:
   a. If selectable and `ALLOY_OUTPUT_<ID>` is `false`: skip (not selected - either an opt-in output not requested, or explicitly deselected).
   b. Check `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/${OUTPUT_ID}` for a registered path.
   c. If registered: read the path, verify the file exists. If missing, abort with error. Otherwise, add to summary.
   d. If **not** registered and selectable with `ALLOY_OUTPUT_<ID>=true`: abort - the user selected this output but no hook produced it.
   e. If **not** registered and not selectable: skip silently (variant-conditional or not applicable in this build).
3. Copy the firmware manifest from workspace to the artefact directory under a unique filename (e.g. derived from `ALLOY_PRODUCT` and `ALLOY_PRODUCT_VERSION`) so it does not clash with manifests from other products or previous builds; see [Firmware Build Flow](#57-firmware-build-flow) step 19.
4. Display the build summary.

#### SDK Output API (SDK-time hooks)

Auxiliary/main SDK-time hooks use a parallel API for `sdk_outputs`:

- `alloy_sdk_add_output OUTPUT_ID FILE_PATH`
  - Registers a declared SDK output for the current target.
  - Writes registration under target workspace state for later verification:
    `${TARGET_WORKSPACE}/.sdk_outputs/<OUTPUT_ID>` with absolute output path as file content.
- `alloy_sdk_has_output AUX_ID OUTPUT_ID`
  - Returns success if an auxiliary output was registered and file exists.
- `alloy_sdk_get_output AUX_ID OUTPUT_ID`
  - Prints absolute path for a registered auxiliary output.

Verification and propagation:
- After auxiliary builds, orchestrator verifies all declared auxiliary `sdk_outputs` were registered.
- For main target generation/build, orchestrator exposes resolved outputs as:
  - `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` (always)
  - `ALLOY_SDK_OUTPUT_<OUTPUT_ID>` (only when unique across auxiliaries)

### 5.10 SDK Packing Flow

**Purpose:** Assemble a self-contained SDK tarball from build artefacts, context, and manifest.

**Precondition:** SDK build completed (step 13 in [§5.5](#55-sdk-build-flow)). The **main-target** `alloy_context.sh` is sourced, providing embed lists.

**Steps:**

1. **Initialize state tracking** - Create data structures to track processed files (by canonical path) and current processing chain (for circular symlink detection).
2. **Process embedded images** - Read `ALLOY_EMBED_IMAGES` from the main-target context (each element `NUGGET_NAME:PATH`). For each pattern:
   - Expand glob against `${BUILD_DIR}/workspace/images/`.
   - For each matched file: embed to `sdk/images/` with symlink resolution and path conversion.
3. **Process embedded host tools** - Read `ALLOY_EMBED_HOST` from the main-target context. For each pattern:
   - Expand glob against `${BUILD_DIR}/workspace/host/`.
   - For each matched file: embed to `sdk/host/` preserving directory structure, with automatic shared library dependency resolution (recursive `ldd` analysis; only workspace-internal libraries embedded).
4. **Process embedded nugget content** - Read `ALLOY_EMBED_NUGGETS` from the main-target context. This array contains both explicitly declared `{nugget, ...}` entries and auto-embedded entries (firmware-time hook scripts and `fs_priorities` fragments), already deduplicated by smelterl. For each entry (`NUGGET_NAME:PATH`):
   - Resolve nugget directory from `ALLOY_NUGGET_<NAME>_DIR`.
   - Expand glob against nugget directory.
   - For each matched file: embed to `sdk/motherlode/<REPO>/<NUGGET_NAME>/` preserving the motherlode directory structure (so `alloy_context.sh` paths remain valid in SDK mode).
5. **Copy Buildroot target staging** - The target sysroot (staging) contains all cross-compiled target packages (including target Erlang/OTP, system libraries, and headers) and is used unconditionally - not selectively embedded via nugget lists - because it is a coherent sysroot managed by Buildroot's package dependency system. Project builds use `staging/usr/lib/erlang/` as the source for target ERTS and OTP applications bundled into OTP releases. **When `${BUILD_DIR}/workspace/staging` is a symlink** (Buildroot often makes it point into `workspace/host/<tuple>/sysroot`, e.g. `host/aarch64-<product>-linux-gnu/sysroot`): resolve the link target, copy that directory into the SDK under the same relative path under `host/` (e.g. copy to `sdk/host/aarch64-<product>-linux-gnu/sysroot/`), then create `sdk/staging` as a **relative symlink** to that path (e.g. `staging` -> `host/aarch64-<product>-linux-gnu/sysroot`). This preserves the Buildroot logical structure (staging as a link into host) instead of extracting staging out of the host tree. **When staging is a real directory**, copy it to `sdk/staging/` as usual.
6. **Copy core SDK files:**
   - `alloy` -> `sdk/alloy` (orchestrator script).
   - `scripts/` -> `sdk/scripts/` (all scripts except `scripts/tests/`).
   - `${BUILD_DIR}/alloy_context.sh` -> `sdk/scripts/alloy_context.sh`.
7. **Copy manifest and legal-info:**
   - `${BUILD_DIR}/ALLOY_SDK_MANIFEST` -> `sdk/ALLOY_SDK_MANIFEST`.
   - Legal-info tree from smelterl export (step 12 in [§5.5](#55-sdk-build-flow)) -> `sdk/legal-info/`.
   - Auxiliary sdk outputs from `${ALLOY_SDK_STAGING_DIR}/auxiliary/` -> `sdk/auxiliary/` (this is the auxiliary contribution path; auxiliaries do not contribute via `ALLOY_EMBED_*` arrays).
8. **Verify and fix ELF RPATHs** - Scan the entire SDK tree (including `staging/`) for ELF files and ensure all RPATHs are `$ORIGIN`-relative. See [ELF RPATH verification and fixup](#elf-rpath-verification-and-fixup-phase-1--at-pack-time) below.
9. **Sanitize text-based paths and create relocation files** - Scan all embedded text files (including files in `staging/`) for build-machine absolute paths, replace them with `@@ALLOY_SDK_DIR@@`-based paths, and generate the two relocation control files:
   - `sdk/.alloy_relocation_manifest` - list of all modified files (relative to SDK root) that contain the placeholder.
   - `sdk/.alloy_sdk_dir` - write the string `@@ALLOY_SDK_DIR@@` (the placeholder, to be replaced with the real path on first use).
   See [Text-based path sanitization](#text-based-path-sanitization-phase-2--at-pack-time) below.
10. **Create tarball** - `tar -czf artefacts/sdk/sdk-${PRODUCT}-${VERSION}-${HOST_ARCH}.tar.gz` with symlinks preserved.

**Embedding mechanism details:**

For each file to embed:

- **If symlink:** Validate target is within allowed directory. Convert to relative path. Embed symlink and process target recursively.
- **If directory:** Create directory in SDK; recursively process all contents.
- **If regular file:** Copy to SDK preserving permissions. If ELF binary, run `ldd` and embed workspace-internal library dependencies recursively.
- **Duplicate detection:** Track processed files by canonical path (via `realpath`). Skip already-processed files.
- **Circular symlink detection:** Maintain processing chain; fail if a cycle is detected.
- **External symlink:** If a symlink target is outside the allowed directory (workspace/host/, workspace/images/, or nugget dir), fail with a clear error.

**ELF RPATH verification and fixup (Phase 1 - at pack time):**

Buildroot already relativizes RPATHs during its `host-finalize` step (via the `fix-rpath` script using `patchelf --make-rpath-relative --relative-to-file`), so host ELF files already have `$ORIGIN`-relative RPATHs. However, nuggets may embed their own ELF binaries or libraries that were not processed by Buildroot's `fix-rpath`. After all files are embedded, the packer performs a **verification and fixup pass** across the entire SDK tree (see [Data Design - Relocatability](01_DATA_DESIGN.md#relocatability)):

1. **Scan for ELF files.** Walk `sdk/host/`, `sdk/images/`, and `sdk/motherlode/` and identify all ELF files (binaries and shared libraries) by checking the ELF magic bytes (`\x7fELF`).
2. **Verify RPATH.** For each ELF file, read the `DT_RPATH` or `DT_RUNPATH` entry using `patchelf --print-rpath`. Check that it contains only `$ORIGIN`-relative entries and no absolute paths.
3. **Fix if needed.** If any absolute RPATHs remain (e.g. files missed by Buildroot's `fix-rpath`, nugget-embedded binaries, or files whose relative position changed during selective embedding), compute the correct `$ORIGIN`-relative path and apply with `patchelf --make-rpath-relative` or `patchelf --set-rpath`. Do NOT use `--shrink-rpath` as it would break `dlopen()`-based plugin loading.
4. **Log all changes.** Record RPATH modifications (original and new) for debugging and verification.

**Note:** The ELF interpreter (`PT_INTERP`) is NOT modified. `$ORIGIN` is resolved by the dynamic linker, not by the kernel, so it does not work in `PT_INTERP`. This is not an issue because host tools use the system's standard dynamic linker (e.g. `/lib64/ld-linux-x86-64.so.2`), which is always available on the host.

**Text-based path sanitization (Phase 2 - at pack time):**

Embedded files from different source trees may contain absolute build-machine paths. The packer builds a prefix map from the embedding step and replaces all build-machine paths with `@@ALLOY_SDK_DIR@@`-based paths that reflect the SDK directory structure:

1. **Build prefix map.** Collect source-to-destination prefix mappings:
   - `BUILD_HOST_DIR` -> `@@ALLOY_SDK_DIR@@/host`
   - `BUILD_IMAGES_DIR` -> `@@ALLOY_SDK_DIR@@/images`
   - For each embedded nugget: `MOTHERLODE/<repo>/<nugget_id>` -> `@@ALLOY_SDK_DIR@@/motherlode/<repo>/<nugget_id>`
2. **Scan and replace.** For every embedded text file across all SDK subtrees, scan for occurrences of any build-machine prefix in the map. Replace each with its corresponding `@@ALLOY_SDK_DIR@@/...` destination.
3. **Generate relocation manifest.** Write the list of modified files (relative to the SDK root) to `sdk/.alloy_relocation_manifest`. These files contain `@@ALLOY_SDK_DIR@@` and will need fixup at first use.
4. **Write placeholder to `.alloy_sdk_dir`.** Write the string `@@ALLOY_SDK_DIR@@` to `sdk/.alloy_sdk_dir`. This file is used by `ensure_sdk_relocated` at first use to detect that the SDK needs fixup - see [§8.6.6 sdk_utils.sh](#866-sdkutilssh).

**Build dependency:** `patchelf` is required at SDK build time for ELF RPATH verification/fixup. It is already a Buildroot host dependency (used by `fix-rpath`). It is NOT required on the machine that uses the SDK.

### 5.11 Smelterl Management Flow

**Purpose:** Ensure the smelterl escript is available for use.

**Steps:**

1. **Read version** - Extract smelterl version from `smelterl/src/smelterl.app.src`.
2. **Compute artefact path** - `${ALLOY_ARTEFACT_DIR}/tools/smelterl-${VERSION}`.
3. **Ensure checkout is present** - Repository-mode `build sdk` requires a local `smelterl/` checkout. If it is missing, fail with a clear message telling the user to run `git submodule sync --recursive smelterl` followed by `git submodule update --init --recursive smelterl`, or rerun `alloy build sdk` with `--init-deps`. When `--init-deps` is provided, the orchestrator may initialize the checkout explicitly before continuing.
4. **Check mode:**
   - **Development mode** (`--dev` or `ALLOY_DEV_MODE=true`): Always rebuild. Run `cd smelterl && rebar3 clean && rebar3 escriptize`. Copy result to artefact path.
   - **Normal mode**: Check if artefact exists at the artefact path. If yes, use it. If no, build (`cd smelterl && rebar3 escriptize`), create tools directory if needed, copy to artefact path, make executable.
5. **Use artefact** - The command script invokes smelterl at the artefact path.

---

## 6. Nugget Categories

This section describes the role, responsibilities, expected configuration and exports for each nugget category. It defines the **contracts and guidelines** between categories-which function exports a category is expected to provide, and which categories consume them. **These are not enforced by grisp_alloy:** the roles, config, exports, and "consumes from" described below are normative for nugget authors and integrators but the build system does not validate them. The only category-related rule that grisp_alloy enforces is **category cardinality** (e.g. exactly one builder, exactly one toolchain per tree; see [Data Design - Nugget Categories](01_DATA_DESIGN.md#nugget-categories)). For the metadata format of categories, cardinalities, and validation rules, see that same section.

**Terminology (config vs exports vs consumed config):** In the following subsections, each category is described using three kinds of keys:

- **Exports** - Non-overridable keys that this category **declares** (via metadata `exports`). They define values that other nuggets can rely on (e.g. `buildroot_path`, `target_arch_triplet`). Exports reserve the key across the tree and are never overridden (see [Data Design - Configuration consolidation](01_DATA_DESIGN.md#configuration-consolidation)).
- **Config** - Overridable keys that this category **uses** (declared via metadata `config`). Other nuggets may override them to alter this category's behaviour (e.g. `buildroot_version`, `buildroot_url`).
- **Consumes from other nuggets** - Config or export keys that this category **expects to be provided by** other categories (e.g. toolchain obtains architecture from platform or system exports). These are not declared by this nugget; they are inputs it reads from the consolidated context.

### 6.1 Category Overview

| Category    | Purpose                       | Cardinality |
|-------------|-------------------------------|-------------|
| `builder`   | SDK build backend (Buildroot) | Exactly one |
| `toolchain` | Cross-compilation toolchain   | Exactly one |
| `platform`  | SoC/family (e.g. imx6, imx8)  | Exactly one |
| `system`    | Board (e.g. grisp2, kontron-albl-imx8mm) | Exactly one |
| `bootflow`  | Firmware assembly orchestration | Multiple, one per variant |
| `feature`   | Composable functionality      | Multiple    |
| (product)   | Top-level nugget              | Exactly one (root) |

**Platform vs system:** **Platform** (e.g. imx6, imx8) is SoC/family level: it provides SoC-level Buildroot packages and options; it may optionally export `fun_` helper scripts for bootflows that choose to use that pattern. **System** (e.g. grisp2, kontron-albl-imx8mm, hug) is board level: it is the source of truth for *which* device tree, *which* bootloader config, *which* kernel for this board, and provides board-specific defconfig fragments and overlays. The system depends on the platform and on a set of **bootflows** (one per supported variant). **Bootflow** drives how the bootloader and kernel are packaged and how security is applied; see [§4.4 Bootflows](#bootflows) and [§6.6 bootflow](#66-bootflow).

### 6.2 builder

**Role:** Provides the build system backend. Currently only Buildroot is supported (`builder_buildroot`).

**Responsibilities:**
- Declare the Buildroot version and download URL.
- Provide a `pre_build` hook to download, extract, and configure Buildroot.
- Enable and configure ccache.
- Setup buildroot dowload cache.

**Config:** (may be overridden by other nuggets)
- `buildroot_version` - Buildroot version to download and use.
- `buildroot_url` - Download URL (or mirror) for Buildroot tarball, usually computed from `buildroot_version`.

**Exports:** (non-overridable)
- `buildroot_path` - Path to the extracted Buildroot tree; consumed by downstream nuggets and the SDK build.

**Consumes from other nuggets:** None.

### 6.3 toolchain

**Role:** Provides the cross-compilation toolchain used for building the SDK's target binaries and for project cross-compilation. The toolchain nugget may do so in one of three ways: **build a toolchain from source**, **provide a pre-built vendor toolchain**, or **configure Buildroot to use an internal toolchain** that Buildroot will build as part of the SDK build.

**Responsibilities:**
- Obtain the target architecture and other toolchain parameters from the exports of the platform and/or system nugget and use them to configure, import, or build the correct toolchain for the build.
- **Prefer generated config over per-board defconfigs:** When building a toolchain from source (e.g. Crosstool-NG), generate the backend defconfig from declarative parameters exported by platform/system (see **Consumes from other nuggets** and the parameter table below) so that new systems do not require adding a new config file-only the platform/system nugget exports need to be defined.
- Declare toolchain defaults (GCC version, languages, tarball layout, etc.) in the toolchain nugget or a single base template; platform/system exports override or supply the board-specific subset (arch, arch_cpu, kernel_version, etc.).
- Provide defconfig fragments to configure Buildroot's toolchain when using Buildroot internal toolchain.
- Declare embed lists so the cross-compiler is bundled into the SDK for project builds.

**Config:** (may be overridden by other nuggets; toolchain nugget declares defaults)
- `gcc_version` — GCC major version (e.g. `13`); maps to CT_GCC_V_* for Crosstool-NG.
- `static_toolchain` — Whether to build a static toolchain (e.g. CT_STATIC_TOOLCHAIN); default can be y or n.
- `debug_gdb` — Include GDB in the toolchain (CT_DEBUG_GDB).
- `binutils_gold`, `binutils_plugins` — Use gold linker and/or plugins (CT_BINUTILS_LINKER_LD_GOLD, CT_BINUTILS_PLUGINS).
- `languages` — Extra languages (e.g. CXX, FORTRAN); maps to CT_CC_LANG_*.
- Other architecture-related settings — Kernel headers, ABI, etc., as needed by the nugget.

**Exports:** (non-overridable)
- `target_arch_triplet` - Target architecture triplet (e.g. `arm-buildroot-linux-gnueabihf`); used by `env_utils.sh` and downstream nuggets.
- `cross_compile_prefix` - Cross-compiler prefix for toolchain binaries; used by `env_utils.sh` and project builds.
- Other toolchain values - Any other keys needed by downstream nuggets and `env_utils.sh`.

**Consumes from other nuggets:**
The exact keys depend on the toolchain backend (Crosstool-NG, Buildroot internal, or vendor). **Preferred approach:** the toolchain is driven by **declarative parameters** exported by platform/system; the toolchain nugget **generates** (or selects) the backend config from those parameters, so **no per-board defconfig file** is required. Each toolchain nugget maps these parameters to its own backend: e.g. a Crosstool-NG nugget produces CT_* options; a Buildroot-internal nugget would use them for defconfig fragments; a vendor nugget might use them to select a pre-built tarball. Typical inputs from **platform** and/or **system** (same parameter names across backends; backend-specific mapping is defined by each toolchain nugget):

- `arch` — Target CPU architecture (e.g. `arm`, `aarch64`, `armv7l`). Required; used to configure or select the toolchain and to derive the triplet.
- `arch_cpu` — CPU type (e.g. `cortex-a7`, `cortex-a53`).
- `arch_64` — Whether target is 64-bit (e.g. `true` for aarch64). When false/unset, 32-bit ARM; then `arch_fpu` and `arch_suffix` may apply.
- `arch_fpu` — FPU variant (e.g. `neon-vfpv4` for 32-bit ARM). Omit for 64-bit or soft-float.
- `arch_suffix` — Optional arch suffix (e.g. `v7`).
- `arch_float_hw` — For 32-bit ARM: whether to use hard-float ABI (triplet suffix `-gnueabihf`); when false, soft-float (`-gnueabi`). For 64-bit (aarch64) the triplet suffix is `-gnu` regardless; this parameter is ignored.
- `kernel_version` — Linux kernel version for toolchain kernel headers (e.g. `5.4`, `6.1`). Must match or be compatible with the kernel the platform/Buildroot builds.
- Optionally `target_name` (or `board`) — Board/SoC identifier. Only needed if the toolchain supports a fallback to a pre-made config per target; when config is fully generated, this is optional (e.g. for naming artefacts).

**Example for Crosstool-NG:**
The following describes how a **Crosstool-NG** toolchain nugget would maps the shared parameters above to its backend (CT_* options). Other toolchain nuggets (Buildroot internal, vendor) use the same consumed parameters but map them to their own backend format; only the Crosstool-NG mapping is specified here. When the toolchain backend is Crosstool-NG, the toolchain nugget **must** generate the defconfig from the parameters supplied via **Consumes from other nuggets** and **Config**, and must **not** require a per-board or per-system static defconfig file. The following parameters drive the generated defconfig:

| Parameter (from platform/system or Config)   | Effect in generated defconfig |
|----------------------------------------------|-------------------------------|
| `arch` (e.g. arm) + `arch_64` (false)        | Target 32-bit ARM: set CT_ARCH_ARM; do not set CT_ARCH_64. |
| `arch` (arm) + `arch_64` (true)              | Target 64-bit ARM (aarch64): set CT_ARCH_ARM and CT_ARCH_64=y. |
| `arch_cpu`                                   | CT_ARCH_CPU (e.g. cortex-a7, cortex-a53). |
| `arch_fpu`                                   | CT_ARCH_FPU (e.g. neon-vfpv4); omit when not applicable (e.g. 64-bit or soft-float). |
| `arch_suffix`                                | CT_ARCH_SUFFIX (e.g. v7); optional. |
| `arch_float_hw` (32-bit ARM only)            | CT_ARCH_FLOAT_HW; when true, hard-float ABI; when false, soft-float. Ignored for 64-bit. |
| `kernel_version`                             | CT_LINUX_V_* (e.g. 5.4 -> CT_LINUX_V_5_4, 6.1 -> CT_LINUX_V_6_1). |
| `binutils_gold`, `binutils_plugins`          | CT_BINUTILS_LINKER_LD_GOLD, CT_BINUTILS_PLUGINS, etc.; optional. |
| `static_toolchain`                           | CT_STATIC_TOOLCHAIN; optional, default as defined by toolchain nugget. |

The triplet ABI suffix and its relation to these options are defined by the concrete toolchain nugget (e.g. [§7.2 toolchain_ctng – Exports script](#exports-script-scriptsexportssh)).

All other Crosstool-NG options (GCC version, CT_CONFIG_VERSION, languages, CT_TARBALLS_BUILDROOT_LAYOUT, etc.) are taken from the toolchain nugget’s **Config** defaults or a single **base template** shipped with the toolchain nugget. Host-specific options (e.g. extra CFLAGS/LDFLAGS for the build host) are derived from the build host environment, not from platform or system exports. The toolchain nugget (or a script it invokes) produces the full defconfig from the parameter table above plus the base template, so that no per-board config file is required.

### 6.4 platform

**Role:** Provides **SoC/family-level** support (e.g. imx6, imx8): Buildroot packages and options that are generic for the SoC family. The platform does **not** define which board, which device tree, or which kernel config—those are the **system** responsibility (see §6.5). How the bootloader, kernel, and boot image are *built and assembled* is the **bootflow** responsibility; the bootflow decides the recipe using config and exports from **both platform and system** (the system may override platform or bootflow config for board-specific values). The platform supplies SoC-level building blocks and SoC-specific config/exports that the bootflow uses; it does not own the assembly recipe. For complex SoC families, a platform may optionally offer callable helper scripts via the `fun_` pattern—documented in [§6.8 Function Export Convention and Contracts](#68-function-export-convention-and-contracts); that pattern is optional and not required.

**Responsibilities:**
- Provide Buildroot packages and defconfig fragments that are **SoC-specific** (generic for the SoC family, not board-specific).
- Provide `post_build` / `post_image` hooks for SDK build-time tasks.
- Export **config and value exports** that the bootflow needs to drive assembly (see Config and Exports below). The bootflow consumes these together with system config (e.g. device tree name, U-Boot config, kernel filename) to implement its recipe.
- Platform scripts MUST NOT contain any security logic (signing, encryption); they only build or assist in building unsigned artefacts.
- Optionally, a platform may export callable scripts (`fun_` prefix) for bootflows that choose to delegate steps; see §6.8.

**Config:** (may be overridden by system or product)

Config keys supply defaults that the **system** or **product** may override for board-specific layout or policy. The bootflow reads consolidated config (platform + overrides) to generate the bootloader and kernel image. Typical keys:

- **`boot_scheme`** — SoC boot method (e.g. `none` for plain imx6, `ahab` for imx8 AHAB). Drives which layout and signing flow apply.
- **`kernel_image_format`** — Default kernel artefact format (e.g. `zImage`, `Image`, `fit`). System may override per board.
- **`image_layout_format`** — SoC-level layout type (e.g. `spl_uboot_raw`, `imx8_container`). Informs how the boot image is assembled.
- **`bootloader_seek`** — Offset (bytes or 512-byte blocks) where the bootloader is written on storage (e.g. 33 KiB for i.MX8, 1024 for some imx6). Product/system may override.
- **`bootloader_max_size`** — Maximum bootloader image size (e.g. in 512-byte blocks). Used by fwup/packaging to assert size; system may override.
- **`uboot_env_offset`** — U-Boot environment offset on storage (bytes or blocks). System may override for dual env or layout.
- **`uboot_env_count`** — U-Boot environment size (e.g. in 512-byte blocks). System may override.
- **`kernel_load_addr`** — Load address for the kernel (e.g. `0x3000` for FIT entry point). System may override when required by board.

**Exports:** (non-overridable)

Exports are **fixed for this platform** (SoC/family). They are not overridden; the bootflow and toolchain consume them as-is:

*Architecture (consumed by toolchain; see [§6.3 toolchain](#63-toolchain)):*
- **`arch`** — Target CPU architecture (e.g. `arm`, `aarch64`). Used by toolchain to configure or select the cross-compiler.
- **`arch_cpu`** — CPU type (e.g. `cortex-a7`, `cortex-a53`).
- **`arch_64`** — Whether target is 64-bit (e.g. `true` for aarch64). Omit or false for 32-bit ARM.
- **`arch_fpu`** — FPU variant (e.g. `neon-vfpv4` for 32-bit ARM). Omit for 64-bit or soft-float.
- **`arch_suffix`** — Optional arch suffix (e.g. `v7`).

*Boot layout (consumed by bootflow for image assembly and signing):*
- **`spl_load_addr`** — SPL load address in OCRAM (e.g. `0x920000` for i.MX8MP). Required when platform uses SPL.
- **`uboot_load_addr`** — U-Boot proper load address in DDR (e.g. `0x40200000`). Required when building U-Boot FIT or image.
- **`fit_load_addr`** — Address where SPL loads the FIT in DDR (e.g. `0x401FADC0` for i.MX8MP). Required for HAB/IVT placement in signed FIT.
- **`uboot_container_offset`** — Offset in the boot container where the second loader (U-Boot FIT) is placed (e.g. `0x60000`). Used for imx8-style container.
- **`fit_external_offset`** — Padding between FDT header and external data in FIT (e.g. `0x5000`). Must match U-Boot defconfig for IVT/CSF placement.
- **`fit_container_offset`** — Offset of FIT content inside the container (e.g. `0x58000`). Used when signing the container.
- **`atf_load_addr`** — ATF (BL31) load address when platform uses it.
- **`tee_load_addr`** — OP-TEE (BL32) load address when platform uses it.

*Paths and identifiers:*
- **`mkimage_path`** (or equivalent) — Path to SoC-specific `mkimage` or script when not on PATH from Buildroot.
- **`platform_id`** — SoC/family name (e.g. `imx6`, `imx8mm`, `imx8mp`) so the bootflow can branch or select logic.

### 6.5 system

**Role:** Provides board-level integration - specific hardware configuration, device tree overlays, rootfs customization, and board-specific preparation. The system depends on a **set of bootflows** (one per firmware variant it supports); the bootflow(s) drive how the bootloader and kernel are packaged and how security is applied.

**Responsibilities:**
- Provide **board-specific** Buildroot defconfig fragments: board selection, device tree file name, U-Boot board config fragment, kernel defconfig or fragments. The platform provides SoC-wide packages and options; the system provides the board selection and config used by Buildroot and (when present) by platform `fun_` scripts or bootflow logic.
- Provide hook scripts for board-level customization (post_build, post_fakeroot).
- May provide `pre_firmware` hooks for board-level firmware preparation (dm-verity hash tree generation, encryption preparation, initramfs). These operations are conditional on `ALLOY_FIRMWARE_VARIANT` - checking the variant is acceptable because it is a feature flag check, not security logic.
- May provide firmware overlays and filesystem priority fragments or depend on a feature for that like feature_squashfs.

**Config:** (may be overridden)
- **`device_tree`** — Which device tree (or overlay) to use for this board.
- **`uboot_config`** — Which U-Boot board/config to build.
- **`kernel_version`**, kernel defconfig or fragment — Which kernel and config for this board.
- **`image_layout`** — Boot image layout (SPL, U-Boot, kernel, etc.) for this board.
- **Partition layout** — Reserved/boot/rootfs/app partition offsets and sizes (e.g. for fwup config and crucible). The system is the source of truth for the board’s storage layout.
- **`kernel_its_*`** (or equivalent) — Paths to kernel ITS templates (e.g. with/without ramfs) used by the bootflow to build the kernel FIT. Board-specific when the ITS content or paths differ per board.
- **CSF template paths** — Paths to CSF templates for secure-boot signing when board- or layout-specific (e.g. when provided by the system for the bootflow to use). Otherwise the bootflow or security pack provides them.
- **Board-specific settings** — Networking, storage layout, dm-verity, and other board-level options.

**Exports:** (non-overridable)
- Typically none; system nuggets consume platform exports indirectly via the SDK configuration.

### 6.6 bootflow

**Role:** Defines the **firmware assembly orchestration** for one or more firmware variants. A bootflow nugget is the single "recipe owner" that turns the prepared firmware inputs (SDK base images + consolidated overlay + parameters) into boot artefacts for a specific platform/system and layout family. The model is **bootflow-driven**: each bootflow is compatible with a specific platform or set of platforms; the system depends on a set of bootflows (per variant). Bootflows are frozen definitions—a new *type* of flow requires a new bootflow nugget; a new system with a similar flow can reuse an existing bootflow.

Bootflow nuggets are where the build system expresses *how the device boots*: which boot components exist (SPL, boot container, U-Boot FIT, kernel FIT, initramfs), how they are assembled, and how security is applied (signing, encryption, verified boot) by invoking a security pack.

**Responsibilities:**
- Declare `firmware_variant` metadata for the variants the bootflow supports (e.g. `{firmware_variant, [plain]}` or `{firmware_variant, [secure]}`).
- Provide a `firmware_build` hook that orchestrates the boot assembly for those variants:
  - Build unsigned boot components by **either** calling platform-exported `fun_` helper scripts when the platform provides them and the bootflow chooses to use them, **or** by running the bootflow's own scripts using Buildroot outputs and config from platform/system.
  - Interleave security operations as needed by invoking `security_tools.sh` functions (which call the security pack).
  - Assemble the final boot artefact(s) and declare the path(s) via the nugget’s **exports** (e.g. `firmware_boot_image`) so they are available as `ALLOY_CONFIG_*` for downstream nuggets (hooks run in a subshell and cannot export variables).
- When using platform `fun_` exports, validate availability before calling and fail with clear errors when a required export is missing.
- Treat all security backend specifics (local keys, PKCS#11/HSM, remote signing) as an external dependency of the security pack; bootflow scripts never embed secrets.

**Relationship to system nuggets:** Bootflow selection is part of the board integration. System nuggets typically depend on the appropriate bootflow nugget(s) for that board and layout family, so a system brings along a coherent boot assembly recipe.

**Config:** (may be overridden)
- Layout and policy keys (via `ALLOY_CONFIG_*`) - Output filenames, which artefacts are present, template paths, signing policy inputs, etc.
- Runtime parameters from the security pack (e.g. SRK index, key identifiers, overlay paths) are provided by the orchestrator via `ALLOY_SECURITY_*` from `secpack env` (see [§4.6 Security Pack](#46-security-pack)); these are not nugget config but hook environment.

**Internal constants (signing standard):** A bootflow that implements a given signing standard (e.g. HABv4) holds **internal constants** for that standard’s IVT/CSF layout: alignment, IVT size, CSF reservation size, and field offsets within the IVT. These are defined by the standard and do not vary by platform; they are not config or platform exports.

**Exports:** (non-overridable)

Nuggets cannot export shell variables from hooks (hooks run in a subshell). The bootflow declares **exports** in its metadata (e.g. `firmware_boot_image`) whose values are paths to the generated artefact(s), typically using `${ALLOY_FIRMWARE_WORK_DIR}` so they resolve at firmware build time. These become `ALLOY_CONFIG_*` in the consolidated context for downstream nuggets (e.g. packaging features) to use.

- **`firmware_boot_image`** (or equivalent) — Path to the assembled boot image (e.g. `${ALLOY_FIRMWARE_WORK_DIR}/flash.bin`). Downstream nuggets consume it as `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE`.
- **`firmware_kernel_image`** (or equivalent) — Path to the kernel image (e.g. `${ALLOY_FIRMWARE_WORK_DIR}/fitImage` or signed kernel). Downstream nuggets consume it as `ALLOY_CONFIG_FIRMWARE_KERNEL_IMAGE`.
- Other exports as needed — Layout or policy keys that downstream hooks or nuggets consume.

**Consumes from other nuggets:**
- Config from platform/system (Buildroot outputs, device tree, DTB, U-Boot config, etc.); optionally **platform `fun_` exports** when the platform provides them and the bootflow chooses to use them; **security pack**—operations via `security_tools.sh` (signing, credentials, capability checks).

**Interacting with the Security Pack:**

Bootflow nuggets use `security_tools.sh` functions for all security operations. The hooks read `ALLOY_SECURITY_*` variables (exported by the orchestrator from `secpack env`) for configuration, and call `alloy_security_sign` / `alloy_security_get_credential` for cryptographic operations, for example:

```bash
# Example: HABv4 firmware signing in a bootflow nugget's firmware_build hook.
# The bootflow implements the flow using Buildroot outputs and config; it may
# optionally call a platform fun_ helper for one step (see comment at step 5).

SDK_IMAGES="${ALLOY_CONFIG_SDK_IMAGES_PATH:-${ALLOY_SDK_DIR}/images}"
WORK="${ALLOY_FIRMWARE_WORK_DIR}"

# 1. Check that the security pack supports firmware signing
if ! alloy_security_check_capability sign-boot; then
    log_error "Security pack does not support boot signing"
    exit 1
fi

# 2. Build the unsigned U-Boot FIT (bootflow's own script using platform config/exports)
build_uboot_fit_from_sdk "${SDK_IMAGES}" "${WORK}"  # uses ALLOY_CONFIG_* from platform/system

# 3. Get SRK table from the security pack
cred_dir=$(mktemp -d)
alloy_security_get_credential boot-signing srk-table "${cred_dir}"

# 4. Generate HABv4 CSF and insert IVT+CSF into the FIT (bootflow logic; pack does crypto only)
alloy_security_sign boot \
    "${WORK}/u-boot.itb" "${WORK}/u-boot.itb.csf.bin" \
    format=hab4-csf csf_template="${WORK}/csf_uboot_fit.txt" \
    blocks="${WORK}/csf_uboot_fit.blocks" srk_index="${ALLOY_SECURITY_SRK_INDEX:-0}"
insert_ivt_csf_into_uboot_fit "${WORK}/u-boot.itb" "${WORK}/u-boot.itb.csf.bin" "${WORK}/u-boot.itb.signed"

# 5. Build the kernel FIT (bootflow script; optionally use platform helper if available)
if [[ -n "${ALLOY_CONFIG_FUN_BUILD_KERNEL_FIT:-}" ]]; then
    "${ALLOY_CONFIG_FUN_BUILD_KERNEL_FIT}"   # optional: platform may provide this
else
    build_kernel_fit_from_sdk "${SDK_IMAGES}" "${WORK}"
fi

# 6. Sign the kernel FIT (check capability per security pack contract)
if ! alloy_security_check_capability sign-kernel; then
    log_error "Security pack does not support kernel signing"
    exit 1
fi
alloy_security_sign kernel \
    "${WORK}/kernel.itb" "${WORK}/kernel.itb.signed" \
    format=fit-rsa key_id="${ALLOY_CONFIG_KERNEL_SIGNING_KEY_ID:-default}"

# 7. Assemble the final boot image (bootflow's own script using platform layout exports)
assemble_boot_image "${WORK}" "${WORK}/flash.bin"
```

This pattern ensures that the bootflow nugget:
- Never invokes the security pack executable directly or accesses its internal files.
- Receives signing configuration from the pack via `ALLOY_SECURITY_*` variables.
- Delegates all cryptographic operations to the pack via `alloy_security_sign`.
- Works identically whether the pack uses local keys, an HSM, or a remote signing service.

**Multiple firmware variants from one SDK:** Nuggets declaring `firmware_variant` coexist in the SDK. The orchestrator selects which variant to run at firmware build time via `--variant`. See [§4.6 Security Pack](#46-security-pack) for details.

### 6.7 feature

**Role:** Provides composable, optional functionality that can be included by any product. Features are self-contained components that add specific capabilities to the SDK or firmware.

**Responsibilities:**
- Provide Buildroot packages and defconfig fragments for the feature's functionality.
- May provide hooks at any build stage (pre_build, post_build, pre_firmware, post_firmware, etc.).
- May provide embed lists to bundle tools or data into the SDK.
- May declare `firmware_outputs` metadata to describe firmware artefacts they produce, with optional `{selectable, true}` for user-controllable outputs (see [Data Design - Firmware Outputs Metadata](01_DATA_DESIGN.md#firmware-outputs-metadata)). Hooks that produce selectable outputs MUST check `ALLOY_OUTPUT_<ID>` before running and call `alloy_firmware_add_output` upon completion.
- May export configuration values or function scripts for downstream use.

**Common feature patterns:**

| Pattern | Examples | Selectable Output | Description |
|---------|----------|-------------------|-------------|
| Init system | `feature_erlinit` | - | Configures the firmware's init system. |
| Language runtime | `feature_erlang`, `feature_elixir` | - | Provides host language runtime (build tools) and target runtime (for OTP releases) in the SDK. |
| Filesystem builder | `feature_squashfs` | - | Merges rootfs with overlay and priorities during `pre_firmware`. |
| Firmware packager | `feature_fwup` | `fwup_firmware` | Packages firmware into `.fw` format during `post_firmware`. |
| Image generator | `feature_image` | `image` | Generates raw disk images during `post_firmware`. |
| GRiSP Update packager | `feature_grisp_updater` | `grisp_update` | Packages a software update package (`.tar` with `MANIFEST`) for grisp.io deployment during `post_firmware`. |

**Config:** (may be overridden; feature-specific)
- `squashfs_output_name` (e.g. feature_squashfs) - Output filename for the merged rootfs image.
- `fwup_output_name`, `fwup_*` (e.g. feature_fwup) - Firmware package output name and fwup options.
- `otp_version`, `host_erlang_root`, `host_rebar3` (e.g. feature_erlang) - Erlang/OTP version and host tool paths.
- Other feature-specific keys - As declared by each feature nugget.

**Exports:** (non-overridable; feature-specific)
- `host_erlang_root`, `host_rebar3`, `host_mix` (e.g. feature_erlang, feature_elixir) - Paths to host language runtimes and build tools; consumed by project plugins and `env_utils.sh`.
- Other feature exports - e.g. `squashfs_output_name` as resolved path, or tool paths; consumed by hooks and orchestrator.

**Consumes from other nuggets:** (depends on the feature)
- Toolchain exports - e.g. Erlang/Elixir features may use `target_arch_triplet`, `cross_compile_prefix` for NIFs and releases.
- Bootflow/platform context - Firmware features consume `ALLOY_CONFIG_*` and hook environment set by the orchestrator.

### 6.8 Function Export Convention and Contracts

Export keys follow a naming convention that distinguishes **value exports** from **callable function exports**:

| Prefix | Meaning | Example | Shell Variable |
|--------|---------|---------|----------------|
| (none) | Value export - configuration data, paths, version strings. | `target_arch_triplet` | `ALLOY_CONFIG_TARGET_ARCH_TRIPLET` |
| `fun_` | Function export - path to a callable script. | `fun_build_uboot_fit` | `ALLOY_CONFIG_FUN_BUILD_UBOOT_FIT` |

**Function export (`fun_`) rules:**

1. The value of a `fun_` export MUST be a `{path, PathSpec}` pointing to an executable script (typically in the nugget's `scripts/` directory).
2. The script MUST be self-contained: it reads its inputs from `ALLOY_CONFIG_*` and `ALLOY_FIRMWARE_*` environment variables, accepts optional command-line arguments (e.g. `--signed`), and writes its outputs to `ALLOY_FIRMWARE_WORK_DIR`.
3. The script MUST exit 0 on success and non-zero on failure.
4. The script SHOULD accept `--help` for documentation purposes.

**Contracts:**

A **contract** is a set of `fun_` exports that a nugget category may provide and that another nugget category may use. Contracts are enforced by convention and documentation.

**Contract definition:** A contract is identified by a name and lists:
- The **provider** category and the `fun_` export keys it may declare.
- The **consumer** category and how it may use those exports (if present).
- The **required** exports that the consumer needs when it chooses to use that contract.
- The **optional** exports that the consumer MAY use if present.

**Useful pattern - platform helper scripts via `fun_` exports:**

Platform nuggets MAY export building/assembly helper scripts via `exports` using the `fun_` naming convention. This is an **optional** reuse/convenience pattern: it keeps platform-specific tooling details (e.g. `mkimage`, `mkimage_imx8`, `genimage`) out of bootflow scripts and can make bootflows easier to share across boards that use the same SoC family. Bootflows may use these when available or implement the flow themselves.

Example:

```erlang
%% platform_imx8.nugget
{exports, [
    {fun_build_uboot_fit, {path, <<"scripts/build-uboot-fit.sh">>}},
    {fun_build_boot_container, {path, <<"scripts/build-boot-container.sh">>}},
    {fun_build_kernel_fit, {path, <<"scripts/build-kernel-fit.sh">>}},
    {fun_assemble_boot_image, {path, <<"scripts/assemble-boot-image.sh">>}}
]}
```

These scripts perform platform-specific operations and are unaware of security. They read configuration from `ALLOY_CONFIG_*` variables and write outputs to `ALLOY_FIRMWARE_WORK_DIR`.

---

## 7. Builtin Nuggets

This section describes the builtin nuggets shipped with the grisp_alloy repository. Each nugget is defined by a `.nugget` metadata file and associated files (defconfig fragments, hook scripts, overlays, packages). The nuggets are located under `nuggets/` in the repository. For generic category roles and contracts, see [§6 Nugget Categories](#6-nugget-categories).

**Work in progress:** The nugget designs below are preliminary and will evolve during implementation. Details (config keys, exports, defconfig fragments, hook behaviour) may be refined as the build system and nuggets are implemented.

### 7.1 builder_buildroot

**Category:** `builder` (exactly one per build)

**Purpose:** Provides the Buildroot SDK build backend: version, source URL, placement, ccache configuration, and download-cache symlink.

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `buildroot_version` | `<<"2025.05">>` | Buildroot version string. |
| `buildroot_url` | `{computed, <<"https://buildroot.org/downloads/buildroot-[[ALLOY_CONFIG_BUILDROOT_VERSION]].tar.gz">>}` | Full URL for the Buildroot tarball. |
| `buildroot_path` | `{computed, <<"[[ALLOY_BUILD_DIR]]/buildroot">>}` | Path where the Buildroot tree is available after extraction. |

**Defconfig fragment:** Enables ccache and points it at the cache:
```ini
BR2_CCACHE=y
BR2_CCACHE_DIR="[[ALLOY_CACHE_DIR]]/buildroot/ccache"
```

**Pre_build hook responsibilities:**

1. Ensure `${ALLOY_CACHE_DIR}/buildroot/downloads` exists.
2. Check for the Buildroot tarball at `${ALLOY_CACHE_DIR}/buildroot/buildroot-${ALLOY_CONFIG_BUILDROOT_VERSION}.tar.gz`.
3. If missing, download using `ALLOY_CONFIG_BUILDROOT_URL`.
4. Extract to the build directory and create a symlink so `ALLOY_CONFIG_BUILDROOT_PATH` points to the tree.
5. Create the dl symlink: `ln -sf "${ALLOY_CACHE_DIR}/buildroot/downloads" "${ALLOY_CONFIG_BUILDROOT_PATH}/dl"`.

After `pre_build`, the Buildroot tree is ready at `ALLOY_CONFIG_BUILDROOT_PATH` with the download cache linked.

### 7.2 toolchain_ctng

**Category:** `toolchain` (exactly one per build)

**Purpose:** Provides the cross-compilation toolchain built with Crosstool-NG. This nugget is the concrete implementation of the [toolchain category](#63-toolchain) using Crosstool-NG as the backend. It builds the toolchain from source (or reuses an existing artefact), caches Crosstool-NG and component sources, and exports the target triplet and sysroot path for use by `env_utils.sh` and Buildroot.

**Config keys:**

- **`ctng_source`** — `<<"release">>` (Default) or `<<"git">>`. How to obtain Crosstool-NG: `release` for official tarball, `git` for a git clone.
- **`ctng_url`** — Default (computed): `https://crosstool-ng.org/download/crosstool-ng/crosstool-ng-[[ALLOY_CONFIG_CTNG_VERSION]].tar.xz`; when `ctng_source=git`, the upstream git repository URL (e.g. `https://github.com/crosstool-ng/crosstool-ng.git`). May be overridden for mirrors or forks.
- **`ctng_version`** — Used when `ctng_source=release`. Crosstool-NG release version (e.g. `1.25.0`); used to compute the default `ctng_url`.
- **`ctng_git_ref`** — Used when `ctng_source=git`. Git ref (commit hash or tag) to check out. Default: `master`; e.g. `<<"5595edc370d8146ca3bbb3052dde48aceaff4970">>` for a pinned commit.
- **Shared toolchain options** — See [§6.3 toolchain](#63-toolchain): `gcc_version`, `static_toolchain`, `debug_gdb`, `binutils_gold`, `binutils_plugins`, `languages`, etc. These are merged with parameters consumed from platform/system to produce the CT_* defconfig.

**Exports:**

Exports are defined when smelterl generates `alloy_context.sh` (before the SDK build runs), so they must be **computable from known config** at that time. The toolchain nugget declares `target_arch_triplet`, `cross_compile_prefix`, and `sysroot_path` with an **exec** value (script `scripts/exports.sh`) because a simple template is not flexible enough and because `sysroot_path` depends on the triplet (exec outputs are not available when resolving computed values); the script generates each value from `ALLOY_CONFIG_*` and `ALLOY_EXPORT_*` (e.g. triplet for sysroot_path). Other exports are literal or computed from templates. Downstream nuggets and `env_utils.sh` use `ALLOY_EXPORT_*` from the context.

- **`toolchain_name`** — `<<"Crosstool-NG">>`.
- **`toolchain_version`** — From config `toolchain_version`; e.g. `<<"3.0">>`. Used in artefact naming and stored in the built toolchain as a tag file.
- **`target_arch_triplet`** — Value from exec script `scripts/exports.sh` (key as argument); see [Exports script (scripts/exports.sh)](#exports-script-scriptsexportssh). Used by `env_utils.sh` and for artefact naming. The pre_build script **validates** that the built toolchain’s actual triplet (e.g. from `ct-ng show-tuple`) matches this value and fails the build if it differs.
- **`cross_compile_prefix`** — Value from exec script `scripts/exports.sh` (key as argument); see [Exports script (scripts/exports.sh)](#exports-script-scriptsexportssh). Cross-compiler prefix for toolchain binaries; used by `env_utils.sh` and project builds.
- **`sysroot_path`** — Value from exec script `scripts/exports.sh` (key as argument); see [Exports script (scripts/exports.sh)](#exports-script-scriptsexportssh). Depends on the triplet (which is also exec-generated), so it cannot be a computed template. Used for cross-compilation headers and libraries.

**Validation:** Because exports are fixed at context generation time, the pre_build script must verify that the toolchain it builds (or reuses) actually produces that triplet. After building or when reusing an artefact, compare the actual triplet (from `ct-ng show-tuple` or from the extracted toolchain directory name) to `ALLOY_EXPORT_target_arch_triplet`. If they differ, fail with a clear error so the expected value and the generated toolchain stay in sync.

**Defconfig fragment:** The nugget provides a Buildroot defconfig fragment that configures Buildroot to use the external toolchain (path and triplet from the nugget’s exports).

**Embed:** The cross-compilation toolchain binaries and sysroot. The embed list must include the toolchain install tree (or the subset needed at SDK runtime): e.g. all files under `host/bin/<TRIPLET>-*` (cross-compiler, linker, assembler, etc.), the sysroot at `host/<TRIPLET>/sysroot/` (or the path matching the actual layout), and any host shared libraries required by these tools. This ensures the SDK is self-contained for cross-compilation without requiring a system-installed cross-compiler.

**Host and Vagrant:** Toolchain builds require a suitable host (build tools, bison, gettext, etc.). The current grisp_alloy flow runs `build-toolchain.sh`; on non-Linux hosts it can delegate to a Vagrant VM so that the toolchain is built on Linux. The nugget pre_build hook, when run by the alloy SDK build, runs in the same environment as other hooks; if the SDK build is intended to run only on Linux, no Vagrant logic is needed inside the nugget; otherwise the hook or the orchestrator may document or delegate to a Linux environment for the actual Crosstool-NG build.

#### Exports script (scripts/exports.sh)

Because a simple computed template is not flexible enough to derive the triplet (and thus the cross-compiler prefix) or the sysroot path from the many combinations of arch, ABI, and float settings, and because `sysroot_path` depends on the triplet (which is exec-generated — exec outputs are not available when resolving computed values), the nugget declares `target_arch_triplet`, `cross_compile_prefix`, and `sysroot_path` with an **exec** value: `{exec, "scripts/exports.sh"}`. During configuration resolution, smelterl runs the script with the **export key** as the first argument (e.g. `scripts/exports.sh target_arch_triplet`); the script has access to all already-resolved `ALLOY_CONFIG_*` and `ALLOY_EXPORT_*` variables (see Data Design – configuration consolidation). It must be deterministic and side-effect-free; it prints the value to stdout (trimmed) and exits 0.

**Config-to-triplet mapping (Crosstool-NG):** The script derives the triplet from the same config that drives the CT_* defconfig (see [§6.3 Example for Crosstool-NG](#63-toolchain)). The ABI/suffix part of the triplet must match what Crosstool-NG produces so that pre_build validation against `ct-ng show-tuple` succeeds:

| Config / export (from platform or toolchain) | Triplet ABI suffix | Example triplet |
|---------------------------------------------|---------------------|------------------|
| `arch_64` true (aarch64)                    | `-gnu`              | `aarch64-undefined-linux-gnu` |
| 32-bit ARM, `arch_float_hw` true            | `-gnueabihf`        | `arm-undefined-linux-gnueabihf` |
| 32-bit ARM, `arch_float_hw` false or unset  | `-gnueabi`          | `arm-undefined-linux-gnueabi` |

How the script generates each value:

- **`target_arch_triplet`** — Read from config: `arch`, `arch_64`, `arch_float_hw`, and optionally `arch_cpu`, `arch_suffix`. Assemble the triplet:
  - **Machine:** 64-bit ARM (`arch_64` true) -> `aarch64`; 32-bit ARM -> `arm` (optionally with suffix per CT-NG conventions).
  - **Vendor:** Fixed string (e.g. `buildroot`) to match Crosstool-NG default.
  - **OS:** `linux`.
  - **ABI/suffix:** Use the mapping table above. Output the single line `<machine>-<vendor>-<os>-<suffix>`.

- **`cross_compile_prefix`** — The script outputs the same string as for `target_arch_triplet` (the cross-compiler prefix is the triplet). Alternatively it can accept the key `cross_compile_prefix` and return the value of `target_arch_triplet` if that is already in the environment (when resolution order runs exports in sequence), or recompute it with the same logic.

- **`sysroot_path`** — Depends on the triplet, so it must be produced by the same exec script (triplet is not available in computed templates). The script obtains the triplet (from `ALLOY_EXPORT_target_arch_triplet` if already resolved, or by recomputing it). It then outputs the sysroot path in the form used by downstream nuggets and `env_utils.sh`: typically a path relative to the SDK root or to the toolchain install root, e.g. `host/<TRIPLET>/sysroot` or `<TRIPLET>/<TRIPLET>/sysroot` depending on Crosstool-NG layout (the script substitutes the actual triplet). If the path must be absolute at resolution time, the script may use context variables (e.g. `ALLOY_BUILD_DIR`, or a toolchain install path from config) when available.

Unknown keys must cause the script to exit non-zero or print nothing so resolution fails clearly.

#### Nugget layout (conventional)

- **Config and defconfig base** — The nugget holds default Config and a **base template** of CT_* options (GCC version, CT_CONFIG_VERSION, CT_TARBALLS_BUILDROOT_LAYOUT, languages, etc.). Platform/system exports supply the board-specific subset (arch, arch_cpu, kernel_version, etc.); the hook **generates** the full Crosstool-NG defconfig from these (see [§6.3 toolchain – Example for Crosstool-NG](#63-toolchain)), so no per-board static defconfig file is required.
- **Patches** — The nugget includes a `patches/crosstool-ng/` directory (or equivalent) containing patches to apply to the Crosstool-NG source tree before building. Patches are applied in a defined order (e.g. by filename or via a `series` file). The current grisp_alloy tree uses patches such as fixes for Linux headers on macOS, GCC arm_acle.h, and macOS/Xcode build fixes.
- **Scripts** — The pre_build hook script may delegate to a helper script (e.g. a `build-crosstool-ng.sh`-style script) that performs the steps below; the hook is responsible for environment (ALLOY_* variables, cache paths, artefact dir) and for validating that the built toolchain’s triplet matches the expected export from context.

#### Pre_build hook responsibilities

The following describes what the pre_build script must do so that a developer can implement it. The current implementation is in `toolchain/scripts/build-crosstool-ng.sh`; the nugget hook runs in the alloy context (ALLOY_BUILD_DIR, ALLOY_CACHE_DIR, ALLOY_ARTEFACT_DIR, platform/system exports via ALLOY_CONFIG_* / ALLOY_EXPORT_*).

1. **Check for existing toolchain artefact**  
   Use the expected triplet from context (`ALLOY_EXPORT_target_arch_triplet`) and `toolchain_version` to form the artefact name (e.g. `grisp_toolchain_<toolchain_name>-<toolchain_version>.<HOST_OS>-<HOST_ARCH>.tar.xz`). Look in the artefact directory (`${ALLOY_ARTEFACT_DIR}/toolchains/`) for an archive matching that name. If found, extract it to the location where the SDK build expects the toolchain (or register the path), **validate** that the extracted toolchain’s triplet (e.g. from the directory name under the install tree) matches `ALLOY_EXPORT_target_arch_triplet`, and exit without building. If validation fails, report an error and do not reuse the artefact.

2. **Prepare environment and directories**  
   Create and use a dedicated work directory for this build (e.g. under `ALLOY_BUILD_DIR/toolchain/`). On Linux, long path lengths can cause build failures; the current implementation uses a short path (e.g. `/tmp/ctng-work`) for the Crosstool-NG work dir when on Linux. Ensure `${ALLOY_CACHE_DIR}/toolchain/` and, inside it, a directory for Crosstool-NG source archives and a directory for component tarballs (e.g. `downloads/`) exist. Ensure the artefact output directory exists.

3. **Obtain and cache Crosstool-NG source**  
   - If using release tarballs: download from `ctng_url` (default is the standard tarball URL built from `ctng_version`). Check the cache (e.g. `ALLOY_CACHE_DIR/toolchain/`) for the tarball; if missing, download and store it there.  
   - If using git: check the cache for an existing archive of the Crosstool-NG source at the requested ref (e.g. a tarball named by ref or tag); if missing, clone from `ctng_url`, check out `ctng_git_ref`, create a tarball (excluding `.git`) and store it in the cache for future runs.  
   Extract the Crosstool-NG source into the work directory (e.g. `work/crosstool-ng/`).

4. **Apply patches**  
   Apply all patches from the nugget’s patch directory (e.g. `patches/crosstool-ng/`) to the extracted Crosstool-NG source tree using `patch_tools.sh` (see [§8.6.10 patch_tools.sh](#8610-patchtoolssh)). Call `alloy_apply_patches` (hook API). Use deterministic order (e.g. `series` file or sorted by path). Fail the build if any patch does not apply cleanly.

5. **Build Crosstool-NG (host tool)**  
   Configure and build Crosstool-NG as a host tool: run bootstrap if the source came from git; run configure with a prefix inside the work directory (e.g. `work/usr`); run make and make install. On non-Linux hosts (e.g. macOS), the current implementation sets environment variables for bison, gettext, GNU sed/make, and optional compiler overrides to satisfy build requirements. Verify that the `ct-ng` binary is installed and runnable.

6. **Generate Crosstool-NG defconfig and prepare toolchain build**  
   Build the defconfig that Crosstool-NG will use:  
   - Combine the nugget’s base template (CT_* options from Config and defaults) with the parameters consumed from platform/system (arch, arch_cpu, kernel_version, etc.) and map them to CT_* options as in [§6.3 Example for Crosstool-NG](#63-toolchain). Strip any non-CT_* keys (e.g. nugget-specific keys like `toolchain_version`, `ctng_*`) from the written defconfig so that only Crosstool-NG options remain.  
   - Append or set in the defconfig: `CT_LOCAL_TARBALLS_DIR` pointing to the cache directory for component downloads (e.g. a path relative to the build dir pointing to `ALLOY_CACHE_DIR/toolchain/downloads/`), and `CT_PREFIX_DIR` (and optionally `CT_WORK_DIR` when using a global work dir).  
   - Run `ct-ng defconfig` to load the generated defconfig, then optionally `ct-ng savedefconfig` to produce a full `.config`. Keep a copy of the defconfig used (e.g. `defconfig.orig`) for reproducibility and for storing in the toolchain tree later.

7. **Build the cross toolchain**  
   Run `ct-ng build`. This downloads (and caches in `CT_LOCAL_TARBALLS_DIR`) any missing component tarballs (GCC, binutils, kernel headers, C library, etc.), then builds the cross-compiler and target sysroot. This step is long-running; the current implementation runs it with optional keepalive output for CI. After the build, fix permissions on the install tree if Crosstool-NG made files read-only (e.g. `chmod -R u+w` on the target triplet directory under the install prefix). **Validate** that the built toolchain’s triplet (e.g. from `ct-ng show-tuple` in the build dir) equals `ALLOY_EXPORT_target_arch_triplet`; if not, fail the build with a clear message so the expected value (from alloy_context.sh) and the generated toolchain stay in sync.

8. **Save build info and clean optional artefacts**  
   Inside the toolchain install directory (e.g. `work/x-tools/<tuple>/`), store the toolchain version tag (e.g. in a file such as `grisp-toolchain.tag`), and copy the defconfig and final `.config` (e.g. `ct-ng.defconfig`, `ct-ng.config`) for reproducibility. Remove unneeded artefacts from the install tree (e.g. Crosstool-NG’s compressed build log) if desired. If the work directory was in a global location (e.g. `/tmp/ctng-work`), remove it to avoid leaving large temporary data.

9. **Pack the toolchain and write to artefacts**  
   Create an archive of the toolchain install tree (the directory containing the target triplet, e.g. `x-tools/<tuple>/`). The archive name should uniquely identify the toolchain: e.g. `grisp_toolchain_<tuple_underscores>-<toolchain_version>.<HOST_OS>-<HOST_ARCH>.tar.xz`. On macOS, the current implementation may also produce a case-sensitive DMG and/or fix kernel header case conflicts before creating a tarball for compatibility with case-insensitive filesystems. Write the archive to the configured artefact directory (e.g. `ALLOY_ARTEFACT_DIR/toolchains/`).

10. **Verify exports**  
    Exports (`target_arch_triplet`, `cross_compile_prefix`, `sysroot_path`) are already set in alloy_context.sh from smelterl’s computed values. The script has already validated that the actual triplet matches (in step 1 when reusing, or in step 7 when building). Optionally record the toolchain install path or sysroot path to a well-known location if downstream steps need to resolve them at build time (e.g. for embed lists or Buildroot defconfig).

### 7.3 common_base

**Category:** `feature`

**Purpose:** Foundation nugget providing only what is **generic for any embedded Linux product**: minimal rootfs skeleton, locale, reproducible build settings, and a generic post-build layout for `/var` and `/tmp`. It does **not** include Erlang/OTP, Elixir, erlinit, fwup, grisp-updater, or any product- or board-specific packages or scripts; those are provided by separate feature or system nuggets (e.g. `feature_erlinit`, `feature_erlang`, `feature_elixir`, `feature_fwup`, `feature_squashfs`). A product or system nugget that needs a “GRiSP-style” base composes `common_base` with those feature nuggets.

**Scope — what common_base provides:**

- **Buildroot defconfig fragment** — Options that apply to any embedded Linux rootfs built with Buildroot:
  - **Reproducible builds:** `BR2_REPRODUCIBLE=y`.
  - **Locale:** Enable a minimal locale whitelist and generate a default locale (e.g. `en_US.UTF-8`) so the rootfs has a consistent locale archive.
  - **Rootfs skeleton:** Custom skeleton via `BR2_ROOTFS_SKELETON_CUSTOM` and a path to the nugget’s skeleton directory. The skeleton contains only the minimal Unix base: `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/hosts`, `/etc/protocols`, and optionally a device table for `/dev`, `/tmp`, `/etc`, `/root`, `/var/log`, `/var/lib` (and similar generic directories). No application-specific or product-specific files.
  - **Rootfs overlay:** Optional overlay directory; if present, it contains only generic layout (e.g. empty placeholder dirs or symlinks that any product might need). No Erlang, erlinit, or product config files (those go in feature or system overlays).
  - **Post-build script:** A single post-build script that performs only **generic** steps: create `/var` runtime symlinks (`/var/tmp` -> `/tmp`, `/var/run` -> `/run`, `/var/lock` -> `/run/lock`, `/var/cache` -> `/run/cache`, `/var/spool` -> `/run/spool`), ensure `/var/log` exists. Optionally write a minimal `/usr/lib/os-release` from config (product name can be a placeholder or from a nugget config key). It must **not** remove inittab, fstab, or shell configs (that is the responsibility of init/erlinit or other feature nuggets). It must **not** call product-specific scrub or git-info scripts unless they are generic.
  - **Post-image script:** None. Image packaging (fwup, genimage, etc.) is provided by `feature_fwup` or other feature nuggets.
  - **Busybox:** Either use Buildroot default or point to a **minimal** Busybox config that is generic (no product-specific applets).
- **Buildroot patches:** Only patches that are truly global (e.g. toolchain or Buildroot core fixes). Patches that affect a single package (Erlang, fwup, mtools, libp11, etc.) belong in the nugget that provides or depends on that package.
- **No extra packages in the defconfig fragment:** common_base does **not** enable F2FS, linux-firmware, libp11, libmnl, nbtty, grisp-config, host elixir, host grisp-updater-tools, or any Erlang/elixir/erlinit package. Those are added by feature nuggets (`feature_erlang`, `feature_elixir`, `feature_erlinit`, `feature_fwup`) or system nuggets.

**Scope — what common_base does not provide (and where it lives):**

| Concern | Nugget or location |
|--------|---------------------|
| Init / PID 1 (erlinit) | `feature_erlinit` |
| Erlang/OTP, rebar3 (target or host) | `feature_erlang` |
| Elixir (host) | `feature_elixir` |
| Firmware packaging (fwup, post-image) | `feature_fwup` |
| Rootfs image format (SquashFS, etc.) | `feature_squashfs` (or equivalent) |
| Raw disk image | `feature_image` |
| GRiSP updater, grisp-config, nbtty, cryptoauthlib | System or product nuggets |
| Scrub that removes inittab/fstab/shell configs | `feature_erlinit` (or similar) |
| ccache | `builder_buildroot` (see [§7.1](#71-builderbuildroot)) |

**Nugget layout (conventional):**

- **defconfig fragment** — As above; merged by smelterl with builder and toolchain fragments. Paths in the fragment use placeholders (e.g. `[[ALLOY_NUGGET_common_base_PATH]]` or similar) so the skeleton and overlay paths resolve to the staged nugget directory.
- **skeleton/** — Minimal `/etc` and device table only.
- **rootfs_overlay/** — Empty or minimal (e.g. only `/tmp` or `/var` stubs if not covered by skeleton/device table).
- **post-build.sh** — Generic steps only; sourced or invoked by Buildroot’s `BR2_ROOTFS_POST_BUILD_SCRIPT` (or the alloy equivalent). Must not depend on product-specific environment variables except those provided by config consolidation.

**Dependencies:** Depends on `builder_buildroot` and `toolchain_ctng` (or equivalent). It does not depend on any feature nugget (erlinit, erlang, fwup, etc.); those feature nuggets depend on `common_base` when they need a minimal rootfs base.

### 7.4 bootflow_grisp2_plain

**Category:** `bootflow`

**Firmware variant:** `plain`

**Purpose:** Bootflow nugget for GRiSP 2 class systems (plain, unsigned variant). It does **not** produce the final firmware package (`.fw`): that is produced by [feature_fwup](#714-featurefwup) in `post_firmware`. This nugget is responsible only for ensuring that all **boot artefacts** required by the packaging phase exist and for exporting their paths so that `feature_fwup` (and any other packaging features) can consume them. For the plain variant there is no separate bootloader or kernel at firmware build time—the kernel is part of the base rootfs—so the only boot artefact is the combined rootfs (base + overlay, merged with the system’s SquashFS priorities). The combined rootfs is normally produced in `pre_firmware` by `feature_squashfs`; the bootflow validates that it exists and exports its path as the boot image for this variant.

**Responsibility split (design):**

- **bootflow_grisp2_plain:** Ensures boot artefacts exist; exports their paths (e.g. `firmware_boot_image`) for downstream packaging. Does **not** run fwup or produce the `.fw` file.
- **System nugget (e.g. system_grisp2):** Provides layout and packaging configuration: path to `fwup.conf`, SquashFS priorities, kernel/partition metadata for update packages, and any product-specific fwup template variables.
- **feature_fwup:** In `post_firmware`, consumes the bootflow’s exported path(s) and the system’s `fwup.conf`, runs fwup, and produces the `.fw` package (see [§7.14](#714-featurefwup)).

**Config and exports consumed:**

- **From system nugget:** SquashFS priorities (if the bootflow were to build the combined rootfs; when `feature_squashfs` does it, the bootflow only needs the path). Optionally layout keys used to validate or name artefacts.
- **From platform or context:** Path to the combined rootfs (e.g. `ALLOY_CONFIG_ROOTFS` from `feature_squashfs`) and any config needed to validate that inputs for packaging are present (e.g. path to `fwup.conf` for validation only; the system sets it for `feature_fwup`).

**Firmware_build hook (assembly recipe):**

The hook does **not** run fwup. It ensures boot artefacts exist and declares their path(s) via the nugget’s **exports** so they appear as `ALLOY_CONFIG_*` for `feature_fwup` and other post_firmware hooks. The hook may call platform-exported `fun_` helpers (see [§6.8](#68-function-export-convention-and-contracts)) where useful.

At minimum, the hook MUST:

1. **Validate** that the inputs required for packaging exist: combined rootfs path (e.g. `ALLOY_CONFIG_ROOTFS`), and—for consistency—that the system has provided packaging config (e.g. path to `fwup.conf`) so that `feature_fwup` will be able to run later. Fail with a clear error if any required input is missing.
2. **Ensure boot artefacts exist:** For GRiSP2 plain there are no unsigned boot components to build (no U-Boot or kernel image at firmware time). The combined rootfs is produced in `pre_firmware` by `feature_squashfs`. If for some reason it were not yet present (e.g. a different orchestrator ordering), the hook would need to ensure it exists; in the standard flow the hook only needs to validate and pass through.
3. **Export boot artefact path(s):** Declare the path to the boot image for this variant via the nugget’s export (e.g. `firmware_boot_image`). For plain, the only boot artefact is the combined rootfs, so the exported path is the combined rootfs path (the same as `ALLOY_CONFIG_ROOTFS`). Downstream, `feature_fwup` uses this as `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE` when expanding `fwup.conf` and building the `.fw` package.

### 7.5 bootflow_imx8_fit_plain

**Category:** `bootflow`

**Firmware variant:** `plain`

**Purpose:** Bootflow nugget providing a generic “i.MX8 FIT boot” plain assembly recipe for i.MX8MM- and i.MX8MP-class systems (e.g. Kontron ALBL i.MX8MM). It does **not** produce the final firmware package (`.fw`): that is produced by [feature_fwup](#714-featurefwup) in `post_firmware`. This nugget is responsible only for ensuring that all **boot artefacts** required by the packaging phase exist and for exporting their paths so that `feature_fwup` and other packaging features can consume them. The boot artefacts for this flow are:

- An unsigned U-Boot FIT image.
- An unsigned kernel FIT image.
- An i.MX8 boot container (when required by the SoC/boot media).
- A final assembled boot image

This bootflow does not perform signing or encryption. Secure boot variants are provided by separate bootflows (e.g. an external `bootflow_imx8_fit_habv4`).

**Responsibility split (design):**

- **bootflow_imx8_fit_plain:** Builds the boot artefacts above and declares their paths via nugget exports (`firmware_boot_image`, `firmware_kernel_image`). Does **not** run fwup or produce the `.fw` file.
- **System nugget (e.g. system_kontron-albl-imx8mm):** Provides board-specific config: device tree, U-Boot/FIT templates, `genimage` config, path to `fwup.conf`, and any fwup template variables. Platform nugget (e.g. `platform_imx8`) provides the `fun_` helper scripts and SoC-level config.
- **feature_fwup:** In `post_firmware`, consumes the bootflow’s exported paths and the system’s `fwup.conf`, runs fwup, and produces the `.fw` package (see [§7.14](#714-featurefwup)).

**Common config keys:**

These keys define the most common inputs and outputs for i.MX8 FIT-based bootflows. They are typically exported by the platform/system nuggets; the bootflow consumes them as `ALLOY_CONFIG_*` variables.

| Key | Type | Purpose |
|-----|------|---------|
| `uboot_fit_its` | `{path, ...}` | U-Boot FIT ITS template path (system or platform). |
| `kernel_fit_its` | `{path, ...}` | Kernel FIT ITS template path (system or platform). |
| `uboot_fit_output_name` | value | Filename to produce for the unsigned U-Boot FIT (prefixed with `ALLOY_FIRMWARE_WORK_DIR`). |
| `kernel_fit_output_name` | value | Filename to produce for the unsigned kernel FIT (prefixed with `ALLOY_FIRMWARE_WORK_DIR`). |
| `boot_container_output_name` | value | Filename to produce for the unsigned boot container (prefixed with `ALLOY_FIRMWARE_WORK_DIR`). |
| `boot_image_output_name` | value | Filename to produce for the final assembled boot image (prefixed with `ALLOY_FIRMWARE_WORK_DIR`). |
| `boot_media` | value | Boot media identifier (e.g. `sd`, `emmc`). |
| `soc_family` | value | SoC family identifier (e.g. `imx8mm`, `imx8mp`). |

Bootflows MAY define additional keys as needed for specific layouts (e.g. DTB selection, initramfs inclusion, boot partition size). Keys that are purely board-specific belong in the system nugget; keys that are purely SoC/tool-specific belong in the platform nugget.

**Firmware_build hook (assembly recipe):**

The hook does **not** run fwup. It builds the boot artefacts using **Buildroot outputs** (from the SDK), **config values** from the platform and system (e.g. load addresses, paths to ITS templates, genimage config), and **host tools** provided by Buildroot packages (e.g. `mkimage`, `mkimage_imx8`, `genimage`). The platform does not export build scripts; the bootflow implements the recipe. The hook:

1. **Validate** — Required config and SDK paths must be present: paths to U-Boot and kernel images from the SDK, ITS templates (or paths), genimage config, output name keys, and platform layout values (load addresses, offsets). Fail with a clear error if any required input is missing.
2. **Build unsigned U-Boot FIT** — Using `mkimage` (and config from `ALLOY_CONFIG_*`), produce the U-Boot FIT image; output `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_UBOOT_FIT_OUTPUT_NAME}`.
3. **Build unsigned kernel FIT** — Using `mkimage` and kernel/DTB (and optional initramfs) from the SDK, produce the kernel FIT image; output `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_KERNEL_FIT_OUTPUT_NAME}`.
4. **Build unsigned boot container** — When required by the SoC/boot media, using `mkimage_imx8` and platform config, produce the i.MX8 boot container; output `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_BOOT_CONTAINER_OUTPUT_NAME}`.
5. **Assemble final boot image** — Using `genimage` and the platform/system genimage config, assemble the final boot partition image from the artefacts above; output `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_BOOT_IMAGE_OUTPUT_NAME}`.
6. **Export boot artefact path(s):** Declare exports (e.g. `firmware_boot_image`, `firmware_kernel_image`) so they become `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE` and `ALLOY_CONFIG_FIRMWARE_KERNEL_IMAGE`. Downstream, `feature_fwup` uses these when expanding `fwup.conf` and building the `.fw` package.

### 7.6 platform_imx6

**Category:** `platform` (exactly one per build)

**Purpose:** Provides NXP i.MX6 SoC-family support: ARMv7 architecture, toolchain selection, kernel base configuration for the SoC, and optional U-Boot support. The platform does **not** define which board, which device tree file, or which kernel version/source—those are the responsibility of the system nugget that depends on this platform (see [§6.5 system](#65-system)). A system nugget (e.g. for a board based on i.MX6ULL) depends on `platform_imx6` with the appropriate flavor and adds board-specific device tree, kernel fragments, and overlays.

**Provides:** `nxp_imx6`, `arm`.

**Flavors:** `imx6ull`, `imx6ul` (SoC qualifier). The flavor selects the exact SoC variant; i.MX6ULL is a member of the i.MX6UL family (Cortex-A7, same core).

**Config keys (platform-level):**

| Key | Purpose |
|-----|---------|
| Architecture / CPU | Expose SoC family and CPU core (e.g. `imx6ul` / `imx6ull`, Cortex-A7) for bootflows and config resolution. |
| Device tree (default) | Optional default device tree path per flavor; the system nugget typically overrides with the board DTS. |
| Kernel base fragment | Path to a Linux kernel defconfig fragment that enables SoC support (e.g. `ARCH_MXC`, `SOC_IMX6UL`, serial, I2C, SPI, GPIO, MMC, thermal, watchdog, NVMEM, OP-TEE if used). The system adds its own fragment and DTS path. |

**Defconfig fragment (Buildroot):**

The platform nugget’s defconfig fragment must set the following so that any system depending on it gets a working i.MX6 SDK. The system nugget’s fragment is merged after the platform’s and adds board-specific options (kernel source/version, DTS path, rootfs overlay, etc.).

**Architecture and toolchain:**

- **Target architecture:** The platform sets all architecture-related Buildroot options so that (1) the **toolchain nugget** can build (or select) the appropriate toolchain for this platform, and (2) Buildroot is configured for the platform when building the SDK. Set `BR2_arm=y`, `BR2_cortex_a7=y` (i.MX6UL/ULL use Cortex-A7), and `BR2_ARM_FPU_NEON_VFPV4=y` so the target is ARMv7-A EABIHF and the toolchain nugget and kernel build match the SoC. The platform does **not** build or configure the toolchain directly; it only sets the architecture config that the toolchain nugget consumes. The toolchain nugget is responsible for providing the actual toolchain (external or Buildroot-built); the platform’s defconfig fragment configures Buildroot to use that target (e.g. via the merged defconfig produced from platform + toolchain + system).

**Kernel (base):**

- Enable Linux kernel: `BR2_LINUX_KERNEL=y`. The system nugget sets kernel source (tarball URL or defconfig), version, and custom config/DTS path.
- Enable device tree: `BR2_LINUX_KERNEL_DTS_SUPPORT=y`.
- Kernel compression: e.g. `BR2_LINUX_KERNEL_XZ=y` (or the compression method required by the board).
- If the kernel build requires host OpenSSL: `BR2_LINUX_KERNEL_NEEDS_HOST_OPENSSL=y`.
- **Platform kernel fragment (SoC-only):** The platform contributes a kernel config fragment that enables **everything related to the CPU/SoC**—i.e. integrated blocks only. If the CPU has integrated I2C, SPI, GPIO, UART, MMC, USB, RTC, thermal, watchdog, PWM, DMA, or NVMEM/OCOTP, those drivers belong in the platform fragment. For i.MX6UL/ULL this includes: `CONFIG_ARCH_MXC=y`, `CONFIG_SOC_IMX6UL=y`, `CONFIG_ARM_IMX6Q_CPUFREQ=y`, `CONFIG_IMX_WEIM=y`, `CONFIG_SERIAL_IMX=y`, `CONFIG_I2C_IMX=y`, `CONFIG_SPI_IMX=y`, `CONFIG_GPIO_MXC=y`, `CONFIG_MMC_SDHCI_ESDHC_IMX=y`, `CONFIG_IMX_THERMAL=y`, `CONFIG_IMX2_WDT=y`, `CONFIG_REGULATOR_ANATOP=y`, `CONFIG_USB_CHIPIDEA`, `CONFIG_USB_MXS_PHY`, `CONFIG_RTC_DRV_MXC` / `CONFIG_RTC_DRV_SNVS`, `CONFIG_FSL_EDMA`, `CONFIG_IMX_SDMA`, `CONFIG_MXS_DMA`, `CONFIG_PWM_FSL_FTM`, `CONFIG_NVMEM_IMX_OCOTP`, `CONFIG_POWER_RESET_SYSCON`, and similar SoC-integrated options. The fragment is added via the cumulative key `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`. **Board-level** features—peripherals that are not part of the SoC (Ethernet PHY, WiFi module, off-chip EEPROM, board-specific GPIO LEDs, etc.)—belong in the **system** nugget’s kernel fragment. The system also sets `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` to the board device tree.

**SoC-specific packages:**

- **Freescale i.MX support:** `BR2_PACKAGE_FREESCALE_IMX=y` and, for the chosen flavor, the matching platform option (e.g. `BR2_PACKAGE_FREESCALE_IMX_PLATFORM_IMX6UL=y` for both imx6ul and imx6ull).
- **NXP i.MX firmware:** `BR2_PACKAGE_FIRMWARE_IMX=y` (VPU and other firmware blobs as needed).
- **Device tree utilities:** `BR2_PACKAGE_DT_UTILS=y` (for device tree tools on target or host if needed).
- **Dynamic device creation:** `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y` is commonly used for i.MX6-based rootfs; the platform or common base can set it.

**U-Boot (optional):**

- The bootloader is **split between platform and system**, consistent with [§6.4 platform](#64-platform) and [§6.5 system](#65-system). The **platform** enables building a bootloader for the SoC: it may enable `BR2_TARGET_UBOOT` and set **SoC-specific** Buildroot options (e.g. SoC/family so that U-Boot is built for i.MX6). The **system** is the source of truth for *which* bootloader config: it sets the board defconfig (e.g. `BR2_TARGET_UBOOT_BOARD_DEFCONFIG`), any board-specific patches, and U-Boot environment. If the bootflow does not use a separate bootloader (e.g. plain bootflow with kernel in rootfs), the system need not enable U-Boot in Buildroot.

**Embed:**

- SoC-level device tree blobs (if any generic ones are needed), SPL/U-Boot binary only if the platform ships pre-built bootloader; otherwise the system or builder provides them. Host tools required by the bootflow (e.g. device tree compiler, `mkimage`) are provided by Buildroot packages or the platform embed as needed.

**Exports:**

- **`platform_id`** — SoC/family name (e.g. `imx6ul`, `imx6ull`) for bootflows and config. Optional **`device_tree`** path (default DTS per flavor) if the platform provides one; the system overrides with the board DTS.

### 7.7 platform_imx8

**Category:** `platform` (exactly one per build)

**Purpose:** Provides NXP i.MX8 SoC-family support: ARM64 architecture, Buildroot configuration for the SoC, kernel base configuration (SoC-integrated drivers only), optional U-Boot and ATF support, and **config values** that the bootflow and other nuggets consume to assemble the boot image and package firmware. The **bootflow** is responsible for the assembly recipe and uses Buildroot outputs plus platform and system config. The platform does not define which board, which device tree, or which kernel/U-Boot source—those are the **system** responsibility (see [§6.5 system](#65-system)).

**Provides:** `nxp_imx8`, `arm64`.

**Flavors:** `imx8mm`, `imx8mp` (SoC qualifier). The flavor selects the exact SoC (e.g. Cortex-A53 for i.MX8MM/i.MX8MP; ATF platform name `imx8mm` or `imx8mp`).

**Config keys (platform-level):**

| Key | Purpose |
|-----|---------|
| Architecture / CPU | SoC family and CPU core (e.g. `imx8mm`, `imx8mp`, Cortex-A53) for toolchain and bootflows. |
| Device tree (default) | Optional default DTS path per flavor; the system overrides with the board DTS. |
| Kernel base fragment | Path to Linux kernel fragment for SoC-only options (see below). |
| Boot layout | Values consumed by the bootflow: `boot_scheme`, `kernel_image_format`, `image_layout_format`, `bootloader_seek`, `spl_load_addr`, `uboot_load_addr`, `fit_load_addr`, `uboot_container_offset`, `fit_external_offset`, `fit_container_offset`, `atf_load_addr`, etc. (see [§6.4 platform – Exports](#64-platform)). |

**Defconfig fragment (Buildroot):**

The platform sets SoC-level Buildroot options. The system nugget’s fragment is merged after and adds board-specific options (kernel source, DTS name, U-Boot board defconfig, ATF variables, rootfs overlay, etc.).

**Architecture and toolchain:**

- **Target architecture:** The platform sets all architecture-related options so that (1) the **toolchain nugget** can build (or select) the appropriate toolchain, and (2) Buildroot is configured for the platform. For i.MX8MM/i.MX8MP: `BR2_aarch64=y`, `BR2_cortex_a53=y`, `BR2_ARM_FPU_VFPV3=y`. The platform does not build or configure the toolchain directly.
- **Toolchain:** The toolchain nugget provides the actual toolchain (e.g. prefix `aarch64-unknown-linux-gnu` or `aarch64-buildroot-linux-gnu`); the platform only sets the architecture config the toolchain nugget consumes.

**Kernel (base):**

- Enable Linux kernel: `BR2_LINUX_KERNEL=y`. The system sets kernel source (git or tarball), version, custom config path, and device tree name (`BR2_LINUX_KERNEL_INTREE_DTS_NAME` or `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH`).
- Enable device tree: `BR2_LINUX_KERNEL_DTS_SUPPORT=y`.
- Kernel compression: e.g. `BR2_LINUX_KERNEL_XZ=y`. If the kernel build requires host OpenSSL: `BR2_LINUX_KERNEL_NEEDS_HOST_OPENSSL=y`.
- **Platform kernel fragment (SoC-only):** The platform contributes a kernel config fragment that enables everything related to the CPU/SoC (integrated blocks only). For i.MX8 this includes ARM64, `ARCH_MXC` or the appropriate i.MX8 SoC option, serial, I2C, SPI, GPIO, MMC, USB, thermal, watchdog, and other SoC-integrated drivers. Board-level drivers (Ethernet PHY, WiFi, etc.) belong in the **system** nugget’s kernel fragment.

**SoC-specific packages:**

- **Freescale i.MX:** `BR2_PACKAGE_FREESCALE_IMX=y` and the matching platform option per flavor (e.g. `BR2_PACKAGE_FREESCALE_IMX_PLATFORM_IMX8MM=y`, `BR2_PACKAGE_FREESCALE_IMX_PLATFORM_IMX8MP=y`).
- **NXP i.MX firmware:** `BR2_PACKAGE_FIRMWARE_IMX=y`.
- **Host tools for boot assembly:** `BR2_PACKAGE_HOST_IMX_MKIMAGE=y`, `BR2_PACKAGE_HOST_UBOOT_TOOLS=y`, `BR2_PACKAGE_HOST_UBOOT_TOOLS_FIT_SUPPORT=y` (and optionally FIT signature support). These provide `mkimage`, `mkimage_imx8`, and FIT tooling; the **bootflow** uses them when implementing its recipe. The platform does not ship scripts—it enables the packages that produce the tools.
- **Dynamic device creation:** `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y` (platform or common base).
- Optional: `BR2_PACKAGE_IMX_GPU_VIV=y` for i.MX8MM when GPU support is desired.

**ATF (ARM Trusted Firmware):**

- For i.MX8 the platform enables `BR2_TARGET_ARM_TRUSTED_FIRMWARE=y` and sets the SoC platform (e.g. `BR2_TARGET_ARM_TRUSTED_FIRMWARE_PLATFORM="imx8mm"` or `"imx8mp"`). The system may set version and additional variables (e.g. `IMX_BOOT_UART_BASE`).

**U-Boot (split between platform and system):**

- **Platform:** Enables `BR2_TARGET_UBOOT=y` and SoC-specific U-Boot options: `BR2_TARGET_UBOOT_NEEDS_ATF_BL31=y`, `BR2_TARGET_UBOOT_NEEDS_IMX_FIRMWARE=y`, `BR2_TARGET_UBOOT_SPL=y`, and build dependencies (DTC, OpenSSL, etc.). May set default format options generic for i.MX8.
- **System:** Sets board defconfig (`BR2_TARGET_UBOOT_BOARD_DEFCONFIG`), U-Boot source/version, `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE`, `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES`, and `BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME` when board-specific.

**Exports (value-only; no scripts):**

The platform exports **config values** that the bootflow and packaging nuggets consume (see [§6.4 platform – Exports](#64-platform)). No `fun_` callable scripts are exported. Typical value exports:

- **`platform_id`** — SoC name (e.g. `imx8mm`, `imx8mp`).
- **`target_arch_triplet`** — Cross-compiler prefix (e.g. `aarch64-unknown-linux-gnu` or `aarch64-buildroot-linux-gnu`).
- **Boot layout:** `spl_load_addr`, `uboot_load_addr`, `fit_load_addr`, `uboot_container_offset`, `fit_external_offset`, `fit_container_offset`, `atf_load_addr`, `bootloader_seek`, etc., so the bootflow can assemble the boot image and fwup/genimage can use correct offsets.

The **bootflow** (e.g. `bootflow_imx8_fit_plain`) implements the assembly recipe: it builds the U-Boot FIT, kernel FIT, boot container, and final boot image using Buildroot outputs (from the SDK) and these config values. It may use host tools provided by Buildroot packages (`mkimage`, `mkimage_imx8`, `genimage`) enabled by the platform and system.

**Embed:**

- SoC-level device tree blobs if any; host tools are provided by Buildroot packages (host-imx-mkimage, host-uboot-tools) enabled in the defconfig, not by embedding scripts in the platform nugget.

### 7.8 system_grisp2

**Category:** `system` (exactly one per build)

**Purpose:** Defines the board integration for a product based on i.MX6ULL with a plain bootflow: kernel and device tree are part of the SDK rootfs (no separate U-Boot build in the SDK for this board). Storage layout is MBR-based with a boot partition (FAT) holding the kernel image, rootfs A/B (squashfs), and an application partition (f2fs). U-Boot environment resides at fixed offsets on storage. The system provides the board device tree, kernel source and board-specific kernel config, rootfs overlay, and firmware packaging configuration so that the bootflow and feature_fwup can produce an equivalent firmware image.

**Dependencies:** Depends on `platform_imx6` (with flavor `imx6ull`), `common_base`, and `bootflow_grisp2_plain`.

**Config keys:**

| Key | Purpose |
|-----|---------|
| `device_tree` | Path to the board device tree source (or built DTB name). Consumed by Buildroot kernel build and by the bootflow/packaging for layout metadata. |
| `fwup_config` | Path to the fwup.conf template. Overrides the default in feature_fwup; defines partition layout (boot, rootfs A/B, application), offsets, and metadata (product name, platform id, architecture). |
| SquashFS priorities | Path/weight pairs for merging overlay onto base rootfs (e.g. boot image, device tree, init config). Consumed by feature_squashfs and bootflow. |
| Kernel/partition metadata | Paths or identifiers for the kernel and partitions in the fwup layout, for update packages and fwup template variables. |

**Defconfig fragment (board-specific):**

The platform supplies SoC-level options (architecture, FREESCALE_IMX, kernel base, etc.). The system fragment adds only board-level options:

- **Rootfs:** Append this nugget’s rootfs overlay path and post-build script to the cumulative `BR2_ROOTFS_OVERLAY` and `BR2_ROOTFS_POST_BUILD_SCRIPT`.
- **Kernel:** Set kernel source (tarball URL or equivalent), kernel patch directory (board patches), kernel custom config path (board defconfig or fragment), and custom device tree path (board DTS). Enable installing the kernel image and DTB into the target rootfs so the combined rootfs contains them for the plain bootflow.
- **Packages:** Enable any board- or product-specific packages (e.g. wireless regulatory DB, WPA supplicant, optional debug tools). Do not enable U-Boot; this board uses a plain bootflow with kernel in rootfs.

**Post-build hook:**

- Copy fwup include files (partition layout snippets or resource definitions) into the SDK images output directory so they are available when building the firmware.
- Ensure the kernel image and device tree are present in the target rootfs under a standard boot path (e.g. `/boot`) so the merged rootfs used by the bootflow and feature_fwup contains them.

**Embed:**

- Board device tree source.
- Kernel config fragment (board-specific drivers and options: Ethernet PHY, WiFi, EEPROM, or other board peripherals not in the platform SoC fragment).
- Kernel patches (e.g. board or driver fixes).
- Rootfs overlay: init configuration, U-Boot environment config for the target (device path, offsets).
- fwup.conf and fwup include files defining partition layout, metadata (product, platform, architecture), and resource blocks for the firmware packager.

---

### 7.9 system_kontron-albl-imx8mm

**Category:** `system` (exactly one per build)

**Purpose:** Defines the board integration for a product based on i.MX8M Mini with U-Boot, ATF, and a FIT-based bootflow. Storage layout is GPT-based: bootloader at a fixed offset (e.g. 33 KiB), dual U-Boot environment, then boot partition (FAT) for the kernel FIT image, rootfs A/B (squashfs), and application partition (f2fs). The system provides the board device tree, kernel and U-Boot source and board config, FIT ITS templates, U-Boot environment and config fragment, and firmware packaging configuration so that the bootflow and feature_fwup produce an equivalent firmware image.

**Dependencies:** Depends on `platform_imx8` (with flavor `imx8mm`), `common_base`, and `bootflow_imx8_fit_plain`.

**Config keys:**

| Key | Purpose |
|-----|---------|
| `device_tree` | Intree device tree name or path for the board (e.g. `freescale/imx8mm-<board>`). Used by Buildroot kernel build. |
| `fwup_config` | Path to the fwup.conf template. Defines GPT layout, bootloader and env offsets, partition sizes, and metadata. |
| `uboot_board_defconfig` | U-Boot board defconfig name. |
| `uboot_env_file` | Path to U-Boot environment source file (for envimage). |
| `uboot_config_fragment` | Path to U-Boot config fragment (e.g. env layout, boot from eMMC). |
| `kernel_its_*` | Paths to kernel FIT ITS templates (e.g. with/without initramfs) used by the bootflow to build the kernel FIT image. |
| SquashFS priorities, kernel/partition metadata | As for system_grisp2; consumed by feature_squashfs, bootflow, and feature_fwup. |

**Defconfig fragment (board-specific):**

The platform supplies SoC-level options (aarch64, ATF platform, host-imx-mkimage, host-uboot-tools, etc.). The system fragment adds:

- **Rootfs:** Append this nugget’s rootfs overlay and post-build script.
- **Kernel:** Set kernel source (git repo and version or tarball), kernel custom config path (board defconfig), and device tree name (intree or custom path). Kernel patches directory for board-specific patches.
- **U-Boot:** Set board defconfig name, U-Boot source and version, default env file path, config fragment path, and custom format/output names (e.g. flash.bin, u-boot-spl.bin, u-boot-nodtb.bin, u-boot.bin).
- **ATF:** Set version and any board-specific ATF variables (e.g. UART base for debug).
- **Console:** Set getty port (e.g. ttymxc2) for the board.
- **Host U-Boot tools:** Set envimage source (path to env file), size, and redundant env layout when building redundant env blobs for the image.
- **Packages:** Board- or product-specific packages (e.g. MTD tools for flashing, debug tools, RT tests, GPIO tools).

**Post-build hook:**

- Copy kernel FIT ITS templates into the SDK images output directory so the bootflow can use them when building the kernel FIT image during the firmware build.

**Embed:**

- Board device tree (intree name or DTS path).
- Kernel defconfig (board-specific) and kernel patches.
- U-Boot environment source file and U-Boot config fragment; U-Boot patches if any.
- Kernel FIT ITS templates (with and without initramfs).
- Rootfs overlay: U-Boot env config for the target (device path, offsets), init configuration.
- fwup.conf defining GPT layout, bootloader/env offsets, partition layout, and metadata for the firmware packager.

### 7.10 feature_erlinit

**Category:** `feature`

**Purpose:** Provides erlinit as the PID 1 init system for Erlang-based embedded systems. Erlinit replaces the default init: it mounts pseudo-filesystems and any board-configured block mounts, runs an optional early-init script (e.g. to mount a data partition and set up runtime dirs), then starts the Erlang VM and boots the release. This nugget is abstracted so that **board-specific** settings (console TTY, mount points, hostname pattern, early-init arguments) are not hardcoded here; the **system** nugget supplies a board-specific `erlinit.config` via its rootfs overlay, which overrides or extends the feature’s default. The feature provides the Buildroot package, a generic default config, the shared early-init script, and the rootfs cleanup required when erlinit is the init.

**Dependencies:** Depends on `common_base` when a minimal rootfs is needed. Typically used together with `feature_erlang` (or equivalent) so that the release path and Erlang runtime exist. May be required by packages that assume erlinit (e.g. a grisp-config–style package that configures the board at runtime).

**Config keys:**

| Key | Purpose |
|-----|---------|
| `init_system` | Set to `erlinit` so other nuggets and the build know the init system. Consumed as `ALLOY_CONFIG_INIT_SYSTEM`. |
| (optional) | Future: `erlinit_release_path`, `erlinit_console_tty`, etc., if the feature ever generates `erlinit.config` from a template; today the system provides the full file. |

**Defconfig fragment:**

- Enable the erlinit Buildroot package so that erlinit is built and installed as `/sbin/init` (replacing the default init). The package build must ensure erlinit is installed after the default init so that the final `/sbin/init` is erlinit.

**Rootfs overlay (feature-provided):**

- **`etc/erlinit.config`** — Default configuration: Erlang release path (e.g. `-r /srv/erlang`), boot mode (`--boot start`), optional nbtty helper (`-s /usr/bin/nbtty`), pre-run rngd for entropy, environment (LANG, ERL_CRASH_DUMP, etc.), tmpfs mounts for `/root` and `/var/log`, and a placeholder or generic `--pre-run-exec` for the early-init script. Board-specific options (console TTY, block mounts, hostname pattern, early-init device argument) are **not** in the feature; the system overlay provides `etc/erlinit.config` with those values and overrides this default.
- **`sbin/early-init.sh`** — Generic script run by erlinit before starting Erlang: ensures runtime dirs and permissions under `/run` and `/var`, optional bind mount for `/etc/resolv.conf`, and optional mount of a data partition (e.g. f2fs on a given block device). The script accepts an optional argument (data device path); if omitted, it can use a default or skip the data mount. The **system**’s `erlinit.config` invokes this script with the board-specific device (e.g. `--pre-run-exec "/sbin/early-init.sh /dev/rootdisk0p5"`).

**Post-build (or equivalent cleanup):**

- So that erlinit is the only init and no legacy configs conflict, the feature must ensure the target rootfs is prepared for erlinit: remove SysV init configs (`etc/init.d`, `etc/random-seed`, `etc/network`), remove the default `etc/fstab` (erlinit manages mounts via its config), and optionally remove a default `etc/wpa_supplicant.conf` if the build would otherwise leave a static one. The build must not rely on Busybox init or inittab for normal boot; any constraint (e.g. Buildroot requiring inittab for root rw/ro) is handled so that erlinit runs as PID 1.

**System nugget responsibility (board-specific erlinit):**

- The **system** nugget (e.g. system_grisp2, system_kontron-albl-imx8mm) provides its own `etc/erlinit.config` in its rootfs overlay. That file is merged after the feature overlay and overrides the feature’s default. It sets:
  - **Console TTY** — Which serial port erlinit uses for the Erlang prompt (e.g. `ttymxc0`, `ttymxc2`).
  - **Mounts** — Boot and data partition block devices and mount points (must match the board’s fwup partition layout).
  - **Early-init argument** — Device path for the data partition passed to `early-init.sh`.
  - **Hostname pattern** — e.g. `grisp-%s` or `kmx8mm-%s` for board identification.
- The feature does not reference any specific board or device name; it only provides the generic erlinit package, default config, and early-init script so that any system can supply a board-specific config and get equivalent behaviour.

### 7.11 feature_erlang

**Category:** `feature`

**Purpose:** Provides two distinct Erlang/OTP installations in the SDK:

1. **Host Erlang/OTP** (in `host/usr/lib/erlang/`) - Used to *run* build tools (rebar3, escript, manifest-tool, artefact-server) on the build machine. Embedded via the standard `{embed, [{host, Pattern}]}` mechanism. This eliminates the requirement for Erlang to be installed on the host system.
2. **Target Erlang/OTP** (in `staging/usr/lib/erlang/`) - Cross-compiled for the target architecture via Buildroot. Used as the source for the ERTS runtime and OTP applications that get *bundled into project releases* for the embedded device. This is included in the SDK as part of the full `staging/` directory copy (see [§5.10 SDK Packing Flow](#510-sdk-packing-flow)). Target Erlang is **not** installed in the firmware rootfs - it only enters the firmware as part of project OTP releases.

**Provides:** `host_erlang`.

**Exports:**

| Export Key | Value | Purpose |
|------------|-------|---------|
| `host_erlang_root` | `{computed, <<"[[ALLOY_BUILD_DIR]]/workspace/host/usr/lib/erlang">>}` | Root of the host Erlang/OTP installation. |
| `host_rebar3` | `{path, <<"host/usr/bin/rebar3">>}` | Path to rebar3 in the SDK (resolved relative to SDK root after embedding). |
| `otp_version` | e.g. `<<"26.2">>` | Erlang/OTP version built by Buildroot. |

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `erlang_version` | (from Buildroot) | Erlang/OTP version to build. Typically inherited from the Buildroot package version. |

**Defconfig fragment:** Enables both host and target Erlang/OTP Buildroot packages:
```ini
BR2_PACKAGE_HOST_ERLANG=y
BR2_PACKAGE_HOST_ERLANG_REBAR3=y
BR2_PACKAGE_ERLANG=y
```

The `BR2_PACKAGE_ERLANG=y` line enables the *target* Erlang/OTP cross-compilation. Buildroot installs the target build to `staging/usr/lib/erlang/` (not to the rootfs). This provides the target ERTS and OTP applications needed by project builds.

**Embed (host tools):** All host Erlang/OTP binaries, libraries, and the rebar3 escript:
- `host/usr/bin/erl`
- `host/usr/bin/erlc`
- `host/usr/bin/escript`
- `host/usr/bin/rebar3`
- `host/usr/lib/erlang/**` (OTP applications, ERTS runtime, include files)

These are embedded via the standard `{embed, [{host, Pattern}]}` mechanism, which also auto-resolves shared library dependencies.

**Target ERTS (via staging):** The target Erlang/OTP at `staging/usr/lib/erlang/` is included in the SDK as part of the unconditional `staging/` directory copy - it is not selectively embedded. Project build plugins reference it via the `TARGET_ERLANG` environment variable set by `env_utils.sh`.

**Integration with SDK tools:** The SDK escripts (`scripts/tools/artefact-server` and `scripts/tools/manifest-tool`) use `#!/usr/bin/env escript` as their shebang. Since `env_utils.sh` / the orchestrator prepends `host/usr/bin/` to `PATH`, the SDK's embedded `escript` is used. This eliminates the requirement for Erlang to be installed on the host system when using the SDK.

**Integration with `env_utils.sh`:** The `setup_cross_env` function reads `ALLOY_CONFIG_HOST_ERLANG_ROOT` and `ALLOY_CONFIG_OTP_VERSION` to set `HOST_ERLANG`, `ERTS_INCLUDE_DIR`, `ERL_EI_INCLUDE_DIR`, and related variables for cross-compiling NIFs. It also sets `TARGET_ERLANG` to `${SDK_DIR}/staging/usr/lib/erlang` for project plugins to use when bundling the target runtime into OTP releases.

### 7.12 feature_elixir

**Category:** `feature`

**Purpose:** Provides the host Elixir installation in the SDK, enabling building Elixir projects using the SDK's own tools (mix).

**Provides:** `host_elixir`.

**Dependencies:** `{required, nugget, feature_erlang}`.

**Exports:**

| Export Key | Value | Purpose |
|------------|-------|---------|
| `host_mix` | `{path, <<"host/usr/bin/mix">>}` | Path to mix in the SDK. |
| `elixir_version` | e.g. `<<"1.16">>` | Elixir version built by Buildroot. |

**Defconfig fragment:** Enables the host Elixir Buildroot package:
```ini
BR2_PACKAGE_HOST_ELIXIR=y
```

**Embed:** Elixir binaries and libraries on top of Erlang:
- `host/usr/bin/mix`
- `host/usr/bin/elixir`
- `host/usr/bin/iex`
- `host/usr/lib/elixir/**` (Elixir standard library)

**Integration with project plugins:** The Elixir project plugin (`scripts/plugins/project/elixir.sh`) uses `ALLOY_CONFIG_HOST_MIX` (or discovers `mix` on `PATH` via the embedded host tools) for building Elixir releases.

### 7.13 feature_squashfs

**Category:** `feature`

**Purpose:** Merges the SDK base rootfs with the firmware overlay into a combined SquashFS filesystem, applying consolidated filesystem priorities.

**Provides:** `rootfs_squashfs`.

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `squashfs_comp` | `<<"xz">>` | SquashFS compression algorithm. |
| `squashfs_block_size` | `<<"256K">>` | SquashFS block size. |
| `squashfs_output_name` | `<<"combined.squashfs">>` | Output filename (relative to `ALLOY_FIRMWARE_WORK_DIR`). |

**Embed:** `host/bin/mksquashfs`, `host/bin/unsquashfs`, `scripts/merge-squashfs`.

**Defconfig fragment:** Enables `BR2_PACKAGE_HOST_SQUASHFS`.

**Pre_firmware hook:**
1. Call the nugget's `merge-squashfs` script (located via `ALLOY_NUGGET_FEATURE_SQUASHFS_DIR`) to merge the base rootfs with the overlay into the output SquashFS. Pass `ALLOY_FIRMWARE_BASE_ROOTFS` as input, the overlay directory, priorities file, compression algorithm, and block size.
2. Write combined rootfs to `${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_SQUASHFS_OUTPUT_NAME}` (or the path defined by the nugget's config). The nugget does not export variables for other hooks; at **SDK build time** it declares a config (e.g. `ALLOY_CONFIG_ROOTFS`) with value like `${ALLOY_FIRMWARE_WORK_DIR}/rootfs.merged.squashfs`, so downstream hooks obtain the path from that config.

#### merge-squashfs script

**Location:** `nuggets/feature_squashfs/scripts/merge-squashfs`

**Purpose:** Merge an overlay directory into an existing SquashFS archive, preserving file permissions, ownership, device nodes, and special bits (setuid, setgid, sticky) from both the original archive and the overlay. Optionally apply a filesystem priority sort file. Inspired by the [Nerves project's merge-squashfs](https://github.com/nerves-project/nerves_system_br/blob/main/scripts/merge-squashfs) (Apache-2.0).

**Why this tool is needed:** `mksquashfs` only supports appending to archives, not replacing files. A naive "unsquash -> copy overlay -> mksquashfs" approach loses file permissions and ownership information because the unpacked directory tree on the build host is owned by the build user, and device nodes cannot be created without root. The pseudo file approach solves this without requiring `fakeroot`.

**Interface:**

```
merge-squashfs INPUT_SQUASHFS OUTPUT_SQUASHFS OVERLAY_DIR [OPTIONS]
  --sort FILE           Filesystem priority sort file (mksquashfs -sort format)
  --comp ALGORITHM      Compression algorithm (default: xz)
  --block-size SIZE     Block size (default: 256K)
```

**Algorithm:**

1. **Extract permissions from the input SquashFS** - Run `unsquashfs -n -ll INPUT_SQUASHFS` to obtain a detailed listing of every entry in the archive (files, directories, symlinks, device nodes) with their permissions, ownership (uid/gid), and for device nodes their major/minor numbers. Parse each line and convert it to a `mksquashfs` pseudo file entry: `path type mode uid gid [major minor]`. The pseudo file format tells `mksquashfs` to override the on-disk permissions with the specified values. This captures the original archive's permission state.

2. **Extract permissions from the overlay directory** - Walk the overlay directory with `find` + `stat` to obtain the mode of each file. Convert each entry to a pseudo file entry with uid 0 and gid 0 (overlay files are assumed to be root-owned in the target filesystem). This captures the overlay's intended permissions.

3. **Merge pseudo files with last-wins deduplication** - Concatenate the base archive pseudo entries followed by the overlay pseudo entries. Deduplicate by path, keeping the **last** occurrence. This ensures that when the overlay provides a file that also exists in the base archive, the overlay's permissions take precedence - consistent with the overlay last-wins convention used throughout the firmware build. (Note: the original merge-squashfs uses first-wins deduplication; we deliberately reverse this to match alloy's overlay semantics.)

4. **Merge file content** - Unsquash the input archive into a temporary working directory (`unsquashfs -f INPUT_SQUASHFS`). Copy the overlay directory on top (`cp -Rf OVERLAY_DIR/. workdir/squashfs-root/`). Overlay files replace base files; new files are added.

5. **Rebuild SquashFS** - Run `mksquashfs` on the merged directory tree with:
   - The consolidated pseudo file (`-pf`) to enforce correct permissions and ownership.
   - The sort/priorities file (`-sort`) if provided (the consolidated `ALLOY_FIRMWARE_FS_PRIORITIES` file, which uses `mksquashfs -sort` format directly).
   - The specified compression algorithm (`-comp`) and block size (`-b`).
   - Flags: `-noappend` (create fresh archive), `-no-recovery`, `-no-progress`.

6. **Cleanup** - Remove the temporary working directory.

**Error handling:** The script must use strict mode (`set -euo pipefail`). If any step fails (unsquashfs, mksquashfs, file operations), the script aborts immediately with a non-zero exit code. The temporary working directory is cleaned up on exit (via a trap).

### 7.14 feature_fwup

**Category:** `feature`

**Purpose:** Builds `.fw` firmware update packages using fwup. The fwup configuration is provided by the system or product nugget; this nugget provides the fwup host tool and the packaging logic.

**Provides:** `firmware_fwup`.

**Dependencies:** `{required, capability, rootfs_squashfs}` (needs a merged rootfs).

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `fwup_config` | (none - must be overridden by system/product) | Path to `fwup.conf` template. |
| `fwup_image_targets` | `<<"complete">>` | Comma-separated list of fwup targets for image generation. |
| `fwup_output_name` | `<<"firmware.fw">>` | Output filename (relative to `ALLOY_FIRMWARE_WORK_DIR`). |

**Embed:** `host/bin/fwup`.

**Defconfig fragment:** Enables `BR2_PACKAGE_HOST_FWUP`.

**Outputs:**

```erlang
{firmware_outputs, [
    {fwup_firmware, [
        {selectable, true},
        {display_name, <<"Firmware update package">>},
        {description, <<"fwup firmware update package for OTA deployment">>}
    ]}
]}.
```

**Post_firmware hook:**
1. Check `ALLOY_OUTPUT_FWUP_FIRMWARE`; if not `true`, log skip and return 0.
2. Read `ALLOY_CONFIG_FWUP_CONFIG` — path to fwup.conf (typically overridden by the system nugget).
3. Expand fwup.conf template variables from `ALLOY_FIRMWARE_*` and `ALLOY_CONFIG_*`. The rootfs path (e.g. for `ROOTFS`) is taken from `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE` when set (bootflow export). The kernel path and bootloader path are taken from bootflow exports when the bootflow builds them (e.g. `ALLOY_CONFIG_FIRMWARE_KERNEL_IMAGE`) or from config/platform exports as provided by the system nugget.
4. Run `fwup -c -f expanded.conf -o ${ALLOY_FIRMWARE_WORK_DIR}/${ALLOY_CONFIG_FWUP_OUTPUT_NAME}`.
5. Register the output: `alloy_firmware_add_output fwup_firmware "${output_path}"`.

### 7.15 feature_image

**Category:** `feature`

**Purpose:** Generates raw disk images (`.img`) from fwup packages by applying fwup targets to an empty disk image.

**Provides:** `raw_image`.

**Dependencies:** `{required, nugget, feature_fwup}`.

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `image_targets` | (inherited from `fwup_image_targets`) | Comma-separated fwup targets to apply for image generation. |
| `image_output_pattern` | `<<"firmware-[[ALLOY_PRODUCT]].img">>` | Output filename pattern for generated images. |

**Outputs:**

```erlang
{firmware_outputs, [
    {image, [
        {selectable, true},
        {display_name, <<"Raw disk image">>},
        {description, <<"Complete disk image for flashing via dd or fwup">>}
    ]}
]}.
```

**Post_firmware hook:**
1. Check `ALLOY_OUTPUT_IMAGE`; if not `true`, log skip and return 0.
2. For each target in `ALLOY_CONFIG_IMAGE_TARGETS` (comma-separated):
   - Create empty image file using the naming pattern from `ALLOY_CONFIG_IMAGE_OUTPUT_PATTERN`.
   - Run `fwup -a -d <image> -t <target> -i "$(cat ${ALLOY_FIRMWARE_WORK_DIR}/.outputs/fwup_firmware)"`.
3. Move images to the firmware output directory.
4. Register the output: `alloy_firmware_add_output image "${image_path}"`.

### 7.16 feature_grisp_updater

**Category:** `feature`

**Purpose:** Packages a software update package (`.tar` archive with a `MANIFEST` at its root) suitable for upload to the grisp.io platform. The update package bundles the firmware payload and metadata needed for OTA deployments. The payload is the **same artefacts** that the firmware packager (e.g. feature_fwup) uses—e.g. the boot image or combined rootfs from the bootflow, or the `.fw` file when feature_fwup has produced it. This nugget does **not** depend on the feature_fwup nugget; it depends on the availability of those firmware payload artefacts (from bootflow exports or from a registered fwup output when present). It uses the host Buildroot package **grisp_updater_tools** to generate the update package and may use the **security pack** to sign the update package.

**Provides:** `grisp_update_package`.

**Dependencies:** Requires the **same firmware payload artefacts** that the firmware packager consumes (e.g. `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE`, or the registered fwup_firmware output when feature_fwup has run). Does not depend on the feature_fwup nugget; product or build order may still run feature_fwup so that the payload is the `.fw` file, or the payload may be built from the bootflow exports directly.

**Defconfig fragment:** Enables the **host** Buildroot package for grisp_updater_tools (e.g. `BR2_PACKAGE_HOST_GRISP_UPDATER_TOOLS=y`), which provides the tools used in the post_firmware hook to generate the MANIFEST and the update archive.

**Config keys:**

| Key | Default | Purpose |
|-----|---------|---------|
| `grisp_update_output_name` | `<<"[[PROJECT_NAME]]-[[PROJECT_VERSION]]-[[ALLOY_PRODUCT]]-[[ALLOY_PRODUCT_VERSION]].tar">>` | Output filename pattern for the update package. |

**Outputs:**

```erlang
{firmware_outputs, [
    {grisp_update, [
        {selectable, true},
        {display_name, <<"Software update package">>},
        {description, <<"Software update package (.tar) for grisp.io OTA deployment">>}
    ]}
]}.
```

**Post_firmware hook:**
1. Check `ALLOY_OUTPUT_GRISP_UPDATE`; if not `true`, log skip and return 0.
2. Obtain the firmware payload from the same artefacts the firmware packager uses: e.g. the path registered in `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/fwup_firmware` when feature_fwup has run, or the boot image / combined rootfs path from the bootflow (e.g. `ALLOY_CONFIG_FIRMWARE_BOOT_IMAGE`) when building without the fwup package. The payload is whatever the product has chosen to ship in the update (typically the `.fw` file when feature_fwup is used).
3. Optionally sign the update package using the security pack (e.g. `alloy_security_sign` or equivalent for update-package signing), if the variant and security pack support it.
4. Generate a `MANIFEST` file containing update metadata (package name, version, platform, build date, integrity hash of the firmware payload) using the host grisp_updater_tools.
5. Create the `.tar` archive containing the `MANIFEST` and the firmware payload (and signature if applicable).
6. Copy the update package to `${ALLOY_ARTEFACT_DIR}/grisp_updates/` using the filename pattern from `ALLOY_CONFIG_GRISP_UPDATE_OUTPUT_NAME`.
7. Register the output: `alloy_firmware_add_output grisp_update "${output_path}"`.

### 7.17 grisp2_vanilla

**Category:** `feature` (used as product)

**Purpose:** Complete vanilla configuration for the GRiSP 2 board. Can be used directly as a product (`alloy build sdk grisp2_vanilla`) or as a dependency for custom products.

**Dependencies:** Depends on `system_grisp2`, `common_base`, `feature_erlinit`, `feature_erlang`, `feature_squashfs`, `feature_fwup`, `feature_image`, `feature_grisp_updater`, `toolchain_ctng`, `builder_buildroot`.

**Provides:** A complete, buildable configuration for GRiSP 2 without secure boot.

### 7.18 kontron-albl-imx8mm_vanilla

**Category:** `feature` (used as product)

**Purpose:** Complete vanilla configuration for the Kontron ALBL i.MX8MM board. Can be used directly as a product or as a dependency.

**Dependencies:** Depends on `system_kontron-albl-imx8mm`, `common_base`, `feature_erlinit`, `feature_erlang`, `feature_squashfs`, `feature_fwup`, `feature_image`, `feature_grisp_updater`, `toolchain_ctng`, `builder_buildroot`.

**Provides:** A complete, buildable configuration for Kontron ALBL i.MX8MM without secure boot.

---

## 8. Implementation Details

This section provides guidance for implementing the alloy orchestrator. It describes the project structure, general principles, and per-script responsibilities at a level sufficient for a developer to implement the complete software.

### 8.1 Project Structure

```
grisp_alloy/
├── alloy                          # Main orchestrator script (bash)
├── Vagrantfile                    # Cross-platform build VM configuration
├── nuggets/                       # Builtin nuggets
│   ├── .nuggets                   # Builtin nugget registry
│   ├── builder_buildroot/
│   ├── toolchain_ctng/
│   ├── common_base/
│   ├── bootflow_grisp2_plain/
│   ├── bootflow_imx8_fit_plain/
│   ├── platform_imx6/
│   ├── platform_imx8/
│   ├── system_grisp2/
│   ├── system_kontron-albl-imx8mm/
│   ├── feature_erlinit/
│   ├── feature_erlang/
│   ├── feature_elixir/
│   ├── feature_squashfs/
│   ├── feature_fwup/
│   ├── feature_image/
│   ├── feature_grisp_updater/
│   ├── grisp2_vanilla/
│   └── kontron-albl-imx8mm_vanilla/
├── smelterl/                     # Erlang code generator (see 02_SMELTERL_DESIGN.md)
├── scripts/
│   ├── commands/                 # Command implementations
│   │   ├── build-sdk.sh
│   │   ├── build-project.sh
│   │   ├── build-firmware.sh
│   │   ├── serve-artefacts.sh
│   │   └── grispio.sh
│   ├── utils/                    # Sourceable bash libraries
│   │   ├── common.sh
│   │   ├── console_utils.sh      # ANSI/terminal formatting + shared print helpers
│   │   ├── debug_utils.sh        # Orchestrator logging/trace internals
│   │   ├── argparse.sh
│   │   ├── vagrant_utils.sh
│   │   ├── vcs_utils.sh
│   │   ├── patch_tools.sh
│   │   ├── file_utils.sh
│   │   ├── sdk_utils.sh
│   │   ├── env_utils.sh          # Cross-compilation environment setup
│   │   ├── otp_utils.sh          # OTP release scrubbing (strip, cleanup) for project build
│   │   ├── manifest_utils.sh     # Bash wrappers around manifest-tool escript
│   │   ├── plugin_utils.sh       # Category-agnostic plugin framework
│   │   ├── security_tools.sh     # Bash API for security pack interaction (hooks)
│   │   ├── security_utils.sh     # Security pack resolution, validation, key=value parsing
│   │   └── dev_utils.sh
│   ├── buildroot/
│   │   └── script_hook.sh        # Universal hook wrapper
│   ├── tests/
│   │   ├── run_tests.sh
│   │   ├── test_common.sh
│   │   ├── test_file_utils.sh
│   │   ├── test_sdk_utils.sh
│   │   └── test_*.sh
│   ├── tools/
│   │   ├── artefact-server        # HTTP/HTTPS artefact server (Erlang escript)
│   │   ├── grispio                # grisp.io API client (Erlang escript)
│   │   └── manifest-tool          # Manifest merging/hashing tool (Erlang escript)
│   └── plugins/
│       ├── project.sh             # Project plugin API
│       └── project/
│           ├── erlang.sh          # Erlang/rebar3 project handler
│           └── elixir.sh          # Elixir/mix project handler
├── samples/                       # Reference implementations
│   ├── hello_grisp                # Sample erlang project for grisp2
│   ├── hello_elixir               # Sample Elixir project for grisp2
│   └── security_pack/             # Sample directory-based security pack (contains secpack entry point)
├── artefacts/                     # Default artefact storage
├── _cache/                        # Default cache directory
└── _build/                        # Default build directory
```

### 8.2 General Principles

- **`set -euo pipefail`** in every script - Fail on errors, undefined variables, and pipeline failures.
- **Source utilities at the top** - Every command script sources `common.sh` and any other needed utilities before doing work.
- **Quote all variables** - Use `"${VAR}"` consistently to prevent word splitting.
- **Use functions** - Break scripts into functions with clear names. Export functions (`export -f`) when they must be available to child processes.
- **Avoid global state** - Pass parameters to functions explicitly. Use local variables (`local`).
- **Use `readonly`** - Mark constants with `readonly` to prevent accidental modification.
- **Use traps for cleanup** - Register cleanup functions with `trap` for `EXIT` and `ERR`.

### 8.3 Documentation

- Each utility script (`scripts/utils/*.sh`) begins with a comment block describing its purpose and listing exported functions.
- Each function has a comment block describing its purpose, parameters, and return value.
- Command scripts (`scripts/commands/*.sh`) begin with a usage comment block.
- Each script must document the **expected environment variables** it uses (e.g. which `ALLOY_*` or other variables must be set when the script is invoked, and what they are used for).

### 8.4 Testing

- One test file per tested utility or command script (e.g. `test_common.sh` tests `common.sh`).
- Test functions are named `test_*` (bash_unit convention).
- Each test file sources the code under test and uses bash_unit assertions (`assert_equals`, `assert_status_code`, etc.).
- The `run_tests.sh` wrapper discovers and runs all `test_*.sh` files from the repository root.
- Tests are excluded from the SDK pack step.

### 8.5 Shared Variables and Data Structures

The following variables are used across multiple scripts and must be set consistently. This is a **subset** of the common orchestrator-set variables; the full list (including variables defined in the context script and hook-type–specific sets) is in [Data Design - Environment Variables and Functions](01_DATA_DESIGN.md#environment-variables-and-functions).

**Set by the orchestrator (`alloy`):**

| Variable | Description |
|----------|-------------|
| `ALLOY_ROOT` | Repository root directory (resolved from alloy script location). |
| `ALLOY_ROOT_DIR` | Root of the alloy installation (same as `ALLOY_ROOT` in repo mode; SDK root in SDK mode). Used by hook wrapper and hooks to locate `scripts/utils/hook_common.sh`. |
| `ALLOY_MODE` | Operating mode: `repo` or `sdk`. |
| `ALLOY_BUILD_DIR` | Build output directory for this run. |
| `ALLOY_ARTEFACT_DIR` | Artefact output directory. |
| `ALLOY_CACHE_DIR` | Cache directory. |
| `ALLOY_DEBUG` | Debug verbosity level (integer); non-empty when debug mode is enabled. Propagated to wrappers and hooks. |
| `ALLOY_TRACE` | Non-empty when bash execution tracing is enabled (`--trace`). Enables `set -x` in common.sh and in hook_common.sh; propagated to wrappers and hooks. |
| `ALLOY_DEV_MODE` | Non-empty when development mode is enabled (`--dev`). |

### 8.6 Shared Utilities

**Naming convention:** Files in `scripts/utils/` follow a two-tier naming convention that signals their intended audience:

- **`*_tools.sh`** - **Hook developer API.** Functions in these files form the stable public contract available to nugget hook scripts. Hook developers need only read `*_tools.sh` files to see what they can call. All functions exposed to hooks use the **`alloy_` prefix** (e.g. `alloy_log_info`, `alloy_enter_hidden`, `alloy_firmware_add_output`). This avoids name collisions with hook-defined functions and makes the API discoverable. Currently: `debug_tools.sh` (logging and trace), `path_tools.sh` (path resolution/join for hooks), `patch_tools.sh` (apply patches to source trees), `firmware_tools.sh` (firmware build API), `security_tools.sh` (security pack interaction API).
- **`*_utils.sh`** - **Orchestrator internals.** Functions used by the orchestrator's own command scripts; internal names (e.g. `log_info`, `enter_hidden`) are not part of the hook contract. Hook developers can ignore these files.

**Clear boundary:**

- **`*_tools.sh`** - Sourced **only** by hook scripts (via the single hook entry point [hook_common.sh](#860-hookcommonsh-hook-entry-point), which may source them conditionally based on `ALLOY_HOOK_TYPE`). They form the hook developer API. No function export: hooks get the API by **sourcing** the hook entry point. _tools.sh must be self-sufficient in the hook process: they have **no access** to any `*_utils.sh` (orchestrator-only). All hook-visible functions use the **`alloy_` prefix**.
- **`*_utils.sh`** - Sourced **only** by the orchestrator or by the **wrapper** (the wrapper is considered part of the orchestrator, even when invoked by Buildroot). The wrapper sources `common.sh` (which enables tracing for the wrapper when `ALLOY_TRACE=true`) and may source `*_utils.sh` as needed. Hook scripts never source _utils.sh. Internal names (e.g. `log_info`, `enter_hidden`) are not part of the hook contract.
- **Sourced-library idempotence** - Every sourced utility (`scripts/utils/*.sh`) must protect against multiple sourcing in the same process with an include guard variable and early return, so shared dependencies can be sourced directly without recursion or redefinition side effects.

**Path helpers (path_utils vs path_tools vs scripts/tools):** The script that builds or verifies the toolchain is the **pre_build hook** of the toolchain nugget (see step 8 in the SDK build flow). Hooks run with only the hook API: they source `hook_common.sh` and get `*_tools.sh`; they do **not** source `*_utils.sh`. So path helpers needed by the toolchain pre_build hook (or any other hook) must be exposed as **`path_tools.sh`** in `scripts/utils/` with **`alloy_`-prefixed** functions (e.g. `alloy_path_resolve`, `alloy_path_join`), and `hook_common.sh` must source it so that hooks (including the toolchain nugget's pre_build) can call them. Use **`path_utils.sh`** with internal names only for path logic used **exclusively** by orchestrator command scripts or the wrapper (e.g. path handling in the main entry point or in non-hook scripts). Do not put a path **library** in `scripts/tools/`: that directory is for **self-contained runnable tools** (escripts, binaries) invoked as commands, not for sourced bash libraries. The same principle applies to **patch** functions: they are used by the toolchain nugget's pre_build hook (and potentially other hooks) to apply patches to source trees, so they must be provided as **`patch_tools.sh`** with **`alloy_`-prefixed** functions (e.g. `alloy_apply_patches`, `alloy_reverse_patch`), sourced by `hook_common.sh` for hook types that need them (e.g. `pre_build`), not as `patch_utils.sh`.

**Hook entry point - `hook_common.sh`**

Hooks **usually** source only the **single entry point** `hook_common.sh`, parallel to `common.sh` for the orchestrator. That entry point sources the _tools.sh that are needed by many hooks (e.g. `debug_tools.sh`, `path_tools.sh`, `security_tools.sh`, `firmware_tools.sh` when applicable). **_Tools.sh that are used only by a few hooks** (e.g. `patch_tools.sh` for the toolchain nugget's pre_build) **may be sourced explicitly** by those hooks after `hook_common.sh`, so that `hook_common.sh` does not have to load them for every hook of that type. Either approach is valid: hook_common.sh can source a _tools.sh conditionally by hook type, or the hook can source the _tools.sh explicitly when it needs it.

- **Path:** `${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh`
- **Purpose:** Provide hooks with the core alloy API (logging, trace, and the _tools.sh that are widely used), and any other setup. Hooks source it at the top. If a hook needs a niche _tools.sh that is not loaded by hook_common.sh, it may source that file explicitly (e.g. `source "${ALLOY_ROOT_DIR}/scripts/utils/patch_tools.sh"`) after sourcing the entry point.
- **Contents (conceptually):** Source the _tools.sh that are needed by most hooks or by whole hook types (e.g. `debug_tools.sh` always; `path_tools.sh`, `security_tools.sh`, `firmware_tools.sh` conditionally by `ALLOY_HOOK_TYPE`). Optionally leave niche _tools.sh (e.g. `patch_tools.sh`) to be sourced explicitly by the hooks that need them. Enable `set -x` when `ALLOY_TRACE=true`; any other hook-environment setup. The wrapper must export `ALLOY_ROOT_DIR` (and `ALLOY_TRACE`, etc.) so hooks can resolve the path.

**Contract for `*_tools.sh` (hook API) - no export; hooks source hook_common.sh**

1. **Wrapper executes the hook** - The wrapper runs each hook script (e.g. `bash "${ALLOY_NUGGET_DIR}/${SCRIPT_RELATIVE_PATH}" "$@"`). The wrapper does **not** source any _tools.sh and does **not** export functions. It only sets the environment (e.g. `ALLOY_ROOT_DIR`, `ALLOY_TRACE`, per-nugget variables) and executes the hook.
2. **Hook sources the entry point** - Each hook script must **source** `hook_common.sh` at the top (e.g. `source "${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh"`). That file sources the common _tools.sh and sets up tracing. A hook that needs a _tools.sh not loaded by hook_common.sh (e.g. `patch_tools.sh`) may source it explicitly after the entry point. If the hook does not source the entry point, it cannot expect any `alloy_*` functions.
3. **No export in _tools.sh** - `*_tools.sh` files do **not** export functions. They are sourced either by `hook_common.sh` or explicitly by a hook. No `export -f` is used.
4. **_tools.sh are hook-only and self-sufficient** - Each _tools.sh is written with the knowledge that it is sourced in the **hook** process. It has **no access** to `*_utils.sh` (those are never sourced in the hook). So _tools.sh must implement everything they need inline or via other _tools.sh (already sourced by hook_common.sh or by the same hook). No dependency on orchestrator internals.

#### 8.6.0 hook_common.sh (hook entry point)

**Purpose:** Single entry point for all nugget hook scripts, parallel to `common.sh` for the orchestrator. Hooks source this file at the top of their script to obtain the full `alloy_*` API, tracing (when `ALLOY_TRACE=true`), and any other hook-environment setup. If a hook does not source it, it cannot expect any `alloy_*` functions or correct tracing.

**Location:** `${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh`

**Responsibilities:**
- Source the relevant `*_tools.sh` **conditionally** depending on `ALLOY_HOOK_TYPE` (exported by the wrapper). Not every _tools.sh is needed for every hook type. For example: `debug_tools.sh` is sourced for all hook types (logging and trace); `path_tools.sh` when the hook type commonly needs path helpers; `sdk_tools.sh` for SDK-time hooks (`pre_build`, `post_build`, `post_image`, `post_fakeroot`) to provide `alloy_sdk_add_output` and lookup helpers; `firmware_tools.sh` for firmware-time hooks (`pre_firmware`, `firmware_build`, `post_firmware`); `security_tools.sh` when the hook may need security pack services. **_Tools.sh that are used only by a few hooks** (e.g. `patch_tools.sh`, used by the toolchain nugget's pre_build) need not be sourced by hook_common.sh; those hooks may **source them explicitly** after hook_common.sh (e.g. `source "${ALLOY_ROOT_DIR}/scripts/utils/patch_tools.sh"`).
- If `ALLOY_TRACE=true`, run `set -x` so that the rest of the hook (and any commands it runs) are traced.
- Any other setup desired for every hook (e.g. `set -e` if the project standard is that hooks run with exit-on-error).

**Usage in hooks:** At the top of each hook script, before using any `alloy_*` function:
```bash
source "${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh"
```
The wrapper must export `ALLOY_ROOT_DIR`, `ALLOY_HOOK_TYPE`, `ALLOY_TRACE`, `ALLOY_DEBUG`, etc., so that the hook can resolve the path, the entry point can choose which _tools.sh to source, and tracing can be configured.

#### 8.6.1 common.sh

**Purpose:** Error handling, environment setup, temporary directory management, and process cleanup. Sourced by all orchestrator command scripts **and by the hook wrapper** (`script_hook.sh`): the wrapper is considered part of the orchestrator (even when invoked by Buildroot). `common.sh` sources `console_utils.sh` and `debug_utils.sh` as its foundational dependencies. **Tracing and debug level:** When sourced, `common.sh` applies the current `ALLOY_TRACE` and `ALLOY_DEBUG` from the environment (if set) so that wrappers invoked with those variables already set get the correct behaviour. In addition, `common.sh` **exposes functions** so that the orchestrator can set tracing and debug level **after** parsing command arguments: the command script sources `common.sh` early, parses `--trace` and `--debug[=N]`, then calls these functions to enable tracing and set the debug level. That way the same entry point handles both "env already set" (e.g. Buildroot wrapper) and "set from CLI" (orchestrator command script). Hook scripts do **not** source `common.sh`; they source [hook_common.sh](#860-hookcommonsh-hook-entry-point) to get the `alloy_*` API and tracing for the hook process.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `die [EXIT_CODE] MESSAGE` | Print error to stderr and exit (default exit code 1). May be provided by common.sh or by debug_utils.sh and re-exported. |
| `make_temp_dir [PREFIX]` | Create a temporary directory; register for cleanup on exit. |
| `cleanup` | Remove registered temporary directories (called via trap on exit). |
| `set_trace true` or `set_trace false` | Enable or disable bash `set -x` for the current process. The orchestrator calls this after argument parsing when `--trace` was passed. Also updates and exports `ALLOY_TRACE` so child processes inherit it. |
| `set_debug_level N` | Set the log verbosity level for the current process (`ALLOY_DEBUG=N`, exported). The orchestrator calls this after argument parsing when `--debug` or `-d` was passed. Ensures `log_info`, `log_debug`, etc. (from debug_utils.sh) respect the new level. |
| `print_result MESSAGE` | Emit user-facing success/result output via `console_utils.sh`. |
| `print_note MESSAGE` | Emit user-facing informational note output via `console_utils.sh`. |
| `print_hint MESSAGE` | Emit user-facing usage/help hint output via `console_utils.sh`. |
| `require_command NAME` | Verify that a required host command exists on `PATH`; return 127 if missing. |
| `require_commands NAME...` | Verify a list of required host commands; fail on the first missing command. |

**Color support:** Where common.sh or the scripts it sources produce terminal output, ANSI colors are used and automatically disabled when stdout/stderr is not a terminal or when `NO_COLOR` is set.

#### 8.6.1a1 console_utils.sh

**Purpose:** Shared console formatting/printing primitives for orchestrator-side scripts. Defines terminal-capability checks, ANSI style application, and shared user-facing print helpers. This module is sourced directly by both `common.sh` and `debug_utils.sh` so logging and printing share one formatting path without introducing a `debug_utils.sh -> common.sh` dependency.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `console_supports_color [stdout|stderr]` | Return success when ANSI colors are allowed for the selected stream (interactive terminal and `NO_COLOR` unset). |
| `console_format_text STREAM STYLE MESSAGE` | Apply style-based ANSI formatting when enabled, otherwise return plain text. |
| `console_print_to STREAM STYLE MESSAGE` | Print formatted text to stdout/stderr with newline. |
| `print_result MESSAGE` | User-facing result/success output helper. |
| `print_note MESSAGE` | User-facing informational output helper. |
| `print_hint MESSAGE` | User-facing hint/help output helper. |

#### 8.6.1a debug_utils.sh

**Purpose:** Orchestrator-internal logging and bash trace control. Defines the implementation used by the orchestrator (internal names: `log_*`, `enter_hidden`, etc.). `debug_utils.sh` sources `console_utils.sh` directly for ANSI/terminal-aware formatting and remains independent from `common.sh`. **Not** sourced by hook scripts or by `hook_common.sh`; hooks have no access to _utils.sh. See [§8.6](#86-shared-utilities) for the boundary.

**Key functions (internal names):**

| Function | Shown when | Purpose |
|----------|-----------|---------|
| `log_error MESSAGE` | `ALLOY_DEBUG >= 0` (always) | Print error message to stderr. |
| `log_warn MESSAGE` | `ALLOY_DEBUG >= 0` (always) | Print warning message to stderr. |
| `die [EXIT_CODE] MESSAGE` | Always | Print error to stderr and exit (default exit code 1). |
| `log_info MESSAGE` | `ALLOY_DEBUG >= 1` | Print informational progress message to stdout. |
| `log_debug MESSAGE` | `ALLOY_DEBUG >= 2` | Print developer debug message to stderr. |
| `enter_hidden` | - | Temporarily suppress `set -x` trace (use around sensitive operations). |
| `leave_hidden` | - | Re-enable `set -x` trace if it was active before `enter_hidden`. |

The orchestrator uses these internal names. Hook scripts never source this file; they get the `alloy_*` API by sourcing [hook_common.sh](#860-hookcommonsh-hook-entry-point).

#### 8.6.1b debug_tools.sh

**Purpose:** Hook developer API for logging and trace control. Part of the `*_tools.sh` set. Sourced by [hook_common.sh](#860-hookcommonsh-hook-entry-point), not by the wrapper; hook scripts get it by sourcing the entry point. Defines the `alloy_*` logging/trace functions; hooks must use these (and other `alloy_*` from firmware_tools.sh, security_tools.sh) and must not call any _utils.sh.

**Key functions (all `alloy_` prefixed):**

| Function | Shown when | Purpose |
|----------|-----------|---------|
| `alloy_log_error MESSAGE` | `ALLOY_DEBUG >= 0` (always) | Print error message to stderr. |
| `alloy_log_warn MESSAGE` | `ALLOY_DEBUG >= 0` (always) | Print warning message to stderr. |
| `alloy_die [EXIT_CODE] MESSAGE` | Always | Print error to stderr and exit (default exit code 1). |
| `alloy_log_info MESSAGE` | `ALLOY_DEBUG >= 1` | Print informational progress message to stdout. |
| `alloy_log_debug MESSAGE` | `ALLOY_DEBUG >= 2` | Print developer debug message to stderr. |
| `alloy_enter_hidden` | - | Temporarily suppress `set -x` trace (use around sensitive operations, e.g. crypto or credential access). |
| `alloy_leave_hidden` | - | Re-enable `set -x` trace if it was active before `alloy_enter_hidden`. |

**Implementation contract:** Sourced only by [hook_common.sh](#860-hookcommonsh-hook-entry-point) (which is sourced by the hook). **No export**: no `export -f` in this file. The _tools.sh is loaded in the hook process when the hook sources the entry point. It must be **self-sufficient** in the hook context: it has no access to `*_utils.sh` (orchestrator-only), so all behaviour must be implemented inline or via other _tools.sh already sourced by hook_common.sh.

**Sensitive operations:** Hooks that perform cryptographic operations (signing, key reading, credential handling) or that touch secrets from the environment MUST wrap those sections in `alloy_enter_hidden` / `alloy_leave_hidden` so that `set -x` does not expose keys or tokens in build logs.

#### 8.6.2 argparse.sh

**Purpose:** GNU-style argument parser for Bash 3.2+. Used by all orchestrator command scripts. It must support short and long options, combined short flags, optional and required values, repeatable (accum) options, count options (e.g. `-ddd` or `--debug=3`), and the option terminator `--`. The script lives at `scripts/argparse.sh` (or `${ALLOY_ROOT_DIR}/scripts/utils/argparse.sh` when using the SDK path convention). A developer implementing or extending this script has all required behaviour specified below; no reference to any existing codebase is needed.

**Public API**

| Function | Purpose |
|----------|---------|
| `args_init` | Reset internal state. Must be called once at the top of each script before any `args_add`. |
| `args_add SHORT LONG VAR TYPE [DEFAULTS...]` | Declare one option. `SHORT` is a single letter or empty; `LONG` is the long name without `--` or empty. `VAR` is the destination variable name. Defaults depend on `TYPE`; see option types below. |
| `args_parse "$@"` | Parse the argument list. Sets each `VAR`, sets `<VAR>_OPT` (occurrence count, 0 if the option was never seen), and populates the `POSITIONAL` array. On error, prints a message to stderr and returns non-zero. |

**Option types**

The parser must support exactly four option types. For each option, the variable `<VAR>_OPT` is set to the number of times that option was seen (0 if absent).

| Type | Description | Default args for `args_add` |
|------|-------------|----------------------------|
| `flag` | Boolean/fixed-value switch. When the option is present, `VAR` is set to `SET_VAL`; when absent, to `DEF_VAL`. Long form with `=VALUE` is invalid and must be rejected with an error. | `SET_VAL DEF_VAL` |
| `value` | Option that takes a value. Accepted forms: `-o VAL`, `-oVAL`, `--opt VAL`, `--opt=VAL`. If the option is not provided, `VAR` is set to the default. | `DEFAULT` |
| `accum` | Repeatable option; each occurrence appends its value to the bash array `VAR`. No default args. | *(none)* |
| `count` | Integer that can be incremented by bare occurrences or set directly. Bare: `-d` or `--debug` (no value) adds 1 to `VAR`. Direct: `-dN` or `--debug=N` sets `VAR` to N (non-negative integer only). Multiple bare occurrences are cumulative (e.g. `-dd` -> VAR increases by 2). If the option is never seen, `VAR` is set to the default. See `Count type behaviour` below. | `[DEFAULT]` (optional; if omitted, default is `0`) |

**General behaviour (all types)**

- **Combined short options:** A token like `-abc` is processed character by character; each character must be a registered short option. For `flag`, each character sets the variable (last wins if multiple). For `value` and `accum`, the remainder of the token (e.g. `-oVAL`) or the next argv element is the value. For `count`, see [Count type behaviour](#count-type-behaviour).
- **Terminator:** The token `--` ends option parsing; all following arguments are appended to `POSITIONAL` in order.
- **Positional arguments:** Any argument that is not an option and not the argument of an option (e.g. the `VAL` in `-o VAL`) is appended to `POSITIONAL` in order.

**Count type behaviour**

For options of type `count`, the following rules apply so that both `-ddd` (three increments) and `-d3` (set to 3) are supported unambiguously.

1. **Registration:** `args_add SHORT LONG VAR count [DEFAULT]`. If the default is omitted, it is `0`. The default is applied when the option is never seen (after parsing, if `VAR` is still unset, set it to the default).

2. **Long option parsing:** If the token contains `=` (e.g. `--debug=3`), the part after `=` is the value. It must be a non-negative integer (e.g. match `^[0-9]+$`); otherwise the parser must print a clear error to stderr and return non-zero. Set `VAR` to that integer (direct assignment; any previous increments in this parse are overwritten). If there is no `=`, treat as a bare occurrence: add 1 to `VAR` (initial 0 if unset). Do **not** consume the next argv element; the next token remains in the stream (e.g. `--debug 3` yields one increment and `3` in `POSITIONAL`).

3. **Short option parsing (combined token):** Let `rest` be the remainder of the short token after the option character (e.g. for `-d3`, after `d` the rest is `3`; for `-ddd`, after the first `d` the rest is `dd`). If `rest` is non-empty and every character in `rest` is a digit, treat the entire `rest` as the value: validate as non-negative integer, set `VAR` to it, increment `<VAR>_OPT` by 1, and advance past the whole token. Otherwise (rest empty or any non-digit), treat as a bare occurrence: add 1 to `VAR`, increment `<VAR>_OPT` by 1, and advance by one character so that the next character (e.g. another `d` in `-dd`) is processed in the next iteration. Result: `-d3` sets VAR=3; `-ddd` adds 1 three times; `-vd3` processes `v` (flag), then `d` with rest `3` -> VAR=3.

4. **Assignment helper:** The internal helper that applies a value to an option (e.g. `_args_assign_value`) must support `count` with a second argument: empty string means bare occurrence (read current `VAR` or 0, add 1, write back); non-empty string means direct value (validate as non-negative integer, set `VAR` to it). In both cases, increment `<VAR>_OPT` by 1.

5. **Edge cases:** `--debug=0` is valid (VAR=0, `<VAR>_OPT=1`). `--debug=abc` or `-d3x` are invalid; the parser must emit a clear error that the value must be a non-negative integer and return non-zero. If the command line has `-d --debug=2`, the first occurrence increments (VAR=1), the second sets (VAR=2). Default application runs after the main parse loop: for `count`, if `VAR` is still unset, set it to the declared default.

**Count type: required mapping**

| Form | Effect on VAR | Effect on \<VAR\>_OPT |
|------|----------------|------------------------|
| *(not present)* | default (e.g. 0) | 0 |
| `-d` | += 1 | 1 |
| `-dd` | += 1 twice | 2 |
| `-ddd` | += 1 three times | 3 |
| `-d3` (attached digits) | = 3 | 1 |
| `--debug` | += 1 | 1 |
| `--debug=3` | = 3 | 1 |
| `--debug 3` | += 1; `3` in POSITIONAL | 1 |

**Usage example**

Command scripts source the script, call `args_init`, declare options with `args_add`, then call `args_parse "$@"`. After a successful parse, option variables and `POSITIONAL` are set. The orchestrator uses the `count` type for debug level (e.g. `args_add d debug ARG_DEBUG count 0`) so that `-d`, `-ddd`, `--debug=3`, and `-d3` all yield a usable integer level.

```bash
source "${ALLOY_ROOT_DIR}/scripts/utils/argparse.sh"
args_init
args_add t trace  ARG_TRACE   flag   true false      # --trace
args_add d debug  ARG_DEBUG   count  0               # --debug, -d, -ddd, --debug=N
args_add o output ARG_OUTPUT  value  ""              # --output VALUE
args_add p pkg    ARG_PKGS    accum                  # --pkg PKG (repeatable)

args_parse "$@" || exit 1

# After parse: ARG_TRACE, ARG_DEBUG, ARG_OUTPUT, ARG_PKGS (array), POSITIONAL (array),
# and ARG_TRACE_OPT, ARG_DEBUG_OPT, ARG_OUTPUT_OPT, ARG_PKGS_OPT (occurrence counts).
```

#### 8.6.3 vagrant_utils.sh

**Purpose:** VM lifecycle management and cross-platform build support.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `vagrant_start` | Start VM if not running; provision if needed. |
| `vagrant_stop` | Stop VM (halt). |
| `vagrant_status` | Check VM running state. |
| `vagrant_sync_path HOST_PATH VM_PATH` | Rsync a host directory to a VM path over SSH. Must use `--delete` so that files deleted on the host are removed in the VM. |
| `vagrant_sync_file HOST_FILE VM_PATH` | Copy a single file to a VM path over SSH. |
| `vagrant_map_path HOST_PATH TYPE` | Map a host path to a unique VM path; record in path map. |
| `vagrant_rewrite_arguments ARGS...` | Rewrite argument list replacing host paths with VM paths. |
| `vagrant_collect_forwarded_env` | Collect all `ALLOY_*` variables and user-declared forwarded variables (from `--forward-env` / `ALLOY_FORWARD_ENV`) into an associative array. Applies the blocklist to exclude system variables. |
| `vagrant_rewrite_env_paths ENV_MAP` | Rewrite path-bearing variables in the collected environment map using the path map. Only `ALLOY_SECURITY_PACK` requires rewriting (directory variables are fixed conventions, not forwarded from the host). |
| `vagrant_build_env_prefix ENV_MAP` | Build a shell-escaped `env VAR=val ...` prefix string from the collected and rewritten environment map, suitable for prepending to the in-VM command. |

**Path map:** Maintained as a bash array `VAGRANT_PATH_MAP` with entries in the format `HOST_PATH:VM_PATH:STATUS`.

#### 8.6.4 vcs_utils.sh

**Purpose:** VCS-agnostic repository operations. The orchestrator calls these functions and does not need to know VCS details (e.g. git commands).

**Key functions:**

| Function | Purpose |
|----------|---------|
| `vcs_clone_or_validate VCS_TYPE URL REF TARGET_DIR ALLOW_DIRTY` | Clone if missing; validate if existing (URL match, ref match, cleanliness) while treating dirty-check policy as an explicit caller-controlled argument. |
| `vcs_get_provenance TARGET_DIR` | Extract VCS metadata: URL, commit, describe, dirty flag. |
| `write_alloy_repo_info REPO_ROOT` | If `REPO_ROOT` is a VCS checkout (e.g. git), capture URL, commit, describe, dirty and write `.alloy_repo_info` at `REPO_ROOT` per [Data Design - Alloy repository info file](01_DATA_DESIGN.md#alloy-repository-info-file-alloy_repo_info). If not a checkout, do nothing. Used by the Vagrant flow before syncing repository content so smelterl in the VM can get provenance without `.git`. |

**Validation operations:**

1. **URL mismatch detection** - If cached repo's remote URL differs from requested, reclone.
2. **Ref/branch validation** - Verify current checkout matches requested ref; fetch and checkout if mismatched.
3. **Working tree cleanliness** - Fail if dirty unless the caller passes `ALLOW_DIRTY=true`.
4. **Dirty ref protection** - When a checkout is dirty and `ALLOW_DIRTY=true`, validation may keep the checkout only when it is already at the requested commit; it must not discard edits to force a different ref.
5. **Missing directory** - Clone fresh.

#### 8.6.5 file_utils.sh

**Purpose:** File operations, path normalization, directory merging.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `copy_with_exclusions SRC DEST EXCLUDES...` | Recursive copy excluding specified patterns. Uses `rsync`; fails clearly if `rsync` is unavailable. |
| `merge_directories SRC DEST` | Merge source into destination (later files override). |
| `normalize_path PATH` | Normalize a path (resolve `.`, `..`, remove trailing `/`). |
| `relative_path FROM TO` | Compute relative path from one location to another. |
| `make_symlink_relative LINK_FILE LINK_TARGET` | Convert a symlink to use a relative target path. |

#### 8.6.6 sdk_utils.sh

**Purpose:** SDK packing logic (embed artefacts, resolve dependencies, relocate, create tarball) and SDK relocation at first use.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `embed_file SOURCE DEST WORKSPACE_BASE SDK_BASE` | Embed a single file with symlink and dependency resolution. |
| `embed_directory SOURCE DEST WORKSPACE_BASE SDK_BASE` | Recursively embed a directory. |
| `resolve_dynamic_libraries FILE WORKSPACE_BASE SDK_BASE` | Run `ldd`, embed workspace-internal libraries recursively. |
| `verify_elf_rpaths SDK_DIR` | Phase 1: scan all ELF files across the entire SDK tree (`host/`, `images/`, `motherlode/`), verify each has only `$ORIGIN`-relative RPATHs. Fix any remaining absolute RPATHs using `patchelf --make-rpath-relative`. Does NOT use `--shrink-rpath` (would break `dlopen()`). Requires `patchelf` at build time. |
| `sanitize_text_paths SDK_DIR PREFIX_MAP` | Phase 2 (pack time): given a prefix map (source->destination pairs), scan all embedded text files for build-machine prefixes, replace each with the corresponding `@@ALLOY_SDK_DIR@@/<dest>` path, write `.alloy_relocation_manifest` (list of modified files), and write `@@ALLOY_SDK_DIR@@` to `.alloy_sdk_dir`. |
| `check_sdk_relocation SDK_DIR` | Check if the SDK needs relocation. Reads `.alloy_sdk_dir` and compares to the current SDK root path. Returns 0 if they match (no fixup needed), 1 if relocation is needed (includes freshly unpacked SDKs where the value is still the placeholder `@@ALLOY_SDK_DIR@@`). |
| `relocate_sdk SDK_DIR` | First-use fixup: read `.alloy_sdk_dir` (placeholder or stale path), replace it with the actual SDK root path in all files listed in `.alloy_relocation_manifest` via `sed -i`, then update `.alloy_sdk_dir` to the current real path. No-op if paths already match. |
| `ensure_sdk_relocated SDK_DIR` | Auto-relocation gate called by the orchestrator before any SDK operation. Calls `check_sdk_relocation`; if relocation is needed: (a) check if SDK directory is writable; (b) if writable, call `relocate_sdk` and log `"Relocating SDK to <path>..."`; (c) if not writable, abort with an error directing the user to `alloy prepare sdk` (or `sudo alloy prepare sdk` for system-wide installs). |
| `pack_sdk BUILD_DIR SDK_DIR PRODUCT VERSION` | Orchestrate the full SDK packing (steps from [§5.10](#510-sdk-packing-flow)), including ELF RPATH verification and text-path sanitization. |

**State tracking:** Uses bash associative arrays for processed files (by canonical path) and processing chain (for circular symlink detection).

**Auto-relocation flow:** The `ensure_sdk_relocated` function is called by the orchestrator before any SDK command that uses host tools (`build project`, `build firmware`, `serve artefacts`). The `alloy prepare sdk` command calls `relocate_sdk` directly (bypassing the writable check since the user explicitly requests the operation).

The flow is:

1. `check_sdk_relocation` reads `.alloy_sdk_dir` and compares to the real path of the SDK root directory. For a freshly unpacked SDK, `.alloy_sdk_dir` contains the placeholder `@@ALLOY_SDK_DIR@@`, which will never match the real path, so relocation always triggers on first use. After a successful relocation, `.alloy_sdk_dir` contains the real SDK root path, so subsequent checks are no-ops.
2. If relocation is needed, `ensure_sdk_relocated` tests write permission on the SDK directory (`[ -w "${SDK_DIR}" ]`).
3. **Writable:** Calls `relocate_sdk`, which performs `sed -i` replacements in all files listed in `.alloy_relocation_manifest` (replacing `@@ALLOY_SDK_DIR@@` or a stale path with the current SDK root path) and updates `.alloy_sdk_dir`. Logs: `"Relocating SDK to ${NEW_PATH}..."`.
4. **Not writable:** Exits with:
   ```
   Error: SDK needs relocation but the SDK directory is not writable.
   Run: sudo alloy prepare sdk
   ```

**Privacy:** The distributed SDK tarball never contains the builder's filesystem path. All text files contain paths relative to the placeholder `@@ALLOY_SDK_DIR@@`, which is replaced with the user's actual SDK root path on first use.

**Idempotency:** Both `relocate_sdk` and `ensure_sdk_relocated` are idempotent. If the paths already match, they return immediately with no side effects.

**Sourced by:** `build-sdk.sh` for packing; also sourced by the orchestrator for the `ensure_sdk_relocated` gate at SDK use time.

#### 8.6.7 env_utils.sh

**Purpose:** Cross-compilation environment setup for project builds and firmware assembly. Replaces the old `grisp-env.sh`.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `setup_cross_env SDK_DIR` | Set up the complete cross-compilation environment using SDK host tools. **Preconditions:** Caller must have already validated the SDK directory, ensured the SDK is relocated, and sourced `alloy_context.sh` (see [§5.6 Project Build Flow](#56-project-build-flow) and [§5.7 Firmware Build Flow](#57-firmware-build-flow)). |
| `validate_sdk_dir SDK_DIR` | Validate that SDK_DIR contains the expected structure (`host/`, `images/`). Used by the orchestrator before calling `setup_cross_env`. |
| `validate_release_target_arch RELEASE_DIR [OVERLAY_DIR]` | Validate that all ELF executables and shared libraries under RELEASE_DIR (and optionally OVERLAY_DIR) are for the target architecture. Follows the algorithm in [§5.6 Project Build Flow](#56-project-build-flow) step 6. Uses the cross-compiler and `readelf` already set up by `setup_cross_env`. Exits 0 if all ELF files match the target; non-zero with a clear error (file path, expected vs actual Machine) on mismatch. May be implemented in this file or in a dedicated script; see step 6 for the full specification. |

**`setup_cross_env SDK_DIR` details:**

The function **assumes** the caller (orchestrator) has already: (1) validated the SDK directory (e.g. via `validate_sdk_dir`), (2) ensured the SDK is relocated (e.g. via `ensure_sdk_relocated` from sdk_utils.sh), and (3) sourced `SDK_DIR/scripts/alloy_context.sh` so that `ALLOY_CONFIG_*` and `ALLOY_EXPORT_*` are set. It then performs only the environment setup:

1. **Derive cross-compiler prefix** - Uses the toolchain nugget's exported configuration:
   - **Primary:** Read `ALLOY_CONFIG_TARGET_ARCH_TRIPLET` (exported by `toolchain_ctng` via `exports`). This gives the exact prefix (e.g. `arm-buildroot-linux-gnueabihf`).
   - **Fallback:** Scan `SDK_DIR/host/bin/*gcc` and derive the prefix from the first match. This handles SDKs built before the triplet export was added.
2. **Set cross-compilation variables:**
   - `CC`, `CXX`, `LD`, `AR`, `AS`, `NM`, `STRIP`, `OBJCOPY`, `OBJDUMP`, `RANLIB`, `READELF` - All prefixed with the cross-compiler prefix, pointing into `SDK_DIR/host/bin/`.
   - `CROSSCOMPILE_PREFIX` - The derived prefix (e.g. `arm-buildroot-linux-gnueabihf-`).
3. **Set PATH** - Prepend `SDK_DIR/host/bin` and `SDK_DIR/host/usr/bin` to `PATH`.
4. **Set sysroot variables:**
   - `CFLAGS` - `--sysroot=SDK_DIR/host/<TRIPLET>/sysroot -I SDK_DIR/host/<TRIPLET>/sysroot/usr/include`.
   - `LDFLAGS` - `--sysroot=SDK_DIR/host/<TRIPLET>/sysroot`.
   - `PKG_CONFIG_SYSROOT_DIR` - `SDK_DIR/host/<TRIPLET>/sysroot`.
   - `PKG_CONFIG_LIBDIR` - `SDK_DIR/host/<TRIPLET>/sysroot/usr/lib/pkgconfig`.
5. **Set Erlang SDK variables** - Uses `feature_erlang` nugget exports:
   - `HOST_ERLANG` - Path to host Erlang/OTP in SDK (`ALLOY_CONFIG_HOST_ERLANG_ROOT`; exported by `feature_erlang`).
   - `HOST_REBAR3` - Path to the SDK's rebar3 (`ALLOY_CONFIG_HOST_REBAR3`; exported by `feature_erlang`).
   - `TARGET_ERLANG` - Path to target Erlang/OTP in SDK (`${SDK_DIR}/staging/usr/lib/erlang`). This is the cross-compiled target ERTS and OTP applications that project plugins bundle into OTP releases via `--include-erts` / `--system_libs`.
   - `ERL_LIBS` - Set to `${TARGET_ERLANG}/lib` (target OTP applications). Note: project plugins that run host tools (rebar3, mix) for dependency fetching must temporarily unset this variable to avoid confusing the host Erlang with target libraries - see [§8.8.3 erlang.sh](#883-erlangsh) and [§8.8.4 elixir.sh](#884-elixirsh).
   - `REBAR_PLT_DIR` - Set to `${TARGET_ERLANG}` (PLT cache directory for dialyzer).
   - `ERTS_INCLUDE_DIR`, `ERL_EI_INCLUDE_DIR`, `ERL_EI_LIBDIR` - Derived from `TARGET_ERLANG` path structure (discovered by scanning `staging/usr/lib/erlang/erts-*` and `staging/usr/lib/erlang/lib/erl_interface-*`).
   - `ERL_CFLAGS`, `ERL_LDFLAGS` - Combined cross-compilation and Erlang include/lib flags for NIF compilation against the target ERTS.
   - `REBAR_TARGET_ARCH` - Set to the cross-compiler prefix for rebar3 cross-compilation.
   - `OTP_VERSION` - Erlang/OTP version (`ALLOY_CONFIG_OTP_VERSION`; exported by `feature_erlang`).
6. **Set build-for-host variables:**
   - `CC_FOR_BUILD`, `CXX_FOR_BUILD`, `LD_FOR_BUILD`, `AR_FOR_BUILD` - Set to native system tools (so host-only build steps use the host compiler, not the cross-compiler).

**Nugget integration:** The function relies on exports from two nuggets:

1. **`toolchain_ctng`** exports `target_arch_triplet`:
```erlang
%% toolchain_ctng.nugget
{exports, [
    {target_arch_triplet, <<"arm-buildroot-linux-gnueabihf">>}
]}
```
After config consolidation, this is available as `ALLOY_CONFIG_TARGET_ARCH_TRIPLET` in `alloy_context.sh`. The `setup_cross_env` function reads this variable to determine the cross-compiler prefix without scanning the filesystem.

2. **`feature_erlang`** exports `host_erlang_root`, `host_rebar3`, and `otp_version`:
```erlang
%% feature_erlang.nugget
{exports, [
    {host_erlang_root, {computed, <<"[[ALLOY_BUILD_DIR]]/workspace/host/usr/lib/erlang">>}},
    {host_rebar3, {path, <<"host/usr/bin/rebar3">>}},
    {otp_version, <<"26.2">>}
]}
```
After config consolidation, these are available as `ALLOY_CONFIG_HOST_ERLANG_ROOT`, `ALLOY_CONFIG_HOST_REBAR3`, and `ALLOY_CONFIG_OTP_VERSION`. The function uses these to set `HOST_ERLANG`, `HOST_REBAR3`, and derive ERTS include paths.

**Sourced by:** `build-project.sh` (before project plugin dispatch and for `setup_cross_env` used by scrub and plugins), `build-firmware.sh` (for cross env used by packaging and hooks).

#### 8.6.8 otp_utils.sh

**Purpose:** OTP release scrubbing for **project builds**. Encapsulates stripping of ELF binaries and cleanup of release directories so the project artefact (and thus the rootfs overlay when the artefact is used in firmware) stays minimal. Implements the behaviour specified in [OTP release scrubbing](#otp-release-scrubbing). Used in the Project Build Flow (step 9) after the plugin writes the release and before architecture validation and packaging. There is **one release directory per project build**; the orchestrator calls `scrub_otp_release` once per project build. At firmware build time there are **multiple OTP releases** (one per project) under `srv/alloy/`, but they are already scrubbed when packed at project build time, so the firmware flow does not call the scrub.

**Location:** `scripts/utils/otp_utils.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `scrub_otp_release RELEASE_DIR` | If `RELEASE_DIR` is not an OTP release (e.g. missing `lib/` and `releases/`), return 0 without modifying the directory—non-OTP projects must not fail. Otherwise run the full scrub: strip ELF binaries with the cross-compiler `strip`, remove empty directories, remove stray files from the release root, and remove build-time-only files from `releases/` (e.g. `*.sh`, `*.bat`, `*.ps1`, `*.script`, `*gz`). Keeps files required to boot the release. Operates in-place. Returns 0 on success; on failure (e.g. invalid directory) exits non-zero. Strip failures for individual files are logged as warnings and do not abort the scrub. |

**Prerequisites:** The caller must have sourced `env_utils.sh` and called `setup_cross_env` (or otherwise set up the cross toolchain) before calling `scrub_otp_release`, so that `STRIP` and `READELF` (or `CROSSCOMPILE`-prefixed equivalents) are available. The project build command sets up the cross-compilation environment in step 7 and calls `scrub_otp_release` in step 9 on the single staging release directory.

**Implementation details:**

0. **Detect OTP release** - Before stripping or cleanup, check that `RELEASE_DIR` looks like an OTP release (e.g. contains `lib/` and `releases/` as directories). The exact heuristic is implementation-defined. If the directory is not an OTP release, return 0 immediately without changing anything; do not fail. This ensures projects that are not based on OTP (e.g. other plugin types that produce a different layout) do not fail scrubbing.

1. **ELF stripping** - For each file under `RELEASE_DIR` that is an ELF executable or shared library (e.g. detected via `file` or `readelf -h`), run the SDK's cross-compiler `strip` (e.g. `${STRIP}` or `${CROSSCOMPILE}strip`) to remove debug symbols. Skip non-ELF files (scripts, BEAM, data). If a file is read-only, make it writable (e.g. `chmod +w`) before stripping. If `strip` fails for a file, log a warning and continue; do not fail the whole scrub.
2. **Cleanup** - Remove empty directories (e.g. `find RELEASE_DIR -type d -empty -delete`). In the release root (top level of the OTP release), delete any regular files; the release root should contain only directories (`bin/`, `lib/`, `releases/`, etc.). In `releases/`, delete script and archive files not needed at runtime: e.g. `*.sh`, `*.bat`, `*.ps1`, `*.script`, `*gz`. The exact list of patterns is implementation-defined but must not remove files required to boot the release (e.g. release metadata, start.boot, start.script if used by ERTS).
3. **Exclusions (optional)** - The implementation may support excluding subtrees (e.g. a directory containing a `.noscrub` marker file) from stripping or cleanup; such directories are left unchanged.
4. **Architecture validation** - Target-architecture validation is done at project build time (Project Build Flow step 10; see `validate_release_target_arch` in [§8.6.7 env_utils.sh](#867-envutilssh)). The scrub does not perform architecture validation; that is a separate step after scrubbing.

**Sourced by:** `build-project.sh` (after the project plugin builds the release, step 9; before architecture validation and packaging). Not used by the firmware build command, which receives already-scrubbed releases in each project tarball.

#### 8.6.9 manifest_utils.sh

**Purpose:** Bash convenience wrappers around `scripts/tools/manifest-tool` for manifest operations. All Erlang term parsing, generation, and integrity hashing is delegated to the manifest-tool escript - no Erlang term construction in bash.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `write_project_manifest DEST_PATH` | Create `ALLOY_PROJECT_MANIFEST` via `manifest-tool create-project`. |
| `read_manifest_field MANIFEST_PATH FIELD` | Read a single field from any manifest via `manifest-tool get`. |
| `verify_manifest_integrity MANIFEST_PATH` | Quick integrity check via `manifest-tool verify --integrity-only`. |
| `merge_firmware_manifest SDK_MANIFEST PROJECT_MANIFESTS_GLOB OUTPUT [FIRMWARE_INFO...]` | Merge SDK + projects into firmware manifest via `manifest-tool merge`. Firmware-info includes variant, security pack identity (opaque key=value pairs from `secpack info`), project roots (`project_root_<id>=<path>`), and build parameters. |

**`write_project_manifest` details:**

Collects project metadata from environment variables set by the project plugin (`PROJECT_NAME`, `PROJECT_VERSION`, `APP_NAME`, `APP_VERSION`, `PROJECT_TYPE`, `PROJECT_PROFILE`) and SDK context from `alloy_context.sh` (`ALLOY_PRODUCT`, `ALLOY_PRODUCT_VERSION`, `ALLOY_CONFIG_TARGET_ARCH_TRIPLET`). The `PROJECT_NAME` and `PROJECT_VERSION` are the OTP release name and version; `APP_NAME` and `APP_VERSION` are the main OTP application name and version (see [Data Design - Project Manifest](01_DATA_DESIGN.md#project-manifest-specification)). Captures VCS information from the project source directory (URL, commit, `git describe`, dirty flag). For each dependency, checks for `_checkouts/` overrides (see step 6 of the [project build flow](#56-project-build-flow)): checkout dependencies are flagged with `checkout=true` and their actual VCS state is recorded. Assembles all collected metadata into `--field`, `--repository`, and `--dependency` arguments and invokes `manifest-tool create-project --output DEST_PATH`. The manifest-tool handles Erlang term construction, field validation, and integrity hash generation.

**`read_manifest_field` details:**

Thin wrapper: `manifest-tool get --manifest "$1" --field "$2"`. Used by artefact resolution to read `target_arch` from project manifests, and by build scripts to read SDK metadata.

**`verify_manifest_integrity` details:**

Thin wrapper: `manifest-tool verify --manifest "$1" --integrity-only`. Returns exit code 0 if integrity matches, 1 if mismatched. Used before consuming artefacts (e.g. artefact resolution, merge inputs).

**`merge_firmware_manifest` details:**

Assembles the `manifest-tool merge` invocation with `--sdk-manifest`, `--project-manifests`, `--firmware-info`, and `--output` arguments. Security pack identity metadata is passed as `--firmware-info security_pack_<key>=<value>` pairs, where the keys and values are exactly as reported by `secpack info` (opaque - the orchestrator does not interpret them). Build-time parameters from `--param` are passed as `--firmware-info param_<key>:<type>=<value>` pairs (e.g. `param_serial_number:string=SN123`, `param_factory_mode:boolean=true`); the manifest-tool parses the type tag, converts the value accordingly (binary for `string`, integer for `integer`, atom for `boolean`), and collects them into the `{parameters, [...]}` section. The manifest-tool handles input integrity verification, version validation, repository consolidation, and output integrity hash generation.

**Sourced by:** `build-project.sh`, `build-firmware.sh`.

#### 8.6.10 patch_tools.sh

**Purpose:** Apply patches from a directory to a source tree with deterministic order, optional `series` file, and support for compressed patch files. This is a `*_tools.sh` file — part of the hook developer API. Used by nugget pre_build hooks (e.g. toolchain_ctng) to patch upstream source before building. Sourced by [hook_common.sh](#860-hookcommonsh-hook-entry-point) for hook types that need patch operations (e.g. `pre_build`). **No export**; hooks get this API by sourcing the entry point. Must be self-sufficient in the hook context (no access to _utils.sh). A developer implementing this must provide the behaviour described below so that callers such as the toolchain pre_build hook can rely on it (the current grisp_alloy implementation uses `scripts/apply-patches.sh`; `patch_tools.sh` should offer the same contract as sourced `alloy_*` functions).

**Location:** `scripts/utils/patch_tools.sh`

**Key functions (hook API — all use `alloy_` prefix):**

| Function | Purpose |
|----------|---------|
| `alloy_apply_patches PATCH_DIR TARGET_DIR [PATTERN]` | Apply all patches from PATCH_DIR to TARGET_DIR. Optional PATTERN (default `*`) limits which patch files are considered when not using a `series` file. Fails the build (exit non-zero) if any patch does not apply cleanly. See implementation details below. |
| `alloy_reverse_patch PATCH_FILE TARGET_DIR` | Reverse a previously applied patch (optional; for development or cleanup). |

**Implementation details for `alloy_apply_patches`:**

A developer must implement the following so that behaviour matches the current grisp_alloy toolchain flow (which applies patches to Crosstool-NG and other source trees). The function is invoked as `alloy_apply_patches PATCH_DIR TARGET_DIR` or `alloy_apply_patches PATCH_DIR TARGET_DIR PATTERN`.

1. **Validation** — Verify that PATCH_DIR and TARGET_DIR exist and are directories. If not, exit with a clear error (e.g. abort with a message that the directory is missing or not a directory).

2. **Deterministic ordering** — Use a fixed locale for sorting (e.g. `LC_COLLATE=C`) when listing files so that patch order is reproducible across hosts.

3. **Clean state before patching** — Remove any existing reject files in TARGET_DIR before applying patches: delete files matching `*.rej` and `.*.rej` under TARGET_DIR. This avoids false failures from leftover rejects from a previous run.

4. **Discovery: `series` file vs directory scan** — Scan PATCH_DIR recursively.
   - **If a file named `series` exists in a directory:** Treat it as the ordered list of patches for that directory. Read lines from `series`; skip empty lines, lines starting with `#`, and lines whose first field starts with `-`. The first whitespace-separated field of each remaining line is the patch file name (a second field may specify `-pN`; the implementation may support it or assume `-p1`). Apply only the patches listed in `series`, in the order they appear. Do not apply patches that are in the directory but not listed in `series`.
   - **If no `series` file:** List entries in the directory matching PATTERN (default `*`). For each entry: if it is a subdirectory, recurse into it; if it is an archive (e.g. filename matches `*.tar*`, `*.tbz2`, `*.tgz`), unpack it into a temporary directory (e.g. under TARGET_DIR or in a temp dir) and scan that directory recursively with pattern `*`; otherwise treat the entry as a patch file (subject to supported extensions below).

5. **Supported patch formats** — Only apply files that look like patches. Supported extensions/formats: `.patch`, `.diff` (and variants such as `.diff*`), and compressed forms (e.g. `.gz`, `.bz2`, `.bz`, `.xz`, `.zip`, `.Z`). Decompress as needed (e.g. `gunzip -dc`, `unxz -dc`, `bunzip2 -dc`, `cat` for uncompressed). Skip files that do not match these patterns (optionally log "skipping" for unknown types); do not treat them as patches.

6. **Applying each patch** — For each patch file (in the order determined above), run `patch` with options equivalent to `-p1 -E -d TARGET_DIR -t -N`: strip one path component (`-p1`), ignore empty matches (`-E`), apply in TARGET_DIR (`-d`), allow timestamps to be fuzzily matched (`-t`), ignore already-applied patches (`-N`). Pipe the decompressed patch content into `patch`. If `patch` exits non-zero, abort immediately with a clear error (e.g. "Patch failed: <patch_name>") and exit non-zero; do not continue applying further patches.

7. **Record applied patches (optional)** — Append each successfully applied patch name to a file under TARGET_DIR (e.g. `.applied_patches_list`) so that later steps or debugging can see what was applied.

8. **Reject and backup cleanup** — After all patches have been applied: if any `.rej` or `.*.rej` files exist under TARGET_DIR, abort with an error (e.g. "Reject files found") and exit non-zero. Remove backup files created by `patch` (e.g. `*.orig`, `.*.orig`) under TARGET_DIR so the tree is left clean.

**Invocation example (toolchain_ctng):** The toolchain pre_build hook applies patches to the Crosstool-NG source tree by calling `alloy_apply_patches "$PATCH_DIR" "$SOURCE_DIR"`, where PATCH_DIR is the nugget’s `patches/crosstool-ng/` directory and SOURCE_DIR is the extracted Crosstool-NG source. The patch directory may contain a `series` file for explicit order or a set of `*.patch` files (e.g. `0001-Fix-....patch`) applied in sorted order.

**Sourced by:** Hooks that need to patch source trees source this file **explicitly** after [hook_common.sh](#860-hookcommonsh-hook-entry-point) (e.g. toolchain_ctng pre_build, or other nugget pre_build hooks that apply patches).

#### 8.6.11 dev_utils.sh

**Purpose:** Development helpers for debugging and interactive work.

**Key functions:**

| Function | Purpose |
|----------|---------|
| `mount_rootfs IMAGE MOUNT_POINT` | Mount a rootfs image for inspection. |
| `umount_rootfs MOUNT_POINT` | Unmount a previously mounted rootfs. |

#### 8.6.12 security_tools.sh

**Purpose:** Bash API for **hook-called** interactions with the security pack. This is a `*_tools.sh` file - it is part of the hook developer API. **Only functions defined here and called by hooks use the `alloy_` prefix** (e.g. `alloy_security_sign`, `alloy_security_check_capability`). Functions used by the orchestrator are in [security_utils.sh](#8614-securityutilssh) and do **not** use the prefix (e.g. `security_generate_overlay`, `security_export_env`, `security_info`). All hooks that need security pack services MUST use the `alloy_*` functions from this file - never invoke the security pack executable directly. This provides a stable interface between hooks and the security pack, consistent error handling, and allows the underlying command contract to evolve without breaking hook contracts. Sourced by [hook_common.sh](#860-hookcommonsh-hook-entry-point) (which hooks source). **No export**; hooks get this API by sourcing the entry point. Must be self-sufficient in the hook context (no access to _utils.sh). See [*_tools.sh contract](#86-shared-utilities).

**Location:** `scripts/utils/security_tools.sh`

**Key functions (hook API — all use `alloy_` prefix):**

| Function | Purpose |
|----------|---------|
| `alloy_security_available` | Check if a security pack is configured. Returns 0 if `ALLOY_SECURITY_PACK` is set and points to an executable file; returns 1 otherwise. |
| `alloy_security_check_capability CAPABILITY` | Check if the pack supports a capability. Returns 0 if supported, 1 if not. |
| `alloy_security_sign PURPOSE INPUT OUTPUT [EXTRA_ARGS...]` | Sign a file. PURPOSE is one of: `boot`, `kernel`, `update`, `verity`, or custom. |
| `alloy_security_get_credential PURPOSE TYPE OUTPUT_DIR [EXTRA_ARGS...]` | Export a credential file. |
| `alloy_security_tls ROLE IDENTITY TYPE OUTPUT_FILE` | Export a TLS material file (key, cert, chain, or CA bundle) in PEM format. |

**Error handling:** Each function:
1. Checks that `ALLOY_SECURITY_PACK` is set and the executable exists. If not, fails with: `"No security pack configured. Use --security-pack or set ALLOY_SECURITY_PACK."`.
2. Invokes `"${ALLOY_SECURITY_PACK}" <command> [args...] "$@"` - extra arguments from the caller are forwarded to the security pack transparently.
3. Captures stdout and passes it through to the caller.
4. Translates exit codes into human-readable log messages:
   - Exit 0: return 0.
   - Exit 1: `log_error "Security pack error: <stderr content>"`, return 1.
   - Exit 2: `log_error "Security pack does not support '<command>' (capability not available)"`, return 2.
   - Exit 3: `log_error "Security pack cannot export sensitive material for '<command>' - material is non-exportable (e.g. HSM-backed)"`, return 3.
5. In all error cases, stderr from the security pack is captured and included in the log message for diagnostics.

**Extra argument passthrough:** All functions accept trailing arguments that are forwarded to the security pack as-is. This allows hooks to pass pack-specific key=value parameters without `security_tools.sh` needing to enumerate all possible arguments:

```bash
# In a bootflow nugget's firmware_build hook:
alloy_security_sign boot "${unsigned_image}" "${csf_blob}" \
    format=hab4-csf \
    csf_template="${csf_template}" \
    blocks="${csf_blocks}" \
    srk_index="${ALLOY_SECURITY_SRK_INDEX}"
```

**Sourced by:** `build-firmware.sh` and any hook script that needs security pack services. (The artefact-server escript interacts with the security pack directly from Erlang using the same command contract - it does not use `security_tools.sh`.)

#### 8.6.13 plugin_utils.sh

**Purpose:** Category-agnostic plugin loading and dispatch framework. Provides a uniform API for loading plugin files from a directory, checking function availability, invoking plugin functions with proper error handling, and parsing key=value output from plugins that return structured data. This utility is not specific to project plugins - it can be used for any future plugin category.

**Location:** `scripts/utils/plugin_utils.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `plugin_load CATEGORY DIR` | Load all `*.sh` plugin files from `DIR` for the given category. |
| `plugin_call CATEGORY TYPE ACTION [ARGS...]` | Invoke `<CATEGORY>_<TYPE>_<ACTION>` and return its exit code. Aborts with error if the function does not exist. |
| `plugin_read CATEGORY TYPE ACTION ARRAY_NAME [ARGS...]` | Invoke `<CATEGORY>_<TYPE>_<ACTION>`, check exit code, parse stdout key=value pairs into the named associative array. |
| `plugin_has CATEGORY TYPE ACTION` | Return 0 if `<CATEGORY>_<TYPE>_<ACTION>` is a defined function, 1 otherwise. Does not invoke the function. |

**`plugin_load CATEGORY DIR` details:**

1. Validate that `DIR` exists and is a directory. Abort with error if not.
2. Iterate all `*.sh` files in `DIR` (sorted alphabetically for deterministic load order).
3. For each file, `source` it into the current shell. This makes all functions defined in the file (following the `<CATEGORY>_<TYPE>_<ACTION>` naming convention) available for dispatch.
4. Track which types have been loaded (e.g. by recording filenames or by scanning for `<CATEGORY>_<TYPE>_detect` functions) so that detection can iterate all known types.

**`plugin_call CATEGORY TYPE ACTION [ARGS...]` details:**

1. Construct the function name: `fn="${CATEGORY}_${TYPE}_${ACTION}"`.
2. Verify the function exists (using `declare -f "$fn"` or `type -t "$fn"`). If not, abort with an error: `"Plugin ${CATEGORY}/${TYPE} does not implement '${ACTION}'"`.
3. Invoke `"$fn" "$@"` and return its exit code directly. The caller is responsible for checking the exit code.

**`plugin_read CATEGORY TYPE ACTION ARRAY_NAME [ARGS...]` details:**

1. Construct the function name: `fn="${CATEGORY}_${TYPE}_${ACTION}"`.
2. Verify the function exists. If not, abort with error.
3. Capture the function's stdout and exit code in a single invocation: `output=$("$fn" "$@"); rc=$?`.
4. If the exit code is non-zero, abort with error: `"Plugin ${CATEGORY}/${TYPE} '${ACTION}' failed (exit $rc)"`. This ensures the caller never receives partial or corrupt data from a failed plugin.
5. Parse the captured output line by line. For each line, split on the first `=` to extract key and value. Store each pair in the named associative array (passed by nameref): `array[key]=value`. Empty lines and lines without `=` are skipped.

**`plugin_has CATEGORY TYPE ACTION` details:**

1. Construct the function name: `fn="${CATEGORY}_${TYPE}_${ACTION}"`.
2. Return 0 if `declare -f "$fn"` succeeds (function is defined), 1 otherwise.
3. Does not invoke the function - purely a capability check. Used by the orchestrator to test for optional plugin functions before calling them.

**Error handling:**

- All `plugin_call` and `plugin_read` invocations for **required** functions abort the build on failure. The error message always includes the plugin category, type, action name, and exit code for easy diagnosis.
- For **optional** functions, the caller first checks `plugin_has` before calling. If the function is not defined, it is silently skipped.
- Plugin functions should write error details to stderr. The framework does not capture stderr - it is passed through to the terminal for immediate visibility.

**Sourced by:** `scripts/plugins/project.sh` (to load and dispatch project plugins), and potentially future plugin category loaders.

#### 8.6.14 security_utils.sh

**Purpose:** Security pack resolution, validation, overlay generation, and key=value output parsing. This utility is used by the **orchestrator** (not by hooks). Functions here do **not** use the `alloy_` prefix; the prefix is reserved for the hook API in [security_tools.sh](#8612-securitytoolssh).

**Location:** `scripts/utils/security_utils.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `security_resolve_pack VALUE` | Resolve, validate, and canonicalize a security pack from a user-provided value (file path or directory path). Returns the absolute path to the validated executable. |
| `security_generate_overlay OUTPUT_DIR [EXTRA_ARGS...]` | Generate security overlay into OUTPUT_DIR. Called by the orchestrator during overlay consolidation. |
| `security_info` | Get pack identity metadata. Prints key=value pairs to stdout. Used by the orchestrator (e.g. manifest, ALLOY_SECURITY_PACK_INFO_ARGS). |
| `security_export_env` | Get hook environment configuration. Prints key=value pairs to stdout. Used by the orchestrator to set up the hook environment. |
| `security_validate_kv_output COMMAND OUTPUT` | Validate key=value output from a security pack command. Checks that all keys match `[a-z][a-z0-9_]*` and values are valid. |

**`security_resolve_pack VALUE` details:**

The function accepts a path to either a file or a directory:

1. If `VALUE` is a **directory** (`-d`):
   - Check that `"${VALUE}/secpack"` exists and is executable. If not found, fail with: `"Security pack directory '${VALUE}' does not contain a 'secpack' executable at its root."`.
   - Set the resolved executable to `"${VALUE}/secpack"`.
2. If `VALUE` is a **file** (`-f`):
   - Check that `VALUE` is executable (`-x`). If not, fail with: `"Security pack is not executable: ${VALUE}"`.
   - Set the resolved executable to `VALUE`.
3. If `VALUE` is neither a file nor a directory, fail with: `"Security pack not found: ${VALUE}"`.
4. Call `"${resolved}" capabilities` and check that it exits 0 and produces non-empty output. If this fails, fail with: `"'${resolved}' does not appear to be a valid security pack (capabilities command failed)."`.
5. Convert to an absolute path: `realpath "${resolved}"`.
6. Print the absolute path to stdout.

Bare command names (without `/`) are **not** supported. The value must always be a path. This avoids host/VM architecture mismatches (a macOS binary in `$PATH` would not run inside a Linux VM) and ensures the Vagrant flow can reliably sync the pack. If the user passes a bare name without `/`, the path check at step 3 will fail with a clear message.

The caller (the orchestrator's firmware build or serve-artefacts command handler) captures the output and exports `ALLOY_SECURITY_PACK` with the resolved absolute path. Invalid or missing security packs are detected early with clear error messages, before any build work begins.

**`security_validate_kv_output COMMAND OUTPUT` details:**

1. Parse `OUTPUT` line by line. For each non-empty line:
   - Split on the first `=`. If no `=` is found, skip the line.
   - Validate the key against the regex `^[a-z][a-z0-9_]*$`. If invalid, fail with: `"Security pack error: invalid key '${key}' in '${COMMAND}' output - keys must match [a-z][a-z0-9_]*."`.
2. Return 0 if all keys are valid.

The orchestrator uses this when processing key=value output from `security_info` and `security_export_env` to enforce the key format contract.

**Sourced by:** `build-firmware.sh`, `serve-artefacts.sh`, and any script that calls `security_info` or `security_export_env`.

#### 8.6.15 firmware_tools.sh

**Purpose:** Bash API for firmware hooks (`pre_firmware`, `firmware_build`, `post_firmware`). This is a `*_tools.sh` file - it is part of the hook developer API. It provides functions for structured communication between hook scripts and the orchestrator during the firmware build phase. Hook scripts MUST use these functions rather than manipulating orchestrator state directly. Sourced by [hook_common.sh](#860-hookcommonsh-hook-entry-point) (which hooks source). **No export**; hooks get this API by sourcing the entry point. Must be self-sufficient in the hook context (no access to _utils.sh). See [*_tools.sh contract](#86-shared-utilities).

**Location:** `scripts/utils/firmware_tools.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `alloy_firmware_add_output OUTPUT_ID FILE_PATH` | Register a produced firmware artefact with the orchestrator. See [§5.9 Firmware Hook API](#59-firmware-hook-api) for full specification. |
| `alloy_firmware_has_output OUTPUT_ID` | Check whether an output was registered by earlier hooks. |
| `alloy_firmware_get_output OUTPUT_ID` | Return the registered absolute path for an output. |

**Sourced by:** [hook_common.sh](#860-hookcommonsh-hook-entry-point), which firmware hooks source at the top of their script. Not sourced by the orchestrator for the purpose of exporting; the hook loads it via the entry point.

See [§5.9 Firmware Hook API](#59-firmware-hook-api) for full function specifications, parameters, behavior, and error handling.

#### 8.6.16 firmware_utils.sh

**Purpose:** Orchestrator-internal utilities for the firmware build phase. This is a `*_utils.sh` file - it is not part of the hook developer API. It contains helper functions used by `build-firmware.sh` for work directory setup, overlay consolidation, rootfs merging, and other orchestration steps that run outside of hooks.

**Location:** `scripts/utils/firmware_utils.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `firmware_setup_work_dir WORK_DIR` | Initialize the firmware build work directory layout, including `.outputs/` subdirectory. |
| `firmware_consolidate_overlays WORK_DIR NUGGET_OVERLAYS PROJECT_OVERLAYS SECURITY_OVERLAY CLI_OVERLAYS` | Merge all overlay sources into the consolidated rootfs overlay directory. |
| `firmware_merge_rootfs WORK_DIR BASE_SQUASHFS OVERLAY_DIR FS_PRIORITIES_FILE` | Produce the combined squashfs from SDK base rootfs and consolidated overlay. |
| `firmware_verify_outputs WORK_DIR` | After all hooks have completed, iterate declared outputs and verify registration and file existence. See [§5.9 Firmware Hook API](#59-firmware-hook-api) for the verification algorithm. |

**Sourced by:** `build-firmware.sh` only. Hook scripts MUST NOT source or call functions from this file directly.

#### 8.6.17 sdk_tools.sh

**Purpose:** Bash API for SDK-time hooks (`pre_build`, `post_build`, `post_image`, `post_fakeroot`). Provides registration/lookup of `sdk_outputs` produced during SDK build, especially in auxiliary targets.

**Location:** `scripts/utils/sdk_tools.sh`

**Key functions:**

| Function | Purpose |
|----------|---------|
| `alloy_sdk_add_output OUTPUT_ID FILE_PATH` | Register a produced SDK output for the current target. |
| `alloy_sdk_has_output AUX_ID OUTPUT_ID` | Check whether an auxiliary output exists and is registered. |
| `alloy_sdk_get_output AUX_ID OUTPUT_ID` | Return the registered absolute path for an auxiliary output. |

**Registration layout contract:**
- For each target build workspace, sdk output registrations are stored in `${TARGET_WORKSPACE}/.sdk_outputs/`.
- Each registered output writes one file named `<OUTPUT_ID>` whose content is the absolute produced path.
- Orchestrator verification and propagation (`ALLOY_SDK_OUTPUT_*`) consume this registry after auxiliary builds.

**Sourced by:** `hook_common.sh` for SDK-time hooks.

### 8.7 Commands Handling

#### 8.7.1 alloy (main script)

**Purpose:** Entry point. Parse global options, detect mode, handle Vagrant, dispatch to command scripts.

**Implementation guidance:**

1. Resolve `ALLOY_ROOT` from the script's own location (handle symlinks).
2. Parse global options from `$@`. Separate them from the command verb/noun and command-specific arguments.
3. Source `scripts/utils/common.sh`.
4. Detect mode (check for `ALLOY_SDK_MANIFEST` in `ALLOY_ROOT`).
5. Set directories based on mode (fixed conventions, not overridable):
   - Repository: `ALLOY_BUILD_DIR=${ALLOY_ROOT}/_build`, `ALLOY_ARTEFACT_DIR=${ALLOY_ROOT}/artefacts`, `ALLOY_CACHE_DIR=${ALLOY_ROOT}/_cache`.
   - SDK: `ALLOY_BUILD_DIR=~/.grisp_alloy/build`, `ALLOY_ARTEFACT_DIR=~/.grisp_alloy/artefacts`, `ALLOY_CACHE_DIR=~/.grisp_alloy/cache`.
6. Export `ALLOY_MODE` (`repo` or `sdk`).
7. Extract verb and noun. Map to script path: `scripts/commands/${VERB}-${NOUN}.sh` or `scripts/commands/${VERB}.sh`.
8. Validate command availability for current mode.
9. Check Vagrant need (OS detection or `--force-vagrant`). If needed, set `VAGRANT_DOTFILE_PATH` in SDK mode (to `~/.grisp_alloy/vagrant/.vagrant`), then enter Vagrant flow.
10. Source or execute the command script with remaining arguments.

#### 8.7.2 build-sdk.sh

**Purpose:** Implement `alloy build sdk`.

**Implementation guidance:** Follow [§5.5 SDK Build Flow](#55-sdk-build-flow). The script orchestrates:
- Argument parsing (require PRODUCT_NUGGET positional argument, accept `-n`, `--include-sources`, etc.).
- Nugget staging.
- `smelterl plan`.
- Per-target `smelterl generate` + Buildroot loop (auxiliaries then main).
- Hook script symlink creation.
- Pre_build hook execution with once-per-nugget semantics across targets.
- Per-target legal-info generation and merged legal export.
- Final main-manifest generation including auxiliary metadata.
- SDK packing (via `sdk_utils.sh`).

#### 8.7.3 build-project.sh

**Purpose:** Implement `alloy build project`.

**Implementation guidance:** Follow [§5.6 Project Build Flow](#56-project-build-flow). The script:
- Resolves the SDK (SDK mode or `--sdk`).
- Resolves the project source (local or VCS).
- Sources `plugin_utils.sh` and `plugins/project.sh`, loads project plugins via `project_load_plugins`.
- Detects project type via `project_detect`.
- Sources `env_utils.sh` and calls `setup_cross_env` to set up the full cross-compilation environment.
- Creates staging directory with `release/` and `overlay/`, then dispatches the build via the project plugin API (writes into those directories).
- Calls the target-architecture validation (step 6 of [§5.6](#56-project-build-flow)) on the staging release and overlay directories-e.g. `validate_release_target_arch "${STAGING_DIR}/release" "${STAGING_DIR}/overlay"`-so that wrong-architecture binaries cause an immediate failure before manifest and tarball.
- Extracts project info and writes manifest via the project plugin API.
- Packages the artefact (tarball), then cleanup if SDK was temporary.

#### 8.7.4 build-firmware.sh

**Purpose:** Implement `alloy build firmware`.

**Implementation guidance:** Follow [§5.7 Firmware Build Flow](#57-firmware-build-flow). The script:
- In repository mode with `--sdk`: extracts SDK, delegates to SDK's alloy.
- In SDK mode: sources the **main-target** context, resolves firmware variant from `ALLOY_FIRMWARE_VARIANTS` (defaulting to `plain` or using `--variant`), unpacks projects, consolidates overlays and priorities, runs `pre_firmware` hooks, selects variant-specific `firmware_build` hook array and runs it, runs `post_firmware` hooks, generates `ALLOY_FIRMWARE_MANIFEST`, copies output.
- Does not build auxiliary targets; it consumes auxiliary artefacts already embedded in the SDK.

#### 8.7.5 prepare-sdk.sh

**Purpose:** Implement `alloy prepare sdk`.

**Implementation guidance:** Follow [§3.4 alloy prepare sdk](#34-alloy-prepare-sdk). The script:
- Validates that the current mode is SDK mode. Fails with an error if called in repository mode.
- Sources `sdk_utils.sh`.
- Calls `check_sdk_relocation "${ALLOY_ROOT}"`. If no relocation is needed, prints `"SDK is already relocated."` and exits.
- If relocation is needed, calls `relocate_sdk "${ALLOY_ROOT}"` and prints the relocation log.

#### 8.7.6 serve-artefacts.sh

**Purpose:** Implement `alloy serve artefacts`.

**Implementation guidance:** Follow [§3.5 alloy serve artefacts](#35-alloy-serve-artefacts). The script:

1. Parse options: `--port`, `--tls`, `--cert`, `--key`, `--ca-cert`, `--security-pack`, `--identity`, `--verbose`.
2. Validate option combinations:
   - `--tls` and `--security-pack` are mutually exclusive. If both are given, fail: `"--tls and --security-pack are mutually exclusive. Use one or the other."`.
   - `--cert` and `--key` are required with `--tls`. If either is missing, fail: `"--tls requires --cert and --key."`.
   - `--identity` is only valid with `--security-pack`. If given without it, fail: `"--identity is only used with --security-pack."`.
3. Invoke `scripts/tools/artefact-server` with the parsed options. The script forwards all relevant options to the escript:
   - **No TLS**: pass `--root` and `--port`.
   - **Manual TLS**: pass `--root`, `--port`, `--certfile`, `--keyfile`, and optionally `--cacertfile`.
   - **Security-pack TLS**: pass `--security-pack PATH` (and optionally `--identity IDENTITY`). Can also use the `ALLOY_SECURITY_PACK` environment variable. The escript handles security pack interaction directly using the security pack command contract (see [§4.6](#security-pack-command-contract)).
4. The escript is self-contained and requires no system Erlang (uses the SDK's embedded `escript`).

#### 8.7.8 Scripts Tools

**`scripts/tools/artefact-server`** - Erlang escript that starts an HTTP/HTTPS server serving files from the artefact directory. Used by `alloy serve artefacts` via `serve-artefacts.sh`. Runs on the host Erlang/OTP embedded by `feature_erlang` - no system Erlang installation required.

**Command-line interface:**

```
artefact-server [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-p, --port PORT` | HTTP(S) listen port. Default: `8080` (HTTP) or `8443` (HTTPS). |
| `-r, --root DIR` | Root directory to serve. Default: `./artefacts`. |
| `--certfile FILE` | TLS server certificate file (PEM). Enables HTTPS. |
| `--keyfile FILE` | TLS server private key file (PEM). Required with `--certfile`. |
| `--cacertfile FILE` | CA certificate bundle for client verification (PEM). Enables mTLS (mutual TLS) - clients must present a certificate signed by a CA in this bundle. Optional; when omitted, one-way TLS is used. |
| `--security-pack PATH` | Path to the security pack - either an executable file or a directory containing a `secpack` executable at its root. The escript resolves and validates the pack, then invokes it directly to obtain TLS materials. Mutually exclusive with `--certfile`/`--keyfile`. Can also be specified via the `ALLOY_SECURITY_PACK` environment variable (`--security-pack` overrides it). |
| `--identity IDENTITY` | Server identity name when using `--security-pack` (optional; defaults to `artefact-server`). Passed as `--identity` to the pack's `tls` command. |
| `-v, --verbose` | Log each request as `METHOD STATUS PATH`. |

**Behaviour:**
- If none of `--certfile`, `--keyfile`, or `--security-pack` is given, the server runs plain HTTP.
- If `--certfile` and `--keyfile` are given, the server runs HTTPS. Default port changes to `8443`.
- If `--cacertfile` is also given, mutual TLS is enabled: `verify_peer`, `fail_if_no_peer_cert`, `depth=3`. TLS versions restricted to TLS 1.2 and 1.3.
- If `--security-pack` is given (or `ALLOY_SECURITY_PACK` is set), the escript resolves and validates the security pack (equivalent to the `security_resolve_pack` logic in [§8.6.14](#8614-securityutilssh)), then invokes it directly using the security pack command contract (see [§4.6](#security-pack-command-contract)):
  1. Calls `secpack capabilities` to check `tls` support. Fails with a clear message if not supported.
  2. Calls `secpack tls --role server --identity IDENTITY --type key --output TMPDIR/server.key.pem` and `secpack tls --role server --identity IDENTITY --type chain --output TMPDIR/server.chain.pem` to obtain the server key and certificate. Fails with a clear message if exit code 3 (key not exportable).
  3. Attempts `secpack tls --role ca --identity device --type ca --output TMPDIR/device-ca.pem`. If supported, enables mTLS automatically. If not supported (exit 2), proceeds with one-way TLS.
  4. Default port changes to `8443`.
- Serves files from the root directory. If a URL path matches `<name>/<path>` and `<name>.tar` exists in the root, the server serves the file from inside the tarball without extracting to disk.
- Directory listing is plain text (one entry per line).
- Symlink traversal is rejected (404) for security.
- The escript is self-contained and has no dependencies beyond Erlang/OTP stdlib and ssl.

**`scripts/tools/grispio`** - Erlang escript that implements the grisp.io API client for software update package management and device operations. Used by `alloy grispio` via `grispio.sh`. Runs on the host Erlang/OTP embedded by `feature_erlang` - no system Erlang installation required.

**Command-line interface:**

```
grispio ACTION [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--host HOST` | grisp.io host (e.g. `app.grisp.io:443`). Required - always provided by the calling script. |
| `--token-file FILE` | Path to the encrypted API token file. Required for all actions except `authenticate`. |
| `--no-tls-verify` | Disable TLS certificate verification. |
| `--package-path PATH` | Absolute path to the local update package `.tar` file (for `upload`). Resolved by the orchestrator script. |
| `--package-ref REF` | Package reference identifier on grisp.io (for `delete`, `deploy`). |
| `--device DEVICE` | Target device identifier (for `deploy`, `validate`, `reboot`). |

**Actions:**

| Action | Required Options | Description |
|--------|-----------------|-------------|
| `authenticate` | `--host` | Prompt for credentials, obtain API token, encrypt and store at `--token-file` path. |
| `upload` | `--host`, `--token-file`, `--package-path` | Upload the software update package at the given absolute path to grisp.io. The file must be a `.tar` archive containing a `MANIFEST` at its root. |
| `delete` | `--host`, `--token-file`, `--package-ref` | Delete a software update package from grisp.io by reference. |
| `deploy` | `--host`, `--token-file`, `--package-ref`, `--device` | Deploy a software update package to a device or device group. |
| `validate` | `--host`, `--token-file`, `--device` | Validate the deployed software update on a device. |
| `reboot` | `--host`, `--token-file`, `--device` | Reboot a device. |

**Behaviour:**
- The escript handles all grisp.io HTTP(S) API communication using Erlang/OTP `httpc` (inets) or `ssl`.
- Authentication uses the grisp.io API to obtain a token, which is encrypted with AES-256-CBC (PBKDF2 key derivation from a user-provided passphrase) and written to the `--token-file` path.
- For upload, the escript reads the update package from the `--package-path` absolute path. It never performs prefix matching or artefact resolution - that responsibility belongs to the `grispio.sh` orchestrator script. The package name sent to the grisp.io API is derived from the filename.
- All API errors (HTTP 4xx/5xx, network failures, authentication failures) produce clear error messages on stderr and exit with a non-zero code.
- The escript is self-contained and has no dependencies beyond Erlang/OTP stdlib, inets, ssl, and crypto.

**`scripts/tools/manifest-tool`** - Erlang escript for all manifest operations: querying fields, creating project manifests, merging into firmware manifests, verifying integrity, and recomputing hashes. Runs on the host Erlang/OTP embedded by `feature_erlang` - no system Erlang installation required. Used by `manifest_utils.sh` and directly by orchestrator scripts. Shipped in the SDK alongside the artefact-server.

All manifest types (`sdk_manifest`, `project_manifest`, `firmware_manifest`) share the same root tuple convention `{Tag, ManifestVersion, [Fields]}` and the same [integrity specification](01_DATA_DESIGN.md#manifest-integrity-specification), so the tool operates uniformly on any manifest without requiring a `--type` flag.

##### Commands

**`manifest-tool get`** - Read a single top-level field from any manifest and print its value.

```
manifest-tool get --manifest PATH --field FIELD_NAME
```

Parameters:
- `--manifest PATH` - Path to any Alloy manifest file (SDK, project, or firmware).
- `--field FIELD_NAME` - Name of the top-level field to read (e.g. `product`, `target_arch`, `build_date`, `product_version`).

Behaviour:
- Parse the manifest. Extract the named field from the root proplist.
- **Output format:** Print the value as a plain string to stdout:
  - Binaries: printed without `<<"...">>` delimiters (e.g. `arm-buildroot-linux-gnueabihf`).
  - Atoms: printed as-is (e.g. `grisp2_vanilla`).
  - Integers: printed as decimal.
  - Lists of atoms: printed space-separated (e.g. `plain secure encrypted`).
  - Nested proplists: not supported for plain output; use `--format erlang` to get the raw Erlang term.
- `--format erlang` (optional) - Print the value as an Erlang term (useful for complex nested fields like `build_environment` or `capabilities`).

Exit codes: `0` on success (field found), `1` if the field is not present, `2` on structural error, `3` on parse error.

**Use cases:**
- Artefact resolution: `target_arch=$(manifest-tool get --manifest "$tarball_manifest" --field target_arch)`
- Build scripts reading SDK metadata: `product=$(manifest-tool get --manifest ALLOY_SDK_MANIFEST --field product)`

---

**`manifest-tool create-project`** - Create a project manifest from key-value fields, with integrity hash.

```
manifest-tool create-project \
    --field KEY=VALUE [...] \
    --repository KEY=VALUE [...] \
    --dependency KEY=VALUE [...] \
    --output PATH
```

Parameters:
- `--field KEY=VALUE` - Top-level manifest field. Repeatable. Required fields: `project` (identifier atom), `project_version`, `target_arch`. Optional: `project_name`, `project_description`, `project_type` (erlang | elixir), `app_name` (main OTP application name atom), `app_version` (main OTP application version string), `profiles`, `sdk_product`, `sdk_version`, `build_date` (defaults to current UTC if omitted).
- `--repository KEY=VALUE` - Repository entry. Repeatable (one invocation per repository). Keys: `id` (atom, required), `name`, `url`, `commit`, `describe`, `dirty` (boolean). The first repository is used as the project's own repository reference.
- `--dependency KEY=VALUE` - Dependency entry. Repeatable. Keys: `name` (required), `version`, `repository` (repo id reference), `checkout` (boolean, true if from `_checkouts/`), `scm` (git | hex | path), `source` (URL or path).
- `--output PATH` - Path to write the resulting `ALLOY_PROJECT_MANIFEST`.

Create flow:

1. **Validate required fields.** Ensure `project`, `project_version`, and `target_arch` are present.
2. **Build project manifest term.** Construct `{project_manifest, <<"1.0">>, [Fields]}` with all provided fields, repositories, and dependencies. Derive `build_date` from current UTC if not provided. The project `id` atom is derived from the `project` field.
3. **Compute integrity hash.** Serialize to canonical form, compute SHA-256, add `integrity` section.
4. **Write output.** Serialize as human-readable Erlang term file with `%% coding: utf-8` header.

---

**`manifest-tool merge`** - Merge an SDK manifest and one or more project manifests into a firmware manifest.

```
manifest-tool merge \
    --sdk-manifest PATH \
    --project-manifests GLOB \
    --firmware-info KEY=VALUE [...] \
    --output PATH
```

Parameters:
- `--sdk-manifest PATH` - Path to the `ALLOY_SDK_MANIFEST` file.
- `--project-manifests GLOB` - Glob pattern matching one or more `ALLOY_PROJECT_MANIFEST` files (e.g. `build/firmware/projects/*/ALLOY_PROJECT_MANIFEST`).
- `--firmware-info KEY=VALUE` - Zero or more key-value pairs for firmware-level metadata. Recognized keys: `firmware_variant` (atom), `security_pack_<key>=<value>` (opaque key-value pairs from `secpack info` - all stored as binaries in the `{security_pack, [...]}` proplist; the manifest-tool does not interpret or validate these fields), `firmware_name` (binary), `firmware_version` (binary), `project_root_<id>=<path>` (per-project installation path in the firmware rootfs; `<id>` is the project's `id` atom, `<path>` is the absolute path, e.g. `project_root_my_app=/srv/alloy/my_app`), and `param_<name>:<type>=<value>` (typed build-time parameters; `<type>` is `string`, `integer`, or `boolean`; see [§4.8 Firmware Build Parameters](#48-firmware-build-parameters)). Repeatable.
- `--output PATH` - Path to write the resulting `ALLOY_FIRMWARE_MANIFEST`.

Merge flow:

1. **Parse the SDK manifest.** Read the file at `--sdk-manifest`. Parse as Erlang term and validate the root tuple is `{sdk_manifest, Version, Fields}`. Extract `Version` as the SDK manifest version.

2. **Parse all project manifests.** Expand the `--project-manifests` glob. For each matching file, parse as Erlang term and validate the root tuple is `{project_manifest, Version, Fields}`. Extract `Version` as the project manifest version.

3. **Verify integrity of all inputs.** For each input manifest (SDK and all projects), verify the `integrity` section hash. If any manifest fails integrity verification, abort with an error listing the offending file. This ensures the firmware manifest is assembled only from untampered sources.

4. **Validate version compatibility.** Compare the `ManifestVersion` of every source manifest (SDK and all projects) against the firmware manifest version (`<<"1.0">>`). If any source has an incompatible major version, abort with an error listing the offending file and version.

5. **Consolidate repositories.** Collect the `repositories` section from the SDK manifest and from every project manifest. Apply the [Repository Deduplication](01_DATA_DESIGN.md#repository-deduplication) algorithm:
   - Deduplicate entries by canonical URL.
   - If a `RepoId` conflict occurs between sources (same ID, different URL), resolve by appending a numeric suffix and update the corresponding `repository` references in the affected nuggets or dependencies.
   - The result is a single `{repositories, [...]}` list for the firmware manifest.

6. **Strip and embed the SDK manifest.** Remove the `integrity` and `repositories` sections from the SDK manifest's fields proplist. Store the remainder as `{sdk, StrippedFields}`.

7. **Strip and embed project manifests.** For each project manifest, remove `integrity` and `repositories` from its fields proplist. Inject the `{project_root, Path}` field from the corresponding `--firmware-info project_root_<id>=<path>` pair, matching by the project's `id` field. If no `project_root_<id>` key is provided for a project, abort with a clear error - every project must have an installation path recorded. Collect all augmented proplists into a list. Store as `{projects, [AugmentedFields1, AugmentedFields2, ...]}`.

8. **Build firmware-level sections.** From the `--firmware-info` key-value pairs (excluding `project_root_*` keys, which are consumed in step 7), construct:
   - `{build_date, Timestamp}` - current UTC timestamp in ISO 8601.
   - `{firmware_name, Name}` - from `--firmware-info firmware_name=...` or derived from product + project names.
   - `{firmware_version, Version}` - from `--firmware-info firmware_version=...` or derived from product + project versions.
   - `{firmware_variant, Atom}` - from `--firmware-info firmware_variant=...`.
   - `{security_pack, PackInfo}` - `none` if no `security_pack_*` firmware-info keys are provided. Otherwise a proplist built from all `--firmware-info` keys matching `security_pack_<key>=<value>`: strip the `security_pack_` prefix, convert the key to a binary, store the value as a binary. The manifest-tool treats these as **opaque** - it does not validate or interpret the key names or values. Example: `security_pack_name=acme_v1` and `security_pack_version=2.0` become `[{<<"name">>, <<"acme_v1">>}, {<<"version">>, <<"2.0">>}]`. See [§4.6 Security Pack - secpack info](03_ALLOY_DESIGN.md#security-pack-command-contract).
   - `{parameters, ParamList}` - Collect all `--firmware-info` keys matching `param_<name>:<type>=<value>`. Strip the `param_` prefix, convert `<name>` to an atom, and convert `<value>` according to `<type>`:
     - `string` -> binary (e.g. `<<"SN123">>`).
     - `integer` -> integer (e.g. `42`).
     - `boolean` -> atom `true` or `false`.
     If no `param_*` keys are present, omit the section entirely. Example: `--firmware-info param_serial_number:string=SN123 --firmware-info param_factory_mode:boolean=true` produces `{parameters, [{serial_number, <<"SN123">>}, {factory_mode, true}]}`.

9. **Assemble the firmware manifest.** Construct the root term:
   `{firmware_manifest, <<"1.0">>, [BuildDate, FirmwareName, FirmwareVariant, SecurityPack, Parameters, Repositories, Sdk, Projects]}`.
   The `Parameters` section is omitted from the list if no build parameters were provided.

10. **Compute integrity hash.** Serialize the assembled manifest to canonical form `basic_term_canon` (order-preserving, normalized whitespace, no `integrity` section). Compute SHA-256 over the canonical binary. Append the `integrity` section with `{digest_algorithm, sha256}`, `{canonical_form, basic_term_canon}`, and `{digest, HexHash}`. See [Data Design - Manifest Integrity Specification](01_DATA_DESIGN.md#manifest-integrity-specification).

11. **Write output.** Serialize the final term as a human-readable Erlang term file with the `%% coding: utf-8` header. Write to `--output`.

---

**`manifest-tool verify`** - Verify a manifest file's structure and/or integrity hash.

```
manifest-tool verify --manifest PATH [--integrity-only]
```

Parameters:
- `--manifest PATH` - Path to any Alloy manifest file (SDK, project, or firmware).
- `--integrity-only` (optional) - Skip structural and cross-reference validation; only verify the integrity hash. Useful for quick checks in build scripts (e.g. artefact resolution, pre-merge validation).

Full verify flow (default):

1. **Parse the manifest.** Read and parse the file. Validate the root tuple is `{Tag, Version, Fields}` where `Tag` is one of `sdk_manifest`, `project_manifest`, or `firmware_manifest`.

2. **Validate structure.** Check that all required sections/fields are present for the detected manifest type. Validate field types (e.g. binaries are binaries, atoms are atoms, lists are lists).

3. **Validate cross-references.** For SDK manifests: verify every nugget's `repository` field references a `RepoId` present in `repositories`. For project manifests: verify every dependency's `repository` field references a `RepoId` present in `repositories`. For firmware manifests: verify the embedded `sdk` and `projects` proplists have internally consistent references into the consolidated `repositories`.

4. **Verify integrity hash.** Extract the `integrity` section. Read `digest_algorithm` and `canonical_form` - refuse if the verifier does not support them. Remove the `integrity` section from the fields. Serialize the remainder using the named canonical form. Compute the digest using the named algorithm. Compare against the stored `digest`. Report match or mismatch.

5. **Report.** Print a summary: manifest type, version, product/project/firmware name, integrity status (PASS/FAIL), any structural warnings.

Integrity-only flow (`--integrity-only`): executes steps 1 and 4 only. Reports PASS/FAIL for the integrity hash without structural validation.

Exit codes: `0` on success (integrity matches, and structure valid if checked), `1` on integrity mismatch, `2` on structural validation error (only in full mode), `3` on parse error.

---

**`manifest-tool hash`** - Recompute and update the integrity hash of a manifest file in place.

```
manifest-tool hash --manifest PATH
```

Parameters:
- `--manifest PATH` - Path to any Alloy manifest file.

Hash flow:

1. **Parse the manifest.** Read and parse the file.
2. **Strip existing integrity.** Remove the `integrity` section from the fields if present.
3. **Compute new hash.** Serialize to canonical form `basic_term_canon` per [Data Design - Manifest Integrity Specification](01_DATA_DESIGN.md#manifest-integrity-specification), compute SHA-256.
4. **Update and write.** Add the `integrity` section with `{digest_algorithm, sha256}`, `{canonical_form, basic_term_canon}`, and `{digest, NewHash}`. Write the file back in human-readable Erlang term format.

This command is useful for re-signing a manifest after manual edits (e.g. patching a version or adding metadata).

---

##### Canonicalization Algorithm

All commands that produce or verify integrity hashes (`create-project`, `merge`, `verify`, `hash`) use the same canonicalization as smelterl and all other manifest producers. The algorithm is **defined in [Data Design - Manifest Integrity Specification](01_DATA_DESIGN.md#manifest-integrity-specification)** and must not be duplicated here. In short: remove the `integrity` entry from the root proplist; serialize the remainder with the `basic_term_canon` form (order-preserving, minimal Erlang term text per the serialization rules in 01_DATA_DESIGN); compute SHA-256 over that UTF-8 binary. Implementations (manifest-tool, smelterl) must follow that specification so that hashes are consistent across SDK, project, and firmware manifests.

##### Error Handling

All commands follow these error handling principles:

- Parse errors (malformed Erlang term, missing period, encoding issues) produce a clear error message with file path and line number when possible.
- Version incompatibility during `merge` lists all offending files and their versions.
- Repository deduplication conflicts during `merge` are logged as warnings (the tool resolves them automatically).
- Missing files (glob matches nothing for `--project-manifests`) produce an error unless explicitly allowed.
- All errors exit with a non-zero code so the calling script (`alloy build firmware`) can detect and report the failure.

#### 8.7.7 grispio.sh

**Purpose:** Implement `alloy grispio`. Acts as the orchestrator layer that resolves artefact references and delegates the actual grisp.io API interaction to the grispio escript.

**Implementation guidance:**

1. **Parse action and common options:** Extract the action (first positional argument after `grispio`) and parse common options (`-H`/`--host`, `--no-tls-verify`). For `--host`, also check the `GRISPIO_HOST` environment variable as a fallback; the CLI option takes precedence.

2. **Resolve host:** Determine the target host using this precedence:
   1. `--host` / `-H` CLI option (highest priority).
   2. `GRISPIO_HOST` environment variable.
   3. Default: `app.grisp.io:443`.

3. **Update package resolution (for `upload`):** When the action is `upload`, the `PACKAGE_REF` refers to a local software update package (`.tar` with `MANIFEST`). Resolve it using the standard [artefact resolution](#artefact-resolution) mechanism with `${ALLOY_ARTEFACT_DIR}/grisp_updates/` as the search directory. After resolution, validate that the file is a `.tar` archive containing a `MANIFEST` at its root. The resolved **absolute path** is what gets passed to the grispio escript via `--package-path` - the escript never performs prefix matching itself. For `delete`, `deploy`, and other remote-only actions, the `PACKAGE_REF` is passed through to the escript as-is via `--package-ref` (it identifies the package on grisp.io, not a local file).

4. **Token management:** Before any API action (except `authenticate`), check for an existing encrypted token file. If missing, prompt the user to authenticate first. The token file path depends on the mode:
   - **Repository mode:** `${REPO_ROOT}/.grispio.token`
   - **SDK mode:** `~/.grisp_alloy/.grispio.token`

5. **Invoke the grispio escript:** After resolving all references and validating options, invoke the grispio escript with fully resolved arguments:

   ```bash
   # Upload example - the escript receives a resolved path, never a prefix
   "${ALLOY_ROOT_DIR}/tools/grispio" upload \
       --host "${RESOLVED_HOST}" \
       --token-file "${TOKEN_FILE}" \
       --package-path "/absolute/path/to/my_app-1.2.0-grisp2_vanilla-1.0.0.tar"

   # Deploy example
   "${ALLOY_ROOT_DIR}/tools/grispio" deploy \
       --host "${RESOLVED_HOST}" \
       --token-file "${TOKEN_FILE}" \
       --package-ref "my_app-1.2.0-grisp2_vanilla-1.0.0" \
       --device "my-device-serial"
   ```

6. **Error handling:**
   - Artefact resolution failures (zero or multiple matches) produce a clear message and exit non-zero before reaching the escript.
   - Escript failures (HTTP errors, authentication errors, network errors) are propagated to the user with the escript's error message.
   - Missing `--device` for actions that require it is caught during option parsing.

### 8.8 Project Plugins

**Purpose:** Extensible system for supporting different project types (Erlang, Elixir, and potentially Rust, C, Python, or other languages in the future). Built on top of the generic plugin framework (`plugin_utils.sh` - see [§8.6.13](#8613-pluginutilssh)).

#### 8.8.1 Plugin Contract

Every project plugin is a Bash script located in `scripts/plugins/project/` and named `<type>.sh` (e.g. `erlang.sh`, `elixir.sh`). The script defines functions following the naming convention `project_<type>_<action>`. Functions are either **required** (must be defined and succeed) or **optional** (silently skipped if not defined).

**Required functions:**

| Function | Signature | Description |
|----------|-----------|-------------|
| `detect` | `project_<type>_detect PROJECT_DIR` | Determine whether the project in `PROJECT_DIR` is of this type. Return 0 if yes, non-zero otherwise. Must be fast (filesystem checks only - e.g. test for `rebar.config` or `mix.exs`). Must not produce output on stdout. |
| `build` | `project_<type>_build PROJECT_DIR PROFILE RELEASE_STAGING_DIR OVERLAY_STAGING_DIR` | Build the project and write directly into the orchestrator-provided staging directories. The orchestrator creates `release/` and `overlay/` under the project staging dir and passes their absolute paths. The plugin builds the OTP release (using the cross-compilation environment set up by `env_utils.sh`) and writes the release contents into `RELEASE_STAGING_DIR`; it may optionally write overlay content (rootfs files, and optionally `ALLOY_FS_PRIORITIES` at the overlay root) into `OVERLAY_STAGING_DIR`. The plugin is free to write whatever it wants in either directory; no copying is done by the orchestrator. Returns 0 on success, non-zero on failure. Error details go to stderr. |
| `info` | `project_<type>_info RELEASE_DIR PROJECT_DIR` | Extract project metadata from the built release (the same directory the plugin wrote in the build step). Writes key=value pairs to stdout (one per line). Returns 0 on success. See **Info output contract** below. |

**Info output contract:**

The `info` function writes key=value pairs to stdout. The framework (`plugin_read`) parses these into an associative array. Required and optional keys:

| Key | Required | Description |
|-----|----------|-------------|
| `name` | Yes | Release name (e.g. `my_app`). Derived from the OTP release directory name. |
| `version` | Yes | Release version (e.g. `1.2.0`). Derived from the release's version directory. |
| `app_name` | No | Main OTP application name. If not provided, defaults to `name`. Extracted from `.app.src` (Erlang) or `mix.exs` `:app` key (Elixir), validated against `lib/<app>-*` in the built release. |
| `app_version` | No | Main OTP application version. Extracted from `lib/<app_name>-<version>/` in the built release. |
| `runtime` | No | Runtime identifier (e.g. `erlang`, `elixir`). |
| `otp_version` | No | OTP version used for the release (e.g. `26.2`). |

Example output from an Erlang plugin:
```
name=my_app
version=1.0.0
app_name=my_app
app_version=1.0.0
runtime=erlang
otp_version=26.2
```

**Cross-compilation environment available to plugins:**

Before any plugin function is called, the orchestrator has already called `setup_cross_env "${SDK_DIR}"` (see [§8.6.7](#867-envutilssh)). Every plugin function inherits the following environment variables:

| Variable | Description |
|----------|-------------|
| `CC`, `CXX`, `LD`, `AR`, `STRIP`, ... | Cross-compiler toolchain binaries (e.g. `arm-buildroot-linux-gnueabihf-gcc`). |
| `CROSSCOMPILE_PREFIX` | Cross-compiler prefix (e.g. `arm-buildroot-linux-gnueabihf-`). |
| `CFLAGS`, `CXXFLAGS`, `LDFLAGS` | Cross-compilation flags including `--sysroot` and target include paths. |
| `HOST_ERLANG` | Path to host Erlang/OTP in the SDK (e.g. `SDK_DIR/host/usr/lib/erlang`). Used for running rebar3, escript, and mix. |
| `HOST_REBAR3` | Path to the SDK's rebar3 binary. |
| `TARGET_ERLANG` | Path to target Erlang/OTP in the SDK (e.g. `SDK_DIR/staging/usr/lib/erlang`). Contains cross-compiled ERTS and OTP applications for the target architecture. Plugins bundle this into OTP releases. |
| `OTP_VERSION` | Erlang/OTP version string (e.g. `26.2`). |
| `ERL_CFLAGS`, `ERL_LDFLAGS` | Flags for compiling and linking NIFs against the target ERTS. |
| `ERTS_INCLUDE_DIR` | Path to target ERTS include directory (for NIF headers). |
| `ERL_EI_INCLUDE_DIR`, `ERL_EI_LIBDIR` | Paths to erl_interface include and library directories. |
| `REBAR_TARGET_ARCH` | Cross-compiler prefix for rebar3 NIF cross-compilation. |
| `PKG_CONFIG`, `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_LIBDIR` | pkg-config configuration pointing to the target sysroot. |
| `CC_FOR_BUILD`, `CXX_FOR_BUILD`, ... | Native host tools for build-for-host steps (so that host-only build steps use the host compiler, not the cross-compiler). |
| `PATH` | Prepended with `SDK_DIR/host/bin` and `SDK_DIR/host/usr/bin`, making rebar3, escript, mix, and the cross-compiler available. |

Plugins do not set up any of these variables themselves. The environment is their sole input for build context. This design ensures that plugins are portable across different SDK versions and target architectures without modification.

#### 8.8.2 scripts/plugins/project.sh

**Purpose:** Project-specific plugin loader and high-level dispatch API. Acts as the bridge between the orchestrator (which calls project-level functions) and the generic plugin framework (which handles loading and dispatch).

**Implementation guidance:**

1. Source `scripts/utils/plugin_utils.sh` for the generic framework.
2. Define a `project_load_plugins SDK_DIR` function that calls `plugin_load project "${SDK_DIR}/scripts/plugins/project"`. This sources all `*.sh` files from the plugin directory, making all `project_<type>_<action>` functions available.
3. Define a `project_detect PROJECT_DIR` function that iterates all known project types (discovered during load by scanning for `project_<type>_detect` functions). For each type, call `project_<type>_detect "${PROJECT_DIR}"`. The first type that returns 0 wins. Store the detected type in a module-level variable (e.g. `_PROJECT_TYPE`). If no plugin matches, abort with an error listing the available types and what was checked.
4. Define high-level dispatch functions that delegate to the detected type via the plugin framework:
   - `project_build PROJECT_DIR PROFILE RELEASE_STAGING_DIR OVERLAY_STAGING_DIR` - Calls `plugin_call project "${_PROJECT_TYPE}" build "${PROJECT_DIR}" "${PROFILE}" "${RELEASE_STAGING_DIR}" "${OVERLAY_STAGING_DIR}"`. The plugin writes the release and optionally the overlay into those directories; nothing is returned on stdout.
   - `project_info RELEASE_DIR PROJECT_DIR` - Calls `plugin_read project "${_PROJECT_TYPE}" info INFO_ARRAY "${RELEASE_DIR}" "${PROJECT_DIR}"`. Returns the populated associative array to the caller.
5. The `project_type` function returns the detected type string (e.g. `erlang`, `elixir`) for inclusion in the project manifest.

**Sourced by:** `build-project.sh` (step 3 of [§5.6 Project Build Flow](#56-project-build-flow)).

#### 8.8.3 erlang.sh

**Location:** `scripts/plugins/project/erlang.sh`

**Purpose:** Project plugin for Erlang/rebar3 projects.

**`project_erlang_detect PROJECT_DIR`:**

Return 0 if `PROJECT_DIR/rebar.config` exists, non-zero otherwise. No output.

**`project_erlang_build PROJECT_DIR PROFILE RELEASE_STAGING_DIR OVERLAY_STAGING_DIR`:**

Build the Erlang OTP release using the SDK's rebar3 and target Erlang/OTP, then write the release into `RELEASE_STAGING_DIR` and optionally overlay content into `OVERLAY_STAGING_DIR`. The function relies entirely on the cross-compilation environment set up by `env_utils.sh` - it does not discover paths itself.

Implementation guidance:

1. Resolve the rebar3 command from `HOST_REBAR3` (or from `PATH`, since `host/usr/bin` is prepended). Verify the binary exists and is executable.
2. **Fetch dependencies** - Run `rebar3 as ${PROFILE} get-deps` in the project directory with `ERL_LIBS` **unset**. Unsetting `ERL_LIBS` is critical: this variable is set to `${TARGET_ERLANG}/lib` by `env_utils.sh` for NIF compilation, but during dependency fetching rebar3 should not see the target libraries, only the host Erlang environment. Use `env -u ERL_LIBS` to unset it for this step only.
3. **Build release** - Run `rebar3 as ${PROFILE} release --system_libs "${TARGET_ERLANG}" --include-erts "${TARGET_ERLANG}"` in the project directory. The `--include-erts` flag tells rebar3 to bundle the ERTS from `TARGET_ERLANG` (the cross-compiled target runtime) instead of the host ERTS. The `--system_libs` flag tells rebar3 to use OTP applications from `TARGET_ERLANG` instead of the host's. This is the mechanism by which the target Erlang/OTP runtime enters the project's OTP release.
4. **Write release to staging** - Copy or move the built release (`PROJECT_DIR/_build/${PROFILE}/rel/*/`) into `RELEASE_STAGING_DIR`. The plugin may optionally write `ALLOY_FS_PRIORITIES` at the root of `RELEASE_STAGING_DIR`. Optionally write overlay files (e.g. from a project `overlay/` or `config/` tree) into `OVERLAY_STAGING_DIR`, including `ALLOY_FS_PRIORITIES` at the overlay root if desired.

**`project_erlang_info RELEASE_DIR PROJECT_DIR`:**

Extract metadata from the built release. Write key=value pairs to stdout.

Implementation guidance:

1. **Release name** - `basename "${RELEASE_DIR}"` (the release directory name is the release name).
2. **Release version** - Find the version directory under `RELEASE_DIR/releases/` (first child directory). Its name is the version.
3. **Application name** - Scan `PROJECT_DIR/src/*.app.src` for the `{application, Name, ...}` tuple. Extract `Name`. Validate that `RELEASE_DIR/lib/${Name}-*` exists (the app is in the release). If no `.app.src` match, fall back to the release name.
4. **Application version** - From the `RELEASE_DIR/lib/${app_name}-<version>/` directory name, extract the version suffix.
5. **Runtime** - Write `runtime=erlang`.
6. **OTP version** - Write `otp_version=${OTP_VERSION}` (from the environment).

The plugin may optionally write overlay content (and `ALLOY_FS_PRIORITIES` in release or overlay root) into `OVERLAY_STAGING_DIR`; the build function receives both staging paths and is free to populate either or both.

#### 8.8.4 elixir.sh

**Location:** `scripts/plugins/project/elixir.sh`

**Purpose:** Project plugin for Elixir/Mix projects.

**`project_elixir_detect PROJECT_DIR`:**

Return 0 if `PROJECT_DIR/mix.exs` exists, non-zero otherwise. No output.

**`project_elixir_build PROJECT_DIR PROFILE RELEASE_STAGING_DIR OVERLAY_STAGING_DIR`:**

Build the Elixir OTP release using the SDK's mix, replace the host ERTS/OTP with target versions, then write the release into `RELEASE_STAGING_DIR` and optionally overlay into `OVERLAY_STAGING_DIR`. The Elixir build is more complex than Erlang because `mix release` does not natively support cross-compilation via a single flag - the plugin must perform a post-build replacement step.

Implementation guidance:

1. **Map profile to Mix environment** - If `PROFILE` is empty or `default`, use `prod` as the Mix environment. Otherwise use `PROFILE` as-is.
2. Resolve the mix command from `PATH` (the SDK's `host/usr/bin/mix` should be available). Verify the binary exists.
3. **Fetch dependencies** - Run `mix deps.get --only ${MIX_ENV}` in the project directory. Unset `ERL_LIBS`, `ERL_FLAGS`, `ERL_AFLAGS`, `ERL_ZFLAGS`, and `MIX_TARGET` to prevent target libraries from interfering with dependency resolution. Set `LANG=en_US.UTF-8`, `LC_ALL=en_US.UTF-8`, and `ELIXIR_ERL_OPTIONS=+fnu` for proper Unicode handling.
4. **Compile** - Run `mix compile` with the same environment cleanup. This compiles the project using host Erlang/OTP (for running the compiler) but produces BEAM files that are architecture-independent.
5. **Build release** - Run `mix release --overwrite` with `MIX_ENV` set and `ERTS_DIR` pointing to the target ERTS directory (`${TARGET_ERLANG}/erts-*/`), `ERL_LIB_DIR` to `${TARGET_ERLANG}`, and `ERL_SYSTEM_LIB_DIR` to `${TARGET_ERLANG}/lib`. This hints to mix where target libraries are, though the definitive replacement happens in the next step.
6. **Replace host ERTS with target ERTS** - After `mix release`, the release directory contains the host ERTS (since mix ran on the host). Replace it:
   - Remove all `RELEASE_DIR/erts-*/` directories.
   - Copy the target ERTS directory from `${TARGET_ERLANG}/erts-*/` into the release.
7. **Replace host OTP applications with target versions** - For each OTP application directory in `${TARGET_ERLANG}/lib/`, check if a matching application (by base name, ignoring version) exists in `RELEASE_DIR/lib/`. If it does:
   - Remove the host version from the release.
   - Create the target version directory and copy `ebin/` and `priv/` from the target. Only `ebin/` (compiled BEAM files and `.app` file) and `priv/` (native code and data) need to be replaced - these are the architecture-dependent parts. Source, docs, and include directories are not needed at runtime.
8. **Write release to staging** - Copy the built release (`PROJECT_DIR/_build/${MIX_ENV}/rel/*/`) into `RELEASE_STAGING_DIR`. Optionally write overlay content and/or `ALLOY_FS_PRIORITIES` into `OVERLAY_STAGING_DIR`.

**`project_elixir_info RELEASE_DIR PROJECT_DIR`:**

Extract metadata from the built release. Write key=value pairs to stdout.

Implementation guidance:

1. **Release name** - `basename "${RELEASE_DIR}"`.
2. **Release version** - Find the version directory under `RELEASE_DIR/releases/`.
3. **Application name** - Parse `PROJECT_DIR/mix.exs` for the `app:` key (e.g. `app: :my_app`). Extract the atom name. Validate against `RELEASE_DIR/lib/${Name}-*`. If no match, fall back to the release name.
4. **Application version** - From `RELEASE_DIR/lib/${app_name}-<version>/`, extract version.
5. **Runtime** - Write `runtime=elixir`.
6. **OTP version** - Write `otp_version=${OTP_VERSION}`.

The plugin may optionally write overlay content (and `ALLOY_FS_PRIORITIES`) into `OVERLAY_STAGING_DIR`; the build function receives both staging paths and is free to populate either or both.

#### 8.8.5 Adding a New Project Type

To add support for a new project type (e.g. Rust, C, Python):

1. Create a new plugin file: `scripts/plugins/project/<type>.sh`.
2. Implement the three required functions: `project_<type>_detect`, `project_<type>_build`, `project_<type>_info`.
3. The `build` function receives `RELEASE_STAGING_DIR` and `OVERLAY_STAGING_DIR`; write the release into the first and optionally overlay content (and `ALLOY_FS_PRIORITIES` in either root) into the second. No separate overlay or fs_priorities function - the plugin writes whatever it needs into the two staging directories.
4. The plugin is automatically discovered and loaded by `project.sh` - no registration or configuration is needed.

For non-OTP project types (e.g. Rust, C), the `info` function should still output `name` and `version` keys. The `runtime` key can identify the language (e.g. `runtime=rust`). The `build` function should produce a directory structure that can be staged into `release/` - even if it is not an OTP release, the packaging convention remains the same: the contents of the build output go into `staging/release/` and are installed under `/srv/alloy/<name>/` in the firmware.

The cross-compilation environment set by `env_utils.sh` provides `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, and other standard variables that any C/Rust/Go toolchain can use directly. Erlang-specific variables (`HOST_ERLANG`, `TARGET_ERLANG`, etc.) are simply ignored by non-Erlang plugins.

### 8.9 Buildroot Integration

#### 8.9.1 script_hook.sh

**Purpose:** Universal wrapper for Buildroot-invoked hooks (`post-build`, `post-image`, `post-fakeroot`).

**Location:** `scripts/buildroot/script_hook.sh` (static in repository; symlinked into `br2_external/board/PRODUCT/scripts/`).

**Implementation guidance:**

1. Resolve the directory of the script as invoked (symlink directory).
2. Determine hook type from invocation name: strip `.sh`, replace `-` with `_`. Map to array name (e.g. `post_image` -> `ALLOY_POST_IMAGE_HOOKS`).
3. Expect `ALLOY_MOTHERLODE`, `ALLOY_BUILD_DIR`, `ALLOY_CACHE_DIR`, `ALLOY_ARTEFACT_DIR`, `ALLOY_DEBUG`, `ALLOY_TRACE`, and `ALLOY_ROOT_DIR` from Buildroot make parameters. `ALLOY_PRODUCT`, `ALLOY_IS_AUXILIARY`, and `ALLOY_AUXILIARY` come from the sourced target context (not from Config.in).
4. Source `alloy_context.sh` from the same directory as the symlink.
5. Export `ALLOY_HOOK_TYPE`.
6. Iterate the selected hook array. For each element, parse nugget name and script path, set per-nugget environment, and invoke the script. Skip missing scripts with a warning. Abort on non-zero exit.

The symlinks in `br2_external/board/PRODUCT/scripts/` all point to the same `script_hook.sh`. Buildroot calls them by their names (`post-build.sh`, `post-image.sh`, etc.); the wrapper uses the invocation name to determine which hook type to dispatch.
