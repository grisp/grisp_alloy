# GRiSP Alloy - Overview

**Version:** 2.0 (Draft)  
**Status:** Design Document  
**Last Updated:** 2026-02-04

This document is the entry point for the GRiSP Alloy architecture. It defines goals, glossary, conventions, and a high-level architecture overview. Detailed design is split into:

- **[Data Design](01_DATA_DESIGN.md)** - Repository and SDK directory structure, nugget discovery, metadata (`.nuggets`, `.nugget`), and manifest specification.
- **[Smelterl Design Redirect](02_SMELTERL_DESIGN.md)** - Alloy-side redirect to the authoritative Smelterl design document:
  local checkout/submodule [smelterl/docs/DESIGN.md](../smelterl/docs/DESIGN.md),
  web view [github.com/grisp/smelter/docs/DESIGN.md](https://github.com/grisp/smelter/blob/main/docs/DESIGN.md).
- **[Alloy Design](03_ALLOY_DESIGN.md)** - Alloy bash orchestrator: how it uses smelterl and Buildroot, SDK and project generation, toolchain and builder nuggets, commands (repository vs SDK), security pack concept and contract.

---

## Table of Contents

1. [Goals](#goals)
2. [Glossary](#glossary)
   - [Key Concepts](#key-concepts)
3. [Conventions](#conventions)
   - [Erlang Term File Format Conventions](#erlang-term-file-format-conventions)
   - [Naming Conventions](#naming-conventions)
4. [Architecture Overview](#architecture-overview)

---

## Goals

GRiSP Alloy is a build system for embedded Linux firmware targeting Erlang/Elixir applications. It is designed around the following principles:

1. **Flexibility**
   - Support multiple hardware platforms (i.MX6, i.MX8, future platforms).
   - Allow mixing open-source and proprietary components in a single build.
- Enable third-party and customer-specific hardware, system, and bootflow definitions alongside builtin ones.

2. **Developer Experience**
   - Simple, intuitive command structure (`alloy build sdk`, `alloy build firmware`).
- Clear separation of concerns between different aspects of the build (hardware, system, bootflow, application features).
   - Easy creation of new reusable build components without deep Buildroot knowledge.
   - Helpful error messages and early validation.

3. **Maintainability**
   - Single source of truth for each concern.
   - Minimal code duplication through composable, reusable build components.
   - Clear architectural boundaries and interfaces.
   - Well-documented design decisions.

4. **CI/CD Integration**
   - Reproducible builds with pinned dependencies.
   - Support for remote signing services (no cryptographic keys on CI runners).
   - Comprehensive build metadata for traceability.
   - Headless operation support (no interactive prompts).

5. **Buildroot Foundation**
   - Leverage Buildroot’s proven embedded Linux build system.
   - Don't fight Buildroot’s design; extend it cleanly.
   - Use standard Buildroot mechanisms where possible.
   - Maintain compatibility with Buildroot tooling.

6. **Reproducibility**
   - Version tracking for all components (packages, build components, toolchain).
   - VCS provenance tracking (commit hashes, dirty status).
   - Comprehensive SBOM-compatible metadata generation.
   - Build environment documentation.

7. **SDK Self-Containment**
   - Generated SDKs work independently, without the source repository.
   - All required tools embedded in the SDK: cross-compiler, host Erlang/OTP, rebar3.
   - No external language runtimes or cross-compilers required on the host system.
   - Relocatable SDK structure (no hardcoded paths) where possible.
   - Same entry-point script works in both development (repository) and distribution (SDK) modes.
   - SDK build supports multiple build targets (main product + auxiliary products) with deterministic orchestration.

8. **Open/Closed Source Composition**
   - A public repository can produce private, customer-specific firmware.
   - Cryptographic materials (keys, certificates, signing scripts) are kept external to the repository and SDK.
   - Customer applications can build on top of shared base components.
   - Clear licensing and attribution for all components.

9. **Security Awareness**
   - Support for secure boot and disk encryption in firmware builds.
   - External storage for keys, certificates, and signing scripts (no secrets in the repository or SDK).
   - HSM and remote signing support for keyless, secure CI/CD pipelines.
   - Clear capability reporting (e.g. "this SDK supports secure boot") and graceful degradation when unsupported options are requested.

---

## Glossary

| Term | Definition |
|------|-------------|
| **Alloy** | The complete firmware build system and the name of the main orchestrator script. |
| **Nugget** | A self-contained, composable build component (platform, system, bootflow, feature, etc.). Nuggets can depend on other nuggets and declare capabilities. |
| **Product** | The top-level nugget being built. Any nugget can serve as a product; it is a build-time choice, not a category. |
| **Main Product** | The primary product selected by the user for `alloy build sdk`. |
| **Auxiliary Product** | A secondary SDK-build-time product target declared by nugget metadata and built before the main product; does not run firmware-time hooks. |
| **Build Target** | One concrete SDK build target instance: either `main` or one auxiliary target identified by `AuxId`. |
| **Motherlode** | The directory containing the set of nugget repositories used to generate the Buildroot configuration. All nugget sources are staged there before generation. |
| **Platform** | A nugget that provides hardware platform support (CPU, bootloader, kernel). Exactly one per build. |
| **System** | A nugget that defines a specific board or hardware integration. Exactly one per build. |
| **Bootflow** | A nugget that defines the firmware assembly orchestration for a firmware variant (e.g. plain boot, secure boot). Exactly one bootflow participates in each variant. |
| **Security Pack** | An external component providing security services (signing, credential export, overlay generation, TLS material export) through a defined command contract. Provided as either a single executable file or a directory containing an executable named `secpack` at its root. Must be Linux-compatible, relocatable, and self-contained. May wrap local key files, an HSM, or a remote signing service. Accessed by hooks exclusively through `security_tools.sh` functions. Not shipped in SDKs. See [Alloy Design](03_ALLOY_DESIGN.md#46-security-pack). |
| **Feature** | A nugget providing composable functionality (bases, utilities, products, apps). Multiple allowed; the usual composition unit. |
| **Toolchain** | A nugget that provides the cross-compilation toolchain. Exactly one per build; it may build one (e.g. Crosstool-NG), use a vendor prebuilt, or use Buildroot’s internal toolchain. See [03_ALLOY_DESIGN.md](03_ALLOY_DESIGN.md#63-toolchain). |
| **Builder** | A nugget that sets up the SDK build backend (e.g. Buildroot: version, placement, download cache). Exactly one per build. See [03_ALLOY_DESIGN.md](03_ALLOY_DESIGN.md#62-builder). |
| **Flavor** | A qualifier for a nugget, expressing a subtle configuration difference within the same nugget (e.g. a specific SoC for a platform nugget, or a `minimal` vs `full` system configuration). Not to be confused with *firmware variant*. |
| **Capability** | A feature flag a nugget declares (e.g. `secure_boot`). Used for dependency resolution and validation. |
| **Configuration** | Key-value settings from nuggets, consolidated for use in hooks and Buildroot config. See [Data Design](01_DATA_DESIGN.md#nugget-configuration-metadata). |
| **Host Erlang** | The Erlang/OTP runtime embedded in the SDK by `feature_erlang`. Used for building Erlang projects (rebar3), running escripts (manifest-tool, artefact-server), and NIF compilation. Eliminates the need for a system-installed Erlang. |
| **SDK** | Self-contained kit to build firmware: images, host tools, scripts, cross-compiler, host Erlang/OTP, and metadata generated from all SDK build targets (main + auxiliaries). No grisp_alloy checkout or system-installed toolchains needed. |
| **Firmware** | Final flashable image, built from an SDK with optional secure boot or disk encryption. |
| **BR2_EXTERNAL** | Buildroot’s mechanism for external tree overlays; smelterl generates it from nuggets. |
| **smelterl** | The Erlang tool that plans and generates SDK build targets from nugget metadata (`plan` + target-scoped `generate`). See the Alloy-side [Smelterl Design Redirect](02_SMELTERL_DESIGN.md), the local standalone document [smelterl/docs/DESIGN.md](../smelterl/docs/DESIGN.md), or the web view [github.com/grisp/smelter/docs/DESIGN.md](https://github.com/grisp/smelter/blob/main/docs/DESIGN.md). |
| **SDK Manifest** | Build metadata (nuggets, repos, Buildroot packages, environment, licensing). Stored as `ALLOY_SDK_MANIFEST`. |
| **Project Manifest** | Project build metadata (release name, release version, main OTP application name and version, dependencies, SDK provenance). Stored as `ALLOY_PROJECT_MANIFEST`. |
| **Firmware Manifest** | Firmware-level metadata combining SDK and project manifests. Stored as `ALLOY_FIRMWARE_MANIFEST`. |
| **Firmware Variant** | A distinct firmware build configuration (e.g. plain, secure, encrypted) selectable at firmware build time via `--variant`. Not to be confused with nugget *flavor*. |
| **SBOM** | Software Bill of Materials: inventory of components, versions, licenses, and provenance. |
| **Artefact Directory** | Where build outputs are stored (toolchains, SDKs, firmware). |
| **Build directory** | Working directory for one SDK or project build. Holds the build tree; ephemeral and distinct from artefacts and cache. See [Data Design](01_DATA_DESIGN.md#build-directory). |
| **Cache directory** | Long-lived caches (downloads, ccache, toolchain). Separate from artefacts so outputs can be relocated without touching cache. |
| **VCS** | Version Control System (Git, Mercurial). Nuggets can be loaded from VCS URLs. |

### Key Concepts

The glossary above gives short definitions. This section provides the conceptual foundation for the terms used throughout the design documents.

#### Nuggets

A **nugget** is Alloy's fundamental unit of composition. It represents a self-contained piece of the firmware build - a hardware platform definition, a system board integration, a bootflow (firmware assembly recipe), a reusable feature, or even the toolchain and build backend themselves. Each nugget is a small directory of metadata files and optional scripts that declare *what* the nugget needs and *what* it provides, without hard-wiring how the final firmware is assembled.

Nuggets are designed so that different concerns are kept in separate, independently maintainable units:

- A **platform** nugget describes a hardware family (e.g. which processor, bootloader, and kernel to use). A build has exactly one.
- A **system** nugget describes a specific board or hardware integration built on top of a platform. A build has exactly one.
- A **bootflow** nugget describes how firmware is assembled for a variant (e.g. plain bootflow, secure bootflow). The active bootflow is selected by firmware variant at firmware build time.
- A **feature** nugget provides a reusable piece of functionality - a base configuration, a utility, a filesystem tool, or an application-level service. Multiple features compose freely.
- A **toolchain** nugget provides the cross-compilation toolchain. A build has exactly one.
- A **builder** nugget configures the build backend (e.g. which Buildroot version to use). A build has exactly one.

Nuggets can depend on other nuggets and declare capabilities (e.g. "I provide secure boot"). The build system resolves these dependencies into a deterministic order, merges their configurations, and orchestrates their build hooks.

A **product** is a build-time role, not a nugget category. In SDK build v2, one run has one **main product** and zero or more **auxiliary products** (each auxiliary identified by `AuxId`). Auxiliary products are independent target trees built during SDK generation and consumed by the main target.

#### SDK

An **SDK** (Software Development Kit) is the primary output of the first build phase. It is a self-contained directory (or tarball) that contains everything needed to build firmware and application projects - cross-compiler, host tools, base filesystem images, build scripts, metadata, legal information, and auxiliary-target-produced SDK outputs - without requiring access to the original source repository or any system-installed toolchains.

The SDK is designed to be distributable: hand it to a developer or a CI runner, and they can build firmware from it immediately.

#### Security Pack

A **security pack** is an external component that provides security services to the alloy build system through a defined command contract. It can be provided in two forms: a single executable file (script, binary, etc.) or a directory containing an executable named `secpack` at its root alongside supporting files (keys, certificates, templates). The entry point may be a shell script, a compiled binary, or any other executable program. It may wrap local key files, a Hardware Security Module (HSM) via PKCS#11, or a remote signing service. It is deliberately kept *outside* the repository and *outside* the SDK, so that:

- Keys and certificates are never committed to version control.
- SDKs can be distributed without exposing signing secrets.
- CI/CD pipelines can use remote signing services without local key access.

At firmware build time, the security pack is specified via `--security-pack PATH` or the `ALLOY_SECURITY_PACK` environment variable, where `PATH` is a path to either an executable file or a directory. The orchestrator resolves, validates, and canonicalizes the pack to an absolute path before any build steps run. The security pack must be Linux-compatible (it may run inside a Vagrant VM), relocatable (no absolute internal paths), and self-contained (no symlinks outside its own tree). All interaction with the security pack goes through `security_tools.sh` functions (e.g. `security_sign`, `security_get_credential`) - hooks never invoke the security pack directly. Implementation-specific configuration (API tokens, service URLs) is provided via environment variables. See [Alloy Design - Security Pack](03_ALLOY_DESIGN.md#46-security-pack).

#### Firmware Variants

A **firmware variant** represents a distinct firmware build configuration that can be selected at build time. The most common use case is security: a single SDK can support a `plain` (unsigned) variant, a `secure` (signed boot) variant, and an `encrypted` (signed + encrypted disk) variant. The user selects which variant to build with a command-line flag.

Variants are not limited to security - any aspect of the build that should produce a different firmware configuration from the same SDK can be modeled as a variant. Nuggets that are variant-specific declare which variants they participate in; nuggets without a variant declaration participate in all variants.

#### Flavor vs Firmware Variant - Disambiguation

These two concepts are orthogonal and must not be confused:

| | **Flavor** (nugget qualifier) | **Firmware Variant** (build configuration) |
|---|---|---|
| **What** | A qualifier within a single nugget expressing a subtle configuration difference | A firmware build configuration across the whole nugget tree |
| **Example** | `imx6ull` vs `imx6ul` (SoC), `minimal` vs `full` (system) | `plain` vs `secure` vs `encrypted` |
| **Declared by** | The nugget: `{flavors, [imx6ull, imx6ul]}` | Any nugget: `{firmware_variant, [plain, secure]}` |
| **Selected by** | A dependent nugget: `{flavor, imx6ull}` | The user at build time: `--variant secure` |
| **Resolved when** | Dependency resolution (SDK build) | Firmware build |
| **Effect** | Selects config values via `flavor_map` | Selects which nuggets participate in `firmware_build` hooks |

**Naming convention:** Always use the qualified terms - "nugget flavor" and "firmware variant" - when context is ambiguous. Never use "nugget variant" or "firmware flavor".

#### Motherlode

The **motherlode** is a staging directory where the build system collects all nugget sources before processing them. Nuggets can come from the builtin repository, local directories, or remote VCS URLs - the motherlode normalizes them into a single directory tree. Once staged, the code generation tool (smelterl) reads the motherlode to resolve dependencies, merge configurations, and generate the build files.

---

## Conventions

### Erlang Term File Format Conventions

**All Erlang term files** (`.nuggets`, `.nugget`, `ALLOY_SDK_MANIFEST`, `ALLOY_PROJECT_MANIFEST`, `ALLOY_FIRMWARE_MANIFEST`) **MUST** follow these conventions:

1. **UTF-8 Encoding**
   - Files MUST be UTF-8 encoded.
   - Files SHOULD include encoding header: `%% coding: utf-8`.
   - Smelterl assumes UTF-8 encoding for all term files without BOM.

2. **String Representation**
   - Use **binaries** (`<<"string">>`) for all string values, lists and ambiguous.

3. **File Structure**
   - One Erlang term per file.
   - Term MUST end with `.` (period).
   - Comments use `%` or `%%`.

4. **Uniform Root Tuple Convention**
   - Every Alloy term file uses the same root shape: `{Tag, Version, [Fields]}`.
   - `Tag` (atom) identifies the file type: `nugget_registry`, `nugget`, `sdk_manifest`, `project_manifest`, `firmware_manifest`.
   - `Version` (binary) is the schema version of that file type (e.g. `<<"1.0">>`). Tools use this to detect incompatible schema changes and provide clear error messages.
   - `Fields` (proplist) carries all data; consumers look up entries by key.
   - This convention allows a single parser to read any Alloy file, identify its type, and validate version compatibility before processing.

**Example:**

```erlang
%% coding: utf-8
%% Example metadata file
{nugget, <<"1.0">>, [
    {id, example},
    {version, <<"1.0.0">>},
    {description, <<"Example with UTF-8: café, 日本語">>},
    {author, <<"Company Name">>}
]}.
```

### Naming Conventions

#### Nugget Naming

**Recommended naming patterns** (not enforced by the system):

- **Category prefixes:** `platform_`, `system_`, `security_`, `toolchain_`, `builder_`, `feature_`.
- **Feature nuggets:** Reusable functionality (e.g., `feature_erlinit`, `feature_network`).
- **Base nuggets (suffix `_base`):** Foundation nuggets (e.g., `common_base`, `acme_base`). Base nuggets usually do **not** depend on feature nuggets.
- **Product-like nuggets:** Complete product configurations (e.g., `grisp2_vanilla`, `acme_app`).
- **Multi-part names:** Use **hyphens** for vendor-model-soc (e.g., `system_kontron-albl-imx8mm`).

#### Artefact Naming

Naming patterns for build outputs (recommendations; not enforced):

| Artefact | Pattern |
|----------|---------|
| Tools | `<NAME>-<VERSION>` |
| Toolchain | `toolchain-<TARGET_ARCH>-<VENDOR>-<TARGET_OS>-<TARGET_ABI>-<VERSION>-<HOST_OS>-<HOST_ARCH>.tar.xz` |
| SDK | `sdk-<PRODUCT_NAME>-<PRODUCT_VERSION>-<HOST_ARCH>.tar.gz` |
| Project | `project-<PROJECT_NAME>-<PROJECT_VERSION>[-<PROFILES>]-<TARGET_ARCH>.tar.gz` |
| Firmware | `firmware-<PROJECT_NAME>-<PROJECT_VERSION>-<PRODUCT_NAME>-<PRODUCT_VERSION>.fwup` |
| GRiSP update package | `<PROJECT_NAME>-<PROJECT_VERSION>-<PRODUCT_NAME>-<PRODUCT_VERSION>.tar` |
| Image | `image-<PROJECT_NAME>-<PROJECT_VERSION>-<PRODUCT_NAME>-<PRODUCT_VERSION>.img` |

**Project profile naming:** `<PROFILES>` is the sorted, `+`-joined list of active profiles with the `default` profile elided. If only `default` is active, the `[-<PROFILES>]` segment is omitted entirely. Examples:

| Active profiles | Filename segment |
|-----------------|-----------------|
| `default` | *(omitted)* - `project-my_app-1.0.0-aarch64.tar.gz` |
| `prod` | `-prod` - `project-my_app-1.0.0-prod-aarch64.tar.gz` |
| `default`, `debug` | `-debug` - `project-my_app-1.0.0-debug-aarch64.tar.gz` |
| `prod`, `debug` | `-debug+prod` - `project-my_app-1.0.0-debug+prod-aarch64.tar.gz` |

#### Export Key Naming

- **Value exports:** Plain descriptive names (e.g. `target_arch_triplet`, `otp_version`, `squashfs_comp`). Become `ALLOY_CONFIG_<KEY>`.
- **Function exports (`fun_` prefix):** Callable scripts exported for use by other nuggets' hooks (e.g. `fun_build_uboot_fit`, `fun_assemble_boot_image`). Become `ALLOY_CONFIG_FUN_<NAME>`. See [Alloy Design - Nugget Categories](03_ALLOY_DESIGN.md#6-nugget-categories) for category roles, contracts, and availability checking.

#### Environment and Template Variables

- All build-context and hook-visible variables use the **`ALLOY_`** prefix.
- **Template substitution:** In computed config and defconfig fragments, markers use the form **`[[KEY]]`** (e.g. `[[ALLOY_CONFIG_INIT_SYSTEM]]`, `[[ALLOY_ARTEFACT_DIR]]`).

Variable naming details are in [Data Design](01_DATA_DESIGN.md#environment-variables-and-functions); the full context script content is in the standalone Smelterl design document:
local checkout/submodule [smelterl/docs/DESIGN.md#412-generating-alloy_contextsh](../smelterl/docs/DESIGN.md#412-generating-alloy_contextsh),
web view [github.com/grisp/smelter/docs/DESIGN.md#412-generating-alloy_contextsh](https://github.com/grisp/smelter/blob/main/docs/DESIGN.md#412-generating-alloy_contextsh).

---

## Architecture Overview

**Key design principles:**

1. **Bash-first orchestration** - alloy handles orchestration, Vagrant, mode detection, and command dispatch.
2. **Erlang for file generation** - smelterl focuses on parsing, dependency resolution, and file generation.
3. **Single script, dual modes** - Same alloy scripts in repository (full commands) and SDK (project/firmware/serve/grispio subset).
4. **Buildroot as build engine** - Orchestrate from above; treat Buildroot as lower-level build system.
5. **Context generation** - One generated context file per build target (`alloy_context.sh`) provides hook scripts with all the information they need (dependency order, paths, configuration) without re-parsing nugget metadata at build time.
6. **Manifest and legal-info for SBOM** - Manifest and legal-information tracking are designed to meet modern SBOM and compliance requirements (components, versions, licenses, provenance).
7. **Self-contained SDK** - Images, host tools, scripts, context; no grisp_alloy checkout required.
8. **Composability and reusability** - Nuggets are composable building blocks; mix and match platform, system, and features; reuse across products.
9. **Separation of concerns** - Clear boundaries: orchestration (alloy), code generation (smelterl), build execution (Buildroot).
10. **Security abstraction** - Cryptographic materials (keys, certificates, signing scripts) live in an external security pack or remote service - never in the repository or SDK. This enables secure CI pipelines and customer-specific deployment.


### Building a SDK

The following diagram summarizes how alloy, smelterl, and Buildroot interact when building an SDK. Nuggets are the input; smelterl turns them into a Buildroot “project” (BR2_EXTERNAL + defconfig); Buildroot does the actual build. If you know Buildroot, think of smelterl as the generator of your external tree and defconfig from declarative nugget metadata.

**Example (from repository):**
```bash
alloy build sdk grisp2_vanilla
# with extra nugget paths (local or VCS):
alloy build sdk acme_product -n ../acme_nuggets -n git+https://example.com/nugget.git#main
```

```
  Nuggets (repos) + main product
              |
              v
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy (Bash) - build sdk                                                 │
  │   - Optionally set up Vagrant VM and delegate to it                       │
  │   - Stage nugget sources into motherlode                                  │
  │   - Call smelterl plan                                                    │
  └───────────┬───────────────────────────────────────────────────────────────┘
              |
              |  staged motherlode + main product
              v
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  smelterl plan (Erlang)                                                   │
  │   - Resolve main + auxiliary targets                                      │
  │   - Validate target trees and constraints                                 │
  │   - Emit build_plan.term / build_plan.env                                 │
  └───────────┬───────────────────────────────────────────────────────────────┘
              |
              |  deterministic build plan
              v
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy (Bash) - target loop (auxiliaries first, then main)                │
  │   - smelterl generate for selected target                                 │
  │   - Run pre_build hooks (once per nugget globally)                        │
  │   - Build target with Buildroot                                           │
  │   - Run make legal-info for that target                                   │
  └───────────┬───────────────────────────────────────────────────────────────┘
              |
              |  per-target artefacts + per-target legal-info
              v
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy + smelterl generate (main finalization pass)                       │
  │   - Collect/validate auxiliary sdk outputs                                │
  │   - Merge legal-info from all targets into one export tree                │
  │   - Generate merged legal-info README                                     │
  │   - Emit final ALLOY_SDK_MANIFEST                                         │
  └───────────┬───────────────────────────────────────────────────────────────┘
              |
              |  merged manifest + consolidated legal-info
              v
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy (Bash)                                                             │
  │   - Pack SDK: images, host tools, scripts, context, motherlode            │
  │   - Include manifest, legal-info, and auxiliary outputs                   │
  │   - Produce SDK tarball                                                   │
  └───────────────────────────────────────────────────────────────────────────┘
```

For someone used to Buildroot: **smelterl** produces the equivalent of your hand-written BR2_EXTERNAL and defconfig from nugget metadata; **alloy** stages the nugget repos, runs smelterl, then runs Buildroot with that tree, and finally packs the result into an SDK.

### Building a project

Project build produces an application package (e.g. Erlang/Elixir release) from a project path or VCS URL, using the SDK’s host tools and sysroot. Run from an SDK directory (or from the repository with an SDK tarball). No smelterl or Buildroot involved.

**Example (from SDK directory):**
```bash
./alloy build project /path/to/my_app
# or from a VCS URL:
./alloy build project git+https://github.com/acme/my_app.git#v1.0.0
```

```
  SDK + project path (or git+url)
              │
              ▼
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy (Bash) - build project                                             │
  │   - Optionally set up Vagrant VM and delegate to it                       │
  │     - Synchronize external data (project dir, etc.) into VM               │
  │   - Resolve project source: VCS clone or copy into workspace              │
  │   - Detect project type (Erlang/Elixir)                                   │
  │   - Set up cross-compilation environment for NIFs targeting the platform  │
  │   - Build release using SDK host tools                                    │
  │   - Package release with manifests into package/                          │
  │   - Write tarball to artefacts directory                                  │
  └───────────────────────────────────────────────────────────────────────────┘
```

### Building firmware

Firmware build assembles a flashable image from the SDK’s base images, host tools, and **one or more project artefacts** (tarballs from `alloy build project`). Run from an SDK directory, or from the repository with `--sdk` so alloy delegates. Merges projects and the rootfs overlay with the SDK base into one root file system, then packages bootloader, kernel, and firmware. Can optionally support secure boot and disk encryption with an external security pack; see [Alloy Design](03_ALLOY_DESIGN.md).

**Example (from SDK directory):**
```bash
# single project (artefact name prefix or path to .tgz):
./alloy build firmware my_project
# multiple projects with explicit names under /srv/alloy/<name>:
./alloy build firmware my_project --name alpha other_project --name beta
# with secure boot variant and security pack
./alloy build firmware my_project --variant secure --security-pack ../acme_security_pack
```

**Example (from grisp_alloy repository):**
```bash
# single project (artefact name prefix or path to .tgz):
./alloy build firmware --sdk artefacts/sdk/sdk-grisp_vanilla-1.0.0-x86_64.tar.gz my_app my_project
```

```
  SDK + TARGET + one or more project artefacts
              │
              ▼
  ┌───────────────────────────────────────────────────────────────────────────┐
  │  alloy (Bash) - build firmware                                            │
  │   - Optionally set up Vagrant VM and delegate to it                       │
  │     - Synchronize external data (projects, overlay, etc.) into VM         │
  │   - If repository mode: extract SDK to temp, delegate to SDK's alloy      │
  │   - Unpack and validate all project artefacts                             │
  │   - Stage each project under /srv/alloy/<name>                            │
  │   - Consolidate squashfs priorities                                       │
  │   - Merge SDK base rootfs, projects and overlay into a single rootfs      │
  │   - Call the nuggets' build_firmware hooks in order                       │
  │     - Use security_tools.sh to interact with the security pack            │
  │   - Copy firmware to artefact directory                                   │
  └───────────────────────────────────────────────────────────────────────────┘
```

For detailed flows and component responsibilities, see the Alloy-side [Smelterl Design Redirect](02_SMELTERL_DESIGN.md), the local standalone document [smelterl/docs/DESIGN.md](../smelterl/docs/DESIGN.md), the web view [github.com/grisp/smelter/docs/DESIGN.md](https://github.com/grisp/smelter/blob/main/docs/DESIGN.md), and [Alloy Design](03_ALLOY_DESIGN.md).
