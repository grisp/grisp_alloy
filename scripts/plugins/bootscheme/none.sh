bootscheme_package_bootloader() {
    :
}

bootscheme_package_kernel() {
    :
}

bootscheme_package_firmware() {
    local FWUP="${GLB_SDK_HOST_DIR}/bin/fwup"
    local ROOTFS_FILE="${FIRMWARE_DIR}/combined.squashfs"

    if [[ ! -f "${FWUP}" ]]; then
        error 1 "fwup not found at ${FWUP}"
    fi
    if [[ ! -f "${ROOTFS_FILE}" ]]; then
        error 1 "Root filesystem combined.squashfs not found at ${ROOTFS_FILE}"
    fi

    GRISP_FW_DESCRIPTION="${APP_NAME}" \
    GRISP_FW_VERSION="${GLB_COMMON_SYSTEM_VER}/${GLB_TARGET_SYSTEM_VER}/${FIRMWARE_VER}" \
    GRISP_FW_PLATFORM="${GLB_TARGET_NAME}" \
    GRISP_FW_ARCHITECTURE="${CROSSCOMPILE_ARCH}" \
    GRISP_FW_VCS_IDENTIFIER="${GLB_VCS_TAG}${PROJECT_VCS_TAG:+/${PROJECT_VCS_TAG}}" \
    GRISP_SYSTEM="${GLB_SDK_DIR}" \
    ROOTFS="${ROOTFS_FILE}" \
        "${FWUP}" -c -f "${SDK_FWUP_CONFIG}" -o "${FIRMWARE_FILE}"
}

bootscheme_package_update() {
    error 1 "Update package generation not supported for none boot scheme"
}
