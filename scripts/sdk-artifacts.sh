#!/usr/bin/env bash

# Helpers for optional, target-declared SDK artifact profiles.

sdk_artifacts_init_defaults() {
    SDK_ARTIFACT_PROFILES=( )
    SDK_PROFILE_ARTIFACTS=( )
    SDK_SINGLE_ROOTFS=true
    SDK_SINGLE_ROOTFS_IGNORE_PATHS=( )
    SDK_INVARIANT_ARTIFACTS=( )
}

sdk_artifacts_enabled() {
    [[ ${#SDK_ARTIFACT_PROFILES[@]} -gt 0 ]]
}

sdk_artifact_key() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
}

sdk_array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

sdk_bool_true() {
    case "$1" in
        true|yes|1|y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

sdk_validate_artifact_name() {
    local artifact="$1"

    if [[ -z "$artifact" || "$artifact" == /* || "$artifact" == *"/"* ||
        "$artifact" == "." || "$artifact" == ".." || "$artifact" == *".."* ]]; then
        error 1 "Invalid SDK profile artifact name '${artifact}'; expected a simple image filename"
    fi
}

sdk_validate_profile_name() {
    local profile="$1"

    case "$profile" in
        ""|*[^A-Za-z0-9_.-]*)
            error 1 "Invalid SDK artifact profile name '${profile}'"
            ;;
    esac
}

sdk_default_artifact_profile() {
    if [[ -n "${FIRMWARE_DEFAULT_PROFILE:-}" && "${FIRMWARE_DEFAULT_PROFILE}" != "default" ]]; then
        printf '%s\n' "$FIRMWARE_DEFAULT_PROFILE"
    else
        printf '%s\n' "${SDK_ARTIFACT_PROFILES[0]}"
    fi
}

sdk_single_rootfs_source_profile() {
    local last_index

    last_index=$((${#SDK_ARTIFACT_PROFILES[@]} - 1))
    printf '%s\n' "${SDK_ARTIFACT_PROFILES[$last_index]}"
}

sdk_validate_artifact_config() {
    local profile
    local artifact
    local default_profile
    local rootfs_source_profile

    if ! sdk_artifacts_enabled; then
        return 0
    fi

    for profile in "${SDK_ARTIFACT_PROFILES[@]}"; do
        sdk_validate_profile_name "$profile"
    done

    if [[ ${#SDK_PROFILE_ARTIFACTS[@]} -eq 0 ]]; then
        error 1 "Target declares SDK_ARTIFACT_PROFILES but no SDK_PROFILE_ARTIFACTS"
    fi

    for artifact in "${SDK_PROFILE_ARTIFACTS[@]}"; do
        sdk_validate_artifact_name "$artifact"
        if [[ "$artifact" == "rootfs.squashfs" ]] && sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
            error 1 "rootfs.squashfs cannot be profile-driven while SDK_SINGLE_ROOTFS=true"
        fi
    done

    default_profile="$(sdk_default_artifact_profile)"
    if ! sdk_array_contains "$default_profile" "${SDK_ARTIFACT_PROFILES[@]}"; then
        error 1 "Default SDK artifact profile '${default_profile}' is not declared in SDK_ARTIFACT_PROFILES"
    fi

    if sdk_bool_true "$SDK_SINGLE_ROOTFS"; then
        rootfs_source_profile="$(sdk_single_rootfs_source_profile)"
        if [[ -z "$rootfs_source_profile" ]]; then
            error 1 "SDK_SINGLE_ROOTFS=true requires at least one SDK_ARTIFACT_PROFILES entry"
        fi
    fi
}

sdk_artifact_is_profiled() {
    local artifact="$1"

    sdk_array_contains "$artifact" "${SDK_PROFILE_ARTIFACTS[@]}"
}

sdk_validate_firmware_artifact_profile() {
    local profile="$1"

    if ! sdk_artifacts_enabled; then
        return 0
    fi
    if ! sdk_array_contains "$profile" "${SDK_ARTIFACT_PROFILES[@]}"; then
        error 1 "Firmware profile '${profile}' has no matching SDK artifact profile for target ${GLB_TARGET_NAME}"
    fi
}

sdk_resolve_image_artifact() {
    local images_dir="$1"
    local profile="$2"
    local artifact="$3"
    local path

    sdk_validate_artifact_name "$artifact"

    if sdk_artifacts_enabled && sdk_artifact_is_profiled "$artifact"; then
        path="${images_dir}/${artifact}.${profile}"
    else
        path="${images_dir}/${artifact}"
    fi

    printf '%s\n' "$path"
}
