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
    "complete" ""
)

# GRiSP Software Update Package Configuration

GSU_KERNEL_PATH="/boot/fitImage"

# Be sure to keep that in sinc with wfup.conf
GSU_PARTITIONS="gpt=\
reserved:R:01999b27-85c6-727c-a37b-c1838a5c93fa:10240:262144,\
boot:F:01999b27-ae3e-77eb-bc96-2b5da0810af8:272384:131072,\
system:L:01999b27-e0ca-73cf-9908-d9d1961a7df0:403456:524288,\
system:L:01999b27-fffa-74af-9f51-aafad27e9e88:927744:524288,\
data:L:01999b28-1b5a-738e-9a47-649cf192b781:1452032:13817822"
