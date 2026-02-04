# GRiSP Alloy - Data Design

This document defines repository and SDK directory structure, metadata specification (`.nuggets` registry and `.nugget` files), and manifest specification. For overview and glossary see [Overview](00_OVERVIEW.md); for smelterl behavior see [Smelterl Design](02_SMELTERL_DESIGN.md).

---

## Table of Contents

1. [Directory Structure](#directory-structure)
   - [Repository Directory](#repository-directory)
   - [Scripts Directory](#scripts-directory)
   - [Artefact Directory](#artefact-directory)
   - [Cache Directory](#cache-directory)
   - [Build Directory](#build-directory)
     - [SDK build directory](#sdk-build-directory)
     - [Project build directory](#project-build-directory)
     - [Firmware build directory](#firmware-build-directory)
   - [SDK Directory](#sdk-directory)
2. [Nugget Specification](#nugget-specification)
   - [Nugget Registry](#nugget-registry)
   - [Nugget Metadata](#nugget-metadata)
     - [Fields Overview](#fields-overview)
     - [Nugget Categories](#nugget-categories)
     - [Topology Order](#topology-order)
     - [Config Consolidation](#config-consolidation)
     - [Buildroot Defconfig generation](#buildroot-defconfig-generation)
     - [SDK Embedding](#sdk-embedding)
     - [Generic Metadata](#generic-metadata)
     - [Dependencies Metadata](#dependencies-metadata)
     - [Auxiliary Products Metadata](#auxiliary-products-metadata)
     - [Nugget Configuration Metadata](#nugget-configuration-metadata)
     - [Overrides Metadata](#overrides-metadata)
     - [Buildroot Integration Metadata](#buildroot-integration-metadata)
     - [Hooks Metadata](#hooks-metadata)
     - [Embedding Metadata](#embedding-metadata)
     - [SDK Outputs Metadata](#sdk-outputs-metadata)
     - [Firmware Outputs Metadata](#firmware-outputs-metadata)
     - [Firmware Parameters Metadata](#firmware-parameters-metadata)
     - [SBOM & Legal Metadata](#sbom--legal-metadata)
3. [SDK Manifest Specification](#sdk-manifest-specification)
   - [Root Format](#manifest-root-format)
   - [Sections Overview](#manifest-sections-overview)
   - [Product and Build Information](#product-and-build-information)
   - [Build Environment](#manifest-build-environment)
   - [Repositories](#manifest-repositories)
   - [Repository Deduplication](#repository-deduplication)
   - [Alloy repository info file (.alloy_repo_info)](#alloy-repository-info-file-alloy_repo_info)
   - [Nuggets](#manifest-nuggets)
   - [Auxiliary Products](#manifest-auxiliary-products)
   - [Capabilities](#manifest-capabilities)
   - [SDK Outputs](#manifest-sdk-outputs)
   - [Buildroot Packages](#manifest-buildroot-packages)
   - [External Components](#manifest-external-components)
   - [Integrity](#manifest-integrity)
   - [Complete Example](#manifest-complete-example)
4. [Project Manifest Specification](#project-manifest-specification)
5. [Firmware Manifest Specification](#firmware-manifest-specification)
6. [Manifest Integrity Specification](#manifest-integrity-specification)
7. [Filesystem Priority Specification](#filesystem-priority-specification)
8. [Environment Variables and Functions](#environment-variables-and-functions)
   - [Defined By](#defined-by)
   - [Available To](#available-to)
   - [Variables](#variables)
   - [Helper Functions](#helper-functions)
   - [Buildroot Variables](#buildroot-variables)

---

## Directory Structure

### Repository Directory

**Purpose:** Root layout of the grisp_alloy repository (source, scripts, default artefact and cache locations).

**Structure:**

```
grisp_alloy/
├── alloy                  # Main orchestrator script (bash)
├── Vagrantfile            # Cross-platform build VM configuration
├── nuggets/               # Builtin nuggets
│   ├── .nuggets           # Registry; see [Nugget Registry](#nugget-registry)
│   ├── builder_buildroot/
│   ├── toolchain_ctng/
│   ├── platform_imx6/
│   ├── platform_imx8/
│   ├── bootflow_grisp2_plain/
│   ├── bootflow_imx8_fit_plain/
│   ├── common_base/
│   ├── feature_erlinit/
│   ├── feature_erlang/
│   ├── feature_elixir/
│   ├── feature_squashfs/
│   ├── feature_fwup/
│   ├── feature_image/
│   ├── system_grisp2/
│   ├── system_kontron-albl-imx8mm/
│   ├── grisp2_vanilla/
│   └── kontron-albl-imx8mm_vanilla/
├── smelterl/              # Erlang config generator; see [Smelterl Design](02_SMELTERL_DESIGN.md)
├── scripts/               # Alloy scripts; see [Scripts Directory](#scripts-directory)
├── artefacts/             # Default artefact storage; see [Artefact Directory](#artefact-directory)
├── _cache/                # Cache directory; see [Cache Directory](#cache-directory)
└── _build/                # Build directory; see [Build Directory](#build-directory)
```

---

### Scripts Directory

**Purpose:** Commands, utilities, Buildroot hooks, and plugins. Paths below relative to `scripts/`.

**Structure:**

```
scripts/
├── commands/              # Command implementations (invoked by alloy)
│   ├── build-sdk.sh
│   ├── build-project.sh
│   ├── build-firmware.sh
│   ├── serve-artefacts.sh
│   └── grispio.sh
├── utils/                 # Sourceable utilities
│   ├── common.sh          # Error handling, path helpers, temp dirs; sources debug_utils.sh
│   ├── hook_common.sh     # Hook entry point: sourced by each hook; sources *_tools.sh, sets set -x / debug level
│   ├── debug_utils.sh     # Orchestrator-internal: log_*, enter_hidden, leave_hidden, die
│   ├── debug_tools.sh     # Hook API: alloy_log_*, alloy_enter_hidden, alloy_leave_hidden, alloy_die
│   ├── argparse.sh        # Command-line argument parsing
│   ├── vagrant_utils.sh   # Vagrant VM lifecycle and delegation
│   ├── vcs_utils.sh       # VCS operations (clone, checkout, describe)
│   ├── patch_utils.sh     # Patch application utilities
│   ├── file_utils.sh      # File and directory manipulation helpers
│   ├── sdk_utils.sh       # SDK packing, unpacking, and validation
│   ├── env_utils.sh       # Cross-compilation environment setup
│   ├── otp_utils.sh       # OTP release scrubbing (strip, cleanup) for firmware
│   ├── manifest_utils.sh  # Bash wrappers around manifest-tool escript
│   ├── firmware_tools.sh  # Bash API for firmware hooks (add_firmware_output, etc.)
│   ├── firmware_utils.sh  # Orchestrator-internal firmware build utilities
│   ├── security_tools.sh  # Bash API for security pack interaction (hooks)
│   ├── security_utils.sh  # Security pack resolution, validation, parsing
│   └── dev_utils.sh       # Developer convenience (clean, rebuild, debug)
├── buildroot/
│   └── script_hook.sh     # Universal hook (symlinked as post-*.sh)
├── tests/                 # Bash unit tests (bash_unit; not shipped in SDK)
│   ├── run_tests.sh       # Wrapper: runs test_*.sh if bash_unit on PATH
│   ├── test_common.sh     # Tests for utils/common.sh
│   ├── test_file_utils.sh # Tests for utils/file_utils.sh
│   ├── test_sdk_utils.sh  # Tests for utils/sdk_utils.sh
│   └── test_*.sh          # One file per tested script or util
├── tools/                 # Self-contained executables
│   ├── artefact-server    # HTTP/HTTPS artefact server (Erlang escript)
│   └── manifest-tool      # Manifest merging/hashing (Erlang escript)
└── plugins/
    ├── project.sh
    └── project/
        ├── erlang.sh
        └── elixir.sh
```

### Artefact Directory

**Purpose:** Output location for built tools, toolchains, SDKs, project packages, and firmware. Separate from cache so outputs can be relocated without touching cache.

**Location (fixed by mode, not user-configurable):**

| Mode        | Path                          |
|-------------|-------------------------------|
| Repository  | `artefacts/` (relative to alloy root) |
| SDK         | `~/.grisp_alloy/artefacts/`   |

**Structure:**

```
artefacts/
├── tools/                          # Built host tools
│   └── smelterl-1.0.0              # Erlang config generator (escript)
├── toolchains/                     # Toolchain tarballs
│   └── toolchain-arm-unknown-linux-gnueabihf-1.0.linux-x86_64.tar.xz
├── sdk/                            # SDK tarballs
│   └── sdk-grisp_vanilla-1.0.1-x86_64.tar.gz
├── projects/                       # Project package tarballs
│   └── project-my_app-2.1.0-prod.tgz
├── firmware/                       # Firmware images
│   └── firmware-my_project-1.2.0-grisp_vanilla-1.0.0.fw
├── grisp_updates/                   # GRiSP software update packages for grisp.io
│   └── my_project-1.2.0-grisp_vanilla-1.0.0.tar
└── images/                         # Disk images
    └── image-my_project-1.2.0-grisp_vanilla-1.0.0.img
```

---

### Cache Directory

**Purpose:** Long-lived caches (Buildroot downloads, ccache, toolchain source). Separate from artefacts so artefacts can be relocated or cleaned without touching the cache.

**Location (fixed by mode, not user-configurable):**

| Mode        | Path                          |
|-------------|-------------------------------|
| Repository  | `_cache/` (relative to alloy root) |
| SDK         | `~/.grisp_alloy/cache/`       |

**Structure:**

```
cache/
├── buildroot/
│   ├── buildroot-2021.02.3.tar.gz  # Buildroot source tarball (downloaded once, location may vary)
│   ├── downloads/                  # Package sources downloaded by Buildroot (shared across SDK builds)
│   └── ccache/                     # Compiler cache
└── toolchain/
    ├── crosstool-ng-4fa0ba100b8924b27942ff253c5474c655427027.tar.xz # Crosstool-NG source
    └── downloads/                  # Toolchain component downloads
```

### Build Directory

**Purpose:** Ephemeral working directory for SDK, project, and firmware builds.

**Location (fixed by mode, not user-configurable):**

| Mode        | Path                          |
|-------------|-------------------------------|
| Repository  | `_build/` (relative to alloy root) |
| SDK         | `~/.grisp_alloy/build/`       |

#### SDK build directory

**Purpose:** Generated during SDK build; holds the plan artefacts plus one workspace per build target (main and auxiliaries), shared motherlode, and final SDK staging.

**Structure:**

```
_build/sdk/<MAIN_PRODUCT>/
├── plan/
│   ├── build_plan.term       # Smelterl full plan output
│   └── build_plan.env        # Bash-friendly plan output (target list, metadata)
├── targets/
│   ├── main/                 # Main target
│   │   ├── workspace/        # Buildroot output directory (O=) for this target
│   │   │   ├── build/        # Package build artefacts and logs
│   │   │   │   ├── <pkg>-<ver>/
│   │   │   │   │   ├── .stamp_*
│   │   │   │   │   └── build.log
│   │   │   │   └── build-time.log
│   │   │   ├── .sdk_outputs/ # SDK output registration state (one file per OutputId; value = absolute produced path)
│   │   │   ├── host/         # Host tools (cross-compiler, utilities)
│   │   │   ├── images/       # Final target images (rootfs, kernel, bootloader)
│   │   │   ├── staging/      # Target sysroot for cross-compilation
│   │   │   ├── target/       # Target rootfs (before packaging)
│   │   │   └── legal-info/   # Buildroot legal-info output for this target
│   │   ├── br2_external/     # Generated BR2_EXTERNAL tree for this target
│   │   │   ├── external.desc
│   │   │   ├── Config.in
│   │   │   ├── external.mk
│   │   │   ├── configs/
│   │   │   │   └── <TARGET_ID>_defconfig
│   │   │   └── board/<TARGET_ID>/scripts/
│   │   │       ├── post-build.sh     # -> scripts/buildroot/script_hook.sh
│   │   │       ├── post-image.sh     # -> scripts/buildroot/script_hook.sh
│   │   │       ├── post-fakeroot.sh  # -> scripts/buildroot/script_hook.sh
│   │   │       └── alloy_context.sh  # -> ../../../../alloy_context.sh
│   │   └── alloy_context.sh  # Generated target-specific context
│   └── <AUX_ID>/             # Auxiliary target; same structure as main target
│       ├── workspace/
│       │   └── .sdk_outputs/
│       ├── br2_external/
│       └── alloy_context.sh
├── staging/                  # Final SDK staging dir (ALLOY_SDK_STAGING_DIR)
│   ├── ALLOY_SDK_MANIFEST    # Final merged manifest
│   ├── legal-info/           # Final merged legal-info export
│   ├── auxiliary/            # Staged auxiliary sdk outputs for packing
│   │   └── <AUX_ID>/
│   │       └── outputs/
│   │           └── <OUTPUT_ID>/...
│   └── ...
└── motherlode/               # Staged nugget repositories (ALLOY_MOTHERLODE)
    ├── builtin/
    ├── REPO_NAME_1/
    └── ...
```

`targets/main/` and each `targets/<AUX_ID>/` follow the same per-target contract; the tree above shows representative Buildroot internals and generated files. Exact package subdirectories under `workspace/build/` depend on the selected nuggets and Buildroot version.

**Target reference convention:** Directory keys under `targets/` use a target reference (`TargetRef`) where `main` is the main target and each auxiliary target uses its declared `AuxId`.

#### Project build directory

**Purpose:** Generated during project build; holds project source (or copy) and the packaged release ready for firmware assembly.

**Structure:**

```
_build/project/<PROJECT_NAME>/
├── workspace/                  # Project source (VCS clone or directory copy)
│   ├── src/
│   ├── rebar.config           # (Erlang) or mix.exs (Elixir)
│   └── _build/                # Project build artefacts
│       └── prod/rel/RELEASE_NAME/   # OTP release
└── staging/                    # Packaged project artefact (input to firmware build)
    ├── ALLOY_PROJECT_MANIFEST  # Project manifest (Erlang term)
    ├── release/                # OTP release (staged under /srv/alloy/<name>/ at firmware build)
    │   └── ALLOY_FS_PRIORITIES # Optional: paths relative to release root
    └── overlay/                # Optional: project-specific rootfs overlay
        └── ALLOY_FS_PRIORITIES # Optional: paths relative to overlay root (= rootfs root)
```

#### Firmware build directory

**Purpose:** Ephemeral workspace for assembling firmware images: unpacked project artefacts, per-firmware staging, and (when used) overlay or security-pack staging.

**Structure:**

```
_build/firmware/
├── projects/                    # Unpacked project artefacts (one dir per project)
│   └── PROJECT_NAME/
│       ├── ALLOY_PROJECT_MANIFEST
│       ├── release/             # OTP release
│       │   └── ALLOY_FS_PRIORITIES  # Optional: paths relative to release root
│       └── overlay/             # Optional: project-specific overlay
│           └── ALLOY_FS_PRIORITIES  # Optional: paths relative to overlay root (= rootfs root)
└── workspace/                   # Per-firmware staging
    ├── fs.priorities            # Consolidated filesystem priorities (path weight)
    ├── rootfs_overlay/          # Merged overlay (nugget + project + security + CLI)
    │   ├── srv/alloy/           # Per-project release dirs
    │   │   └── PROJECT_NAME/
    │   └── srv/erlang           # Symlink -> first project's release dir
    ├── rootfs/                  # Unsquashed rootfs (intermediate, pre_firmware)
    ├── combined.squashfs        # SDK rootfs + rootfs_overlay (pre_firmware output)
    └── ALLOY_FIRMWARE_MANIFEST  # Firmware manifest (post-build)
```

### Vagrant State Directory

**Purpose:** Holds Vagrant machine state, the persistent cache disk image, and SSH configuration. These files are created and managed by Vagrant and the Vagrantfile.

**Location (fixed by mode, not user-configurable):**

| Mode        | Path                          |
|-------------|-------------------------------|
| Repository  | Alloy root (alongside the Vagrantfile) |
| SDK         | `~/.grisp_alloy/vagrant/`     |

In SDK mode, the SDK directory may be read-only (installed system-wide, extracted to a shared location, etc.), so all Vagrant state must reside outside the SDK. The alloy entry-point sets `VAGRANT_DOTFILE_PATH=~/.grisp_alloy/vagrant/.vagrant` before invoking Vagrant in SDK mode. The Vagrantfile reads `ALLOY_MODE` and computes the cache disk path accordingly.

**Contents:**

| File | Repo mode path | SDK mode path |
|------|----------------|---------------|
| Vagrant machine state | `.vagrant/` | `~/.grisp_alloy/vagrant/.vagrant/` |
| Persistent cache disk | `.vagrant.cache.vmdk` | `~/.grisp_alloy/vagrant/cache.vmdk` |
| SSH configuration (generated) | `.vagrant.ssh_config` | `~/.grisp_alloy/vagrant/ssh_config` |

### SDK Directory

**Purpose:** Self-contained layout for project and firmware builds (extracted from SDK tarball or built in-place).

**Structure:**

```
sdk-<PRODUCT>-<VERSION>-<HOST_ARCH>/
├── alloy                    # Orchestrator script (SDK mode)
├── ALLOY_SDK_MANIFEST           # Complete build manifest (with Buildroot packages)
├── .alloy_sdk_dir               # Placeholder (@@ALLOY_SDK_DIR@@) or current SDK root path (for relocation detection)
├── .alloy_relocation_manifest   # List of text files containing the @@ALLOY_SDK_DIR@@ placeholder
├── legal-info/              # Buildroot (make legal-info) + Alloy additions
│   ├── README               # merged legal-info summary (targets included, merge notes)
│   ├── manifest.csv         # Buildroot target packages
│   ├── host-manifest.csv    # Buildroot host packages
│   ├── licenses/            # Buildroot target package licenses
│   ├── host-licenses/       # Buildroot host package licenses
│   ├── sources/             # (optional) Buildroot target package sources (redistributable only)
│   ├── host-sources/        # (optional) Buildroot host package sources
│   ├── alloy-manifest.csv   # Alloy/nugget components (and external, e.g. toolchain)
│   ├── alloy-licenses/      # Nugget license files
│   │   └── <NUGGET_NAME>-<VERSION>/
│   │       └── <COMPONENT_NAME>-<COMPONENT_VERSION>/
│   ├── alloy-sources/       # (optional) Nugget/external source when --include-sources
│   │   └── <NUGGET_NAME>-<VERSION>/
│   │       └── <COMPONENT_NAME>-<COMPONENT_VERSION>/
│   ├── legal-info.sha256    # Hashes of all files above (Buildroot + alloy)
│   └── buildroot.config     # Buildroot configuration (from make legal-info)
├── scripts/                 # Tools and build context (repo scripts minus tests)
│   ├── alloy_context.sh     # Build context (env vars, nugget order); sourced by build-firmware
│   ├── commands/
│   ├── utils/               # Sourceable utilities (env_utils.sh, otp_utils.sh, manifest_utils.sh, etc.)
│   ├── tools/               # Self-contained executables (artefact-server, manifest-tool)
│   └── plugins/
├── images/                  # Buildroot output images (explicitly embedded)
│   ├── rootfs.squashfs
│   ├── zImage
│   ├── devicetree.dtb
│   ├── spl.bin              # (if a bootflow/feature nugget embedded it)
│   └── u-boot.img           # (if a bootflow/feature nugget embedded it)
├── host/                    # Host tools (explicitly embedded with deps)
│   ├── bin/
│   │   ├── <TRIPLET>-gcc    # Cross-compiler (from toolchain_ctng)
│   │   ├── <TRIPLET>-ld     # Cross-linker (from toolchain_ctng)
│   │   ├── fwup             # (from feature_fwup)
│   │   └── mksquashfs       # (from feature_squashfs)
│   ├── usr/
│   │   ├── bin/
│   │   │   ├── erl          # Host Erlang/OTP (from feature_erlang)
│   │   │   ├── erlc
│   │   │   ├── escript      # Used by manifest-tool, artefact-server
│   │   │   ├── rebar3       # (from feature_erlang)
│   │   │   ├── mix          # (from feature_elixir, if present)
│   │   │   └── elixir       # (from feature_elixir, if present)
│   │   └── lib/
│   │       ├── erlang/      # OTP applications, ERTS runtime (from feature_erlang)
│   │       └── elixir/      # Elixir std library (from feature_elixir, if present)
│   ├── <TRIPLET>/
│   │   └── sysroot/         # Toolchain sysroot (from toolchain_ctng): libc, compiler support
│   └── lib/                 # Shared libraries (auto-resolved via ldd)
│       └── *.so*
├── staging/                 # Buildroot target staging (all target packages)
│   └── usr/lib/erlang/      # Target Erlang/OTP (cross-compiled for target arch)
│       ├── erts-*/           # Target ERTS runtime (bundled into project releases)
│       └── lib/              # Target OTP applications
├── auxiliary/               # Auxiliary target outputs embedded in SDK
│   └── <AUX_ID>/
│       └── outputs/
│           └── <OUTPUT_ID>/...
└── motherlode/              # Embedded nugget content (same structure as build-time motherlode)
    └── <REPO>/              # Repository directory (e.g. builtin, acme_nuggets)
        └── <NUGGET_NAME>/
            ├── scripts/
            │   ├── sign-spl.sh  # (example: bootflow/feature nugget)
            │   └── sign-fit.sh
            └── data/
                └── keys/
                    └── dummy.pub
```

**Not included:** Buildroot source, build output directory, BR2_EXTERNAL, smelterl, script tests.

**Always included:** The cross-compilation toolchain (from `toolchain_ctng`) is embedded so that projects can cross-compile NIFs for the target architecture. The host Erlang/OTP runtime and rebar3 (from `feature_erlang`) are embedded so that Erlang/Elixir projects can be built and escripts can run. The SDK requires no language runtimes or cross-compilers on the host system. Embedding and relocatability are described in [Alloy Design](03_ALLOY_DESIGN.md#510-sdk-packing-flow).

**Relocation control files:**

- **`.alloy_sdk_dir`** - Contains either the placeholder string `@@ALLOY_SDK_DIR@@` (in a freshly packed SDK that has not yet been used) or the real filesystem path of the SDK root (after first use or after `alloy prepare sdk`). This file is the single source of truth for detecting whether the SDK needs text-based path relocation. On first use, the orchestrator compares the content of this file against the actual SDK root path. If they differ (or the file contains the placeholder), relocation is performed: the placeholder is replaced with the real path in all files listed in `.alloy_relocation_manifest`, and `.alloy_sdk_dir` is updated to the real path. If they match, no relocation is needed. Created at pack time (see [Alloy Design - SDK Packing Flow](03_ALLOY_DESIGN.md#510-sdk-packing-flow)). Used at first use (see [Alloy Design - Relocatability](03_ALLOY_DESIGN.md#41-sdk)) and by the explicit `alloy prepare sdk` command (see [Alloy Design - alloy prepare sdk](03_ALLOY_DESIGN.md#34-alloy-prepare-sdk)).

- **`.alloy_relocation_manifest`** - A plain text file listing all SDK-root-relative paths of text files that contain the `@@ALLOY_SDK_DIR@@` placeholder. Generated at pack time during text-based path sanitization (see [Alloy Design - SDK Packing Flow](03_ALLOY_DESIGN.md#510-sdk-packing-flow)). The relocation process reads this file and runs `sed` replacement on each listed file. Only text files with actual build-machine path references are listed - binary files and files without path references are excluded. This avoids scanning the entire SDK tree on every relocation, making the fixup fast and targeted.

**Motherlode in the SDK:** The SDK contains a `motherlode/` directory that is a subset of the build-time motherlode (only explicitly embedded content - scripts, keys, templates, data). It preserves the same `<repo>/<nugget_id>/` directory structure. This is required because `alloy_context.sh` (generated at SDK build time) contains paths like `ALLOY_NUGGET_<NAME>_DIR="${ALLOY_MOTHERLODE}/<repo>/<nugget_id>"`. In SDK mode, `ALLOY_MOTHERLODE` points to `<SDK_ROOT>/motherlode/`, so the directory layout must match for all context paths to remain valid without regeneration.

---

## Nugget Specification

This section covers the `.nuggets` registry format (per-repository) and the `.nugget` file format (per nugget). It defines the **data structures** and the **processes** that derive from them (topological order, configuration consolidation, defconfig generation, SDK embedding).

### Nugget Registry

**Purpose:** Each nugget source directory (repository) is identified by a `.nuggets` file that lists which `.nugget` files belong to it.

**Root Format:** `{nugget_registry, RegistryVersion, [FieldEntry, ...]}.`

This follows the uniform `{Tag, Version, [Fields]}` convention used by all Alloy term files.

**Specification:**

`RegistryVersion`: string (binary)
- Schema version of the nugget registry format.
- Example: `<<"1.0">>`.

`FieldEntry`: tuple
- any of:
    - `{defaults, [DefaultField, ...]}`: proplist (optional) - default values for **license and SBOM attribution only**; applied to all nuggets in this directory, with per-nugget `.nugget` overriding for that nugget. Only the following keys are allowed: `license`, `license_files`, `author`, `maintainer`, `homepage`, `security_contact`. These are the same as in [SBOM & Legal Metadata](#sbom--legal-metadata). Other metadata (version, name, description, category, config, etc.) is inherently per-nugget and must not appear in registry defaults; implementations must ignore or reject unknown keys.
    - `{nuggets, [Path, ...]}`: list of string (binary) (required) - relative paths from the `.nuggets` file to each `.nugget` file.

**Examples:**

```erlang
%% Simple registry
{nugget_registry, <<"1.0">>, [
    {nuggets, [
        <<"platform_imx6/platform_imx6.nugget">>,
        <<"common_base/common_base.nugget">>,
        <<"grisp2_vanilla/grisp2_vanilla.nugget">>
    ]}
]}.

%% With directory defaults (e.g. SBOM)
{nugget_registry, <<"1.0">>, [
    {defaults, [
        {license, <<"Apache-2.0">>},
        {license_files, [<<"LICENSE">>]},
        {author, <<"Acme Corp">>}
    ]},
    {nuggets, [
        <<"acme_base/acme_base.nugget">>,
        <<"acme_app/acme_app.nugget">>
    ]}
]}.
```

### Nugget Metadata

Each nugget is defined by a `.nugget` file (Erlang term). The file format follows the [Erlang term file format conventions](00_OVERVIEW.md#erlang-term-file-format-conventions) defined in the [Overview](00_OVERVIEW.md).

**Root Format:** `{nugget, NuggetVersion, [MetadataField, ...]}.`

This follows the uniform `{Tag, Version, [Fields]}` convention used by all Alloy term files. The nugget identifier is a field (`id`) inside the metadata, not part of the root tuple.

**Specification:**

`NuggetVersion`: string (binary)
- Schema version of the nugget metadata format.
- Example: `<<"1.0">>`.

`MetadataField`: tuple
- One of the fields defined in the sections below. The `id` field is required; all others follow the rules of their respective sections.

**General Specifications:**

`NuggetIdentifier`: atom
- Nugget unique identifier, declared as the `id` field. Used to identify nuggets in dependencies, overrides, etc.
- Examples: `platform_imx8mp`, `common_base`
`CategoryIdentifier`: atom
- Category defined by a nugget in the dependency tree; 
- Examples: `toolchain`, `feature`
`CapabilityIdentifier`: atom
- Declared capability of a nugget;
- Examples: `secure_boot`, `disk_encryption` 
`FlavorIdentifier`: atom
- Supported flavor of a nugget; specified alongside a `NuggetIdentifier`; 
- Examples: `imx6ull`, `imx6ul`, `minimal`

**Identifier format:** All values represented by an atom that act as identifiers in nugget metadata MUST match the pattern `[a-z][a-z0-9_]*`. This applies to: nugget identifiers (`NuggetIdentifier`), category identifiers (`CategoryIdentifier`), capability identifiers (`CapabilityIdentifier`), flavor identifiers (`FlavorIdentifier`), external component identifiers (`ComponentId` in SBOM metadata), config keys and exports keys (`ConfigKey`), repository IDs in the manifest, and any other atom used as a symbolic name in the metadata or manifest. The first character must be a lowercase letter; subsequent characters may be lowercase letters, digits, or underscores. This ensures consistent naming and avoids shell or environment-variable naming issues when identifiers are used in generated context (e.g. `ALLOY_NUGGET_<NAME>_CONFIG_<KEY>`).

**General Validation:**
- A dependency tree should only contain one nugget for each category `builder`, `toolchain`, `platform` and `system`.
- Nugget identifiers referenced in the metadata must be defined by a nugget in the dependency tree.
- Category identifiers referenced in the metadata must be defined by a nugget in the dependency tree.
- Flavor identifiers referenced in the metadata must be declared by a nugget in the dependency tree.

**General Rules**:
 - All nuggets in a dependency tree must have unique identifiers.
 - Multiple nuggets depending on the same nugget will result in the dependency being placed before the first dependent in the topological order.
 - All nuggets version specifications must be compatible, if multiple nuggets depend on the same nugget, all the version specifications must be compatible.
 - All the validations, beside nugget existence and dependency cycles, are enforced after loading the full dependency tree.

#### Fields Overview

- [Generic Metadata](#generic-metadata):
  - `id`
  - `version`
  - `name`
  - `description`
  - `category`
  - `flavors`
  - `provides`
- Dependencies:
  - `depends_on`: [Dependencies](#dependencies)
  - `auxiliary_products`: [Auxiliary Products Metadata](#auxiliary-products-metadata)
- Configuration: [Nugget Configuration Metadata](#nugget-configuration-metadata)
  - `config`
  - `exports`
- Overrides: [Overrides](#overrides)
  - `overrides`
- Build integration:
  - `buildroot`: [Buildroot Integration Metadata](#buildroot-integration-metadata)
  - `hooks`: [Hooks Metadata](#hooks-metadata)
  - `embed`: [Embedding Metadata](#embedding-metadata)
  - `sdk_outputs`: [SDK Outputs Metadata](#sdk-outputs-metadata)
  - `firmware_outputs`: [Firmware Outputs Metadata](#firmware-outputs-metadata)
  - `firmware_parameters`: [Firmware Parameters Metadata](#firmware-parameters-metadata)
  - `fs_priorities`: [Filesystem Priority Metadata](#filesystem-priority-metadata)
- [SBOM & Legal Metadata](#sbom--legal-metadata):
  - `license` 
  - `license_files`
  - `author`
  - `maintainer`
  - `homepage`
  - `security_contact`
  - `external_components`

#### Nugget Categories

The nugget `category` field defines the nugget's role; exactly-one nugget is the dependency tree is allowed for some categories.

| Category    | Purpose                         | Cardinality |
|-------------|---------------------------------|-------------|
| `builder`   | SDK build backend               | Exactly one |
| `platform`  | CPU/hardware platform           | Exactly one |
| `system`    | Board/hardware integration      | Exactly one |
| `toolchain` | Cross-compilation toolchain     | Exactly one |
| `bootflow`  | Firmware assembly orchestration | Multiple    |
| `feature`   | Composable functionality        | Multiple    |

**Validation:**
 - The nugget tree loader will enforce the uniqueness in the tree in function of the category (all categories with cardinality “Exactly one” must appear exactly once).
 - **Bootflow coverage per firmware variant:** For each discovered firmware variant `V`, there MUST be exactly one nugget of category `bootflow` that participates in `V` (i.e. its `firmware_variant` list contains `V`). This ensures the SDK has a single, well-defined firmware assembly orchestrator per variant.
 - **Bootflow variant declaration:** Nuggets of category `bootflow` MUST declare `firmware_variant` (bootflows are always variant-specific; there are no variant-less bootflows).

**Notes:**
 - **product** is not a nugget category, it is the top-level nugget in a nugget dependency tree.

#### Topology Order

**Purpose:** Define the execution order used for hook invocation, defconfig fragment merging, and configuration consolidation. This order must be deterministic and consistent for the same dependency tree.

**Definition:** The **topological order** of nuggets is a total ordering such that for every nugget dependency (A depends on B), B appears before A. The **product** (top-level nugget) is last.

**Process (resolver):**

1. **Load nugget set:** Load all nuggets reachable from the motherlode (all repositories and their `.nugget` files). Validate that no two loaded nuggets share the same identifier.
2. **Build dependency tree:** Starting from the selected top nugget (the product), resolve all `depends_on` constraints. Only **nugget** constraints (`{_ConstraintType_, nugget, _}`) are used to build the tree; category and capability constraints are not used for ordering.
3. **Validate tree:** Apply all validation rules from this specification (category cardinality, capability requirements, version and flavor constraints, conflicts). Fail if any validation fails.
4. **Compute topological order:** Build a directed graph whose nodes are the nuggets in the tree and whose edges are (dependency -> dependent) for each nugget dependency. Perform a topological sort so that every dependency appears before its dependents. When multiple valid orderings exist, preserve a stable order (declaration order of `depends_on`) so the result is deterministic. The product is the last node.

**Result:** The output is an **ordered list of nugget identifiers** (atoms), in dependency order: each nugget appears after all of its nugget-dependencies, and the product is last. This list is what implementations use for defconfig merging, config consolidation, hook invocation, and file embedding.

**Rules:**

- Each nugget appears exactly once in the ordered list.
- Same dependency graph and same tie-breaking rules must yield the same order (reproducible builds).


#### Config Consolidation

**Purpose:** Produce a single configuration map (key -> value) from all nuggets' `config` and `exports`, after resolving paths, templates, flavor maps, and exec scripts. This map is what hook scripts see as environment variables (e.g. `ALLOY_CONFIG_<KEY>`, `ALLOY_NUGGET_<NAME>_CONFIG_<KEY>`) and what defconfig template substitution uses.

**Process (resolver):** The resolver performs the following steps in order. All ordering is by [topological order](#topology-order) of nuggets; within a nugget, `config` entries then `exports` entries in metadata order.

**Prerequisites and scope:**
- Target trees (main + auxiliaries) are constructed and validated first.
- Overrides are applied before consolidation, producing an overridden tree/topology and overridden effective metadata for each target.
- Consolidation then runs **once per target tree** (main and each auxiliary), using that target's overridden inputs.

1. **Initial context (optional):** The resolver may start with extra key-value pairs supplied by the system (e.g. `ALLOY_BUILD_DIR`, `ALLOY_MOTHERLODE`, `ALLOY_CACHE_DIR`). These are used for template and exec resolution and for defconfig substitution but are not part of the final list.
2. **Collect entries in topological order:** For each nugget in the **overridden** topological order, for each `config` entry then each `exports` entry, add a consolidated entry. Each entry is recorded with: key, value (possibly unresolved), declaring nugget, and whether it is from `config` (overridable) or `exports` (not overridable). For a key `foo` declared by nugget A, the resolver maintains both a **per-nugget** slot `ALLOY_NUGGET_A_CONFIG_FOO` and a **global** slot `ALLOY_CONFIG_FOO`. If a later nugget B declares the same key in its `config`, the global slot is updated (last-wins); the per-nugget slot for B is set; the per-nugget slot for A remains unchanged. **Export exclusivity:** If a key has been exported by any nugget, it is an error for another nugget to declare the same key in either `config` or `exports`. Exports reserve the key across the entire tree; they are never overridden.
3. **Use overridden effective values:** The collected values are already override-resolved for this target tree. No additional override application is performed in this resolver step.
4. **Resolve flavor maps:** For each entry whose value is `{flavor_map, [_]}`: select the branch using the **flavor of the nugget that set that entry** (the nugget that declared it, or the nugget that overrode it if the key was overridden). Replace the flavor_map with the selected value.
5. **Resolve paths:** For each entry whose value is `{path, PathSpec}`: resolve to an absolute path. Relative paths become `"${ALLOY_NUGGET_<DECLARING_NUGGET>_DIR}/PathSpec"` or equivalent; `@nugget_id/path` becomes `"${ALLOY_NUGGET_<NUGGET_ID>_DIR}/path"`; absolute paths are kept. The result is stored as the final value (or as a string suitable for environment export).
6. **Resolve computed values:** Process entries with `{computed, Template}` in the same (topological) order. Replace each `[[KEY]]` in the template with the already-resolved value of KEY plus any extra context from step 1. Keys that are not yet resolved (later computed or exec) must not be referenced; An undefined key is an error. Update the entry with the resolved string so subsequent computed entries can reference it.
7. **Resolve exec values:** Process entries with `{exec, ScriptPath}` in the same order. For each: run the script (path relative to the nugget directory) with the config key as first argument; environment contains all already-resolved config/exports as `ALLOY_CONFIG_<KEY>` and `ALLOY_NUGGET_<NAME>_CONFIG_<KEY>`, plus any extra context from step 1. Unresolved exec entries are not in the environment. Script stdout (trimmed) is the new value; exit code must be 0 or the process aborts. Scripts must be deterministic and side-effect-free (may be run multiple times).

**Key conflict rules** (summary of all cases):

| Situation | Severity | Behavior |
|-----------|----------|----------|
| Same key appears multiple times within one nugget's `config` or `exports` list | Warning | Last occurrence wins (probably a mistake). |
| Same key in both `config` and `exports` of the *same* nugget | Error | Ambiguous intent - the nugget author must choose one. |
| Same key in the `config` of multiple nuggets | Allowed | Last-wins by topological order for the global slot; each nugget keeps its own per-nugget slot unchanged. |
| Same key in the `exports` of multiple nuggets | Error | Exports are authoritative; two sources of truth for the same fact is a conflict. |
| A key exported by one nugget appears in another nugget's `config` | Error | An export reserves the key across the entire tree. No other nugget may redeclare it (even as `config`), because last-wins would silently shadow the exported value in the global slot, defeating the export guarantee. |
| An `overrides` entry targets a key from `exports` | Error | Exports are not overridable (see [Overrides Metadata](#overrides-metadata)). |

**Example:**

- **Setup (topological order):**
  - Nugget `platform_imx6`:
    ```erlang
    {config, [
        {device_tree, {path, <<"dts/imx6ull.dts">>}}
    ]}
    ```
  - Nugget `system_grisp2`:
    ```erlang
    {config, [
        {rootfs_overlay, {path, <<"rootfs_overlay">>}}
    ]}
    ```
- **After consolidation:**
    ```ini
    ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_DEVICE_TREE="${ALLOY_NUGGET_PLATFORM_IMX6_DIR}/dts/imx6ull.dts"
    ALLOY_CONFIG_DEVICE_TREE="${ALLOY_NUGGET_PLATFORM_IMX6_DIR}/dts/imx6ull.dts"
    ALLOY_NUGGET_SYSTEM_GRISP2_CONFIG_ROOTFS_OVERLAY="${ALLOY_NUGGET_SYSTEM_GRISP2_DIR}/rootfs_overlay"
    ALLOY_CONFIG_ROOTFS_OVERLAY="${ALLOY_NUGGET_SYSTEM_GRISP2_DIR}/rootfs_overlay"
    ```

**Example: Mix of config and exports**

Last-wins for global `kernel_version`; export `target_arch` is set only by platform_imx6.

- **Setup (topological order):**
  - Nugget `platform_imx6`:
    ```erlang
    {exports, [
        {target_arch, arm}
    ]},
    {config, [
        {debug_level, 0},
        {kernel_version, <<"5.10">>}
    ]}
    ```
  - Nugget `system_grisp2`:
    ```erlang
    {config, [
        {kernel_version, <<"5.15">>}
    ]},
    {overrides, [
        {config, debug_level, 2}
    ]}
    ```
 
- **After consolidation:**
  ```ini
  ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_TARGET_ARCH=arm
  ALLOY_CONFIG_TARGET_ARCH=arm
  ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_LOG_LEVEL=2
  ALLOY_NUGGET_PLATFORM_IMX6_CONFIG_KERNEL_VERSION=5.10
  ALLOY_NUGGET_SYSTEM_GRISP2_CONFIG_LOG_LEVEL=2
  ALLOY_CONFIG_LOG_LEVEL=2
  ALLOY_NUGGET_SYSTEM_GRISP2_CONFIG_KERNEL_VERSION=5.15
  ALLOY_CONFIG_KERNEL_VERSION=5.15
  ```

#### Buildroot Defconfig generation

**Purpose:** Produce a single Buildroot defconfig file by merging each nugget's defconfig fragment in [topological order](#topology-order), with template substitution and cumulative key handling.

**Inputs:** Per nugget, the path to the defconfig fragment from metadata. Fragment content is Buildroot defconfig format (key=value lines; comments allowed). Any line may contain `[[KEY]]` markers; keys are resolved from the [consolidated configuration](#config-consolidation) (and any extra config supplied to the resolver). Substitution is applied **before** parsing key-value pairs and may appear in both key and value; it is single-pass (non-recursive). Unresolved marker are errors.

**Process (resolver):**

1. **Per-nugget fragment path:** For each nugget in topological order: if `defconfig_fragment` is a path, use it; if it is `{flavor_map, [{Flavor, Path}, ...]}`, select the path for that nugget's resolved flavor. Load the fragment file content.
2. **Template expansion:** In each fragment's raw content, replace every `[[KEY]]` with the value of KEY from the consolidated config (or from extra config, e.g. `ALLOY_BUILD_DIR`, `ALLOY_MOTHERLODE`). Result is the expanded fragment text.
3. **Parse:** Parse the expanded text into key-value pairs (and comments). Preserve comments for the final file.
4. **Cumulative keys:** Define the set of **cumulative keys** (e.g. `BR2_ROOTFS_OVERLAY`, `BR2_ROOTFS_POST_BUILD_SCRIPT`, `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`, `BR2_BUSYBOX_CONFIG_FRAGMENT_FILES`, `BR2_GLOBAL_PATCH_DIR`). For these, the resolver **accumulates** values across all fragments in topological order: each fragment may contribute zero or more space-separated values; all are collected into one list per key. Cumulative keys are either **path-valued** or **plain-valued**; the resolver must know which is which (defined in its cumulative-keys specification - see [Smelterl Design](02_SMELTERL_DESIGN.md#411-generating-defconfig)). Only path-valued cumulative keys undergo relative-to-absolute conversion (relative paths become `"${ALLOY_MOTHERLODE}/<nugget_relative_path>/<value>"`); plain-valued cumulative keys are accumulated as-is.
5. **Regular keys:** For keys not in the cumulative set, **last-wins**: the last nugget that sets the key in topological order determines the final value. Paths in values are resolved to absolute as needed.
6. **Emit defconfig:** Write the final defconfig:
  1. optional comment header listing nuggets (identifier and version);
  2. for each nugget in order, emit key-value lines from its fragment for keys that are not overridden by a later nugget (overridden keys may be emitted as commented lines with a note);
  3. emit all cumulative keys as single lines with space-separated accumulated values, with an optional comment listing which nuggets contributed.

**Example:**

- **Input fragment - `platform_imx6`:**
  ```ini
  BR2_ARM_EABIHF=y
  BR2_LINUX_KERNEL=y
  BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="linux.defconfig.fragment"
  BR2_ROOTFS_OVERLAY="rootfs_overlay"
  ```

- **Input fragment - `system_grisp2`:**
  ```ini
  BR2_PACKAGE_ERLANG=y
  BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="linux.defconfig.fragment"
  BR2_ROOTFS_OVERLAY="rootfs_overlay"
  ```

- **Output (merged defconfig):**
  ```ini
  # Generated from nugget fragments (topological order)
  # Nuggets:
  # - platform_imx6: 1.1.0
  # - system_grisp2: 2.1.3

  # From: platform_imx6
  BR2_ARM_EABIHF=y
  BR2_LINUX_KERNEL=y

  # From: system_grisp2
  BR2_PACKAGE_ERLANG=y

  # Merged from: platform_imx6, system_grisp2
  BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="${ALLOY_MOTHERLODE}/builtin/platform_imx6/linux.defconfig.fragment ${ALLOY_MOTHERLODE}/builtin/system_grisp2/linux.defconfig.fragment"
  # Merged from: platform_imx6, system_grisp2
  BR2_ROOTFS_OVERLAY="${ALLOY_MOTHERLODE}/builtin/platform_imx6/rootfs_overlay ${ALLOY_MOTHERLODE}/builtin/system_grisp2/rootfs_overlay"
  ```

#### SDK Embedding

**Purpose:** Define how nuggets and Buildroot artefacts are copied into the SDK so it is self-contained and relocatable. Only explicitly declared entries (via `embed`) and auto-embedded files (see [Embedding Metadata](#embedding-metadata)) are included.

**Sources and targets:** Each `embed` entry has a **source type** and a **path/glob** reative to the source:

- **`images`:** Source = Buildroot output `workspace/images/`. Target = SDK `images/` preserving relative structure.
- **`host`:** Source = Buildroot output `workspace/host/`. Target = SDK `host/` preserving relative structure. 
- **`nugget`:** Source = this nugget's directory in the motherlode. Target = SDK `motherlode/<REPO>/<NUGGET_ID>/` preserving the motherlode directory structure so that `alloy_context.sh` paths remain valid in SDK mode.

**Dynamic dependencies:** For every embedded ELF file (binary or shared library), the embedder must run `ldd` and recursively embed all shared libraries that lie inside the same source; system libraries (outside the tree) are not embedded. This ensures host tools run without depending on the build machine's system libs. Embedded ELF files undergo RPATH verification at pack time to ensure `$ORIGIN`-relative library resolution - see [Relocatability](#relocatability) below.

**Symlinks:** For relocatability, symlinks must not point to absolute paths that break when the SDK is moved. Rules: (1) When the symlink target is **inside** the allowed source tree (same images/, host/, or nugget dir), embed the symlink **and** the target; convert the symlink to a **relative** path (from symlink location to target). (2) When the symlink target is **outside** the allowed tree, the embedder must **fail** with a clear error (external dependencies are not allowed).

**Processing order:** Embed lists are processed in [topological order](#topology-order) of nuggets. For each entry, resolve the path or glob, then for each file: copy (or symlink with relative target), and for host ELF files run ldd and embed workspace-internal libraries; follow symlink chains and convert to relative; detect circular symlinks and fail. Duplicate files (same realpath) are emitted once.

##### Relocatability

Buildroot compiles host tools against a specific `HOST_DIR` (e.g. `/home/user/build/workspace/host`). Several types of absolute paths get baked in:

1. **ELF RPATH** - Dynamic library search paths embedded in ELF binary headers (e.g. `RPATH: /home/user/.../host/usr/lib`). When the SDK is moved, absolute RPATHs point to a nonexistent directory. `LD_LIBRARY_PATH` can override RPATH at runtime but is fragile (affects all child processes, ignored by setuid programs, can conflict with system libs).
2. **Text-based paths** - Libtool `.la` files (`libdir='/original/path'`), pkg-config `.pc` files (`prefix=/original/path`), GCC specs/internal paths, shell wrapper scripts, and Erlang boot configuration may all contain the original build path. `LD_LIBRARY_PATH` does nothing for these.
3. **Cross-compilation toolchain internals** - GCC has default sysroot, include, and library paths compiled into the binary. However, since `env_utils.sh` explicitly passes `--sysroot`, `-I`, and `-L` flags, hardcoded defaults are overridden at use time, mitigating most toolchain issues.

**Important distinction - RPATH vs interpreter:** The ELF `$ORIGIN` token (used in RPATH) is resolved by the **dynamic linker** (`ld-linux`) at runtime. It is NOT resolved by the **kernel**. This means `$ORIGIN` works in `DT_RPATH`/`DT_RUNPATH` entries but does NOT work in `PT_INTERP` (the ELF interpreter/dynamic linker path). This is not a problem for the SDK because host tools use the system's standard dynamic linker (e.g. `/lib64/ld-linux-x86-64.so.2`), which is always at a well-known path. Buildroot does not build a host glibc; host tools are compiled with the host's native compiler and link against the host's system libraries. The SDK never modifies `PT_INTERP`.

**Strategy:** The SDK uses a two-phase approach to achieve full relocatability. Both phases cover **all** embedded source trees (`host/`, `images/`, `motherlode/`), not just host tools - any nugget may embed its own binaries, libraries, or scripts that contain build-machine paths.

**Phase 1 - ELF RPATH verification and fixup at pack time (permanent, zero runtime cost):**

Buildroot already relativizes RPATHs during its `host-finalize` step: the `fix-rpath` script runs `patchelf --make-rpath-relative ${HOST_DIR} --relative-to-file` on **all** host ELF files (both executables and shared libraries), converting absolute RPATHs to `$ORIGIN`-relative paths. `$ORIGIN` is an ELF token resolved by the dynamic linker at runtime to the directory containing the ELF file, making library resolution work regardless of SDK location.

Since our SDK embedding preserves the `host/` directory structure, these relative RPATHs remain valid for Buildroot-built host tools. However, nuggets may also embed their own ELF binaries or shared libraries (e.g. custom tools, prebuilt plugins). These are not processed by Buildroot's `fix-rpath` and may have absolute or incorrect RPATHs.

At pack time, the Alloy packer performs a **verification and fixup pass** on all embedded ELF files across the entire SDK tree:

1. **Scan** all ELF files in the embedded SDK (`sdk/host/`, `sdk/images/`, `sdk/motherlode/`).
2. **Verify** that each file's RPATH contains only `$ORIGIN`-relative entries (no absolute paths). This catches: files missed by Buildroot's `fix-rpath`, nugget-embedded binaries that were never processed by Buildroot, or files whose relative position changed during selective embedding.
3. **Fix** any remaining absolute RPATHs using `patchelf --make-rpath-relative` or `patchelf --set-rpath` with a computed `$ORIGIN`-relative path.
4. **Log** all changes for debugging and verification.

**Technical notes on `$ORIGIN` in RPATH:**
- `$ORIGIN` resolves to the directory of the ELF object that contains it. For a shared library, it resolves to the library's own directory, not the executable's directory. This means both binaries and shared libraries can independently locate their dependencies.
- **`DT_RPATH` vs `DT_RUNPATH`:** `DT_RPATH` supports transitive dependency resolution (if `libA.so` loads `libB.so`, the dynamic linker checks `libA.so`'s RPATH to find `libB.so`). `DT_RUNPATH` does NOT - it only applies to direct dependencies. Buildroot's `fix-rpath` script patches ALL ELF files (executables and shared libraries alike), so each library has its own `$ORIGIN`-relative path, making the choice of `DT_RPATH` vs `DT_RUNPATH` less critical. The verification pass ensures this property is maintained after embedding.
- **`dlopen()` caveat:** Tools that use `dlopen()` to load plugins at runtime depend on RPATH entries even though the loaded library is not listed in `DT_NEEDED`. The verification pass must NOT use `--shrink-rpath` (which removes RPATH entries that don't match `DT_NEEDED` dependencies), as this would break dynamic loading.
- **Symlinks:** On Linux with glibc, `$ORIGIN` is resolved from the real path of the ELF file (symlinks are resolved via `/proc/self/exe` for executables). Since the SDK uses relative symlinks, this works correctly.
- **`patchelf` is a build-time dependency only.** It is not needed on the machine that uses the SDK.

**Phase 2 - Text-based path sanitization at pack time and fixup at first use:**

Embedded files from different source trees may contain absolute paths from the build machine. Each source tree has a different build-machine path and a different destination in the SDK:

| Source tree (build machine) | SDK destination | Example build path |
|---|---|---|
| `${BUILD_HOST_DIR}` (Buildroot host) | `sdk/host/` | `/home/user/build/workspace/host/usr/lib/` |
| `${BUILD_IMAGES_DIR}` (Buildroot images) | `sdk/images/` | `/home/user/build/workspace/images/` |
| `${MOTHERLODE}/<repo>/<nugget_id>/` (per nugget) | `sdk/motherlode/<repo>/<nugget_id>/` | `/home/user/build/motherlode/acme_repo/acme_app/` |

The packer performs path sanitization at pack time, replacing all build-machine paths with a single canonical placeholder. The orchestrator completes the fixup on first use.

**Pack-time (sanitization):**

1. **Build the prefix map.** Collect all source-to-destination prefix mappings from the embedding step:
   - `BUILD_HOST_DIR` -> `@@ALLOY_SDK_DIR@@/host`
   - `BUILD_IMAGES_DIR`-> `@@ALLOY_SDK_DIR@@/images`
   - For each embedded nugget: `MOTHERLODE/<repo>/<nugget_id>` -> `@@ALLOY_SDK_DIR@@/motherlode/<repo>/<nugget_id>`
2. **Scan and replace.** For every embedded text file across all SDK subtrees, scan for occurrences of any build-machine prefix in the map. Replace each occurrence with its corresponding `@@ALLOY_SDK_DIR@@/...` destination. This rewrites the path structure to match the SDK layout while substituting the SDK root with the placeholder.
3. **Generate relocation manifest.** Write the list of files that were modified (relative to the SDK root) to `sdk/.alloy_relocation_manifest`. These are the files that contain `@@ALLOY_SDK_DIR@@` and will need fixup at first use.
4. **Write placeholder to `.alloy_sdk_dir`.** Write the string `@@ALLOY_SDK_DIR@@` to `sdk/.alloy_sdk_dir`. This file is used by the orchestrator at first use to detect that the SDK needs fixup.

**First-use (fixup):**
- On first use, the orchestrator reads `.alloy_sdk_dir` (which contains the placeholder `@@ALLOY_SDK_DIR@@`) and compares it to the actual SDK root directory path. Since they will never match, the relocation always triggers on first use:
  - **SDK is writable:** The fixup runs transparently, logging `"Relocating SDK to <path>..."`. The relocation script (`sdk_utils.sh::relocate_sdk`) replaces `@@ALLOY_SDK_DIR@@` with the actual SDK root path in all files listed in the relocation manifest. After fixup, `.alloy_sdk_dir` is updated to the real current path so the fixup does not run again.
  - **SDK is not writable:** The orchestrator aborts with a clear error directing the user to run `alloy prepare sdk` (or `sudo alloy prepare sdk` for system-wide installs).
- The `alloy prepare sdk` command (SDK mode only) triggers the same relocation explicitly, for cases where the SDK must be prepared by an administrator before use.
- This is similar to Buildroot's own `relocate-sdk.sh` mechanism but is integrated into the `alloy` orchestrator and scoped to the files actually embedded.

**Why a single placeholder works:** At pack time, the prefix map rewrites each source path to its correct SDK-relative destination (e.g. `BUILD_HOST_DIR/usr/lib/foo.la` becomes `@@ALLOY_SDK_DIR@@/host/usr/lib/foo.la`). The SDK's internal directory structure is already baked in - it never changes after packing. Only the SDK root itself is unknown until first use, which is what the placeholder represents. At first use, a single `sed` replacement of `@@ALLOY_SDK_DIR@@` with the real SDK root completes the fixup.

**Privacy:** The real build path from the build machine is never present in the distributed SDK. The placeholder `@@ALLOY_SDK_DIR@@` is a well-known, fixed string that carries no information about the builder's environment. Phase 1 (ELF RPATHs) uses `$ORIGIN`-relative paths which also carry no build-machine information.

**Build dependency:** `patchelf` is required at SDK **build time** for Phase 1 ELF RPATH verification/fixup. It is NOT required on the machine that uses the SDK.

**Outcome:** The SDK is fully relocatable and contains no trace of the builder's filesystem. ELF binaries use `$ORIGIN`-relative RPATHs (permanent, zero-cost). Text-based paths contain a single placeholder (`@@ALLOY_SDK_DIR@@`) that is replaced with the real SDK root path automatically on first use (or explicitly via `alloy prepare sdk`). The ELF interpreter (`PT_INTERP`) is not modified - host tools use the system's standard dynamic linker. No fixed install path is required, and `LD_LIBRARY_PATH` is not needed for normal SDK operation.

#### Generic Metadata

**Purpose:** Identify the nugget and declare its version, description, category, and optional flavors.

**Formats:**
- `{id, NuggetIdentifier}`: required
- `{version, NuggetVersion}`: optional
- `{name, NuggetName}`: optional
- `{description, NuggetDescription}`: optional
- `{category, NuggetCategory}`: required
- `{flavors, FlavorsList}`: optional
- `{provides, CapabilityList}`: optional

**Specification:**

`NuggetIdentifier`: atom
- Unique identifier for this nugget. Used to reference the nugget in dependencies, overrides, and all other cross-references.
- Must match the pattern `[a-z][a-z0-9_]*` (see [identifier format](#identifier-format) above).
- Examples: `platform_imx8mp`, `common_base`, `bootflow_imx8_fit_plain`.

`NuggetVersion`: string (binary)
- Semantic version of the nugget (e.g. for display and constraints).
- Example: `<<"1.2.3">>`.

`NuggetName`: string (binary)
- Human-readable name of the nugget.
- Example: <<"NXP iMX8 Platform">>

`NuggetDescription`: string (binary)
- Human-readable description of the nugget.
- Example: <<"Add support for the NXP iMX8 Platform">>

`NuggetCategory`: atom
- Classification of the nugget; determines uniqueness and validation rules; see [Nugget Categories](#nugget-categories).
- one of:
  - `builder`
  - `platform`
  - `system`
  - `toolchain`
  - `bootflow`
  - `feature`

`FlavorsList`: list of `FlavorIdentifier`
- Defines the qualifiers (flavors) supported by the nugget, expressing subtle configuration differences
- Example: `[imx6ull, imx6ul]` (SoC selection), `[minimal, full]` (feature set)

`CapabilityList`: list of `CapabilityIdentifier`
- List of capabilities provided by this nugget.
- Used for dependency validation (e.g. `{required, capability, secure_boot}`). SDK-level reporting of available features is handled generically by the `firmware_variants` list (see [Manifest Capabilities](#manifest-capabilities)), not by per-capability boolean flags. Selectable firmware outputs are declared via the `firmware_outputs` metadata with `{selectable, true}`, not via capability prefixes. See [Firmware Outputs Metadata](#firmware-outputs-metadata).

**Validation:**
- The `id` and `category` fields are required for every nugget.
- The `id` must be unique across all loaded nuggets.
- When a dependent nugget specifies `{flavor, F}` in its `depends_on` specification, `F` must exists in the dependency nugget list of flavors.
- There must be only one instance of a nugget with category `builder`, `platform`, `system`, `toolchain` per dependency tree.

**Rules:**
- Capabilities should be functional (what the nugget does), not taxonomic.
- At least one nugget in the tree must provide each capability required by dependencies.

#### Dependencies Metadata

**Purpose:** Declare dependencies and constraints; only `nugget` dependencies affect execution order; `category` and `capability` are validation-only.

**Format:** `{depends_on, [ConstraintSpec]}`

**Specification:**

`ConstraintSpec`: `{ConstraintType, ConstraintTarget, ConstraintValue}`
- Defines a dependency constraint.

`ConstraintType`: atom
- Semantics of the dependency; determines how `ConstraintValue` is interpreted.
- one of:
  - `required`: all listed targets must be present (AND).
  - `optional`: use if available; missing is not an error.
  - `one_of`: exactly one of the list must be present (XOR).
  - `any_of`: at least one of the list must be present (OR).
  - `conflicts_with`: the nugget must not coexist with the given target.

`ConstraintTarget`: atom
- Kind of dependency; determines how `ConstraintValue` is interpreted and whether it affects topological order.
- one of:
  - `nugget`: dependency on a specific nugget by name; affects topological order.
  - `category`: validation only; exactly one nugget of this category must exist in the tree.
  - `capability`: validation only; at least one nugget providing this capability must exist in the tree.

`ConstraintValue`:
- When `ConstraintTarget` is `category` and `ConstraintType` is `one_of` or `any_of`: list of `CategoryIdentifier`
- When `ConstraintTarget` is `category`: `CategoryIdentifier`
- When `ConstraintTarget` is `capability` and `ConstraintType` is `one_of` or `any_of`: list of `CapabilityIdentifier`
- When `ConstraintTarget` is `capability`: `CapabilityIdentifier`
- When `ConstraintTarget` is `nugget` and `ConstraintType` is `one_of` or `any_of`: list of `NuggetDependencySpec`
- When `ConstraintTarget` is `nugget`: `NuggetDependencySpec`

`NuggetDependencySpec`:
- Define the constraints of the nugget dependency.
- one of:
  - `NuggetIdentifier`: Only depends on another nugget, without version enforcement or flavor selection.
  - `{NuggetIdentifier, VersionConstraint}`: Depends on another nugget with a specific version constrain.
  - `{NuggetIdentifier, NuggetConstraintProps}`: Depends on another nugget with a list of constraint properties.

`NuggetConstraintProps`: list of tuples
- Defines additional constraints for the nugget dependency.
- list of any of:
  - `{version, VersionConstraint}`: The dependency version should satisfy the version constraint.
  - `{flavor, FlavorIdentifier}`: The dependency should use the requested flavor.

`VersionConstraint`: string (binary)
- Version constraint (rebar3-like); resolved nugget version must satisfy it.
- Examples: `<<"1.2.3">>`, `<<"~> 2.1.2">>`

**Validation:**
- Nuggets, flavors, categories and capability identifiers must exists in the dependency tree.
- If a nugget version is specified, the resolved nugget’s version must satisfy the version specification.
- If a nugget flavor is specified, the target nugget must declare that flavor in its `flavors` list; all dependencies referencing the same nugget must agree on flavor (or all omit).

**Rules:**
- Each nugget appears exactly once in the dependency tree; topological order is determined only by `{ConstraintType, nugget, ...}`; category and capability dependencies do not affect topological order.

**Examples:**

```erlang
{depends_on, [
    {required, capability, toolchain},
    {required, category, builder},
    {required, nugget, toolchain_ctng},
    {required, nugget, {platform_imx6, [{flavor, imx6ull}]}},
    {required, nugget, {common_base, <<"~> 1.0">>}},
    {required, nugget, {system_grisp2, [{version, <<">= 1.2.0">>}, {flavor, minimal}]}},
    {optional, nugget, feature_debug},
    {one_of, nugget, [bootflow_grisp2_plain, bootflow_grisp2_signed]},
    {conflicts_with, nugget, other_nugget}
]}.
```

#### Auxiliary Products Metadata

**Purpose:** Declare auxiliary SDK build targets required by this nugget. Auxiliary targets are planned and built before the main target and may be consumed by the main target through `sdk_outputs`.

**Format:** `{auxiliary_products, [AuxiliaryTargetSpec]}`

**Specification:**

`AuxiliaryTargetSpec`:
- one of:
  - `AuxRootNugget` (shorthand for `{AuxRootNugget, AuxRootNugget}`)
  - `{AuxId, AuxRootNugget}`
  - `{AuxId, AuxRootNugget, VersionConstraint}`
  - `{AuxId, AuxRootNugget, [AuxiliaryConstraintProp, ...]}`

`AuxiliaryConstraintProp`:
- one of:
  - `{version, VersionConstraint}`
  - `{flavor, FlavorIdentifier}`

**Rules:**
- `AuxId` identifies the auxiliary target instance and is used by scoped overrides and target selection.
- `AuxId` must be globally unique across the resolved auxiliary target set (union of all `auxiliary_products` entries declared in the main effective tree).
- `AuxId` must not be `main` or `all` (reserved scope selectors).
- The same `AuxRootNugget` may appear multiple times with different `AuxId` values.

**Validation:**
- Root nugget must exist and satisfy optional version/flavor constraints.
- Auxiliary effective trees are composed from (a) an auxiliary-specific subtree rooted at `AuxRootNugget` and (b) the main-tree backbone (`builder`, `toolchain`, `platform`, `system` plus their transitive nugget dependencies).
- Category restrictions apply to the auxiliary-specific subtree: it must not introduce `builder`, `toolchain`, `platform`, `system`, or `bootflow`.
- Shared nuggets between main and auxiliary trees must resolve to identical flavor (or both unspecified).

**Example:**

```erlang
{auxiliary_products, [
    {plain_initramfs, auxiliary_initramfs, [{flavor, plain}]},
    {encrypted_initramfs, auxiliary_initramfs, [{flavor, encrypted}]}
]}.
```

#### Nugget Configuration Metadata

**Purpose:** Defines the configuration available to the hook scripts, and if it can be overriden by other nuggets; `config` key-value are used by the nugget and can be overriden, while `exports` key-values are provided by the nugget and cannot be overriden.

**Formats:**
- `{config, [ConfigEntry]}`
- `{exports, [ConfigEntry]}`

**Specification:**

`ConfigEntry`: `{ConfigKey, ConfigValue}`
- One key-value pair defining configuration available to hooks.

`ConfigKey`: atom
- Symbolic name of the setting.
- Example: `init_system`, `rootfs_overlay`, `kernel_version`

`ConfigValue`:
- any of:
  - **Plain**: binary, atom, or integer; used as-is after consolidation.
  - **Path** - `{path, PathSpec}`: resolved to an absolut path.
  - **Computed** - `{computed, Template}`: template string with markers `[[VAR]]` resolved during consolidation; result is string (binary).
- **Exec:** `{exec, ScriptPath}` - script path relative to nugget directory; run during consolidation; stdout (as binary) is the value.
- **Flavor-dependent:** `{flavor_map, [{FlavorIdentifier, ConfigValue}]}` - resolved by selecting one entry according to the nugget's flavor; value is the selected `ConfigValue` (recursive).

`PathSpec`: string (binary)
- Defines how a path is resolved to an absolute form.
- any of:
  - **Absolute Path**: kept as-is; e.g. `<<"/opt/foo/bar">>`
  - **Relative Path**: converted to an absolute path; may contain bash variables that evaluate to an absolute path.
    - Example: `<<"scripts/foo.sh">>` -> `<<"${ALLOY_MOTHERLODE}/acme_nuggets/my_nugget/scripts/foo.sh">>`
  - **Other-nugget relative path** (`@NuggetIdentifier/path`): Reference another nugget by identifier; converted to an absolute path; may contain bash variables.
    - Example: `<<"@platform_imx6/dts/imx6.dts">>` -> `<<"${ALLOY_MOTHERLODE}/builtin/platform_imx6/dts/imx6.dts">>`

`Template`: string (binary)
- String containing placeholders `[[VAR]]`; each is replaced by the consolidated value of that key.
- Example: `<<"http://example.com/packages/[[ALLOY_CONFIG_KERNEL_VERSION]].tar.gz">>`

`ScriptPath`: string (binary)
- Path to executable script relative to nugget directory. Executed during consolidation; stdout captured as value.
- Example: `<<"scripts/value-generator.sh">>`

**Validation:**
- `ScriptPath` must exist.
- All substitution keys in `Template` must be defined and already resolved.
- The referenced nugget in a path value must exist in the dependency tree.
- Within one nugget, the same key must not appear in both `config` and `exports`.
- Across the tree, two nuggets cannot export the same key.
- Across the tree, a key exported by one nugget cannot appear in another nugget's `config` (exports reserve the key globally; see [Key conflict rules](#key-conflict-rules) in Config Consolidation).

**Rules:**
- The script called for the `exec` values exit code must be 0.
- The script called for the `exec` values must receive the configuration key as parameter.
- The script called for the `exec` values must receive all the already resolved configuration in its environment.
- If the same key is declared multiple times in a `config` or `exports` declaration, the last one wins; the resolver may issue a warning as it is probably a mistake.

##### Export Key Naming Convention

Export keys follow a naming convention that distinguishes **value exports** from **callable function exports** (scripts intended to be invoked by other nuggets' hooks):

| Prefix | Meaning | Example | Shell Variable |
|--------|---------|---------|----------------|
| (none) | Value export - configuration data, paths, version strings. | `target_arch_triplet` | `ALLOY_CONFIG_TARGET_ARCH_TRIPLET` |
| `fun_` | Function export - path to a callable script that another nugget's hook can invoke. | `fun_build_uboot_fit` | `ALLOY_CONFIG_FUN_BUILD_UBOOT_FIT` |

The value of a `fun_` export MUST be a `{path, PathSpec}` pointing to an executable script. For function export rules, inter-category contracts, availability checking patterns, and the list of defined contracts, see [Alloy Design - Function Export Convention and Contracts](03_ALLOY_DESIGN.md#68-function-export-convention-and-contracts).

**Examples:**

```erlang
% config: overridable key-value settings (plain, path, computed, exec, flavor_map)
{config, [
    {init_system, erlinit},
    {debug_level, 2},
    {package_version, <<"1.2.3">>},
    {rootfs_overlay, {path, <<"rootfs_overlay">>}},
    {kernel_url, {computed, <<"http://example.com/[[ALLOY_CONFIG_KERNEL_VERSION]].tgz">>}},
    {custom_value, {exec, <<"scripts/value-generator.sh">>}},
    {board_type, {flavor_map, [
        {imx6ull, imx6ull_board},
        {imx8mp, imx8mp-evk}
    ]}}
]},

% exports: read-only, not overridable (same value types)
% Value exports use plain names; function exports use fun_ prefix
{exports, [
    {target_arch, arm},
    {target_arch_triplet, <<"arm-buildroot-linux-gnueabihf">>},
    {sysroot, {path, <<"@platform_imx6/sysroot">>}},
    {toolchain_package, {computed, <<"[[ALLOY_CACHE_DIR]]/toolchain/source.tgz">>}},
    {fun_build_uboot_fit, {path, <<"scripts/build-uboot-fit.sh">>}},     % fun_ = callable
    {fun_assemble_boot_image, {path, <<"scripts/assemble-boot-image.sh">>}},
    {device_tree, {flavor_map, [
        {imx6ull, {path, <<"dts/imx6ull.dts">>}},
        {imx8ul, {path, <<"dts/imx6ul.dts">>}}
    ]}}
]}.
```

#### Overrides Metadata

**Purpose:** Customize dependency tree and configuration without modifying original nuggets (e.g. swap builder or set config from product).

**Format:** `{overrides, [OverrideSpec]}`

**Specification:**

`OverrideSpec`: tuple
- one of:
  - `{nugget, TargetNugget, ReplacementNugget}`: nugget override; replacement takes the exact position of the target in execution order.
  - `{auxiliary_product, TargetAuxId, ReplacementAuxId}`: auxiliary target remap; replace one planned auxiliary target ID with another before auxiliary tree construction.
  - `{config, ConfigKey, ConfigValue}`: config override for the current target tree.
  - `{config, Scope, ConfigKey, ConfigValue}`: scoped config override where `Scope = main | all | AuxId`.
  
`TargetNugget`: `NuggetIdentifier`
- Nugget identifier of the nugget to replace. Must exist in the dependency tree.

`ReplacementNugget`: `NuggetIdentifier`
- Nugget identifier of the nugget that replaces the target. Must be loadable and its dependencies satisfied before the target’s position in execution order.

`ConfigKey`: atom
- Key declared in some nugget’s `config` (not in `exports`). Only keys from `config` can be overridden.

`Scope`: atom
- one of `main`, `all`, or an auxiliary target ID (`AuxId`).

**Validation:**
- Target of a nugget override must exist in the tree; replacement nugget must be loadable and its dependencies satisfied before the target’s position, it cannot introduce new dependencies, and the version and flavor constraints must be satisfied.
- Config override key must be declared by some nugget in its `config`; keys from `exports` cannot be overridden.
- For scoped config overrides, `main` and `all` are reserved scope values; any other scope must match a declared `AuxId`.
- When multiple config overrides match one target tree, they are applied in declaration order; last matching value wins.

**Notes:**
- **Declaring** a key in `config` (including when another nugget already declares the same key): the nugget signals that it uses the key and allows other nuggets to change its behavior; last-wins applies during consolidation. There is no requirement that another nugget declared the key first.
- **Overriding** a key in `overrides`: the nugget sets the effective value for that key for all the nuggets in the tree (global and per-nugget). The key must already be declared by some nugget’s `config`. Validation enforces that the key exists and that no nugget has it in `exports`. The semantic is “customize this key for the build; everyone sees the overridden value.”

**Examples:**

```erlang
{overrides, [
    {nugget, builder_buildroot, my_builder_custom},
    {config, all, debug_level, 2},
    {config, main, image_output_pattern, <<"firmware-main.img">>},
    {config, encrypted_initramfs, disk_encryption, true},
    {config, kernel_repository, {computed, <<"git://example.com/kernel_[[ALLOY_CONFIG_KERNEL_VERSION]]">>}},
    % Script path is relative to the nugget applying the override
    {config, custom_value, {exec, <<"scripts/generate-config.sh">>}},
]}.
```

#### Buildroot Integration Metadata

**Purpose:** Specify Buildroot-specific files: defconfig fragment and optional custom packages directory.

**Format:** `{buildroot, [BuildrootSpec]}`

**Specification:**

`BuildrootSpec`: tuple
- any of:
  - `{defconfig_fragment, DefconfigFragmentPath}`: Buildroot defconfig fragment for this nugget.
  - `{packages, Path}`: directory of custom Buildroot packages; Path is relative to the nugget directory.

`DefconfigFragmentPath`: string (binary)
- one of:
  - **relative path**: Path to a buildroot defconfig fragment relative to nugget directory.
  - **Flavor map** -  `{flavor_map, [{FlavorIdentifier, Path}]}`: flavor selects which fragment path to use; each `Path` is relative to nugget directory.

**Validation:**
- Referenced files and directories must exist at generation time.

**Rules:**
- All paths are relative to the nugget directory. Overlays, kernel/busybox fragments, patches are referenced via cumulative keys inside the defconfig fragment (e.g. `BR2_ROOTFS_OVERLAY`, `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`); relative paths in those keys are resolved to absolute by the generator.

**Examples:**

```erlang
{buildroot, [
    {defconfig_fragment, <<"buildroot.defconfig.fragment">>},
    {packages, <<"packages/">>}
]}.
```

#### Hooks Metadata

**Purpose:** Scripts executed at various build stages; paths are relative to nugget directory.

**Format:** `{hooks, [HookSpec]}`

**Specification:**

`HookSpec`:
- one of:
  - `{HookType, ScriptPath}` (defaults to scope `main`)
  - `{HookType, ScriptPath, Scope}`

`HookType`: atom
- Build stage at which the script runs.
- one of:
  - `pre_build`: before main Buildroot build; called by the build orchestrator.
  - `post_build`: after Buildroot build, before image assembly; called by Buildroot.
  - `post_image`: after image assembly; called by Buildroot.
  - `post_fakeroot`: after fakeroot run (if used); called by Buildroot.
  - `pre_firmware`: before firmware assembly; called by the build orchestrator. Used for rootfs merging, dm-verity, encryption, initramfs preparation.
  - `firmware_build`: firmware assembly step; called by the build orchestrator. Variant-filtered: only hooks relevant to the selected variant run (see [Firmware Variant Metadata](#firmware-variant-metadata)). See [Alloy Design - Firmware Build Flow](03_ALLOY_DESIGN.md#57-firmware-build-flow) for how this hook type is used.
  - `post_firmware`: after firmware assembly; called by the build orchestrator. Used for firmware packaging (fwup, raw image, RAUC).

`ScriptPath`: string (binary)
- Path to the script relative to nugget directory. Receives the configuration as environment.

`Scope`: atom
- one of:
  - `main`
  - `auxiliary`
  - `all`
  - `<AuxId>` (specific auxiliary target)

**Validation:**
- Script paths must exist.
- `<AuxId>` scope is valid only for SDK-time hooks and must match a declared auxiliary target ID.
- Firmware-time hooks cannot be auxiliary-only; auxiliary targets do not run firmware hook chains.

**Notes:**
- The scripts receive all the configuration defined in [Config Consolidation](#config-consolidation) as environment variables; they may receive additional variables defined by the build orchestrator and/or Buildroot.
- The script must exit with status 0 or the build will be aborted.
- Firmware-time hooks (`pre_firmware`, `firmware_build`, `post_firmware`) are **variant-filtered** using `firmware_variant`: smelterl generates separate hook arrays per variant for each firmware-time hook type (see [Firmware Variant Metadata](#firmware-variant-metadata)). Each variant’s array includes all variant-less nuggets’ hooks plus all nuggets whose `firmware_variant` list includes the matching variant.
- Firmware-time hook arrays are generated only in the **main target context**. Auxiliary target contexts do not include firmware hook arrays and never execute firmware hook chains.
- Scripts for firmware-time hooks (`pre_firmware`, `firmware_build`, `post_firmware`) are **auto-embedded** in the SDK main context - no explicit `{nugget, ...}` entry in `embed` is needed. SDK-time hooks (`pre_build`, `post_build`, `post_image`, `post_fakeroot`) are not auto-embedded since they run from the real motherlode during SDK build. See [Embedding Metadata - Auto-embedding](#embedding-metadata).

**Examples:**

```erlang
{hooks, [
    {pre_build, <<"scripts/pre-build.sh">>},
    {pre_build, <<"scripts/prepare-aux.sh">>, auxiliary},
    {pre_build, <<"scripts/prepare-encrypted.sh">>, encrypted_initramfs},
    {post_build, <<"scripts/post-build.sh">>},
    {post_image, <<"scripts/post-image.sh">>},
    {post_fakeroot, <<"scripts/post-fakeroot.sh">>},
    {pre_firmware, <<"scripts/pre-firmware.sh">>},
    {firmware_build, <<"scripts/build-firmware.sh">>},
    {post_firmware, <<"scripts/post-firmware.sh">>}
]}.
```

#### SDK Outputs Metadata

**Purpose:** Declare SDK-build-time artefacts produced by hooks for consumption by other SDK build targets (typically main consuming auxiliary outputs).

**Format:** `{sdk_outputs, [SdkOutputSpec]}`

**Specification:**

`SdkOutputSpec`: `{OutputId, [OutputField, ...]}`

`OutputField`:
- one of:
  - `{display_name, binary()}` (optional)
  - `{description, binary()}` (optional)

**Semantics:**
- `sdk_outputs` are target-local declarations: the declaring nugget is resolved in one concrete target tree (main or one auxiliary target).
- All declared SDK outputs are required contract outputs for that target in v1.

**Validation:**
- Output IDs must be unique within a target tree.
- Output IDs must follow standard identifier format (`[a-z][a-z0-9_]*`).

**Runtime registration:**
- Hooks register produced SDK outputs using:
  - `alloy_sdk_add_output <OUTPUT_ID> <FILE_PATH>`
- Registration state is written under the current target workspace:
  - `${TARGET_WORKSPACE}/.sdk_outputs/<OUTPUT_ID>` containing the absolute file path.

**Main-target consumption contract:**
- After auxiliary builds complete, orchestrator injects auxiliary output paths into the main target context:
  - `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>=<ABS_PATH>` (always)
  - `ALLOY_SDK_OUTPUT_<OUTPUT_ID>=<ABS_PATH>` (only when `OUTPUT_ID` is unique across auxiliaries)
- These variables are part of the main target context contract and remain available when the main context is sourced for firmware build orchestration.
- Context metadata for declared outputs is also exported per target:
  - `ALLOY_SDK_OUTPUTS` (ordered output-id array declared for that target)
  - `ALLOY_SDK_OUTPUT_<OUTPUT_ID>_NAME` and `ALLOY_SDK_OUTPUT_<OUTPUT_ID>_DESCRIPTION` (when declared in metadata)
- Helper API lookups use `<AUX_ID>, <OUTPUT_ID>`.

#### Firmware Variant Metadata

**Purpose:** Declare which firmware variants a nugget participates in. A single SDK can produce multiple firmware variants (e.g. plain, secure, encrypted). This metadata lets nuggets express that they are relevant only to specific variants - for instance, a secure-boot signing nugget only participates in the `secure` variant, not in `plain`.

**Format:** `{firmware_variant, [VariantAtom, ...]}.`

**Specification:**

`[VariantAtom, ...]`: list of atoms
- The firmware variants this nugget participates in.
- Built-in variants: `plain`, `secure`, `encrypted`. Custom variants are allowed (must follow identifier format).

**Validation:**
- Any nugget may declare `firmware_variant`. It is optional.
- Nuggets without `firmware_variant` are **variant-less** and participate in **all** variants.
- A nugget with `firmware_variant` participates **only** in the listed variants' **firmware-time** hook chains (`pre_firmware`, `firmware_build`, `post_firmware`). SDK-time hooks (`pre_build`, `post_build`, `post_image`, `post_fakeroot`) are not variant-filtered.
- The list must not contain duplicate atoms (redundant).
- Two or more nuggets may list the same variant atom (they will both appear in that variant's hook chain).

**Behavior:**
- For each declared variant, separate firmware-time hook chains are produced (`pre_firmware`, `firmware_build`, and `post_firmware`): each includes all variant-less nuggets plus all nuggets whose `firmware_variant` list includes that variant, in topological order.
- See [Smelterl Design](02_SMELTERL_DESIGN.md) for generation details and [Alloy Design](03_ALLOY_DESIGN.md#57-firmware-build-flow) for how the orchestrator selects and executes a variant's hook chain at firmware build time.

**Examples:**

```erlang
%% bootflow_grisp2_plain.nugget - boot assembly for the plain variant
{nugget, <<"1.0">>, [
    {id, bootflow_grisp2_plain},
    {category, bootflow},
    {firmware_variant, [plain]},
    {hooks, [
        {firmware_build, <<"scripts/build-firmware.sh">>}
    ]}
]}.

%% bootflow_imx8_fit_habv4.nugget - secure boot assembly (external repository example)
{nugget, <<"1.0">>, [
    {id, bootflow_imx8_fit_habv4},
    {category, bootflow},
    {firmware_variant, [secure]},
    {hooks, [
        {firmware_build, <<"scripts/build-firmware-signed.sh">>}
    ]}
]}.
```

#### Embedding Metadata

**Purpose:** Explicitly declare what to include in the SDK payload controlled by the **main target**; nothing is included by default unless auto-embedded (see below). Paths support glob patterns.

**Format:** `{embed, [EmbedSpec]}`

**Specification:**

`EmbedSpec`: `{SourceType, PathPattern}`
- Define a file or a set of file to be embedded inth SDK.

`SourceType`: atom
- Where the content comes from and where it is placed in the SDK.
- one of:
  - `images`: from Buildroot `output/images/` -> SDK images directory.
  - `host`: from Buildroot `output/host/` -> SDK host directory.
  - `nugget`: from this nugget's directory -> SDK `motherlode/NUGGET_REPO/NUGGET_IDENTIFIER/`.

`PathPattern`: string (binary)
- Path or glob pattern relative to the source: for `images`/`host` relative to that output directory, for `nugget` relative to nugget directory. Glob patterns (e.g. `<<"*.dtb">>`, `<<"lib/*.so*">>`) are supported.

**Validation:**
- Resolved paths must exist at SDK generation time; globs that match nothing may be ignored or warn per implementation.

**Rules:**
- Symlinks are converted to relative paths for relocatability. The process is defined in [SDK Embedding](#sdk-embedding).
- Embed metadata is materialized into `ALLOY_EMBED_*` arrays only in the **main target context**. Auxiliary contexts do not carry embed arrays.

**Auto-embedding (main target context):** Smelterl automatically adds the following nugget files to the embed set, without requiring explicit `{nugget, ...}` entries:

- **Firmware-time hook scripts** - Scripts declared in `{hooks, [...]}` for hook types that run during firmware build: `pre_firmware`, `firmware_build`, `post_firmware`. These scripts must be in the SDK because the real motherlode is not available at firmware build time. SDK-time hook scripts (`pre_build`, `post_build`, `post_image`, `post_fakeroot`) are NOT auto-embedded - they run from the real motherlode during SDK build and are not needed in the SDK.
- **Filesystem priority fragments** - The file declared in `{fs_priorities, Path}`. This file is consumed by the orchestrator at firmware build time for priority consolidation.

Auto-embedded entries are merged with explicit `{embed, [...]}` entries and deduplicated before emitting the main-context `ALLOY_EMBED_NUGGETS` array. If a file appears in both the auto-embed set and the explicit embed list, it is emitted only once. Nugget authors may still explicitly embed the same files (for clarity or forward compatibility) without causing errors.

Note that files referenced by generic config/export `{path, ...}` values (including `fun_`-prefixed callable scripts) are NOT auto-embedded - smelterl cannot determine whether a config value is consumed at SDK build time or firmware build time. Nugget authors must explicitly embed any config-referenced files that are needed in the SDK.

**Examples:**

```erlang
{embed, [
    {images, <<"spl.bin">>},
    {images, <<"*.dtb">>},
    {host, <<"bin/fwup">>},
    {host, <<"lib/libconfuse.so*">>},
    %% Nugget files needed by firmware hooks or config references at firmware time.
    %% Firmware hook scripts and fs_priorities fragments are auto-embedded
    %% and do not need to be listed here.
    {nugget, <<"scripts/sign-spl.sh">>},
    {nugget, <<"data/keys/*.pub">>}
]}.
```

#### Firmware Outputs Metadata

**Purpose:** Declare the firmware build artefacts that this nugget produces. At firmware build time, hooks register produced artefacts via the `add_firmware_output` API function (see [Alloy Design - Firmware Hook API](03_ALLOY_DESIGN.md#59-firmware-hook-api)). The `firmware_outputs` metadata enables the orchestrator to: (a) derive CLI flags for selectable outputs, (b) validate user output selection, (c) verify that declared outputs were actually produced, (d) display a build summary with human-readable names and descriptions, and (e) provide structured output information for CI/CD integration.

**Format:** `{firmware_outputs, [OutputSpec]}`

**Specification:**

`OutputSpec`: `{OutputId, [OutputField, ...]}`
- Declares one artefact that this nugget produces during firmware build.

`OutputId`: atom
- Unique identifier for this output across the entire nugget tree. Used to derive CLI flags and environment variables:
  - CLI flag: `--output-<id>` (underscores to hyphens, e.g. `--output-fwup-firmware`).
  - Selection variable: `ALLOY_OUTPUT_<ID>` (uppercased, e.g. `ALLOY_OUTPUT_FWUP_FIRMWARE`).
  - Output path storage: the path is written to `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/<ID>` when the hook calls `alloy_firmware_add_output`; the orchestrator and downstream hooks read from this file (no environment variable is set, since hooks run in separate processes).
- Must follow identifier format (lowercase, underscores). Choose CLI-friendly names.
- Examples: `fwup_firmware`, `image`, `signed_boot_image`.

`OutputField`: tuple
- One of the fields defined below. Order is not constrained.

`{selectable, Bool}`: boolean (default: `false`)
- When `true`: the output is user-selectable via `--output-<id>` CLI flags. The orchestrator generates `--output-<id>` and `--list-outputs` support. If the user selects this output (`ALLOY_OUTPUT_<ID>=true`) but the hook does not call `add_firmware_output`, the build fails with an error.
- When `false` (default): the output is not exposed as a CLI flag. It is produced unconditionally when the hook runs (e.g. variant-specific artefacts). If `add_firmware_output` is not called, the output is silently skipped in the build summary.

`{default, Bool}`: boolean (default: `true`) - only meaningful when `{selectable, true}`
- When `true` (default): the output is included in the default selection, i.e. it is built automatically when the user passes no `--output-*` flags.
- When `false`: the output is **not** included in the default selection - the user must explicitly request it with `--output-<id>`. It is still selectable (listed in `--list-outputs` and accepted as a CLI flag), but it is opt-in only. Use this for expensive or rarely-needed outputs (e.g. a raw disk image) that should not be generated on every firmware build.
- This field is ignored when `{selectable, false}` - non-selectable outputs are always produced unconditionally when the hook runs.

`{display_name, Name}`: binary
- Human-readable name shown in the build summary and `--list-outputs`. Exported to `alloy_context.sh` as `ALLOY_FIRMWARE_OUT_<ID>_NAME`.
- Example: `<<"Firmware update package">>`

`{description, Desc}`: binary
- Longer description shown in `--list-outputs`. Exported to `alloy_context.sh` as `ALLOY_FIRMWARE_OUT_<ID>_DESCRIPTION`.
- Example: `<<"fwup package for OTA updates via grisp_updater">>`

**Validation:**
- Output IDs must be unique across the entire nugget tree. Two nuggets declaring the same output ID is an error.
- Output IDs must follow the identifier format (`[a-z][a-z0-9_]*`).

**Runtime registration:**

During firmware hooks, the hook that produces an output calls the `add_firmware_output` function to register the artefact path with the orchestrator:

```bash
alloy_firmware_add_output <OUTPUT_ID> <FILE_PATH>
```

- `OUTPUT_ID`: must match a declared output ID from the `firmware_outputs` metadata.
- `FILE_PATH`: absolute path to the produced artefact file (must exist at call time).

The function validates the output ID against the declared outputs in `alloy_context.sh`, validates the file exists, and records the path in `${ALLOY_FIRMWARE_WORK_DIR}/.outputs/<ID>` so the orchestrator can discover what was produced (build summary, verification). No environment variable is exported—hooks run in separate processes; a downstream hook that needs another hook's output path reads it from the `.outputs/<ID>` file.

For implementation details, see [Alloy Design - Firmware Hook API](03_ALLOY_DESIGN.md#59-firmware-hook-api).

**Orchestrator verification (after all firmware hooks):**

The orchestrator iterates all declared outputs in topological order. For each output:
1. If selectable and not selected (`ALLOY_OUTPUT_<ID>=false`): skip.
2. If selectable and selected (`ALLOY_OUTPUT_<ID>=true`): `add_firmware_output` must have been called - if not, build error.
3. If `add_firmware_output` was called: verify file still exists - if not, build error. Include in build summary using `display_name`.
4. If not selectable and `add_firmware_output` was not called: skip silently (variant-conditional or not applicable).

Note: outputs with `{default, false}` are never selected unless the user explicitly passes `--output-<id>`, so they follow rule 1 in a default build. They follow rules 2 and 3 only when explicitly requested.

**Rules:**
- Each nugget's hook is responsible for writing its output file and calling `add_firmware_output` to register it.
- Selectable outputs that the user enables MUST be produced; failure to do so is a build error.
- Non-selectable outputs are conditional (e.g. a signed boot image only produced in the `secure` variant). The build does not fail if they are absent.
- Hook-to-hook intermediates that are NOT user-visible artefacts (e.g. merged rootfs consumed by fwup) cannot be passed by export (hooks run in separate processes). The producing nugget declares a **config at SDK build time** (e.g. `ALLOY_CONFIG_ROOTFS` with value `${ALLOY_FIRMWARE_WORK_DIR}/rootfs.merged.squashfs`) so downstream hooks read the path from that config; see [Alloy Design - §5.9](03_ALLOY_DESIGN.md#59-firmware-hook-api).
- `{default, false}` is only meaningful on selectable outputs. Use it for outputs that are expensive to produce or rarely needed (e.g. raw disk images), so they are not generated on every firmware build unless explicitly requested.

**Examples:**

```erlang
%% feature_fwup.nugget - selectable output, included in default build
{firmware_outputs, [
    {fwup_firmware, [
        {selectable, true},
        {display_name, <<"Firmware update package">>},
        {description, <<"fwup firmware update package for OTA deployment">>}
    ]}
]}.

%% feature_image.nugget - selectable but opt-in only (not built by default)
{firmware_outputs, [
    {image, [
        {selectable, true},
        {default, false},
        {display_name, <<"Raw disk image">>},
        {description, <<"Complete disk image for initial flashing via dd. Not built by default; use --output-image to request it.">>}
    ]}
]}.

%% bootflow_imx8_fit_habv4.nugget - non-selectable, variant-conditional (secure bootflow example)
{firmware_outputs, [
    {signed_boot_image, [
        {display_name, <<"Signed boot image">>},
        {description, <<"HABv4-signed boot image for secure boot">>}
    ]}
]}.
```

**Processing:** Smelterl collects `firmware_outputs` from the **main target tree** and generates the `ALLOY_FIRMWARE_OUTPUTS` ID array, per-output `ALLOY_FIRMWARE_OUT_<ID>_*` metadata variables (including `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT`), and `ALLOY_OUTPUT_SELECTABLE` list in main `alloy_context.sh`. Auxiliary contexts do not emit these variables. See [Smelterl Design - Generating alloy_context.sh](02_SMELTERL_DESIGN.md#412-generating-alloy_contextsh) for the generated format. For hook usage and runtime registration, see [Alloy Design - Firmware Hook API](03_ALLOY_DESIGN.md#59-firmware-hook-api).

#### Firmware Parameters Metadata

**Purpose:** Declare build-time parameters that this nugget's firmware hooks consume. Parameters are user-supplied key-value pairs injected at firmware build time via `--param KEY=VALUE` on `alloy build firmware`. They are designed for device-specific or deployment-specific values (serial numbers, MAC addresses, batch IDs) that do not exist in the SDK or project configuration. Declaring parameters in nugget metadata enables: (a) validation of `--param` keys at build time, (b) type checking of values, (c) `--list-params` discoverability, (d) default values, and (e) documentation of what each parameter is for.

**Format:** `{firmware_parameters, [ParamSpec, ...]}`

**Specification:**

`ParamSpec`: `{ParamId, [ParamField, ...]}`
- Declares one parameter that this nugget's firmware hooks expect to find in `ALLOY_PARAM_<ID>` (uppercased).

`ParamId`: atom
- Identifier for the parameter. Must follow the identifier format (`[a-z][a-z0-9_]*`).
- Multiple nuggets MAY declare the same `ParamId` (e.g., both a platform nugget and a provisioning nugget use `serial_number`). See merge rules below.
- Exported to hooks as `ALLOY_PARAM_<ID>` (uppercased, e.g. `ALLOY_PARAM_SERIAL_NUMBER`).
- Used as `--param <id>=<value>` on the CLI (e.g. `--param serial_number=SN123`).

`ParamField`: tuple
- One of the fields defined below. Order is not constrained.

`{type, Type}`: atom - **required**
- The parameter's value type. Determines CLI validation and manifest representation.
- `string` - arbitrary text. Stored as binary in the manifest. No validation beyond non-empty.
- `integer` - numeric value. The orchestrator validates that the value is a valid integer. Stored as integer in the manifest.
- `boolean` - `true` or `false`. The orchestrator validates that the value is one of `true`, `false`, `1`, `0`, `yes`, `no` (case-insensitive). Stored as atom (`true` or `false`) in the manifest.

`{name, Name}`: binary (optional)
- Human-readable display name shown in `--list-params`.
- Example: `<<"Serial Number">>`

`{description, Desc}`: binary (optional)
- Longer human-readable description of the parameter's purpose. Exported to `alloy_context.sh` as `ALLOY_FIRMWARE_PARAM_<ID>_DESCRIPTION` and stored in the SDK manifest's `capabilities` section. Shown in `--list-params` output.
- Example: `<<"Unique device serial number for factory provisioning">>`

`{required, Bool}`: boolean (default: `false`)
- When `true`: the orchestrator will fail the build if this parameter is not provided via `--param`. Checked before any firmware hook runs.
- When `false` (default): the parameter is optional. If not provided, `ALLOY_PARAM_<ID>` is not set (unless a default is specified).

`{default, Value}`: term (optional)
- Default value used when the parameter is not provided via `--param`. The value must be compatible with the declared `type` (string for `string`, integer for `integer`, boolean atom for `boolean`).
- When a default is specified and the user does not provide `--param <id>=...`, the orchestrator exports `ALLOY_PARAM_<ID>=<default>` and includes the default in the firmware manifest's `{parameters, [...]}` section (marked as default).
- A parameter with `{required, true}` and a `{default, ...}` is valid - the default satisfies the requirement if the user doesn't override it.

**Cross-nugget merge rules:**

Multiple nuggets may declare the same `ParamId`. Smelterl merges them during [§4.6 Discovering Firmware Variants, Selectable Outputs, and Parameters](02_SMELTERL_DESIGN.md#46-discovering-firmware-variants-selectable-outputs-and-parameters):

- **`type`** - must match across all nuggets declaring the same `ParamId`. Mismatched types are a validation error (e.g., "Parameter `serial_number` declared as `string` in `platform_imx8` but as `integer` in `feature_provisioning`").
- **`required`** - if ANY nugget declares `{required, true}`, the merged parameter is required (OR semantics).
- **`default`** - must match across all nuggets that specify it. Conflicting defaults are a validation error. If only some nuggets specify a default, the specified default is used.
- **`name`** - first non-empty value wins (from topological order). This is deterministic and stable.
- **`description`** - first non-empty value wins (from topological order).

**Validation:**
- `ParamId` must follow the identifier format (`[a-z][a-z0-9_]*`).
- `type` is required and must be one of `string`, `integer`, `boolean`.
- If `default` is specified, it must be compatible with `type`.
- Cross-nugget type conflicts are errors.
- Cross-nugget default conflicts are errors.

**Examples:**

```erlang
%% platform_imx8.nugget - platform needs serial number for device tree
{firmware_parameters, [
    {serial_number, [
        {type, string},
        {name, <<"Serial Number">>},
        {description, <<"Unique device serial number written to device tree">>},
        {required, true}
    ]}
]}.

%% feature_provisioning.nugget - provisioning also uses serial number + batch ID
{firmware_parameters, [
    {serial_number, [
        {type, string},
        {name, <<"Serial Number">>},
        {description, <<"Device serial number for provisioning records">>},
        {required, true}
    ]},
    {batch_id, [
        {type, string},
        {name, <<"Batch ID">>},
        {description, <<"Production batch identifier">>}
    ]}
]}.

%% feature_debug.nugget - optional debug toggle
{firmware_parameters, [
    {factory_mode, [
        {type, boolean},
        {name, <<"Factory Mode">>},
        {description, <<"Enable factory test mode (disables watchdog, enables debug console)">>},
        {default, false}
    ]}
]}.
```

**Processing:** Smelterl collects `firmware_parameters` from the **main target tree**, merges parameters with the same ID (validating type consistency and default consistency), and generates the `ALLOY_FIRMWARE_PARAMETERS` array and per-parameter metadata variables in main `alloy_context.sh`. Auxiliary contexts do not emit these variables. See [Smelterl Design - Generating alloy_context.sh](02_SMELTERL_DESIGN.md#412-generating-alloy_contextsh) for the generated format. For orchestrator usage, see [Alloy Design - Firmware Build Parameters](03_ALLOY_DESIGN.md#48-firmware-build-parameters).

#### Filesystem Priority Metadata

**Purpose:** Declare a filesystem priority fragment - a file listing `path weight` pairs that describe the preferred file ordering for the rootfs content this nugget installs (via Buildroot overlays, packages, or other rootfs contributions). These priorities are intrinsic metadata about the nugget's own files, not a configurable setting: they are collected (not overridden) by the orchestrator from all nuggets in topological order and consolidated into a single priority file before firmware hooks run. The consolidated file is consumed by the filesystem builder nugget (e.g. `feature_squashfs`) to optimize file placement.

**Format:** `{fs_priorities, FsPrioritiesPath}`

**Specification:**

`FsPrioritiesPath`: string (binary)
- Path to the priority fragment file, relative to the nugget directory.
- The referenced file must follow the [Filesystem Priority Specification](#filesystem-priority-specification) format (`path weight` per line, comments, globs).
- Example: `<<"fs_priorities.fragment">>`

**Validation:**
- The referenced file must exist in the nugget directory.
- The file content must be valid per the [Filesystem Priority Specification](#filesystem-priority-specification).

**Rules:**
- This field is optional. Most nuggets will not declare it.
- Unlike `config` keys, `fs_priorities` is not subject to last-writer-wins or override semantics. Every nugget's priority fragment is collected independently and appended to the consolidated file in topological order. This is appropriate because priorities describe the nugget's own knowledge about the files it contributes - a system nugget knows which init files matter, a platform nugget knows which kernel modules matter, and both should contribute their priorities.
- Paths in the fragment file are absolute rootfs paths (as they will appear in the final firmware filesystem), not relative to the nugget directory.
- The fragment file is **auto-embedded** in the SDK - no explicit `{nugget, ...}` entry in `embed` is needed. See [Embedding Metadata - Auto-embedding](#embedding-metadata).

**Examples:**

```erlang
%% system_grisp2.nugget - prioritises init and system configuration
{nugget, <<"1.0">>, [
    {id, system_grisp2},
    {category, system},
    {fs_priorities, <<"fs_priorities.fragment">>},
    ...
]}.

%% feature_erlang.nugget - prioritises Erlang runtime for boot speed
{nugget, <<"1.0">>, [
    {id, feature_erlang},
    {category, feature},
    {fs_priorities, <<"fs_priorities.fragment">>},
    ...
]}.
```

**Processing:** Smelterl reads each nugget's `fs_priorities` field (if present) in the **main target tree**, resolves the path relative to the nugget directory (prefixed by `${ALLOY_MOTHERLODE}`), and emits a per-nugget variable `ALLOY_NUGGET_<NAME>_FS_PRIORITIES` in main `alloy_context.sh`. It also generates an `ALLOY_FS_PRIORITIES_FRAGMENTS` array listing, in topological order, the `<NUGGET_IDENTIFIER>:<PATH>` entries for all nuggets that declare `fs_priorities`. Auxiliary contexts do not emit filesystem-priority arrays. See [Smelterl Design - Generating alloy_context.sh](02_SMELTERL_DESIGN.md#412-generating-alloy_contextsh). For consolidation at firmware build time, see [Alloy Design - Filesystem Priority Consolidation](03_ALLOY_DESIGN.md#filesystem-priority-consolidation).

#### SBOM & Legal Metadata

**Purpose:** Declare license, attribution, and legal-info for the nugget and optional external components (for SBOM and legal-info export).

**Formats:**
- `{license, LicenseName}`,
- `{license_files, [LicenseFilePath]}`
- `{author, Author}`
- `{maintainer, Maintainer}`
- `{homepage, HomepageUrl}`
- `{security_contact, SecurityContact}`
- `{external_components, [ExternalComponentSpec]}`

**Specification:**

`LicenseName`: string (binary)
- SPDX or other license identifier.
-Examples: `<<"Apache-2.0">>`, `<<"GPL-2.0">>`.

`LicenseFilePath`: string (binary)
- Path to a license file relative to nugget directory.

`AuthorString`: string (binary)
- Author or copyright holder
- Example: `<<"Acme Corp">>`.

`MaintainerString`: string (binary)
- Maintainer contact (e.g. email or URL).
- Example: `<<"maintainer@acme.com">>`.

`HomepageUrl`: string (binary)
- URL of the nugget’s homepage.

`SecurityContact`: string (binary)
- Security contact (e.g. email) for vulnerability reporting.

`ExternalComponentSpec`: property list
- Describe an external components for legal-info/SBOM.
- any of:
  - `{id, ComponentIdentifier}`: required
  - `{name, ComponentName}`: optional
  - `{description, ComponentDescription}`: optional
  - `{version, ComponentVersion}`: optional
  - `{license, LicenseName}`: optional
  - `{license_files, [LicenseFilePath]}`: optional
  - `{source_dir, ComponentSourceDir}`: optional
  - `{source_archive, ComponentSourceArch}`: optional

`ComponentId`: string (binary)
- The identifier of the component; unique for the nugget.
- Example: `<<"crosstool_ng">>`.

`ComponentName`: string (binary)
- The display name of the component.
- Example: `<<"Crosstool NG">>`.

`ComponentDescription`: string (binary)
- The description of the component
- Example: `<<"Crosstool NG toolchain">>`.

`ComponentVersion`: string (binary)
- Component semantic version.
- Example: `<<"1.4.2-tag">>`.

`ComponentSourceDir`:
`ComponentSourceArch`:
- Define how to locate the source of the component, either a directory that needs to be archived, or an already archived file.
- one of:
  - **Path** - `{path, PathSpec}`: see [Nugget Configuration Metadata](#nugget-configuration-metadata) (PathSpec).
  - **Computed** - `{computed, Template}`: see [Nugget Configuration Metadata](#nugget-configuration-metadata).
  - **Exec:** `{exec, ScriptPath}`: see [Nugget Configuration Metadata](#nugget-configuration-metadata). When used for legal-info source export, exec scripts are run with consolidated config and extra-config; their output may contain shell variable references (e.g. `${ALLOY_CACHE_DIR}/file.tgz`). For source export the exporter must resolve that output to a concrete path by evaluating it in bash with the smelterl (caller) environment-see [Smelterl Design](02_SMELTERL_DESIGN.md) §4.13.

**Validation:**
- All components must have a unique `id`.
- The `license_files` relative path must point to existing files.
- Only one of `source_dir` or `source_archive` must be provided at the same time.

**Rules:**
- When inheriting metadata from the registry (`.nuggets`) defaults, the path of the license files must stay relative to the registry in order to find them.
- For private components whose sources must not be distributed as part of the legal information, `source_dir` or `source_archive` must not be defined.

**Examples:**

```erlang
{license, <<"Apache-2.0">>}.
{license_files, [<<"LICENSE">>]}.
{author, <<"Acme Corp">>}.
{maintainer, <<"dev@acme.example">>}.
{homepage, <<"https://acme.example/nugget">>}.
{external_components, [
    [
        {id, <<"crosstool_ng">>},
        {name, <<"Crosstool NG">>},
        {version, <<"1.25.0">>},
        {license, <<"GPL-2.0">>},
        {license_files, [<<"ctng/LICENSE">>]},
        {source_archive, {computed, <<"[[ALLOY_CACHE_DIR]]/toolchain/ctng-1.25.0.tar.xz">>}}
    ]
]}
```

---

## SDK Manifest Specification

This section defines the `ALLOY_SDK_MANIFEST` file: its structure, sections, and the uniform licensing shape for all tracked components (nuggets, Buildroot packages, external components).

**Purpose:** Provide build metadata for traceability and SBOM: product identity, repositories, nuggets in dependency order, planned auxiliary products, firmware capabilities, sdk output declarations by target, Buildroot target and host packages, external components, and integrity. Stored as the file `ALLOY_SDK_MANIFEST` (typically at SDK root or build output root).

**Format:** Erlang term file. The file MUST follow the [Erlang term file format conventions](00_OVERVIEW.md#erlang-term-file-format-conventions) from the [Overview](00_OVERVIEW.md) (UTF-8, binaries for strings, one term per file, period-terminated).

**Path rule:** All file paths present in the manifest (e.g. `license_files`, paths in package or component entries) MUST be **relative to the manifest file location**. This ensures the manifest and its referenced files are relocatable as a unit (e.g. when the SDK is moved or the legal-info tree is exported).

---

### Manifest Root Format

**Format:** `{sdk_manifest, ManifestVersion, [SectionEntry, ...]}.`

This follows the uniform `{Tag, Version, [Fields]}` convention used by all Alloy term files (see [Erlang Term File Format Conventions](00_OVERVIEW.md#erlang-term-file-format-conventions)).

**Specification:**

`ManifestVersion`: string (binary)
- Schema version of the manifest format.
- Example: `<<"1.0">>`.

`SectionEntry`: tuple
- One of the section types defined in [Sections Overview](#manifest-sections-overview). Order of entries in the list is not constrained by this specification; consumers must look up sections by key. Custom or future sections may be added; consumers must ignore unknown section keys.

**Validation:**
- The root term must be a triple `{sdk_manifest, Version, List}`.
- `Version` must be a binary.
- `List` must be a list of section tuples.

**Rules:**
- Exactly one entry per section key (e.g. one `product`, one `repositories`, one `nuggets`). Duplicate section keys are not allowed; behavior is undefined if present.

---

### Manifest Sections Overview

- **Product and build:** [Product and Build Information](#product-and-build-information)
  - `product`: Product identifier
  - `product_version`: Product semantic version.
  - `product_name`: Product display name.
  - `product_description`: Product description.
  - `target_arch`: Target architecture triplet (from consolidated nugget exports).
  - `build_date`: Build timestamp (ISO 8601).
- **Build environment:** [Build Environment](#manifest-build-environment)
  - `build_environment`: Host OS/arch, smelterl and Buildroot versions, and reference to generator repository.
- **Repositories:** [Repositories](#manifest-repositories)
  - `repositories`: Repository list deduplicated by URL; referenced by ID (atom).
- **Nuggets:** [Nuggets](#manifest-nuggets)
  - `nuggets`: Topologically ordered list of nuggets with metadata.
- **Auxiliary:** [Auxiliary Products](#manifest-auxiliary-products)
  - `auxiliary_products`: Planned auxiliary targets included in SDK build metadata.
- **Capabilities:** [Capabilities](#manifest-capabilities)
  - `capabilities`: Available firmware variants, selectable outputs, and firmware parameters (see [Manifest Capabilities](#manifest-capabilities)).
- **SDK Outputs:** [SDK Outputs](#manifest-sdk-outputs)
  - `sdk_outputs`: Declared `sdk_outputs` summary by target (`main` and auxiliaries).
- **Buildroot:** [Buildroot Packages](#manifest-buildroot-packages)
  - `buildroot_packages`: Buildroot target packages when legal-info was supplied.
  - `buildroot_host_packages`: Buildroot host packages when legal-info was supplied.
- **External:** [External Components](#manifest-external-components)
  - `external_components`: Components not built by Buildroot but declared by nuggets (e.g. toolchain); same licensing shape.
- **Integrity:** [Manifest Integrity Specification](#manifest-integrity-specification)
  - `integrity`: Cryptographic hash for tamper detection; hash excludes the integrity section. Same format across all Alloy manifests.

### Product and Build Information

**Purpose:** Identify the SDK/product, its target architecture, and the build timestamp.

**Formats:**
- `{product, ProductId}`
- `{product_name, ProductName}`
- `{product_description, ProductDescription}`
- `{product_version, ProductVersion}`
- `{target_arch, TargetArch}`
- `{build_date, BuildDate}`

**Specification:**

`ProductId`: atom
- Product (top-level nugget) identifier; matches the nugget identifier used for dependency resolution.
- Example: `grisp2_vanilla`.

`ProductName`: string (binary)
- Human-readable display name of the product.
- Example: `<<"GRiSP 2 Vanilla">>`.

`ProductDescription`: string (binary)
- Human-readable description of the product.
- Example: `<<"Standard GRiSP 2 board support">>`.

`ProductVersion`: string (binary)
- Semantic version of the product/SDK.
- Example: `<<"1.0.0">>`.

`TargetArch`: string (binary)
- GNU target architecture triplet of the SDK's cross-compilation toolchain (e.g. `<<"arm-buildroot-linux-gnueabihf">>`).
- Sourced from the consolidated config: the well-known export key `target_arch_triplet` (see [Smelterl Design - Well-Known Export Keys](02_SMELTERL_DESIGN.md#well-known-export-keys)). `smelterl` reads this value after config consolidation and writes it to the manifest. If no nugget exports `target_arch_triplet`, manifest generation fails with a validation error.
- Example: `<<"arm-buildroot-linux-gnueabihf">>`.

`BuildDate`: string (binary)
- ISO 8601 timestamp of the manifest generation (UTC recommended).
- Example: `<<"2026-02-04T10:30:00Z">>`.

**Validation:**
- `product`, `target_arch`, and `build_date` must be present. `product_name`, `product_description`, and `product_version` are optional but recommended.

**Examples:**

```erlang
{product, <<"grisp2_vanilla">>},
{product_name, <<"GRiSP 2 Vanilla">>},
{product_description, <<"Standard GRiSP 2 board support">>},
{product_version, <<"1.0.0">>},
{target_arch, <<"arm-buildroot-linux-gnueabihf">>},
{build_date, <<"2026-02-04T10:30:00Z">>}
```

### Manifest Build Environment

**Purpose:** Record host and tool versions used to generate the build (for reproducibility and SBOM).

**Format:** `{build_environment, [BuildEnvEntry, ...]}`

**Specification:**

`BuildEnvEntry`: tuple
- any of:
  - `{host_os, HostOs}`: Operating system of the build host (e.g. `<<"Linux">>`).
  - `{host_arch, HostArch}`: Architecture of the build host (e.g. `<<"x86_64">>`).
  - `{smelterl_version, SmelterlVersion}`: Version of the smelterl tool.
  - `{smelterl_repository, RepoId}`: Atom referencing an entry in the `repositories` list (e.g. the grisp_alloy repo); optional.
  - `{buildroot_version, BuildrootVersion}`: Buildroot version used (e.g. `<<"2021.02.3">>`).

`HostOs`, `HostArch`, `SmelterlVersion`, `BuildrootVersion`: string (binary)

`RepoId`: atom
- Key of a repository in the `repositories` section; used so the manifest can point to the generator’s source without duplicating VCS data.

**Validation:**
- If specifed, `smelterl_repository` must reference a repository ID that exists in the `repositories` section.

**Examples:**

```erlang
{build_environment, [
    {host_os, <<"Linux">>},
    {host_arch, <<"x86_64">>},
    {smelterl_version, <<"2.0.0">>},
    {smelterl_repository, grisp_alloy},
    {buildroot_version, <<"2021.02.3">>}
]}
```

### Manifest Repositories

**Purpose:** List all distinct repositories that supply nuggets. Nuggets may reference a repository by ID (optional when a nugget comes from a non-repository directory); repositories are deduplicated by URL so one repo entry is shared by all nuggets from that repo.

**Format:** `{repositories, [RepositoryEntry, ...]}`

**Specification:**

`RepositoryEntry`: `{RepoId, [RepoField, ...]}`

`RepoId`: atom
- unique identifier for this repository; used by `build_environment.smelterl_repository` and by each nugget’s optional `repository` field.

`RepoField`: tuple
- any of:
    - `{name, Name}`: string (binary) - display or logical name (e.g. from URL).
    - `{type, Type}`: atom - repository type: `git` (until more types are supported).
    - `{url, Url}`: string (binary) - VCS URL (e.g. `<<"https://github.com/grisp/grisp_alloy.git">>`).
    - `{commit, Commit}`: string (binary) - full commit hash at build time.
    - `{describe, Describe}`: string (binary) - output of `git describe` (or equivalent) at build time.
    - `{dirty, Dirty}`: boolean - whether the working tree had uncommitted changes at build time.

**Validation:**
- Every `RepoId` referenced by a nugget or by `build_environment` must appear in exactly one `RepositoryEntry`.
- Repository data (URL, commit, ref, dirty) is captured automatically when nuggets are loaded from VCS; no manual declaration in nugget metadata is required.

**Rules:**
- Repository IDs are unique. Deduplication and ID assignment follow [Repository Deduplication](#repository-deduplication).

**Examples:**

```erlang
{repositories, [
    {grisp_alloy, [
        {name, <<"grisp_alloy">>},
        {type, git},
        {url, <<"https://github.com/grisp/grisp_alloy.git">>},
        {commit, <<"abc123def456">>},
        {describe, <<"v2.0.0">>},
        {dirty, false}
    ]},
    {acme_nuggets, [
        {name, <<"acme_nuggets">>},
        {type, git},
        {url, <<"https://github.com/acme/acme_nuggets.git">>},
        {commit, <<"def456abc123">>},
        {describe, <<"v1.2.3-5-gdef456a">>},
        {dirty, false}
    ]}
]}
```

---

### Repository Deduplication

**Purpose:** Define how repository entries in the manifest are derived from nugget sources so that multiple nuggets from the same repository share one entry and reference it by a single ID.

**Process (generator):**

1. **Collect repositories:** For each nugget in the dependency tree, determine the repository that supplied it when the nugget comes from a repository (e.g. from the motherlode directory or VCS metadata); some nuggets may be from a non-repository directory and have no repository.
2. **Deduplicate by URL:** If two repositories have the same canonical URL, treat them as one; keep one entry and assign one `RepoId`.
3. **Assign IDs:** Derive a logical name from the URL (e.g. repository name from path). Use that as the default `RepoId` (as atom). If the same name would be used for another repository, resolve conflicts by appending a numeric suffix: second repo with same name-> `name2`, third -> `name3`, etc. The result is a unique atom per repository.
4. **Nugget references:** When a nugget has an associated repository, set its optional `repository` field in the manifest to that `RepoId`; when the nugget comes from a non-repository directory, omit the `repository` field.

**Rules:**
- Nuggets reference repositories only by `RepoId` (atom). They do not repeat URL or commit data; that lives only in the `repositories` section.

### Alloy repository info file (.alloy_repo_info)

**Purpose:** Supply repository provenance (URL, commit, describe, dirty) for a directory when the directory is not a VCS checkout (e.g. after the alloy repository is rsynced to a Vagrant VM without `.git`). The **orchestrator** writes this file on the host from `git` before delegating; **smelterl** reads it via `smelterl_vcs` when resolving VCS info for that path, so manifest generation gets the same data it would from a real git checkout. See [Alloy Design - Repository provenance when delegating to Vagrant](03_ALLOY_DESIGN.md#repository-provenance-when-delegating-to-vagrant).

**Location:** Optional file at the **repository root** (the directory that would otherwise be the root of the VCS checkout). Smelterl looks for `.alloy_repo_info` in the given path or in any parent directory; the first valid file found is used.

**Format:** Plain text, UTF-8 encoding. One key-value pair per line: `KEY=VALUE`. Leading and trailing whitespace on the line is ignored. Empty lines and lines whose first non-whitespace character is `#` are ignored. The value is the rest of the line after the first `=`; no quoting or escaping is required (values must not contain newlines). Keys are case-sensitive.

**Required keys:** All keys must be present for the file to be valid. Missing or empty value for a required key makes the file invalid (smelterl falls back to VCS or returns no info).

| Key     | Description |
|--------|-------------|
| `NAME` | Repository display name (e.g. `grisp_alloy`). Same as the `name` field in manifest repository entries. |
| `URL`  | VCS remote URL (e.g. `https://github.com/grisp/grisp_alloy.git`). |
| `COMMIT` | Full commit hash at the time the file was generated. |
| `DESCRIBE` | Output of `git describe` (or equivalent) at that time (e.g. `v2.0.0` or `v2.0.0-5-gabc1234`). |
| `DIRTY` | Whether the working tree had uncommitted changes: `true` or `false` (lowercase). |

**Example:**

```
NAME=grisp_alloy
URL=https://github.com/grisp/grisp_alloy.git
COMMIT=abc123def456789
DESCRIBE=v2.0.0
DIRTY=false
```

### Manifest Nuggets

**Purpose:** List all nuggets that are part of the resolved dependency tree, in topological order, with version, optional repository, category, provided capabilities, and licensing information.

**Format:** `{nuggets, [NuggetEntry, ...]}`

**Specification:**

`NuggetEntry`: `{nugget, NuggetId, [NuggetField, ...]}`

`NuggetId`: atom
- nugget identifier (same as in [Nugget Metadata](#nugget-metadata)).

`NuggetField`: tuple
- any of:
  - `{version, Version}`: string (binary) - semantic version of the nugget.
  - `{repository, RepoId}`: atom (optional) - key into the `repositories` section; omit when the nugget comes from a non-repository directory (e.g. local path with no VCS).
- `{category, Category}`: atom - one of `builder`, `toolchain`, `platform`, `system`, `bootflow`, `feature`.
  - `{flavor, Flavor}`: atom (optional) - resolved flavor for this nugget; omit when nugget has no flavors or uses default.
  - `{provides, [CapabilityId, ...]}`: list of atom (optional) - capabilities provided by this nugget (e.g. `secure_boot`, `disk_encryption`).
  - `{license, LicenseName}`: string (binary); SPDX or other license identifier.
  - `{license_files, [LicensePath, ...]}`: list of string (binary); paths to license files, **relative to the manifest file location**.

**Validation:**
- Order of entries MUST be the [topological order](#topology-order) of the nugget dependency tree (dependencies before dependents; product last).
- When present, every `repository` value must be a `RepoId` present in the `repositories` section (nuggets from a non-repository directory omit the field).
- Every `license_files` path must be relative (no leading `/`); resolvable relative to the manifest file.

**Rules:**
- License paths are resolved at generation time from nugget metadata (relative to nugget or registry); the generator writes them into the manifest relative to the manifest location (e.g. SDK root or legal-info export dir) so that the manifest is relocatable.

**Examples:**

```erlang
{nuggets, [
    {nugget, <<"platform_imx6">>, [
        {version, <<"1.0.0">>},
        {repository, grisp_alloy},
        {category, platform},
        {flavor, imx6ull},
        {license, <<"Apache-2.0">>},
        {license_files, [<<"legal-info/alloy-licenses/platform_imx6-1.0.0/Apache-2.0.txt">>]}
    ]},
    {nugget, <<"security_habv4">>, [
        {version, <<"1.0.0">>},
        {repository, acme_nuggets},
        {category, feature},
        {provides, [secure_boot, disk_encryption]},
        {license, <<"Proprietary">>},
        {license_files, [<<"legal-info/alloy-licenses/security_habv4-1.0.0/Proprietary-acme.txt">>]}
    ]}
]}
```

---

### Manifest Auxiliary Products

**Purpose:** Record planned auxiliary SDK targets that were resolved with the main product. These targets are built during SDK build (before main) and may provide artefacts via `sdk_outputs`, but they do not own firmware assembly.

**Format:** `{auxiliary_products, [AuxiliaryEntry, ...]}`

**Specification:**

`AuxiliaryEntry`: `{auxiliary, AuxId, [AuxiliaryField, ...]}`

`AuxId`: atom
- Auxiliary target identifier from `auxiliary_products` metadata resolution.

`AuxiliaryField`: tuple
- any of:
  - `{root_nugget, NuggetId}`: atom - root nugget used to build this auxiliary target.
  - `{constraints, [AuxiliaryConstraint, ...]}`: list (optional) - resolved auxiliary constraints retained for traceability.

`AuxiliaryConstraint`: tuple
- one of:
  - `{version, VersionConstraint}`: string (binary)
  - `{flavor, FlavorIdentifier}`: atom

**Validation:**
- `AuxId` values must be unique in this section.
- `AuxId` must not be `main` or `all`.
- `root_nugget` must reference a nugget identifier that exists in the resolved motherlode.

**Examples:**

```erlang
{auxiliary_products, [
    {auxiliary, plain_initramfs, [
        {root_nugget, auxiliary_initramfs},
        {constraints, [{flavor, plain}]}
    ]},
    {auxiliary, encrypted_initramfs, [
        {root_nugget, auxiliary_initramfs},
        {constraints, [{flavor, encrypted}]}
    ]}
]}
```

---

### Manifest Capabilities

**Purpose:** Expose firmware-build capabilities discovered from the main target tree: available firmware variants, selectable outputs, and declared firmware parameters. Used by firmware build tooling, CI/CD, and SDK introspection.

**Format:** `{capabilities, [CapabilityEntry, ...]}`

**Specification:**

`CapabilityEntry`: tuple
- any of:
  - `{firmware_variants, [VariantAtom, ...]}`: ordered list of available firmware variant names (atoms). The `plain` variant is always present, even if no nugget explicitly declares it - it is the default variant representing a build with no special security or transformation. Order is deterministic (first-occurrence from topological order). Consumers use this list to validate `--variant` CLI flags and to discover which firmware configurations are available.
  - `{selectable_outputs, [OutputIdAtom, ...]}`: ordered list of selectable output identifiers from nuggets’ `firmware_outputs` metadata where `{selectable, true}`. Consumers use this list to validate `--output-*` CLI flags.
  - `{firmware_parameters, [ParamSummary, ...]}`: ordered list of declared firmware build parameters (merged from all nuggets' `firmware_parameters` metadata). Each `ParamSummary` is `{ParamId, ParamFields}` where `ParamFields` is a proplist with `{type, Type}` (required), and optional `{required, Bool}`, `{name, Name}`, `{description, Desc}`, `{default, Value}`. Consumers use this list to validate `--param` CLI flags, provide `--list-params` output, and apply defaults. See [Firmware Parameters Metadata](#firmware-parameters-metadata).

Other capability keys may be added; consumers must ignore unknown keys.

**Validation:**
- `firmware_variants` must include `plain` (added automatically if not declared by any nugget).
- Variant atoms must be unique within the list.
- Output IDs must be unique across the entire nugget tree.
- Parameter IDs must follow the identifier format; types must be consistent across nuggets declaring the same parameter.

**Examples:**

```erlang
{capabilities, [
    {firmware_variants, [plain, secure]},
    {selectable_outputs, [fwup_firmware, image]},
    {firmware_parameters, [
        {serial_number, [{type, string}, {required, true},
                         {name, <<"Serial Number">>},
                         {description, <<"Unique device serial number">>}]},
        {batch_id, [{type, string}, {name, <<"Batch ID">>}]},
        {factory_mode, [{type, boolean}, {default, false},
                        {name, <<"Factory Mode">>}]}
    ]}
]}
```

---

### Manifest SDK Outputs

**Purpose:** Record SDK-time output declarations by target (`main` and auxiliaries). This section describes inter-target SDK artefact contracts and is distinct from firmware capabilities.

**Format:** `{sdk_outputs, [TargetSdkOutputs, ...]}`

**Specification:**

`TargetSdkOutputs`: `{target, TargetId, [SdkOutputSummary, ...]}`

`TargetId`: atom
- `main` or one auxiliary target id.

`SdkOutputSummary`: `{output, OutputId, [SdkOutputField, ...]}`

`OutputId`: atom
- Output identifier from nugget `sdk_outputs` metadata.

`SdkOutputField`: tuple
- any of:
  - `{nugget, NuggetId}`: atom - declaring nugget in the target tree.
  - `{name, Name}`: string (binary) - display name from `sdk_outputs` metadata when declared.
  - `{description, Desc}`: string (binary) - description from `sdk_outputs` metadata when declared.

**Validation:**
- Target IDs must be unique within this section.
- Output IDs must be unique within each target.
- `TargetId` values must reference `main` or a declared auxiliary target.

**Examples:**

```erlang
{sdk_outputs, [
    {target, main, [
        {output, debug_symbols, [
            {nugget, feature_debug_symbols},
            {name, <<"Debug symbols archive">>}
        ]}
    ]},
    {target, encrypted_initramfs, [
        {output, initramfs, [
            {nugget, auxiliary_initramfs},
            {name, <<"Encrypted initramfs image">>},
            {description, <<"initramfs artefact consumed by main target">>}
        ]}
    ]}
]}
```

---

### Manifest Buildroot Packages

**Purpose:** Record Buildroot target and host packages when the manifest is generated with Buildroot legal-info. Source of truth is Buildroot’s `legal-info/manifest.csv` and `legal-info/host-manifest.csv`.

**Formats:**
- `{buildroot_packages, [PackageEntry, ...]}`
- `{buildroot_host_packages, [PackageEntry, ...]}`

**Specification:**

`PackageEntry`: `{package, PackageName, [PackageField, ...]}`

`PackageName`: string (binary)
- Buildroot package name (e.g. `<<"busybox">>`, `<<"erlang">>` for target; `<<"host-gcc">>` for host).

`PackageField`: tuple
- any of:
  - `{version, Version}`: string (binary).
  - `{license, LicenseName}`: string (binary); SPDX or other identifier.
  - `{license_files, [LicensePath, ...]}`: list of string (binary)
    - Licence file paths **relative to the manifest file location**
    - Example: `<<"legal-info/licenses/busybox-1.2.3/LICENCE.txt">>`.

**Validation:**
- These sections are present only when the manifest was generated with Buildroot legal-info. If Buildroot legal-info was not supplied, the sections may be omitted or empty.
- All paths in `license_files` must be relative to the manifest location.

**Rules:**
- Package data is parsed from Buildroot’s `manifest.csv` (target) and `host-manifest.csv` (host). License paths in the manifest are written relative to the manifest so that the legal-info tree (e.g. in the SDK) is relocatable.

**Examples:**

```erlang
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
]}
```

---

### Manifest External Components

**Purpose:** List components that are not built by Buildroot but are declared by nuggets (e.g. Crosstool-NG from a toolchain nugget). Same licensing shape as nuggets and Buildroot packages for uniform SBOM and legal-info.

**Format:** `{external_components, [ExternalEntry, ...]}`

**Specification:**

`ExternalEntry`: `{component, ComponentId, [ComponentField, ...]}`

`ComponentId`: atom
- unique identifier for the component.
- Example: `crosstool_ng`.

`ComponentField`: tuple
- any of:
  - `{name, Name}`: string (binary); human-readable name (from nugget metadata).
  - `{description, Description}`: string (binary); short description (from nugget metadata).
  - `{version, Version}`: string (binary).
  - `{license, LicenseName}`: string (binary).
  - `{license_files, [LicensePath, ...]}`: list of string (binary)
    - Licence file paths **relative to the manifest file location**
    - Example: `<<"legal-info/alloy-licenses/toolchain_ctng-1.0.0/crosstool-ng-1.24.0/COPYING">>`

**Validation:**
- Each component is uniquely identified within the manifest. License paths must be relative to the manifest location.

**Rules:**
- External components are taken from nugget metadata (e.g. `external_components` in [SBOM & Legal Metadata](#sbom--legal-metadata)). The generator aggregates them and writes license paths relative to the manifest so the SDK legal-info tree is relocatable.

**Examples:**

```erlang
{external_components, [
    {component, crosstool_ng, [
        {name, <<"Crosstool-NG">>},
        {description, <<"Crosstool-NG toolchain">>},
        {version, <<"1.24.0">>},
        {license, <<"GPL-2.0">>},
        {license_files, [<<"legal-info/alloy-licenses/toolchain_ctng-1.0.0/crosstool-ng-1.24.0/COPYING">>]}
    ]}
]}
```

### Manifest Integrity

All Alloy manifests (SDK, project, firmware) use the same integrity section format and verification algorithm, defined in [Manifest Integrity Specification](#manifest-integrity-specification). This allows a single tool (e.g. `manifest-tool verify`) to validate any manifest type.

---

### Manifest Complete Example

The following example shows all sections in one manifest. Paths are relative to the manifest file (e.g. at SDK root).

```erlang
%% coding: utf-8
%% GRiSP Alloy SDK Manifest
%% Generated: 2026-02-04T10:30:00Z
{sdk_manifest, <<"1.0">>, [
    {product, <<"grisp2_vanilla">>},
    {product_name, <<"GRiSP 2 Vanilla">>},
    {product_description, <<"Standard GRiSP 2 board support">>},
    {product_version, <<"1.0.0">>},
    {target_arch, <<"arm-buildroot-linux-gnueabihf">>},
    {build_date, <<"2026-02-04T10:30:00Z">>},

    {build_environment, [
        {host_os, <<"Linux">>},
        {host_arch, <<"x86_64">>},
        {smelterl_version, <<"2.0.0">>},
        {smelterl_repository, grisp_alloy},
        {buildroot_version, <<"2021.02.3">>}
    ]},

    {repositories, [
        {grisp_alloy, [
            {name, <<"grisp_alloy">>},
            {url, <<"https://github.com/grisp/grisp_alloy.git">>},
            {commit, <<"abc123def456">>},
            {describe, <<"v2.0.0">>},
            {dirty, false}
        ]},
        {acme_nuggets, [
            {name, <<"acme_nuggets">>},
            {url, <<"https://github.com/acme/acme_nuggets.git">>},
            {commit, <<"def456abc123">>},
            {describe, <<"v1.2.3-5-gdef456a">>},
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
            {license_files, [<<"legal-info/alloy-licenses/platform_imx6-1.0.0/Apache-2.0.txt">>]}
        ]},
        {nugget, <<"security_habv4">>, [
            {version, <<"1.0.0">>},
            {repository, acme_nuggets},
            {category, feature},
            {provides, [secure_boot, disk_encryption]},
            {license, <<"Proprietary">>},
            {license_files, [<<"legal-info/alloy-licenses/security_habv4-1.0.0/Proprietary-acme.txt">>]}
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
                {description, <<"initramfs artefact consumed by main target">>}
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
            {description, <<"Crosstool-NG toolcahin">>},
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

## Project Manifest Specification

This section defines the `ALLOY_PROJECT_MANIFEST` file: its structure and fields.

**Purpose:** Provide project build metadata for traceability: project identity, build parameters, SDK provenance, dependency information. Stored as the file `ALLOY_PROJECT_MANIFEST` in the project artefact staging directory and in unpacked project artefacts during firmware builds.

**Format:** Erlang term file. The file MUST follow the [Erlang term file format conventions](00_OVERVIEW.md#erlang-term-file-format-conventions) from the [Overview](00_OVERVIEW.md).

### Project Manifest Root Format

**Format:** `{project_manifest, ManifestVersion, [FieldEntry, ...]}.`

**Specification:**

`ManifestVersion`: string (binary)
- Schema version of the project manifest format.
- Example: `<<"1.0">>`.

`FieldEntry`: tuple
- Order is not constrained; consumers must look up fields by key.
- any of:
    - `{id, ProjectId}`: atom - project identifier, derived from the OTP release name by lowercasing and replacing hyphens with underscores. Must match the standard [identifier format](#identifier-format) (`[a-z][a-z0-9_]*`). Used as the canonical machine-readable identity for the project. When multiple projects are embedded in a firmware manifest, each must have a distinct `id`. Distinct from `name`, which is the human-readable display name.
    - `{name, Name}`: string (binary) - project release name (as detected by the project plugin). This is the name of the OTP release (the directory name under `_build/<profile>/rel/`). Not to be confused with `app_name`, which identifies the main OTP application within the release.
    - `{version, Version}`: string (binary) - project release version (from OTP release metadata, i.e. the directory name under `releases/`). Not to be confused with `app_version`, which is the version of the main OTP application.
    - `{app_name, AppName}`: atom - main OTP application name. For Erlang projects, extracted from the `.app.src` file and validated against `lib/<app>-*` in the built release. For Elixir projects, extracted from the `:app` key in `mix.exs` and validated against `lib/<app>-*` in the built release. The main application is the project's primary functional component; in many projects it differs from the release name (e.g. release `my_system` may contain main application `my_app`).
    - `{app_version, AppVersion}`: string (binary) - version of the main OTP application. Extracted from the `lib/<app_name>-<version>/` directory in the built release. May differ from the release `version` (e.g. when the release version tracks a deployment scheme while the application version tracks the code).
    - `{type, Type}`: atom - project type: `erlang` or `elixir`.
    - `{profile, Profile}`: string (binary) - build profile used (e.g. `<<"prod">>`, `<<"dev">>`).
    - `{sdk_product, Product}`: string (binary) - product identifier of the SDK used to build this project.
    - `{sdk_version, Version}`: string (binary) - product version of the SDK.
    - `{build_date, Date}`: string (binary) - ISO 8601 UTC timestamp of the build.
    - `{target_arch, Arch}`: string (binary) - target architecture triplet (from SDK context).
    - `{otp_version, OtpVersion}`: string (binary) - Erlang/OTP version used for compilation.
    - `{repository, RepoId}`: atom (optional) - reference to the project's own source repository in the `repositories` section. Present when the project source is a VCS repository (cloned from a URL or built from a local git checkout); absent when built from a non-VCS source (e.g. a tarball). Follows the same indirection pattern as nuggets in the [SDK manifest](#manifest-nuggets).
    - `{repositories, [RepositoryEntry, ...]}`: list - repositories that supply the project itself and its dependencies. Same format and deduplication rules as [Manifest Repositories](#manifest-repositories) in the SDK manifest. The project's own repository (if any) and all dependency repositories are collected here; both the project's `repository` field and each dependency's `repository` field reference entries by `RepoId`.
    - `{dependencies, [DepEntry, ...]}`: list - project dependencies with version and source information. See [Project Dependency Entry](#project-dependency-entry).
    - `{integrity, [IntegrityEntry, ...]}`: proplist - manifest integrity hash. Same format as all Alloy manifests; see [Manifest Integrity Specification](#manifest-integrity-specification).

### Project Dependency Entry

**Format:** `{DepName, [DepField, ...]}`

`DepName`: atom
- Dependency name (application name).

`DepField`: tuple
- any of:
    - `{version, Version}`: string (binary) - dependency version.
    - `{type, Type}`: atom - source type: `git`, `hex`, `path`.
    - `{repository, RepoId}`: atom (optional) - key into the `repositories` section of this manifest. Present for `git` dependencies (including checkout overrides that are git repositories); omit for `hex` and `path`.
    - `{ref, Ref}`: string (binary) - tag, branch, or hex version used to resolve the dependency.
    - `{checkout, Checkout}`: boolean (optional, default `false`) - when `true`, indicates this dependency was resolved from the project's `_checkouts/` directory rather than from the source declared in the lock file (`rebar.lock` or `mix.lock`). This is a traceability marker: it signals that the lock file was not authoritative for this dependency at build time.

**Rules:**
- For `git` dependencies: the `repository` field references a `RepoId` in the project manifest's `repositories` section, which holds the full VCS details (`url`, `commit`, `describe`, `dirty`). This follows the same indirection pattern as nuggets in the [SDK manifest](#manifest-nuggets).
- For `hex` dependencies: no repository reference; `ref` is the hex version.
- For `path` dependencies: no repository reference; `ref` is the local path used to resolve the dependency.
- For **checkout overrides** (dependency resolved from `_checkouts/dep_name/`):
  - Set `{checkout, true}`.
  - If the checkout directory is a git repository: `{type, git}`, `{repository, RepoId}` with the checkout's actual VCS information (URL, commit, describe, dirty), `{ref, Ref}` from the checkout's current git state. The `dirty` flag in the repository entry is particularly important - a dirty checkout means the build used uncommitted local modifications.
  - If the checkout directory is not a git repository (plain source): `{type, path}`, no `repository`, `{ref, <<"_checkouts/dep_name">>}`. No VCS traceability is possible for this dependency.
  - In both cases, the manifest records the **actual code used** at build time, not what the lock file declared.

### Project Manifest Example

```erlang
%% coding: utf-8
{project_manifest, <<"1.0">>, [
    {id, my_app},
    {name, <<"my_app">>},
    {version, <<"1.2.0">>},
    {app_name, my_app},
    {app_version, <<"1.2.0">>},
    {type, erlang},
    {profile, <<"prod">>},
    {sdk_product, <<"grisp2_vanilla">>},
    {sdk_version, <<"1.0.0">>},
    {build_date, <<"2026-02-13T14:30:00Z">>},
    {target_arch, <<"arm-buildroot-linux-gnueabihf">>},
    {otp_version, <<"26.2">>},

    %% Project's own source repository
    {repository, my_app},

    {repositories, [
        {my_app, [
            {name, <<"my_app">>},
            {type, git},
            {url, <<"https://github.com/acme/my_app.git">>},
            {commit, <<"f1e2d3c4b5a6">>},
            {describe, <<"v1.2.0">>},
            {dirty, false}
        ]},
        {grisp_updater, [
            {name, <<"grisp_updater">>},
            {type, git},
            {url, <<"https://github.com/grisp/grisp_updater.git">>},
            {commit, <<"b2c3d4e5f6a7">>},
            {describe, <<"v1.0.1-3-gb2c3d4e-dirty">>},
            {dirty, true}
        ]}
    ]},

    {dependencies, [
        {grisp, [
            {version, <<"2.5.0">>},
            {type, hex},
            {ref, <<"2.5.0">>}
        ]},
        {grisp_updater, [
            {version, <<"1.0.1">>},
            {type, git},
            {repository, grisp_updater},
            {ref, <<"v1.0.1-3-gb2c3d4e-dirty">>},
            {checkout, true}
        ]}
    ]},

    {integrity, [
        {digest_algorithm, sha256},
        {canonical_form, basic_term_canon},
        {digest, <<"b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef12345678">>}
    ]}
]}.
```

---

## Firmware Manifest Specification

This section defines the `ALLOY_FIRMWARE_MANIFEST` file: its structure and fields.

**Purpose:** Provide firmware-level traceability by combining the SDK manifest, all project manifests, and firmware build metadata into a single document. Stored as `ALLOY_FIRMWARE_MANIFEST` in the firmware build output and in the firmware artefact.

**Format:** Erlang term file. The file MUST follow the [Erlang term file format conventions](00_OVERVIEW.md#erlang-term-file-format-conventions) from the [Overview](00_OVERVIEW.md).

**Generated by:** The `manifest-tool` escript invoked by `alloy build firmware`. See [Alloy Design](03_ALLOY_DESIGN.md#878-scripts-tools).

### Firmware Manifest Root Format

**Format:** `{firmware_manifest, ManifestVersion, [SectionEntry, ...]}.`

**Specification:**

`ManifestVersion`: string (binary)
- Schema version of the firmware manifest format.
- Example: `<<"1.0">>`.

`SectionEntry`: tuple
- any of:
    - `{build_date, Date}`: string (binary) - ISO 8601 UTC timestamp of the firmware build.
    - `{firmware_name, Name}`: string (binary) - name assigned to the firmware. May be derived from product + project names or explicitly provided by the user at firmware build time.
    - `{firmware_version, Version}`: string (binary) - firmware version. May be derived from product + project versions or explicitly provided by the user at firmware build time. When explicitly provided, it represents the firmware package version and does not replace project release or app versions in the embedded project manifests.
    - `{firmware_variant, Variant}`: atom - the firmware variant selected for this build (e.g. `plain`, `secure`, `encrypted`). This is the single source of truth for the security/build profile; no separate boolean flags are needed.
    - `{security_pack, PackInfo}`: proplist or `none` - identifying metadata of the security pack used for this build, or `none` when no security pack was used. The metadata is entirely sourced from the pack's `secpack info` command output (see [Alloy Design - Security Pack Command Contract](03_ALLOY_DESIGN.md#security-pack-command-contract)). The orchestrator stores this metadata **opaquely** - it does not interpret, validate, or filter the fields beyond key format validation (keys must match `[a-z][a-z0-9_]*`). The pack is solely responsible for reporting relevant traceability metadata (e.g. name, version, provider, hash) and for ensuring that no sensitive information appears. No build-machine paths or URLs are recorded by the orchestrator. Keys and values are stored as binaries.
    - `{parameters, [{ParamName, ParamValue}, ...]}`: proplist (optional) - build-time parameters injected via `--param KEY=VALUE` on `alloy build firmware`. `ParamName` is an atom (the lowercased key); `ParamValue` is typed according to the parameter's declared type: binary for `string`, integer for `integer`, atom (`true` | `false`) for `boolean`. Includes both user-provided and default values. Omitted entirely when no parameters were resolved. See [Firmware Parameters Metadata](#firmware-parameters-metadata) and [Alloy Design - Firmware Build Parameters](03_ALLOY_DESIGN.md#48-firmware-build-parameters).
    - `{repositories, [RepositoryEntry, ...]}`: list - consolidated repositories from the SDK manifest and all project manifests. Same entry format as [Manifest Repositories](#manifest-repositories). Deduplicated by URL. See [Embedding and Version Compatibility](#embedding-and-version-compatibility).
    - `{sdk, [SdkField, ...]}`: proplist - SDK manifest content (fields proplist from `ALLOY_SDK_MANIFEST`, without root tuple, `integrity`, or `repositories`). See [Embedding and Version Compatibility](#embedding-and-version-compatibility).
    - `{projects, [[ProjectField, ...], ...]}`: list of proplists - project manifest content (fields proplist from each `ALLOY_PROJECT_MANIFEST`, without root tuple, `integrity`, or `repositories`). Each project proplist is augmented with a `{project_root, Path}` field injected at firmware build time (see [Embedding and Version Compatibility](#embedding-and-version-compatibility)).
    - `{integrity, [IntegrityEntry, ...]}`: proplist - manifest integrity hash. Same format as all Alloy manifests; see [Manifest Integrity Specification](#manifest-integrity-specification).

### Embedding and Version Compatibility

When `manifest-tool` builds the firmware manifest, it **strips the root tuple, `integrity`, and `repositories`** from each source manifest, **consolidates all repositories** into a single top-level section, and embeds the remaining fields:

1. **Version compatibility:** Validate that the `ManifestVersion` of every source manifest (SDK and all projects) is compatible with the firmware manifest version. If a source manifest has an incompatible version (e.g. a major version mismatch), abort with a clear error. The firmware manifest's own `ManifestVersion` in the root tuple `{firmware_manifest, <<"1.0">>, ...}` is the single authoritative schema version for the merged result.

2. **Repository consolidation:** Collect the `repositories` section from the SDK manifest and from every project manifest. Deduplicate by URL using the same [Repository Deduplication](#repository-deduplication) algorithm. If a `RepoId` conflict occurs between sources (e.g. the SDK and a project both define a repo named `foo` but with different URLs), resolve using numeric suffixes as specified. The result is a single `{repositories, [...]}` section in the firmware manifest containing all repositories from all sources.

3. **Embedding:**
   - From `{sdk_manifest, Version, Fields}`-> extract `Fields`, remove `integrity` and `repositories`-> store as `{sdk, Fields}`.
   - From each `{project_manifest, Version, Fields}` -> extract `Fields`, remove `integrity` and `repositories` -> append to `{projects, [Fields, ...]}`.

4. **Project root injection:** For each project entry in `{projects, [...]}`, the orchestrator injects a `{project_root, Path}` field recording the absolute filesystem path where the project's OTP release is installed in the firmware rootfs (e.g. `<<"/srv/alloy/alpha">>`). This path is determined at firmware build time from the project name or the `--name` flag, and is not present in the source `ALLOY_PROJECT_MANIFEST`. The `project_root` field is passed to `manifest-tool merge` via `--firmware-info` (see [Alloy Design - manifest-tool merge](03_ALLOY_DESIGN.md#878-scripts-tools)).

Since all `RepoId` references in nuggets, project `repository` fields, and dependencies point into the now-consolidated `repositories` section, all cross-references remain valid. No rewriting of `RepoId` values is needed as long as no ID conflicts occur; when a conflict is resolved by renaming, the tool must also update the corresponding `repository` references in the affected nuggets, projects, or dependencies.

### Firmware Manifest Example

```erlang
%% coding: utf-8
{firmware_manifest, <<"1.0">>, [
    {build_date, <<"2026-02-13T15:00:00Z">>},
    {firmware_name, <<"firmware-my_app-1.2.0-grisp2_vanilla-1.0.0">>},
    {firmware_version, <<"1.0.0">>},
    {firmware_variant, plain},
    {security_pack, none},

    %% Build-time parameters injected via --param (omitted if none resolved)
    %% Values are typed: binary for string, integer for integer, atom for boolean
    {parameters, [
        {serial_number, <<"SN-2026-00042">>},   %% string
        {batch_id, <<"B2026-02">>},              %% string
        {factory_mode, false}                    %% boolean (from default)
    ]},

    %% Consolidated repositories from SDK + all projects (deduplicated by URL)
    {repositories, [
        {grisp_alloy, [
            {name, <<"grisp_alloy">>},
            {type, git},
            {url, <<"https://github.com/grisp/grisp_alloy.git">>},
            {commit, <<"abc123def456">>},
            {describe, <<"v2.0.0">>},
            {dirty, false}
        ]},
        {my_app, [
            {name, <<"my_app">>},
            {type, git},
            {url, <<"https://github.com/acme/my_app.git">>},
            {commit, <<"f1e2d3c4b5a6">>},
            {describe, <<"v1.2.0">>},
            {dirty, false}
        ]},
        {grisp_updater, [
            {name, <<"grisp_updater">>},
            {type, git},
            {url, <<"https://github.com/grisp/grisp_updater.git">>},
            {commit, <<"a1b2c3d4e5f6">>},
            {describe, <<"v1.0.0">>},
            {dirty, false}
        ]}
        %% ... other repos from SDK and projects ...
    ]},

    %% SDK manifest fields (root tuple, integrity, and repositories stripped)
    {sdk, [
        {product, <<"grisp2_vanilla">>},
        {product_version, <<"1.0.0">>},
        {product_name, <<"GRiSP 2 Vanilla">>},
        {target_arch, <<"arm-buildroot-linux-gnueabihf">>},
        {build_date, <<"2026-02-13T12:00:00Z">>},
        {nuggets, [
            %% ... nuggets still reference repos by RepoId ...
        ]}
        %% ... other SDK sections (no integrity, no repositories) ...
    ]},

    %% Project proplists (root tuples, integrity, and repositories stripped)
    %% Each project is augmented with {project_root, ...} injected at firmware build time
    {projects, [
        [
            {id, my_app},
            {name, <<"my_app">>},
            {version, <<"1.2.0">>},
            {app_name, my_app},
            {app_version, <<"1.2.0">>},
            {project_root, <<"/srv/alloy/my_app">>},  %% injected at firmware build time
            {type, erlang},
            {profile, <<"prod">>},
            {sdk_product, <<"grisp2_vanilla">>},
            {sdk_version, <<"1.0.0">>},
            {build_date, <<"2026-02-13T14:30:00Z">>},
            {target_arch, <<"arm-buildroot-linux-gnueabihf">>},
            {otp_version, <<"26.2">>},
            {repository, my_app},
            {dependencies, [
                {grisp, [
                    {version, <<"2.5.0">>},
                    {type, hex},
                    {ref, <<"2.5.0">>}
                ]},
                {grisp_updater, [
                    {version, <<"1.0.0">>},
                    {type, git},
                    {repository, grisp_updater},
                    {ref, <<"v1.0.0">>}
                ]}
            ]}
        ]
    ]},

    {integrity, [
        {digest_algorithm, sha256},
        {canonical_form, basic_term_canon},
        {digest, <<"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890">>}
    ]}
]}.
```

---

## Manifest Integrity Specification

This section defines the `integrity` section that is **common to all Alloy manifests** (SDK, project, firmware). Using the same format and algorithm across all manifest types means a single tool (e.g. `manifest-tool verify`) can validate any manifest without knowing its type.

**Purpose:** Provide a self-describing cryptographic hash of the manifest content so that tampering or accidental change can be detected. The hash is computed over the canonicalized manifest **excluding** the integrity section itself. The integrity section explicitly names the digest algorithm and the canonical form used, making manifests verifiable without external knowledge of the generator version.

**Format:** `{integrity, [IntegrityField, ...]}`

**Specification:**

`IntegrityField`: tuple
- all of:
    - `{digest_algorithm, Algorithm}`: atom - identifies the hash function used. Currently `sha256`. Future versions may introduce additional algorithms (e.g. `sha3_256`).
    - `{canonical_form, FormId}`: atom - identifies the canonicalization algorithm used to serialize the manifest before hashing. Currently `basic_term_canon`. This field enables forward compatibility: if the canonicalization changes in a future version, verifiers can detect the change and select the appropriate algorithm or refuse gracefully.
    - `{digest, Hash}`: string (binary) - hex-encoded digest of the canonicalized manifest content. The length depends on `digest_algorithm` (64 hex characters for `sha256`).

**Canonical forms:**

#### `basic_term_canon`

Strip the `integrity` entry from the root proplist. Serialize the remainder to a minimal Erlang term binary. Compute the digest over the resulting binary.

**Canonicalization procedure:**

1. Parse the manifest as an Erlang term.
2. Remove the `{integrity, _}` entry from the root proplist (the third element of the `{Tag, Version, Fields}` root tuple).
3. Serialize the resulting term to a UTF-8 binary following the serialization rules below.

**Serialization rules:**

The canonical serialization produces valid Erlang term syntax with all non-meaningful whitespace removed. The output is not intended to be human-readable.

- **Encoding:** UTF-8. Line terminator: `\n` (LF only, no `\r`).
- **Term terminator:** The serialized term ends with `.\n` (period followed by newline), as required by the Erlang term file format.
- **Whitespace:** No whitespace between tokens except where syntactically required by Erlang (e.g. between consecutive bare atoms). No comments. No blank lines.
- **Order:** All elements retain their original order - tuples, lists, and property lists are serialized in the order they appear in the parsed term. No sorting or reordering of any kind.
- **Atoms:** Bare atoms that match `[a-z][a-z0-9_@]*` are unquoted. All other atoms are single-quoted using standard Erlang quoting rules (e.g. `'Foo'`, `'hello world'`). No unnecessary quoting.
- **Integers:** Standard decimal representation, no leading zeros, no underscores. Negative integers use the `-` prefix with no space.
- **Binaries:** String binaries use `<<"...">>` syntax. Characters inside binary strings are preserved literally (including whitespace and `\n`). Standard Erlang escape sequences are used for non-printable characters. Binary content is never rewritten to integer-byte syntax.
- **Tuples:** `{E1,E2,...,En}` - no spaces after `{`, before `}`, or around commas.
- **Lists:** `[E1,E2,...,En]` - no spaces after `[`, before `]`, or around commas. Empty list: `[]`.
- **Separators:** Commas between elements, no trailing comma.
- **No formatting tokens:** No comments (`%`), no carriage returns (`\r`), no indentation, no trailing whitespace on any implicit line.

> **Why preserve order:** Alloy manifests use property list order as a semantic signal in many contexts. Nuggets are listed in topological order, repositories in first-occurrence order, and config keys follow last-wins override semantics. Reordering (e.g., sorting keys lexicographically) would destroy this information and could cause semantically different manifests to produce identical hashes. The canonical form normalizes formatting - not structure.
>
> **Top-level field ordering:** Some orderings are semantically meaningful (e.g. nugget lists, repository lists) while others are not (e.g. the order of top-level section fields like `{product, ...}`, `{build_date, ...}`, etc.). Rather than introducing special-case rules (e.g. "sort top-level keys but preserve order elsewhere") or mandating a rigid declaration order, `basic_term_canon` applies the same rule uniformly: **all order is preserved as-is**. Since manifests are machine-generated and the integrity hash is computed by the same tool that writes the manifest, the field order is always deterministic for a given generator version. Reordering any fields - whether semantically significant or not - invalidates the integrity hash. This is correct behavior: it detects any modification to the manifest, including structural rearrangement.

New canonical forms may be added in future versions. Verifiers MUST refuse to verify a manifest whose `canonical_form` they do not recognize, rather than silently failing.

**Validation:**
- All three fields (`digest_algorithm`, `canonical_form`, `digest`) are required.
- `digest` must be a lowercase hex string of the correct length for the named algorithm (64 characters for `sha256`).
- Verification is optional for consumers but MUST use the canonicalization algorithm identified by `canonical_form` and the hash function identified by `digest_algorithm`.

**Rules:**
- The generator must: (1) remove the `integrity` section from the manifest if present, (2) serialize the remainder using the canonical form identified by `canonical_form`, (3) compute the digest using `digest_algorithm`, (4) add the `integrity` section with all three fields. This allows re-verification by repeating the same process.
- The canonicalization and verification algorithm is the same regardless of the manifest type (`sdk_manifest`, `project_manifest`, or `firmware_manifest` root tag). The tool strips the `integrity` entry, serializes, hashes, and compares.
- This uniformity is what allows `manifest-tool verify <file>` to work on any manifest without a `--type` flag.

**Examples:**

```erlang
{integrity, [
    {digest_algorithm, sha256},
    {canonical_form, basic_term_canon},
    {digest, <<"a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456">>}
]}
```

---

## Filesystem Priority Specification

This section defines the `ALLOY_FS_PRIORITIES` file format used for filesystem file ordering.

**Purpose:** Control file ordering in the final firmware filesystem for boot-time performance optimization. Files with higher weight are placed earlier in the filesystem. The format is inspired by the `mksquashfs -sort` file convention (`path weight` per line) but differs in one key way: **paths are always relative** to the directory tree containing the `ALLOY_FS_PRIORITIES` file (no leading `/`). The orchestrator relocates each path by prepending the tree's installation base in the rootfs before producing the final consolidated file. The consolidated file (with absolute rootfs paths) is then passed to the filesystem builder feature nugget (e.g. `feature_squashfs`), which adapts it to the target filesystem. For SquashFS this becomes a direct `mksquashfs -sort` file; other filesystem builders may ignore it or map it to their own ordering mechanism.

**Format:** Plain text, one entry per line. Each entry is `path weight` separated by whitespace.

**Path:** Relative path (no leading `/`) within the directory tree containing the `ALLOY_FS_PRIORITIES` file. Glob patterns (`*`, `?`) are supported. During consolidation, the orchestrator prepends the tree's installation base to produce the final absolute rootfs path (see [Alloy Design - Filesystem Priority Consolidation](03_ALLOY_DESIGN.md#filesystem-priority-consolidation)).

**Weight:** Integer. Higher weight means higher priority (placed earlier in the filesystem). Negative weights are allowed.

**Comments:** Lines starting with `#` are comments. Empty lines are ignored.

**Sources:** Any overlay source may provide a priority fragment: nuggets (via the [`fs_priorities` metadata field](#filesystem-priority-metadata)), projects (via `ALLOY_FS_PRIORITIES` in `release/` and/or at the root of the overlay directory exported by the project plugin), security packs (via `ALLOY_FS_PRIORITIES` in the generated overlay directory), and command-line overlay directories (via `ALLOY_FS_PRIORITIES` at the overlay root). The orchestrator collects all fragments, relocates their paths, and consolidates them before hooks run. For projects, the release is staged under `/srv/alloy/<name>/` at firmware build time, so release-root-relative paths are relocated with that base; the overlay root maps to `/`.

**Relocation:** Each `ALLOY_FS_PRIORITIES` file is associated with a directory tree that has a known installation base in the final rootfs. The orchestrator produces absolute paths by prepending that base: `${INSTALL_BASE}/${PATH}`. The installation base depends on the source:

| Source | Installation base | Example |
|--------|------------------|---------|
| Nugget `fs_priorities` | `/` (rootfs root - nuggets install via Buildroot) | `usr/lib/libfoo.so 500` -> `/usr/lib/libfoo.so 500` |
| Project `release/` | `/srv/alloy/<name>/` | `bin/my_app 1000` -> `/srv/alloy/my_app/bin/my_app 1000` |
| Project `overlay/` | `/` | `etc/my_app.conf 500` -> `/etc/my_app.conf 500` |
| Security pack overlay | `/` | `etc/ssl/device.pem 400` -> `/etc/ssl/device.pem 400` |
| Command-line overlay | `/` | `etc/hostname 100` -> `/etc/hostname 100` |

**Consolidation rules:** When multiple priority files are merged, the **last** occurrence of a path wins (consistent with the overlay last-wins convention - later sources override earlier ones). The final consolidated list is sorted by weight descending. See [Alloy Design - Filesystem Priority Consolidation](03_ALLOY_DESIGN.md#filesystem-priority-consolidation).

**Fragment example** (a nugget `fs_priorities` file - paths relative to rootfs root):

```
# System libraries used early in boot
usr/lib/libcrypto.so* 800
usr/lib/libssl.so* 700
etc/erlinit.config 600
```

**Fragment example** (a project `release/ALLOY_FS_PRIORITIES` - paths relative to the release root, installation base `/srv/alloy/<name>/`):

```
# Application BEAM files
lib/my_app-1.0.0/ebin/* 800
lib/my_app-1.0.0/priv/* 700
releases/1.0.0/my_app.boot 900
bin/my_app 1000
```

**Fragment example** (a project `overlay/ALLOY_FS_PRIORITIES` - paths relative to overlay root, installation base `/`):

```
# Project configuration files
etc/my_app.conf 500
etc/systemd/system/my_app.service 400
```

---

## Environment Variables and Functions

This section lists all variables and functions available in the build environment. The list is the **data contract** for consumers (metadata resolution, hook scripts, context consumer).

### Defined By

- **Orchestrator** - Set at runtime by the component that runs the build. Values do not come from nuggets metadata; they depend on the current run (paths, flags, hook type).
- **Metadata** - Derived from nugget metadata and [config consolidation](#config-consolidation). Keys and structure are determined by the nugget tree.
- **Buildroot** - Set by Buildroot when it invokes hooks. Format and semantics are defined by Buildroot; this document only references their existence where relevant.

### Available To

- **Metadata** - Used during metadata resolution: template substitution in `{computed, Template}`, `[[KEY]]` in defconfig fragments, and the environment of `{exec, Script}` scripts during config consolidation.
- **All hooks** - Passed to every hook script when it runs (`pre_build`, `post_build`, `post_image`, `post_fakeroot`, `pre_firmware`, `firmware_build`, `post_firmware`).
- **pre_build hooks** - Only when `pre_build` hooks run.
- **Firmware hooks** - Only when `pre_firmware`, `firmware_build`, or `post_firmware` hooks run.
- **Everywhere** - means both **Metadata** (during resolution) and **All hooks** (when any hook runs).
- **Orchestrator** - Variable only available for the orchestrator. Generally generated from metadata so the orchestrator can call hooks and embed SDK content.

### Variables

| Variable | Defined By | Available To | Description |
|----------|------------|--------------|-------------|
| `ALLOY_MOTHERLODE` | Orchestrator | Everywhere | Root directory of all staged nugget repositories; base for `ALLOY_NUGGET_<NAME>_DIR` paths. |
| `ALLOY_BUILD_DIR` | Orchestrator | Everywhere | Root of the current build directory for this run. Fixed by mode (not user-configurable); see [Build Directory](#build-directory). |
| `ALLOY_SDK_STAGING_DIR` | Orchestrator | SDK build | During SDK build, staging directory under `${ALLOY_BUILD_DIR}/sdk/<PRODUCT>/staging/` where final manifest and merged legal-info export are written before packing. Used so the pack step and smelterl `--export-legal` (path relative to manifest) produce a consistent layout across all targets. See [SDK build directory](#sdk-build-directory). |
| `ALLOY_CACHE_DIR` | Orchestrator | Everywhere | Cache directory (e.g. Buildroot downloads, toolchain). Fixed by mode (not user-configurable); see [Cache Directory](#cache-directory). |
| `ALLOY_ARTEFACT_DIR` | Orchestrator | Everywhere | Artefact directory (tools, toolchains, SDKs, firmware outputs). Fixed by mode (not user-configurable); see [Artefact Directory](#artefact-directory). |
| `ALLOY_DEBUG` | Orchestrator | All hooks | Integer debug verbosity level (default: `0`). Controls how much structured output is shown: `0` = errors and warnings only; `1` = add informational progress (`log_info`); `2` = add developer debug messages (`log_debug`); `3` = add Buildroot verbose output (`V=1`). Set by `--debug` (implies level 1) or `--debug=N`. Hooks use this to gate calls to `log_info` and `log_debug`. See [Alloy Design - §4.9](03_ALLOY_DESIGN.md#49-logging-and-debugging). |
| `ALLOY_TRACE` | Orchestrator | All hooks | When set to `true`, enables bash `set -x` xtrace in the orchestrator and in all hook wrappers (`script_hook.sh`). Completely independent of `ALLOY_DEBUG` - can be set alone or combined with any debug level. Set by `--trace`. Used for debugging the bash scripts themselves, not for application-level log output. See [Alloy Design - §4.9](03_ALLOY_DESIGN.md#49-logging-and-debugging). |
| `ALLOY_FORWARD_ENV` | User | Vagrant flow | Comma-separated list of environment variable name patterns to forward to the Vagrant VM. Each pattern is an exact name (e.g. `SIGNING_TOKEN`) or a prefix pattern ending with `*` (e.g. `SIGNING_*`). Consumed by the Vagrant abstraction flow and NOT forwarded to the VM itself. Ignored on native Linux builds. Can also be specified via the `--forward-env` global option (repeatable). See [Alloy Design - §5.3 Environment Forwarding](03_ALLOY_DESIGN.md#environment-forwarding). |
| `ALLOY_HOOK_TYPE` | Orchestrator | All hooks | The hook type being invoked: one of `pre_build`, `post_build`, `post_image`, `post_fakeroot`, `pre_firmware`, `firmware_build`, `post_firmware`. |
| `ALLOY_ROOT_DIR` | Orchestrator | All hooks | Root of the alloy installation. In SDK mode (firmware builds) this equals the SDK root (same value as `ALLOY_SDK_DIR`). In builder mode (SDK builds) this equals the alloy repository root. Provides a stable base path to all alloy scripts and tools from any hook context: `${ALLOY_ROOT_DIR}/scripts/utils/`, `${ALLOY_ROOT_DIR}/scripts/tools/`, etc. Passed as a Buildroot make parameter so `script_hook.sh` can source `scripts/utils/common.sh`. Hook scripts do not need to source `common.sh` directly - wrappers do it for them. |
| `ALLOY_SDK_DIR` | Orchestrator | Firmware hooks | SDK root directory (where `alloy_context.sh` and `motherlode/` live). In SDK mode equals `ALLOY_ROOT_DIR`. Kept as a semantically distinct variable for firmware hook context - firmware hooks use this to reference the SDK they were built against. |
| `ALLOY_FIRMWARE_VARIANT` | Orchestrator | Firmware hooks | The selected firmware variant name (lowercase, e.g. `plain`, `secure`). Set from `--firmware-variant` flag or defaulting to `plain`. |
| `ALLOY_SECURITY_PACK` | Orchestrator | Firmware hooks | Absolute path to the resolved security pack entry point executable; unset if no pack is configured. Can be initially set by the user via the `ALLOY_SECURITY_PACK` environment variable or the `--security-pack` CLI option (CLI overrides env). The user provides a path to either an executable file or a directory containing a `secpack` executable at its root. The orchestrator resolves, validates, and canonicalizes the value to the absolute path of the entry point executable using `security_resolve_pack` from `security_utils.sh` (see [Alloy Design - §8.6.14](03_ALLOY_DESIGN.md#8614-securityutilssh)). All interaction with the pack goes through `security_tools.sh` functions (see [Alloy Design - §8.6.12](03_ALLOY_DESIGN.md#8612-securitytoolssh)). Hooks MUST NOT invoke this executable directly. |
| `ALLOY_SECURITY_*` | Orchestrator | Firmware hooks | Security pack configuration exported from `secpack env`. Each key=value pair from the pack's output (keys must match `[a-z][a-z0-9_]*`) is exported as `ALLOY_SECURITY_<KEY>` (key uppercased). Provides signing configuration, overlay file paths, feature flags, etc. See [Alloy Design - Security Pack Command Contract](03_ALLOY_DESIGN.md#security-pack-command-contract). |
| `ALLOY_OUTPUT_<ID>` | Orchestrator | Firmware hooks | `true` or `false` for each selectable output (from `firmware_outputs` metadata with `{selectable, true}`). `<ID>` is the output identifier uppercased (e.g. `ALLOY_OUTPUT_FWUP_FIRMWARE`, `ALLOY_OUTPUT_IMAGE`). Set to `true` if the output was selected (either explicitly via `--output-<id>` or by being in the default selection), `false` otherwise. Hooks check this variable to decide whether to produce their output. See [Firmware Outputs Metadata](#firmware-outputs-metadata) and [Alloy Design - Output Selection](03_ALLOY_DESIGN.md#47-output-selection). |
| `ALLOY_PARAM_<ID>` | Orchestrator | Firmware hooks | Build-time parameter value from `--param <id>=<value>` (or default from metadata). `<ID>` is the parameter identifier uppercased (e.g. `ALLOY_PARAM_SERIAL_NUMBER`). Only set for parameters that were provided or have defaults. See [Firmware Parameters Metadata](#firmware-parameters-metadata) and [Alloy Design - Firmware Build Parameters](03_ALLOY_DESIGN.md#48-firmware-build-parameters). |
| `ALLOY_FIRMWARE_WORK_DIR` | Orchestrator | Firmware hooks | Working directory for the current firmware build. All hook outputs are written here. |
| `ALLOY_FIRMWARE_BASE_ROOTFS` | Orchestrator | Firmware hooks | Path to the SDK base rootfs image. Set in step 13 of the firmware build flow: if `ALLOY_CONFIG_BASE_ROOTFS` is set (from a nugget's `base_rootfs` config/exports), it must be in the form `${ALLOY_SDK_DIR}/images/...` so it resolves when `ALLOY_SDK_DIR` is set; the orchestrator evaluates it and sets `ALLOY_FIRMWARE_BASE_ROOTFS` to the resolved path. Otherwise the orchestrator defaults to `"${ALLOY_SDK_DIR}/images/rootfs.squashfs"`. Thus **which file is the base rootfs** is defined by nugget configuration, not hardcoded. Primarily consumed by `pre_firmware` hooks (e.g. `feature_squashfs`). See [Alloy Design - Base rootfs path](03_ALLOY_DESIGN.md#base-rootfs-path). |
| `ALLOY_FIRMWARE_ROOTFS_OVERLAY` | Orchestrator | Firmware hooks | Path to the consolidated rootfs overlay directory (built by the orchestrator from nugget, project, security pack, and CLI overlays before any hooks run). Primarily consumed by `pre_firmware` hooks. Available to all firmware hooks (e.g. `firmware_build` hooks may reference overlay files for signing). |
| `ALLOY_CONFIG_ROOTFS` | Nugget config | Firmware hooks | Path to the merged rootfs image (e.g. produced by `feature_squashfs`). Declared by the nugget at SDK build time with a value like `${ALLOY_FIRMWARE_WORK_DIR}/rootfs.merged.squashfs`; it resolves when `ALLOY_FIRMWARE_WORK_DIR` is set. Consumed by `firmware_build` and other hooks that need the merged rootfs. See [Alloy Design - Run pre_firmware hooks](03_ALLOY_DESIGN.md#57-firmware-build-flow). |
| `ALLOY_FIRMWARE_FS_PRIORITIES` | Orchestrator | Firmware hooks | Path to the consolidated filesystem priorities file (built by the orchestrator before any hooks run). Primarily consumed by `pre_firmware` hooks. Available to all firmware hooks. |
| `ALLOY_NUGGET` | Orchestrator | All hooks | Identifier of the nugget whose hook is currently running. Set before each hook invocation. |
| `ALLOY_NUGGET_DIR` | Orchestrator | All hooks | Directory of the current nugget. Set before each hook invocation. |
| `ALLOY_NUGGET_NAME` | Orchestrator | All hooks | Display name of the current nugget. Set before each hook invocation. |
| `ALLOY_NUGGET_DESC` | Orchestrator | All hooks | Description of the current nugget. Set before each hook invocation. |
| `ALLOY_NUGGET_VERSION` | Orchestrator | All hooks | Version of the current nugget. Set before each hook invocation. |
| `ALLOY_NUGGET_FLAVOR` | Orchestrator | All hooks | Flavor of the current nugget; empty if not set. Set before each hook invocation. |
| `ALLOY_PRODUCT` | Metadata | Everywhere | Current target identifier from the sourced context script (main product id for main target; auxiliary target id for auxiliary target). |
| `ALLOY_IS_AUXILIARY` | Metadata | Everywhere | `true` when the sourced context is for an auxiliary target, `false` for main target. |
| `ALLOY_AUXILIARY` | Metadata | Everywhere | Auxiliary target ID when `ALLOY_IS_AUXILIARY=true`; empty for main target contexts. |
| `ALLOY_PRODUCT_NAME` | Metadata | Everywhere | Product display name. |
| `ALLOY_PRODUCT_DESC` | Metadata | Everywhere | Product description. |
| `ALLOY_PRODUCT_VERSION` | Metadata | Everywhere | Product version. |
| `ALLOY_NUGGET_<NAME>_DIR` | Metadata | Everywhere | Directory for nugget `<NAME>`. `<NAME>` is the nugget uppercase identifier (e.g. `PLATFORM_IMX6` in shell). |
| `ALLOY_NUGGET_<NAME>` | Metadata | Everywhere | Nugget identifier for `<NAME>` (same as `<NAME>` but usually lowercase). |
| `ALLOY_NUGGET_<NAME>_NAME` | Metadata | Everywhere | Display name of nugget `<NAME>`. |
| `ALLOY_NUGGET_<NAME>_DESC` | Metadata | Everywhere | Description of nugget `<NAME>`. |
| `ALLOY_NUGGET_<NAME>_VERSION` | Metadata | Everywhere | Version of nugget `<NAME>`. |
| `ALLOY_NUGGET_<NAME>_FLAVOR` | Metadata | Everywhere | Resolved flavor of nugget `<NAME>`; empty if no flavor. |
| `ALLOY_NUGGET_<NAME>_CONFIG_<KEY>` | Metadata | Everywhere | Per-nugget configuration value for `<KEY>` declared by nugget `<NAME>`. Keys come from nugget `config` and `exports`; see [Config Consolidation](#config-consolidation). |
| `ALLOY_CONFIG_<KEY>` | Metadata | Everywhere | Global consolidated configuration (last-wins over nugget order). Keys come from nugget `config` and `exports`; see [Config Consolidation](#config-consolidation). |
| `ALLOY_NUGGET_ORDER` | Metadata | Orchestrator | Bash array of nugget identifiers in [topological order](#topology-order). Not exported to hook scripts. |
| `ALLOY_PRE_BUILD_HOOKS` | Metadata | Orchestrator | Bash array of scripts to execute for `pre_build` hooks (topological order). |
| `ALLOY_POST_BUILD_HOOKS` | Metadata | Orchestrator | Bash array of scripts to execute for `post_build` hooks (topological order). |
| `ALLOY_POST_IMAGE_HOOKS` | Metadata | Orchestrator | Bash array of scripts to execute for `post_image` hooks (topological order). |
| `ALLOY_POST_FAKEROOT_HOOKS` | Metadata | Orchestrator | Bash array of scripts to execute for `post_fakeroot` hooks (topological order). |
| `ALLOY_PRE_FIRMWARE_HOOKS_<VARIANT>` | Metadata | Orchestrator (main target context) | One bash array per firmware variant (variant name uppercased). Each array contains `pre_firmware` hook scripts in topological order, including all variant-less nuggets plus all nuggets whose `firmware_variant` list includes the variant. |
| `ALLOY_FIRMWARE_VARIANTS` | Metadata | Main target context and firmware hooks | Bash array of available firmware variant names (lowercase), discovered from all nuggets' `firmware_variant` metadata in the main target tree. Example: `("plain" "secure" "encrypted")`. Allows the orchestrator to enumerate and validate `--firmware-variant` selection at runtime. |
| `ALLOY_FIRMWARE_BUILD_HOOKS_<VARIANT>` | Metadata | Orchestrator (main target context) | One bash array per firmware variant (variant name uppercased). Each array contains `firmware_build` hook scripts in topological order, including all variant-less nuggets plus all nuggets whose `firmware_variant` list includes the variant. Dynamically generated - the set of arrays depends on which nuggets declare `firmware_variant` in the main target tree. Example: `ALLOY_FIRMWARE_BUILD_HOOKS_PLAIN`, `ALLOY_FIRMWARE_BUILD_HOOKS_SECURE`. |
| `ALLOY_POST_FIRMWARE_HOOKS_<VARIANT>` | Metadata | Orchestrator (main target context) | One bash array per firmware variant (variant name uppercased). Each array contains `post_firmware` hook scripts in topological order, including all variant-less nuggets plus all nuggets whose `firmware_variant` list includes the variant. |
| `ALLOY_EMBED_IMAGES` | Metadata | Orchestrator (main target context) | Bash array of embedded files from buildroot images directory. |
| `ALLOY_EMBED_HOST` | Metadata | Orchestrator (main target context) | Bash array of embedded files from buildroot host directory. |
| `ALLOY_EMBED_NUGGETS` | Metadata | Orchestrator (main target context) | Bash array of embedded files from nugget directories. |
| `ALLOY_NUGGET_<NAME>_FS_PRIORITIES` | Metadata | Orchestrator (main target context) | Path to nugget `<NAME>`'s filesystem priority fragment file (from `fs_priorities` metadata). Only present for nuggets that declare `fs_priorities`. Path is `${ALLOY_MOTHERLODE}`-relative. |
| `ALLOY_FS_PRIORITIES_FRAGMENTS` | Metadata | Orchestrator (main target context) | Bash array of priority fragment references in topological order. Each entry is `<NUGGET_IDENTIFIER>:<PATH>` for nuggets that declare `fs_priorities`. Used by the orchestrator to consolidate all nugget priorities at firmware build time. |
| `ALLOY_FIRMWARE_OUTPUTS` | Metadata | Main target context and firmware hooks | Bash array of declared firmware output identifiers from nuggets' `firmware_outputs` metadata in the main target tree (topological order). Example: `("fwup_firmware" "image" "signed_boot_image")`. Used by the orchestrator for build summary, artefact verification, output listing, and `add_firmware_output` validation. Per-output metadata is in `ALLOY_FIRMWARE_OUT_<ID>_*` variables. See [Firmware Outputs Metadata](#firmware-outputs-metadata). |
| `ALLOY_FIRMWARE_OUT_<ID>_NUGGET` | Metadata | Main target context and firmware hooks | Identifier of the nugget that declares output `<ID>`. |
| `ALLOY_FIRMWARE_OUT_<ID>_SELECTABLE` | Metadata | Main target context and firmware hooks | `true` or `false` - whether output `<ID>` is user-selectable via `--output-*` flags. |
| `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` | Metadata | Main target context and firmware hooks | `true` or `false` - whether output `<ID>` is included in the default selection when no `--output-*` flags are given. Always `false` for non-selectable outputs (where `ALLOY_FIRMWARE_OUT_<ID>_SELECTABLE` is `false`). |
| `ALLOY_FIRMWARE_OUT_<ID>_NAME` | Metadata | Main target context and firmware hooks | Human-readable display name for output `<ID>`. Only present if a name is declared. |
| `ALLOY_FIRMWARE_OUT_<ID>_DESCRIPTION` | Metadata | Main target context and firmware hooks | Description of output `<ID>`. Only present if a description is declared. |
| `ALLOY_OUTPUT_SELECTABLE` | Metadata | Main target context and firmware hooks | Bash array of selectable output identifiers (where `ALLOY_FIRMWARE_OUT_<ID>_SELECTABLE` is `true`), in topological order. Example: `("fwup_firmware" "image")`. Derived convenience array - primarily used by the orchestrator to validate `--output-*` CLI flags and to set `ALLOY_OUTPUT_<ID>` variables. For each entry the orchestrator reads `ALLOY_FIRMWARE_OUT_<ID>_DEFAULT` to determine whether the output is included in the default selection. |
| `ALLOY_FIRMWARE_PARAMETERS` | Metadata | Main target context and firmware hooks | Bash array of declared firmware parameter identifiers (merged from nuggets' `firmware_parameters` metadata in the main target tree), in first-occurrence topological order. Example: `("serial_number" "batch_id" "factory_mode")`. Used by the orchestrator to iterate declared parameters for `--param` validation, default application, required enforcement, and `--list-params` output. Per-parameter metadata is in `ALLOY_FIRMWARE_PARAM_<ID>_*` variables. See [Firmware Parameters Metadata](#firmware-parameters-metadata). |
| `ALLOY_FIRMWARE_PARAM_<ID>_TYPE` | Metadata | Main target context and firmware hooks | Declared type for parameter `<ID>` (uppercased): `string`, `integer`, or `boolean`. |
| `ALLOY_FIRMWARE_PARAM_<ID>_REQUIRED` | Metadata | Main target context and firmware hooks | `true` or `false` - whether parameter `<ID>` must be provided via `--param`. |
| `ALLOY_FIRMWARE_PARAM_<ID>_DEFAULT` | Metadata | Main target context and firmware hooks | Default value for parameter `<ID>`. Only present if a default is declared. May contain any characters. |
| `ALLOY_FIRMWARE_PARAM_<ID>_NAME` | Metadata | Main target context and firmware hooks | Human-readable display name for parameter `<ID>`. Only present if a name is declared. |
| `ALLOY_FIRMWARE_PARAM_<ID>_DESCRIPTION` | Metadata | Main target context and firmware hooks | Description of parameter `<ID>`. Only present if a description is declared. |
| `ALLOY_SDK_OUTPUTS` | Metadata | Target context, SDK-time hooks, firmware hooks (main context) | Bash array of SDK output identifiers declared for the currently sourced target (`main` or auxiliary). |
| `ALLOY_SDK_OUTPUT_<ID>_NAME` | Metadata | Target context, SDK-time hooks, firmware hooks (main context) | Human-readable display name for declared SDK output `<ID>`. |
| `ALLOY_SDK_OUTPUT_<ID>_DESCRIPTION` | Metadata | Target context, SDK-time hooks, firmware hooks (main context) | Description for declared SDK output `<ID>`. |
| `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` | Orchestrator | Main target context, SDK-time hooks, firmware hooks | Absolute path to resolved SDK output `<OUTPUT_ID>` produced by auxiliary target `<AUX_ID>`. Injected into main-target context after auxiliary builds. |
| `ALLOY_SDK_OUTPUT_<OUTPUT_ID>` | Orchestrator | Main target context, SDK-time hooks, firmware hooks | Convenience alias for unique output IDs across auxiliaries. Present only when `<OUTPUT_ID>` is unique. |

**Notes:**

- Variables whose name contains `<NAME>` or `<KEY>` are patterns: `<NAME>` is replaced by the nugget identifier (e.g. `platform_imx6` -> `ALLOY_NUGGET_PLATFORM_IMX6_DIR`); `<KEY>` is the config key (e.g. `device_tree` -> `ALLOY_CONFIG_DEVICE_TREE`). In shell, nugget identifiers are typically uppercased when used in variable names.
- The hook, embed, and nugget-order arrays are only available to the orchestrator and are not exported to hook scripts. The exported firmware-capability variables are `ALLOY_FIRMWARE_VARIANTS`, `ALLOY_FIRMWARE_OUTPUTS`, `ALLOY_FIRMWARE_OUT_<ID>_*`, `ALLOY_OUTPUT_SELECTABLE`, `ALLOY_FIRMWARE_PARAMETERS`, and `ALLOY_FIRMWARE_PARAM_<ID>_*`; they are available to firmware hooks in the **main target context** (via sourcing `alloy_context.sh`). Main-target `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` variables are also available there for auxiliary artefact consumption at firmware build time.
- The arrays `ALLOY_<HOOK_NAME>_HOOKS[_<VARIANT>]` values format is `<NUGGET_NAME>:<SCRIPT_RELATIVE_PATH>`.
- The arrays `ALLOY_EMBED_<SOURCE>` values format is `<NUGGET_NAME>:<RELATIVE_PATH_OR_GLOB>`.
- The array `ALLOY_FS_PRIORITIES_FRAGMENTS` values format is `<NUGGET_NAME>:<FS_PRIORITIES_PATH>`.

### Helper Functions

The following functions are available to hook scripts. They take a lowercase nugget identifier as first argument and avoid constructing variable names manually. All return the value or empty if unset.

| Function | Defined By | Available To | Description |
|----------|------------|--------------|-------------|
| `alloy_nugget_dir <name>` | Metadata | All hooks | Nugget directory; same as `ALLOY_NUGGET_<NAME>_DIR`. |
| `alloy_nugget_name <name>` | Metadata | All hooks | Display name of nugget `<name>`. |
| `alloy_nugget_desc <name>` | Metadata | All hooks | Description of nugget `<name>`. |
| `alloy_nugget_version <name>` | Metadata | All hooks | Version of nugget `<name>`. |
| `alloy_nugget_flavor <name>` | Metadata | All hooks | Flavor of nugget `<name>`; empty if not set. |
| `alloy_config <key>` | Metadata | All hooks | Consolidated configuration value for `<key>`; same as `ALLOY_CONFIG_<KEY>`. |

**Notes:**
- The `<name>` and `<key>` parameters are converted to uppercase and used to construct the variable name; the function echoes the variable value or nothing if not defined.

### Buildroot Variables

When hooks are invoked by Buildroot (e.g. `post_build`, `post_image`, `post_fakeroot`), Buildroot also sets variables such as `TARGET_DIR`, `BINARIES_DIR`, `HOST_DIR`, and others. Their format and semantics are defined by Buildroot and are not enumerated in this document.
