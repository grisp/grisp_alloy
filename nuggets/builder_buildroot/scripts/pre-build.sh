#!/usr/bin/env bash
set -euo pipefail

[[ -n "${ALLOY_ROOT_DIR:-}" ]] || {
    printf 'ERROR: ALLOY_ROOT_DIR must be set before running builder_buildroot pre-build hook\n' >&2
    exit 2
}

export ALLOY_HOOK_TYPE="${ALLOY_HOOK_TYPE:-pre_build}"
export ALLOY_NUGGET="${ALLOY_NUGGET:-builder_buildroot}"

# shellcheck source=scripts/utils/hook_common.sh
source "${ALLOY_ROOT_DIR}/scripts/utils/hook_common.sh"

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        alloy_die "required environment variable is not set: ${name}"
    fi
}

safe_remove_dir() {
    local path="$1"
    case "${path}" in
        ""|"/"|".")
            alloy_die "refusing to remove unsafe path: ${path}"
            ;;
    esac
    rm -rf -- "${path}"
}

buildroot_tree_version() {
    local buildroot_path="$1"
    awk '
        /^(export[[:space:]]+)?BR2_VERSION[[:space:]]*:?=/ {
            sub(/^(export[[:space:]]+)?BR2_VERSION[[:space:]]*:?=[[:space:]]*/, "")
            print
            exit
        }
    ' "${buildroot_path}/Makefile"
}

buildroot_tree_matches() {
    local buildroot_path="$1"
    local expected_version="$2"

    [[ -f "${buildroot_path}/Makefile" ]] || return 1
    [[ "$(buildroot_tree_version "${buildroot_path}")" == "${expected_version}" ]]
}

download_buildroot_tarball() {
    local url="$1"
    local tarball_path="$2"
    local tmp_path="${tarball_path}.tmp.$$"

    rm -f -- "${tmp_path}"
    case "${url}" in
        file://*)
            cp "${url#file://}" "${tmp_path}"
            ;;
        /*|./*|../*)
            cp "${url}" "${tmp_path}"
            ;;
        *)
            if command -v curl >/dev/null 2>&1; then
                curl -fL --retry 3 -o "${tmp_path}" "${url}"
            elif command -v wget >/dev/null 2>&1; then
                wget -O "${tmp_path}" "${url}"
            else
                alloy_die "curl or wget is required to download Buildroot"
            fi
            ;;
    esac

    mv -- "${tmp_path}" "${tarball_path}"
}

extract_buildroot_tree() {
    local tarball_path="$1"
    local buildroot_path="$2"
    local expected_version="$3"
    local tmp_dir="${buildroot_path}.tmp.$$"

    safe_remove_dir "${tmp_dir}"
    mkdir -p "${tmp_dir}"
    tar xzf "${tarball_path}" -C "${tmp_dir}" --strip-components=1

    if ! buildroot_tree_matches "${tmp_dir}" "${expected_version}"; then
        local actual_version
        actual_version="$(buildroot_tree_version "${tmp_dir}")"
        safe_remove_dir "${tmp_dir}"
        alloy_die "Buildroot archive version mismatch: expected ${expected_version}, got ${actual_version:-unknown}"
    fi

    safe_remove_dir "${buildroot_path}"
    mv -- "${tmp_dir}" "${buildroot_path}"
}

link_download_cache() {
    local buildroot_path="$1"
    local downloads_dir="$2"
    local dl_path="${buildroot_path}/dl"

    if [[ -e "${dl_path}" && ! -L "${dl_path}" ]]; then
        safe_remove_dir "${dl_path}"
    fi
    ln -sfn "${downloads_dir}" "${dl_path}"
}

main() {
    require_env ALLOY_CACHE_DIR
    require_env ALLOY_CONFIG_BUILDROOT_PATH
    require_env ALLOY_CONFIG_BUILDROOT_URL
    require_env ALLOY_CONFIG_BUILDROOT_VERSION

    local cache_root="${ALLOY_CACHE_DIR}/buildroot"
    local downloads_dir="${cache_root}/downloads"
    local ccache_dir="${cache_root}/ccache"
    local tarball_path="${cache_root}/buildroot-${ALLOY_CONFIG_BUILDROOT_VERSION}.tar.gz"

    mkdir -p "${cache_root}" "${downloads_dir}" "${ccache_dir}" \
        "$(dirname "${ALLOY_CONFIG_BUILDROOT_PATH}")"

    if buildroot_tree_matches "${ALLOY_CONFIG_BUILDROOT_PATH}" "${ALLOY_CONFIG_BUILDROOT_VERSION}"; then
        alloy_log_info "Using existing Buildroot ${ALLOY_CONFIG_BUILDROOT_VERSION} at $(alloy_log_format_path "${ALLOY_CONFIG_BUILDROOT_PATH}")"
        link_download_cache "${ALLOY_CONFIG_BUILDROOT_PATH}" "${downloads_dir}"
        return 0
    fi

    if [[ -e "${ALLOY_CONFIG_BUILDROOT_PATH}" ]]; then
        alloy_log_info "Discarding stale Buildroot tree at $(alloy_log_format_path "${ALLOY_CONFIG_BUILDROOT_PATH}")"
        safe_remove_dir "${ALLOY_CONFIG_BUILDROOT_PATH}"
    fi

    if [[ ! -f "${tarball_path}" ]]; then
        alloy_log_info "Downloading Buildroot ${ALLOY_CONFIG_BUILDROOT_VERSION}"
        download_buildroot_tarball "${ALLOY_CONFIG_BUILDROOT_URL}" "${tarball_path}"
    else
        alloy_log_info "Using cached $(alloy_log_format_path "${tarball_path}")"
    fi

    alloy_log_info "Extracting Buildroot ${ALLOY_CONFIG_BUILDROOT_VERSION} to $(alloy_log_format_path "${ALLOY_CONFIG_BUILDROOT_PATH}")"
    extract_buildroot_tree \
        "${tarball_path}" \
        "${ALLOY_CONFIG_BUILDROOT_PATH}" \
        "${ALLOY_CONFIG_BUILDROOT_VERSION}"
    link_download_cache "${ALLOY_CONFIG_BUILDROOT_PATH}" "${downloads_dir}"
}

main "$@"
