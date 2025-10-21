bootscheme_package_bootloader() {
    # TODO: Sign the bootloader if secureboot is enabled
    :
}

bootscheme_package_kernel() {
    # TODO: Sign the kernel if secureboot is enabled
    # TODO: Add support for encrypted disk via ramdisk
    local USE_RAMFS=${1:-false}
    local MKIMAGE="${GLB_SDK_HOST_DIR}/bin/mkimage"
    local ITS_WITH_RAMFS_TEMPLATE="${GLB_SDK_DIR}/images/${BOOTSCHEME_KERNEL_ITS_WITH_RAMFS}"
    local ITS_WITHOUT_RAMFS_TEMPLATE="${GLB_SDK_DIR}/images/${BOOTSCHEME_KERNEL_ITS_WITHOUT_RAMFS}"
    local KERNEL_FILE="${GLB_SDK_DIR}/images/${BOOTSCHEME_KERNEL_FILENAME}"
    local DTB_FILE="${GLB_SDK_DIR}/images/${BOOTSCHEME_DTB_FILENAME}"

    if [[ ! -f "${MKIMAGE}" ]]; then
        error 1 "mkimage not found at ${MKIMAGE}"
    fi
    if [[ ! -f "${KERNEL_FILE}" ]]; then
        error 1 "kernel image ${BOOTSCHEME_KERNEL_FILENAME} not found at ${KERNEL_FILE}"
    fi
    if [[ "${USE_RAMFS}" == "true" ]]; then
        local ITS_TEMPLATE="${ITS_WITH_RAMFS_TEMPLATE}"
        local INITRAMFS_FILE="${GLB_SDK_DIR}/images/${RAMFS_FILENAME}"
        if [[ ! -f "${INITRAMFS_FILE}" ]]; then
            error 1 "initramfs file ${INITRAMFS_FILENAME} not found at $INITRAMFS_FILE"
        fi
    else
        local ITS_TEMPLATE="$ITS_WITHOUT_RAMFS_TEMPLATE"
        local INITRAMFS_FILE=""
    fi
    if [[ ! -f "${DTB_FILE}" ]]; then
        error 1 "DTB file ${BOOTSCHEME_DTB_FILENAME} not found at ${DTB_FILE}"
    fi
    if [[ ! -f "${ITS_TEMPLATE}" ]]; then
        error 1 "Kernel ITS template not found at ${ITS_TEMPLATE}"
    fi

    local ITS_FILE="${FIRMWARE_DIR}/kernel.its"
    local FITIMAGE_FILE="${FIRMWARE_DIR}/fitImage"

    sed -e "s|%KERNEL%|${KERNEL_FILE}|g" \
        -e "s|%DTB%|${DTB_FILE}|g" \
        -e "s|%RAMFS%|${INITRAMFS_FILE}|g" \
        "${ITS_TEMPLATE}" > "${ITS_FILE}"

    "${MKIMAGE}" -E -p 0x3000 -f "${ITS_FILE}" "${FITIMAGE_FILE}"
}

bootscheme_package_firmware() {
    # TODO: Add support for ramdisk if disk encryption is enabled
    local FWUP="${GLB_SDK_HOST_DIR}/bin/fwup"
    local ROOTFS_FILE="${FIRMWARE_DIR}/combined.squashfs"
    local UBOOT_FILE="${GLB_SDK_DIR}/images/flash.bin"
    local KERNEL_FILE="${FIRMWARE_DIR}/fitImage"

    if [[ ! -f "${FWUP}" ]]; then
        error 1 "fwup not found at ${FWUP}"
    fi
    if [[ ! -f "${UBOOT_FILE}" ]]; then
        error 1 "U-Boot image flash.bin not found at ${UBOOT_FILE}"
    fi
    if [[ ! -f "${ROOTFS_FILE}" ]]; then
        error 1 "Root filesystem combined.squashfs not found at ${ROOTFS_FILE}"
    fi
    if [[ ! -f "${KERNEL_FILE}" ]]; then
        error 1 "Kernel FIT image fitImage not found at ${KERNEL_FILE}"
    fi

    GRISP_FW_DESCRIPTION="${APP_NAME}" \
    GRISP_FW_VERSION="${GLB_COMMON_SYSTEM_VER}-${GLB_TARGET_SYSTEM_VER}-${FIRMWARE_VER}" \
    GRISP_FW_PLATFORM="${GLB_TARGET_NAME}" \
    GRISP_FW_ARCHITECTURE="${CROSSCOMPILE_ARCH}" \
    GRISP_FW_VCS_IDENTIFIER="${GLB_VCS_TAG}${PROJECT_VCS_TAG:+/${PROJECT_VCS_TAG}}" \
    GRISP_SYSTEM="${GLB_SDK_DIR}" \
    UBOOT="${UBOOT_FILE}" \
    ROOTFS="${ROOTFS_FILE}" \
    FITIMAGE="${KERNEL_FILE}" \
        "${FWUP}" -c -f "${SDK_FWUP_CONFIG}" -o "${FIRMWARE_FILE}"
}
