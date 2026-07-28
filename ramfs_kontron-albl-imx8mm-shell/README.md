# Kontron AL/BL i.MX8MM Shell Ramfs Flavour

`ramfs_kontron-albl-imx8mm-shell` is a minimal validation flavour for
`build-ramfs.sh`.

It is not a production initramfs and it is not hardware-generic: its defconfig
targets the Kontron AL/BL i.MX8MM target class. Its `/init` mounts the early
pseudo filesystems, prints basic diagnostics, and drops to a shell so a later
FIT boot test can prove that a ramfs artifact is actually running.
