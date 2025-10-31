OS_RELEASE_PRETTY_NAME="GRiSP2"

BOOTSCHEME=NONE

SQUASHFS_PRIORITIES=(
    "boot/zImage" 32764
    "boot/oftree" 32763
    "sbin/init" 32762
    "etc/erlinit.config" 32761
)

FWUP_IMAGE_TARGETS=(
    "complete" ""
)

# GRiSP Software Update Package Configuration

GSU_KERNEL_PATH="/boot/zImage"

# Be sure to keep that in sinc with wfup.conf
GSU_PARTITIONS="mbr=\
reserved:R:01999b27-85c6-727c-a37b-c1838a5c93fa:8192:262144,\
boot:F:01999b27-ae3e-77eb-bc96-2b5da0810af8:270336:131072,\
system:L:01999b27-e0ca-73cf-9908-d9d1961a7df0:401408:524288,\
system:L:01999b27-fffa-74af-9f51-aafad27e9e88:925696:524288,\
data:L:01999b28-1b5a-738e-9a47-649cf192b781:1449984:13819870"
