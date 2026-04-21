#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ALLOY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
export ALLOY_ROOT="${ROOT_DIR}"
export ALLOY_ROOT_DIR="${ALLOY_ROOT_DIR:-${ROOT_DIR}}"

# shellcheck source=scripts/utils/common.sh
source "${ROOT_DIR}/scripts/utils/common.sh"
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

build_sdk_print_summary() {
    local build_dir="$1"

    print_result "Initialized SDK build workspace for ${ARG_PRODUCT_NUGGET}."
    print_note "Build directory: ${build_dir}"
    print_note "Plan directory: ${ALLOY_SDK_PLAN_DIR}"
    print_note "Targets directory: ${ALLOY_SDK_TARGETS_DIR}"
    print_note "Staging directory: ${ALLOY_SDK_STAGING_DIR}"
    print_note "Motherlode directory: ${ALLOY_MOTHERLODE}"

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

build_sdk_print_summary "${build_dir}"
