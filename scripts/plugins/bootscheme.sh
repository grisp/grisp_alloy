#!/usr/bin/env bash
# bootscheme.sh - Boot scheme plugin loader and contract
#
# This file defines how boot scheme plugins are loaded and documents the
# functions that a boot scheme plugin must provide. It is intentionally
# generic and does not prescribe any scheme-specific implementation.
#
# Plugin contract (must be implemented by each scheme):
#
# bootscheme_package_bootloader()
#   Role: stage or prepare bootloader artifacts or metadata required by the
#   target's boot chain. Validate inputs and exit with error on failure.
#   This may be a no-op for schemes that don't need explicit bootloader
#   packaging at this step.
#
# bootscheme_package_kernel [USE_INITRAMFS=false] [INITRAMFS_FILE]
#   Role: stage or prepare kernel-related artifacts (kernel image, device tree,
#   and optionally an initramfs). Accepts one optional boolean argument to
#   request inclusion of an initramfs; default is false. When true, the second
#   argument is the explicit initramfs artifact path. Expected to read any
#   required inputs from the SDK, build tree, and/or artifact path and write
#   outputs under ${FIRMWARE_DIR} for later consumption by
#   bootscheme_package_firmware.
#
# bootscheme_package_firmware()
#   Role: produce the final firmware artifact for the selected scheme.
#   Must write the firmware to ${FIRMWARE_FILE} and exit non-zero on failure.
#
# Conventions:
# - Do not change the working directory.
# - Call `error` on failure.
# - Use absolute paths or derive from the provided globals.

bootscheme_setup() {
    local name="$1"
    local scheme_name
    scheme_name="$(echo "${name}" | tr '[:upper:]' '[:lower:]')"

    local target_bootscheme_file="${GLB_TARGET_SYSTEM_DIR}/bootscheme/${scheme_name}.sh"
    local common_bootscheme_file="${GLB_SCRIPT_DIR}/plugins/bootscheme/${scheme_name}.sh"

    if [[ -f "$target_bootscheme_file" ]]; then
        BOOTSCHEME_FILE="$target_bootscheme_file"
    else
        BOOTSCHEME_FILE="$common_bootscheme_file"
    fi

    if [[ ! -f "$BOOTSCHEME_FILE" ]]; then
        error 1 "Boot scheme ${name} not found at ${BOOTSCHEME_FILE}"
    fi
    source "$BOOTSCHEME_FILE"
}
