#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ALLOY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
export ALLOY_ROOT="${ROOT_DIR}"
export ALLOY_ROOT_DIR="${ALLOY_ROOT_DIR:-${ROOT_DIR}}"

# shellcheck source=scripts/utils/common.sh
source "${ROOT_DIR}/scripts/utils/common.sh"
# shellcheck source=scripts/utils/vcs_utils.sh
source "${ROOT_DIR}/scripts/utils/vcs_utils.sh"
# shellcheck source=scripts/argparse.sh
source "${ROOT_DIR}/scripts/argparse.sh"

build_sdk_usage() {
    cat <<'EOF'
Usage: alloy build sdk PRODUCT_NUGGET [OPTIONS]

Initialize the repository-mode SDK build workspace for PRODUCT_NUGGET.

Options:
  -n, --nugget-path PATH   Additional nugget source path or VCS URL. Repeatable.
      --allow-dirty        Allow dirty VCS checkouts for staged nugget sources.
      --include-sources    Request redistributable source export in legal-info.
  -c, --clean             Remove the existing SDK build directory before setup.
      --clean-package PKG Queue a package-clean request for later Buildroot stages.
  -h, --help              Show this help.

Global options accepted anywhere:
  -d, -dd, -ddd            Increase debug verbosity.
      --debug[=N]          Set debug verbosity explicitly.
      --trace              Enable bash execution tracing.
EOF
}

build_sdk_infer_mode() {
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

build_sdk_set_repo_directories() {
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

build_sdk_resolve_allow_dirty() {
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

    BUILD_SDK_ALLOW_DIRTY="${effective}"
}

build_sdk_split_env_nugget_paths() {
    BUILD_SDK_ENV_NUGGET_PATHS=()
    local raw_paths="${ALLOY_NUGGET_PATH:-}"
    [[ -n "${raw_paths}" ]] || return 0

    local old_ifs="${IFS}"
    local -a split_paths=()
    IFS=':' read -r -a split_paths <<< "${raw_paths}"
    IFS="${old_ifs}"

    local path_entry
    for path_entry in "${split_paths[@]}"; do
        [[ -n "${path_entry}" ]] || continue
        BUILD_SDK_ENV_NUGGET_PATHS+=("${path_entry}")
    done
}

build_sdk_stage_name_taken() {
    local candidate="$1"
    local stage_name
    for stage_name in "${BUILD_SDK_STAGE_NAMES[@]}"; do
        [[ "${stage_name}" == "${candidate}" ]] && return 0
    done
    return 1
}

build_sdk_allocate_stage_name() {
    local base_name="$1"
    if [[ -z "${base_name}" ]] || [[ "${base_name}" == "." ]] || [[ "${base_name}" == "/" ]]; then
        fail "Unable to derive a staging name for nugget source"
    fi

    local candidate="${base_name}"
    local suffix=2
    while build_sdk_stage_name_taken "${candidate}"; do
        log_debug "Stage name '${candidate}' is already used; trying suffix ${suffix}."
        candidate="${base_name}_${suffix}"
        suffix=$((suffix + 1))
    done

    BUILD_SDK_STAGE_NAMES+=("${candidate}")
    BUILD_SDK_ALLOCATED_STAGE_NAME="${candidate}"
}

build_sdk_rsync_nugget_repo() {
    local source_dir="$1"
    local target_dir="$2"

    require_command rsync
    log_debug "Syncing nugget repository ${source_dir} -> ${target_dir}"
    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"
    rsync -a --checksum --delete --exclude '/.git/' \
        "${source_dir%/}/" "${target_dir%/}/"
}

build_sdk_write_local_repo_info() {
    local source_dir="$1"
    local target_dir="$2"

    local provenance
    if provenance="$(vcs_get_provenance "${source_dir}" 2>/dev/null)"; then
        log_debug "Writing staged repository provenance for ${source_dir}."
        printf '%s\n' "${provenance}" > "${target_dir}/.alloy_repo_info"
    fi
}

build_sdk_validate_local_source() {
    local source_dir="$1"

    if [[ ! -d "${source_dir}" ]]; then
        fail "Local nugget source does not exist or is not a directory: ${source_dir}"
    fi

    if git -C "${source_dir}" rev-parse --show-toplevel >/dev/null 2>&1 &&
        [[ -n "$(git -C "${source_dir}" status --porcelain --untracked-files=normal 2>/dev/null)" ]] &&
        [[ "${BUILD_SDK_ALLOW_DIRTY}" != "true" ]]; then
        fail "Local nugget source is dirty: ${source_dir}"
    fi
}

build_sdk_stage_local_source() {
    local source_dir="$1"
    local base_name="$2"

    build_sdk_validate_local_source "${source_dir}"

    local stage_name
    build_sdk_allocate_stage_name "${base_name}"
    stage_name="${BUILD_SDK_ALLOCATED_STAGE_NAME}"
    local target_dir="${ALLOY_MOTHERLODE}/${stage_name}"

    log_info "Staging local nugget repository ${source_dir} as '${stage_name}'."
    log_debug "Stage target for ${stage_name}: ${target_dir}"
    build_sdk_rsync_nugget_repo "${source_dir}" "${target_dir}"
    build_sdk_write_local_repo_info "${source_dir}" "${target_dir}"
    BUILD_SDK_STAGED_REPOS+=("${stage_name}")
}

build_sdk_parse_vcs_source() {
    local source_spec="$1"

    BUILD_SDK_VCS_URL=""
    BUILD_SDK_VCS_REF=""

    if [[ "${source_spec}" != git+*#* ]]; then
        fail "Unsupported VCS nugget source '${source_spec}'. Expected git+URL#ref."
    fi

    local without_prefix="${source_spec#git+}"
    BUILD_SDK_VCS_URL="${without_prefix%%#*}"
    BUILD_SDK_VCS_REF="${without_prefix#*#}"

    if [[ -z "${BUILD_SDK_VCS_URL}" ]] || [[ -z "${BUILD_SDK_VCS_REF}" ]] ||
        [[ "${BUILD_SDK_VCS_URL}" == "${without_prefix}" ]]; then
        fail "VCS nugget source must include both URL and ref: ${source_spec}"
    fi
}

build_sdk_vcs_repo_name() {
    local url="$1"
    local trimmed="${url%/}"
    local name
    name="$(basename "${trimmed}")"
    name="${name%.git}"

    if [[ -z "${name}" ]] || [[ "${name}" == "." ]] || [[ "${name}" == "/" ]]; then
        fail "Unable to derive repository name from VCS URL: ${url}"
    fi

    printf '%s\n' "${name}"
}

build_sdk_stage_vcs_source() {
    local source_spec="$1"
    build_sdk_parse_vcs_source "${source_spec}"

    local repo_name stage_name target_dir
    repo_name="$(build_sdk_vcs_repo_name "${BUILD_SDK_VCS_URL}")"
    build_sdk_allocate_stage_name "${repo_name}"
    stage_name="${BUILD_SDK_ALLOCATED_STAGE_NAME}"
    target_dir="${ALLOY_MOTHERLODE}/${stage_name}"

    log_info "Staging VCS nugget repository as '${stage_name}' (ref '${BUILD_SDK_VCS_REF}')."
    log_debug "Stage target for ${stage_name}: ${target_dir}"
    if [[ -e "${target_dir}" ]] && ! git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1; then
        log_debug "Removing non-VCS staging target before clone: ${target_dir}"
        rm -rf "${target_dir}"
    fi
    vcs_clone_or_validate git "${BUILD_SDK_VCS_URL}" "${BUILD_SDK_VCS_REF}" \
        "${target_dir}" "${BUILD_SDK_ALLOW_DIRTY}" ||
        fail "Failed to stage VCS nugget source: ${source_spec}"
    BUILD_SDK_STAGED_REPOS+=("${stage_name}")
}

build_sdk_stage_extra_source() {
    local source_spec="$1"

    if [[ "${source_spec}" == git+* ]]; then
        build_sdk_stage_vcs_source "${source_spec}"
        return 0
    fi

    local source_dir
    source_dir="$(cd "${source_spec}" 2>/dev/null && pwd -P)" ||
        fail "Local nugget source does not exist or is not a directory: ${source_spec}"
    build_sdk_stage_local_source "${source_dir}" "$(basename "${source_dir}")"
}

build_sdk_stage_nuggets() {
    BUILD_SDK_STAGE_NAMES=()
    BUILD_SDK_STAGED_REPOS=()

    local builtin_source="${ROOT_DIR}/nuggets"
    if [[ ! -d "${builtin_source}" ]]; then
        fail "Builtin nugget repository is missing: ${builtin_source}"
    fi

    log_info "Staging nugget repositories into ${ALLOY_MOTHERLODE}."
    mkdir -p "${ALLOY_MOTHERLODE}"
    BUILD_SDK_STAGE_NAMES+=("builtin")
    log_info "Staging builtin nugget repository as 'builtin'."
    log_debug "Stage target for builtin: ${ALLOY_MOTHERLODE}/builtin"
    build_sdk_rsync_nugget_repo "${builtin_source}" "${ALLOY_MOTHERLODE}/builtin"
    BUILD_SDK_STAGED_REPOS+=("builtin")

    local source_spec
    for source_spec in "${BUILD_SDK_ENV_NUGGET_PATHS[@]}"; do
        build_sdk_stage_extra_source "${source_spec}"
    done
    for source_spec in "${ARG_NUGGET_PATHS[@]}"; do
        build_sdk_stage_extra_source "${source_spec}"
    done
    log_info "Nugget staging complete: ${#BUILD_SDK_STAGED_REPOS[@]} repositories staged."
}

build_sdk_print_summary() {
    local build_dir="$1"

    print_result "Initialized SDK build workspace for ${ARG_PRODUCT_NUGGET}."
    print_note "Build directory: ${build_dir}"
    print_note "Plan directory: ${ALLOY_SDK_PLAN_DIR}"
    print_note "Targets directory: ${ALLOY_SDK_TARGETS_DIR}"
    print_note "Staging directory: ${ALLOY_SDK_STAGING_DIR}"
    print_note "Motherlode directory: ${ALLOY_MOTHERLODE}"
    print_note "Staged nugget repositories: ${#BUILD_SDK_STAGED_REPOS[@]}"

    if [[ ${#ARG_NUGGET_PATHS[@]} -gt 0 ]]; then
        print_note "Additional command-line nugget sources: ${#ARG_NUGGET_PATHS[@]}"
    fi
    if [[ ${#BUILD_SDK_ENV_NUGGET_PATHS[@]} -gt 0 ]]; then
        print_note "Additional environment nugget sources: ${#BUILD_SDK_ENV_NUGGET_PATHS[@]}"
    fi
    if [[ "${BUILD_SDK_ALLOW_DIRTY}" == "true" ]]; then
        print_note "Dirty VCS checkouts are allowed for nugget staging."
    fi
    if [[ "${ARG_INCLUDE_SOURCES}" == "true" ]]; then
        print_note "Legal-info source export was requested."
    fi
    if [[ ${#ARG_CLEAN_PACKAGES[@]} -gt 0 ]]; then
        print_note "Queued clean-package requests: ${ARG_CLEAN_PACKAGES[*]}"
    fi

    print_hint "Plan/generate/build orchestration follows in later Phase 5 tasks."
}

build_sdk_infer_mode

if [[ "${ALLOY_MODE}" != "repo" ]]; then
    fail "build sdk is only available in repository mode"
fi

build_sdk_set_repo_directories

args_init
args_add h help ARG_SHOW_HELP flag true false
args_add n nugget-path ARG_NUGGET_PATHS accum
args_add '' allow-dirty ARG_ALLOW_DIRTY flag true false
args_add '' include-sources ARG_INCLUDE_SOURCES flag true false
args_add c clean ARG_CLEAN flag true false
args_add '' clean-package ARG_CLEAN_PACKAGES accum

args_parse "$@"

if [[ "${ARG_SHOW_HELP}" == "true" ]]; then
    build_sdk_usage
    exit 0
fi

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
    build_sdk_usage
    fail "Missing PRODUCT_NUGGET"
fi
if [[ ${#POSITIONAL[@]} -gt 1 ]]; then
    build_sdk_usage
    fail "Unexpected positional arguments: ${POSITIONAL[*]:1}"
fi

ARG_PRODUCT_NUGGET="${POSITIONAL[0]}"
build_sdk_resolve_allow_dirty
build_sdk_split_env_nugget_paths

build_dir="${ALLOY_BUILD_DIR}/sdk/${ARG_PRODUCT_NUGGET}"

if [[ "${ARG_CLEAN}" == "true" ]]; then
    rm -rf "${build_dir}"
fi

mkdir -p "${build_dir}/plan" \
    "${build_dir}/targets" \
    "${build_dir}/staging" \
    "${build_dir}/motherlode"

export ALLOY_SDK_BUILD_DIR="${build_dir}"
export ALLOY_SDK_PLAN_DIR="${build_dir}/plan"
export ALLOY_SDK_TARGETS_DIR="${build_dir}/targets"
export ALLOY_SDK_STAGING_DIR="${build_dir}/staging"
export ALLOY_MOTHERLODE="${build_dir}/motherlode"
export ALLOY_BUILD_SDK_PRODUCT="${ARG_PRODUCT_NUGGET}"

log_debug "SDK build workspace root: ${build_dir}"
build_sdk_stage_nuggets
build_sdk_print_summary "${build_dir}"
