# GRiSP Alloy Ramfs Common Base

`ramfs_common` is the shared Buildroot external tree for standalone initramfs
artifacts.

It intentionally does not reuse `system_common`. Ramfs builds run before the
normal root filesystem is available, so they must not inherit Erlang, SDK,
firmware packaging, application overlays, or target runtime assumptions.

Target or product policy belongs in `ramfs_<flavour>/defconfig` and the
matching flavour overlay.
