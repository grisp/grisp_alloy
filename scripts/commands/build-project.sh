#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ALLOY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
export ALLOY_ROOT="${ROOT_DIR}"
export ALLOY_ROOT_DIR="${ALLOY_ROOT_DIR:-${ROOT_DIR}}"

# shellcheck source=scripts/utils/common.sh
source "${ROOT_DIR}/scripts/utils/common.sh"
# shellcheck source=scripts/utils/sdk_utils.sh
source "${ROOT_DIR}/scripts/utils/sdk_utils.sh"
# shellcheck source=scripts/argparse.sh
source "${ROOT_DIR}/scripts/argparse.sh"

build_project_usage() {
    cat <<'USAGE'
Usage: alloy build project PROJECT_SOURCE [OPTIONS]

Build a project artefact using an SDK context.

Options:
      --sdk SDK_REF         SDK reference (repo mode only): name prefix, .tar.gz path, or SDK directory.
      --profile PROFILE     Build profile. Repeatable. Default: default.
      --allow-dirty         Allow dirty VCS project sources.
  -h, --help                Show this help.
USAGE
}

build_project_display_path() {
    local path_value="${1:-}"
    local cwd
    cwd="$(pwd -P)"
    display_path_for_root "${cwd}" "${path_value}"
}

build_project_infer_mode() {
    if [[ -n "${ALLOY_MODE:-}" ]]; then
        return 0
    fi

    if [[ -f "${ROOT_DIR}/ALLOY_SDK_MANIFEST" ]]; then
        ALLOY_MODE="sdk"
    else
        ALLOY_MODE="repo"
    fi
    export ALLOY_MODE
}

build_project_set_repo_directories() {
    if [[ -z "${ALLOY_BUILD_DIR:-}" ]]; then
        ALLOY_BUILD_DIR="${ROOT_DIR}/_build"
        export ALLOY_BUILD_DIR
    fi

    if [[ -z "${ALLOY_ARTEFACT_DIR:-}" ]]; then
        ALLOY_ARTEFACT_DIR="${ROOT_DIR}/artefacts"
        export ALLOY_ARTEFACT_DIR
    fi

    if [[ -z "${ALLOY_CACHE_DIR:-}" ]]; then
        ALLOY_CACHE_DIR="${ROOT_DIR}/_cache"
        export ALLOY_CACHE_DIR
    fi
}

build_project_resolve_allow_dirty() {
    local env_value="${ALLOY_ALLOW_DIRTY:-false}"
    local effective=false

    case "${env_value}" in
        ""|false)
            effective=false
            ;;
        true)
            effective=true
            ;;
        *)
            fail "ALLOY_ALLOW_DIRTY must be true or false"
            ;;
    esac

    if [[ "${ARG_ALLOW_DIRTY}" == "true" ]]; then
        effective=true
    fi

    if [[ "${effective}" == "true" ]]; then
        export ALLOY_ALLOW_DIRTY=true
    else
        unset ALLOY_ALLOW_DIRTY || true
    fi

    BUILD_PROJECT_ALLOW_DIRTY="${effective}"
}

build_project_list_available_archives() {
    BUILD_PROJECT_AVAILABLE_ARCHIVES=()
    local sdk_artefact_dir="${ALLOY_ARTEFACT_DIR}/sdk"
    [[ -d "${sdk_artefact_dir}" ]] || return 0

    local archive
    shopt -s nullglob
    for archive in "${sdk_artefact_dir}"/*.tar.gz; do
        BUILD_PROJECT_AVAILABLE_ARCHIVES+=("${archive}")
    done
    shopt -u nullglob

    if [[ ${#BUILD_PROJECT_AVAILABLE_ARCHIVES[@]} -gt 1 ]]; then
        mapfile -t BUILD_PROJECT_AVAILABLE_ARCHIVES < <(printf '%s\n' "${BUILD_PROJECT_AVAILABLE_ARCHIVES[@]}" | LC_ALL=C sort)
    fi
}

build_project_list_installed_sdks() {
    BUILD_PROJECT_INSTALLED_SDKS=()
    local -a base_roots=()
    if [[ -n "${ALLOY_SDK_INSTALL_ROOT:-}" ]]; then
        base_roots=("${ALLOY_SDK_INSTALL_ROOT}")
    else
        base_roots=("/opt/grisp_alloy" "${HOME}/.grisp_alloy/sdk")
    fi

    local base_root normalized_base
    for base_root in "${base_roots[@]}"; do
        [[ -d "${base_root}" ]] || continue
        normalized_base="$(cd "${base_root}" && pwd -P)"

        local sdk_manifest
        while IFS= read -r sdk_manifest; do
            BUILD_PROJECT_INSTALLED_SDKS+=("$(cd "$(dirname "${sdk_manifest}")" && pwd -P)")
        done < <(find "${normalized_base}" -mindepth 2 -maxdepth 2 -type f -name ALLOY_SDK_MANIFEST | LC_ALL=C sort)
    done

    if [[ ${#BUILD_PROJECT_INSTALLED_SDKS[@]} -gt 0 ]]; then
        mapfile -t BUILD_PROJECT_INSTALLED_SDKS < <(printf '%s\n' "${BUILD_PROJECT_INSTALLED_SDKS[@]}" | LC_ALL=C sort -u)
    fi
}

build_project_print_sdk_candidates() {
    local installed_path
    if [[ ${#BUILD_PROJECT_INSTALLED_SDKS[@]} -gt 0 ]]; then
        printf 'Installed SDKs:\n' >&2
        for installed_path in "${BUILD_PROJECT_INSTALLED_SDKS[@]}"; do
            printf '  - %s\n' "$(build_project_display_path "${installed_path}")" >&2
        done
    else
        printf 'Installed SDKs:\n' >&2
        printf '  - (none)\n' >&2
    fi

    local archive_path
    if [[ ${#BUILD_PROJECT_AVAILABLE_ARCHIVES[@]} -gt 0 ]]; then
        printf 'SDK archives in artefacts/sdk:\n' >&2
        for archive_path in "${BUILD_PROJECT_AVAILABLE_ARCHIVES[@]}"; do
            printf '  - %s\n' "$(build_project_display_path "${archive_path}")" >&2
        done
    else
        printf 'SDK archives in artefacts/sdk:\n' >&2
        printf '  - (none)\n' >&2
    fi
}

build_project_resolve_sdk_ref() {
    local sdk_ref="$1"

    if [[ -d "${sdk_ref}" ]]; then
        BUILD_PROJECT_SDK_REF_TYPE="directory"
        BUILD_PROJECT_SDK_REF_PATH="$(cd "${sdk_ref}" && pwd -P)"
        return 0
    fi

    if [[ -f "${sdk_ref}" ]]; then
        if [[ "${sdk_ref}" != *.tar.gz ]]; then
            fail "SDK file reference must be a .tar.gz archive: ${sdk_ref}"
        fi
        BUILD_PROJECT_SDK_REF_TYPE="archive"
        BUILD_PROJECT_SDK_REF_PATH="$(cd "$(dirname "${sdk_ref}")" && pwd -P)/$(basename "${sdk_ref}")"
        return 0
    fi

    if [[ "${sdk_ref}" == *"/"* ]]; then
        fail "SDK reference path does not exist: ${sdk_ref}"
    fi

    build_project_list_available_archives
    local matches=()
    local archive
    for archive in "${BUILD_PROJECT_AVAILABLE_ARCHIVES[@]}"; do
        if [[ "$(basename "${archive}")" == "sdk-${sdk_ref}"* ]]; then
            matches+=("${archive}")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        fail "No SDK archive matches prefix '${sdk_ref}' in artefacts/sdk"
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        printf 'Multiple SDK archives match prefix %q:\n' "${sdk_ref}" >&2
        printf '  %s\n' "${matches[@]}" >&2
        fail "SDK reference is ambiguous; use a full archive path"
    fi

    BUILD_PROJECT_SDK_REF_TYPE="archive"
    BUILD_PROJECT_SDK_REF_PATH="${matches[0]}"
}

build_project_choose_install_base() {
    local preferred_root="${ALLOY_SDK_INSTALL_ROOT:-/opt/grisp_alloy}"
    local fallback_root="${HOME}/.grisp_alloy/sdk"
    local explicit_install_root=false
    if [[ -n "${ALLOY_SDK_INSTALL_ROOT:-}" ]]; then
        explicit_install_root=true
    fi

    if [[ -d "${preferred_root}" ]]; then
        if [[ -w "${preferred_root}" ]]; then
            BUILD_PROJECT_INSTALL_BASE="$(cd "${preferred_root}" && pwd -P)"
            return 0
        fi
    else
        if mkdir -p "${preferred_root}" 2>/dev/null && [[ -w "${preferred_root}" ]]; then
            BUILD_PROJECT_INSTALL_BASE="$(cd "${preferred_root}" && pwd -P)"
            return 0
        fi
    fi

    if [[ "${explicit_install_root}" == true ]]; then
        fail "ALLOY_SDK_INSTALL_ROOT is set but not usable: ${preferred_root}"
    fi

    mkdir -p "${fallback_root}" 2>/dev/null ||
        fail "Unable to create SDK fallback install root: ${fallback_root}"
    [[ -w "${fallback_root}" ]] ||
        fail "SDK fallback install root is not writable: ${fallback_root}"
    BUILD_PROJECT_INSTALL_BASE="$(cd "${fallback_root}" && pwd -P)"
}

build_project_install_dir_name_for_archive() {
    local archive_path="$1"
    local archive_name
    archive_name="$(basename "${archive_path}")"
    archive_name="${archive_name%.tar.gz}"
    archive_name="${archive_name//[^A-Za-z0-9._-]/_}"
    [[ -n "${archive_name}" ]] || fail "Unable to derive install directory name from archive: ${archive_path}"
    printf '%s\n' "${archive_name}"
}

build_project_sha256() {
    local file_path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file_path}" | awk '{print $1}'
        return 0
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file_path}" | awk '{print $1}'
        return 0
    fi

    fail "Neither sha256sum nor shasum is available"
}

build_project_find_extracted_sdk_root() {
    local install_root="$1"
    local manifest_match
    local -a matches=()

    while IFS= read -r manifest_match; do
        matches+=("${manifest_match}")
    done < <(find "${install_root}" -maxdepth 3 -type f -name 'ALLOY_SDK_MANIFEST' | LC_ALL=C sort)

    if [[ ${#matches[@]} -ne 1 ]]; then
        fail "Expected exactly one SDK manifest after extraction in ${install_root}, found ${#matches[@]}"
    fi

    BUILD_PROJECT_SDK_DIR="$(cd "$(dirname "${matches[0]}")" && pwd -P)"
}

build_project_install_archive_if_needed() {
    local archive_path="$1"

    build_project_choose_install_base
    local install_dir_name
    install_dir_name="$(build_project_install_dir_name_for_archive "${archive_path}")"
    local install_root="${BUILD_PROJECT_INSTALL_BASE}/${install_dir_name}"
    mkdir -p "${install_root}" || fail "Unable to create SDK install directory: ${install_root}"
    local meta_file="${install_root}/.alloy_sdk_install"
    local archive_hash
    archive_hash="$(build_project_sha256 "${archive_path}")"

    local install_required=true
    if [[ -f "${meta_file}" ]] && [[ -f "${install_root}/ALLOY_SDK_MANIFEST" ]]; then
        local existing_source existing_hash
        existing_source="$(sed -n 's/^source_archive_path=//p' "${meta_file}" | head -n 1)"
        existing_hash="$(sed -n 's/^source_archive_sha256=//p' "${meta_file}" | head -n 1)"

        if [[ "${existing_source}" == "${archive_path}" ]] && [[ "${existing_hash}" == "${archive_hash}" ]]; then
            install_required=false
            BUILD_PROJECT_SDK_DIR="${install_root}"
        fi
    fi

    if [[ "${install_required}" == "true" ]]; then
        log_info "Installing SDK archive $(build_project_display_path "${archive_path}")"

        find "${install_root}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        tar -xzf "${archive_path}" -C "${install_root}"
        build_project_find_extracted_sdk_root "${install_root}"

        cat > "${meta_file}" <<META
source_archive_path=${archive_path}
source_archive_sha256=${archive_hash}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

        if [[ "${BUILD_PROJECT_SDK_DIR}" != "${install_root}" ]]; then
            find "${install_root}" -mindepth 1 -maxdepth 1 ! -name "$(basename "${BUILD_PROJECT_SDK_DIR}")" ! -name '.alloy_sdk_install' -exec rm -rf {} +
            cp -a "${BUILD_PROJECT_SDK_DIR}/." "${install_root}/"
            BUILD_PROJECT_SDK_DIR="${install_root}"
        fi
    fi
}

build_project_refresh_installed_sdk_if_archive_changed() {
    local sdk_dir="$1"
    local meta_file="${sdk_dir}/.alloy_sdk_install"
    [[ -f "${meta_file}" ]] || return 0

    local source_archive source_hash
    source_archive="$(sed -n 's/^source_archive_path=//p' "${meta_file}" | head -n 1)"
    source_hash="$(sed -n 's/^source_archive_sha256=//p' "${meta_file}" | head -n 1)"

    [[ -n "${source_archive}" ]] || return 0
    [[ -n "${source_hash}" ]] || return 0
    [[ -f "${source_archive}" ]] || return 0

    local current_hash
    current_hash="$(build_project_sha256 "${source_archive}")"
    if [[ "${current_hash}" == "${source_hash}" ]]; then
        return 0
    fi

    log_info "SDK archive changed since installation; reinstalling ${sdk_dir} from $(build_project_display_path "${source_archive}")"
    BUILD_PROJECT_INSTALL_BASE="$(cd "$(dirname "${sdk_dir}")" && pwd -P)"
    build_project_install_archive_if_needed "${source_archive}"
}

build_project_auto_select_sdk() {
    build_project_list_installed_sdks
    build_project_list_available_archives

    if [[ ${#BUILD_PROJECT_INSTALLED_SDKS[@]} -eq 1 ]]; then
        BUILD_PROJECT_SDK_REF_TYPE="directory"
        BUILD_PROJECT_SDK_REF_PATH="${BUILD_PROJECT_INSTALLED_SDKS[0]}"
        return 0
    fi

    if [[ ${#BUILD_PROJECT_INSTALLED_SDKS[@]} -eq 0 ]] && [[ ${#BUILD_PROJECT_AVAILABLE_ARCHIVES[@]} -eq 1 ]]; then
        BUILD_PROJECT_SDK_REF_TYPE="archive"
        BUILD_PROJECT_SDK_REF_PATH="${BUILD_PROJECT_AVAILABLE_ARCHIVES[0]}"
        return 0
    fi

    build_project_print_sdk_candidates
    fail "Unable to select SDK automatically; use --sdk SDK_REF"
}

build_project_resolve_sdk_dir() {
    if [[ "${ALLOY_MODE}" == "sdk" ]]; then
        BUILD_PROJECT_SDK_DIR="${ROOT_DIR}"
        return 0
    fi

    if [[ ${ARG_SDK_REF_OPT} -gt 0 ]]; then
        build_project_resolve_sdk_ref "${ARG_SDK_REF}"
    else
        build_project_auto_select_sdk
    fi

    if [[ "${BUILD_PROJECT_SDK_REF_TYPE}" == "directory" ]]; then
        BUILD_PROJECT_SDK_DIR="${BUILD_PROJECT_SDK_REF_PATH}"
    else
        build_project_install_archive_if_needed "${BUILD_PROJECT_SDK_REF_PATH}"
    fi

    if [[ ${ARG_SDK_REF_OPT} -eq 0 ]] && [[ "${BUILD_PROJECT_SDK_REF_TYPE}" == "directory" ]]; then
        build_project_refresh_installed_sdk_if_archive_changed "${BUILD_PROJECT_SDK_DIR}"
    fi

    [[ -f "${BUILD_PROJECT_SDK_DIR}/ALLOY_SDK_MANIFEST" ]] ||
        fail "Selected SDK directory is missing ALLOY_SDK_MANIFEST: ${BUILD_PROJECT_SDK_DIR}"
}

build_project_delegate_to_sdk() {
    if [[ "${ALLOY_MODE}" == "sdk" ]]; then
        fail "alloy build project execution is not implemented yet (Task 6.2+). SDK selection/installation/relocation completed, but plugin dispatch and project build flow are not wired yet."
    fi

    local sdk_alloy="${BUILD_PROJECT_SDK_DIR}/alloy"
    [[ -x "${sdk_alloy}" ]] || fail "SDK alloy entrypoint is missing or not executable: ${sdk_alloy}"
    local sdk_build_project_cmd="${BUILD_PROJECT_SDK_DIR}/scripts/commands/build-project.sh"

    if [[ -f "${sdk_build_project_cmd}" ]] &&
        head -n 12 "${sdk_build_project_cmd}" | grep -Fq 'exec "${ROOT_DIR}/build-project.sh" "$@"' &&
        [[ ! -e "${BUILD_PROJECT_SDK_DIR}/build-project.sh" ]]; then
        fail "Selected SDK has a legacy build-project wrapper without its implementation (${BUILD_PROJECT_SDK_DIR}/build-project.sh is missing). Rebuild/update the SDK, or run the legacy repository command directly: ./build-project.sh <target> <project_dir>."
    fi

    local -a delegated_args=(build project "${ARG_PROJECT_SOURCE}")
    local profile
    for profile in "${ARG_PROJECT_PROFILES[@]}"; do
        delegated_args+=(--profile "${profile}")
    done
    if [[ "${BUILD_PROJECT_ALLOW_DIRTY}" == "true" ]]; then
        delegated_args+=(--allow-dirty)
    fi

    log_debug "Delegating project build to SDK command: ${sdk_alloy} ${delegated_args[*]}"

    exec "${sdk_alloy}" "${delegated_args[@]}"
}

args_init
args_add h help ARG_HELP flag true false
args_add '' sdk ARG_SDK_REF value ""
args_add '' profile ARG_PROJECT_PROFILES accum
args_add '' allow-dirty ARG_ALLOW_DIRTY flag true false

if ! args_parse "$@"; then
    exit 1
fi

if [[ "${ARG_HELP}" == "true" ]]; then
    build_project_usage
    exit 0
fi

POSITIONALS=("${POSITIONAL[@]}")
if [[ ${#POSITIONALS[@]} -lt 1 ]]; then
    fail "PROJECT_SOURCE is required"
fi
if [[ ${#POSITIONALS[@]} -gt 1 ]]; then
    fail "Unexpected positional arguments: ${POSITIONALS[*]:1}"
fi
ARG_PROJECT_SOURCE="${POSITIONALS[0]}"

if [[ ${#ARG_PROJECT_PROFILES[@]} -eq 0 ]]; then
    ARG_PROJECT_PROFILES=(default)
fi

build_project_infer_mode
if [[ "${ALLOY_MODE}" == "repo" ]]; then
    build_project_set_repo_directories
fi

if [[ "${ALLOY_MODE}" == "sdk" ]] && [[ ${ARG_SDK_REF_OPT} -gt 0 ]]; then
    fail "--sdk is not valid in sdk mode"
fi

build_project_resolve_allow_dirty
build_project_resolve_sdk_dir
ensure_sdk_relocated "${BUILD_PROJECT_SDK_DIR}"
build_project_delegate_to_sdk
