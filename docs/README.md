# grisp_alloy docs

Per-target design references. These are *design* docs: they explain the
intent and the runtime flow, not the day-to-day build commands. For build
commands see the repo-level [`README.md`](../README.md).

## Index

| Target | Status | Reference |
|---|---|---|
| `system_grisp2` | Supported | (no design doc yet) |
| `system_kontron-albl-imx8mm` | Supported | (no design doc yet) |
| `system_rpi0w` | In development; first-boot working, peripheral bring-up staged, A/B lifecycle not yet exercised on hardware | [`system_rpi0w.md`](./system_rpi0w.md) |

## What a target design doc should cover

Consistency pattern to adopt when filling out the other targets:

1. **Overview**: one-paragraph pitch, one context diagram.
2. **SD / eMMC layout**: byte offsets, partition roles.
3. **Boot chain**: ROM → bootloader (or GPU firmware) → kernel → init.
4. **Runtime state schema**: the `uboot-env` keys, who writes them when.
5. **A/B update lifecycle**: state machine + sequence diagrams for
   factory flash, upgrade, validate, rollback.
6. **Build pipeline**: which `build-*.sh` scripts consume what and
   produce what.
7. **File tree**: `system_<target>/` manifest.
8. **Status / roadmap**: what's done and what's queued.

The Mermaid diagrams in `system_rpi0w.md` are the reference shapes for
the other two targets when we get to them.

## Adding a new target

Before starting, skim [`porting-notes.md`](./porting-notes.md): a
short list of traps we actually hit during the `system_rpi0w`
bring-up (silent Buildroot package ignores, empty `/lib/modules/`,
console-path alignment, etc.). Sample size is one port, so it's a
"read before you start" field notebook, not a canonical guide; expect
it to grow into a proper porting checklist as we add more targets.
