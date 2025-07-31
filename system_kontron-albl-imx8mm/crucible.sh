OS_RELEASE_PRETTY_NAME="Kontron AL/BL i.MX8M Mini"

BOOTSCHEME=AHAB
BOOTSCHEME_KERNEL_FILENAME=Image
BOOTSCHEME_DTB_FILENAME=imx8mm-kontron-bl.dtb
BOOTSCHEME_KERNEL_ITS_WITHOUT_RAMFS=kernel_without_ramfs.its.template
BOOTSCHEME_KERNEL_ITS_WITH_RAMFS=kernel_with_ramfs.its.template

SQUASHFS_PRIORITIES=(
    "sbin/init" 32762
    "etc/erlinit.config" 32761
)

FWUP_IMAGE_TARGETS=(
    "complete" ".emmc"
    "sdcard" ".sdcard"
)
