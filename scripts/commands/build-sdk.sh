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

build_sdk_read_smelterl_version() {
    local app_src="${ROOT_DIR}/smelterl/src/smelterl.app.src"

    if [[ ! -f "${ROOT_DIR}/smelterl/rebar.config" ]] || [[ ! -f "${app_src}" ]]; then
        fail "smelterl checkout is missing or incomplete at ${ROOT_DIR}/smelterl"
    fi

    BUILD_SDK_SMELTERL_VERSION="$(sed -n 's/^[[:space:]]*{vsn,[[:space:]]*"\([^"]\+\)".*/\1/p' "${app_src}" | head -n 1)"
    if [[ -z "${BUILD_SDK_SMELTERL_VERSION}" ]]; then
        fail "Unable to read smelterl version from ${app_src}"
    fi
}

build_sdk_build_smelterl() {
    local mode="$1"
    local source_binary="${ROOT_DIR}/smelterl/_build/default/bin/smelterl"

    require_command rebar3 || fail "rebar3 is required to build smelterl"

    if [[ "${mode}" == "dev" ]]; then
        log_info "Rebuilding smelterl ${BUILD_SDK_SMELTERL_VERSION} in development mode."
        (
            cd "${ROOT_DIR}/smelterl"
            rebar3 clean
            rebar3 escriptize
        ) || fail "Failed to rebuild smelterl"
    else
        log_info "Building smelterl ${BUILD_SDK_SMELTERL_VERSION}."
        (
            cd "${ROOT_DIR}/smelterl"
            rebar3 escriptize
        ) || fail "Failed to build smelterl"
    fi

    if [[ ! -f "${source_binary}" ]]; then
        fail "Smelterl build did not produce expected executable: ${source_binary}"
    fi

    mkdir -p "$(dirname "${ALLOY_SMELTERL}")"
    cp "${source_binary}" "${ALLOY_SMELTERL}"
    chmod +x "${ALLOY_SMELTERL}"
}

build_sdk_update_smelterl_link() {
    local tools_dir target_name link_path
    tools_dir="$(dirname "${ALLOY_SMELTERL}")"
    target_name="$(basename "${ALLOY_SMELTERL}")"
    link_path="${tools_dir}/smelterl"

    mkdir -p "${tools_dir}"
    if [[ -e "${link_path}" || -L "${link_path}" ]]; then
        if [[ -d "${link_path}" && ! -L "${link_path}" ]]; then
            fail "Cannot replace Smelterl current link because it is a directory: ${link_path}"
        fi
        rm -f "${link_path}"
    fi
    ln -s "${target_name}" "${link_path}"

    ALLOY_SMELTERL_LINK="${link_path}"
    export ALLOY_SMELTERL_LINK
    log_debug "Smelterl current link: ${ALLOY_SMELTERL_LINK} -> ${target_name}"
}

build_sdk_ensure_smelterl() {
    build_sdk_read_smelterl_version

    ALLOY_SMELTERL="${ALLOY_ARTEFACT_DIR}/tools/smelterl-${BUILD_SDK_SMELTERL_VERSION}"
    export ALLOY_SMELTERL

    if [[ "${ALLOY_DEV_MODE:-false}" == "true" ]]; then
        build_sdk_build_smelterl dev
    elif [[ -x "${ALLOY_SMELTERL}" ]]; then
        log_info "Using cached smelterl executable ${ALLOY_SMELTERL}."
    else
        build_sdk_build_smelterl normal
    fi

    [[ -x "${ALLOY_SMELTERL}" ]] ||
        fail "Smelterl executable is not available or executable: ${ALLOY_SMELTERL}"
    build_sdk_update_smelterl_link
    log_debug "Smelterl executable path: ${ALLOY_SMELTERL}"
}

build_sdk_run_plan() {
    ALLOY_SDK_PLAN_FILE="${ALLOY_SDK_PLAN_DIR}/build_plan.term"
    ALLOY_SDK_PLAN_ENV_FILE="${ALLOY_SDK_PLAN_DIR}/build_plan.env"
    export ALLOY_SDK_PLAN_FILE ALLOY_SDK_PLAN_ENV_FILE

    local -a plan_args=(
        plan
        --product "${ARG_PRODUCT_NUGGET}"
        --motherlode "${ALLOY_MOTHERLODE}"
        --extra-config 'ALLOY_ROOT_DIR=${ALLOY_ROOT_DIR}'
        --extra-config 'ALLOY_ARTEFACT_DIR=${ALLOY_ARTEFACT_DIR}'
        --extra-config 'ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}'
        --extra-config 'ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}'
        --extra-config 'ALLOY_SDK_DIR=${ALLOY_SDK_DIR}'
        --extra-config 'ALLOY_FIRMWARE_WORK_DIR=${ALLOY_FIRMWARE_WORK_DIR}'
        --extra-config 'ALLOY_DEBUG=${ALLOY_DEBUG}'
        --extra-config 'ALLOY_TRACE=${ALLOY_TRACE}'
        --output-plan "${ALLOY_SDK_PLAN_FILE}"
        --output-plan-env "${ALLOY_SDK_PLAN_ENV_FILE}"
    )

    log_info "Running smelterl plan for ${ARG_PRODUCT_NUGGET}."
    log_debug "Plan term output: ${ALLOY_SDK_PLAN_FILE}"
    log_debug "Plan environment output: ${ALLOY_SDK_PLAN_ENV_FILE}"
    if ! "${ALLOY_SMELTERL}" "${plan_args[@]}"; then
        fail "Smelterl plan failed for product: ${ARG_PRODUCT_NUGGET}"
    fi

    [[ -s "${ALLOY_SDK_PLAN_FILE}" ]] ||
        fail "Smelterl plan did not produce expected artefact: ${ALLOY_SDK_PLAN_FILE}"
    [[ -s "${ALLOY_SDK_PLAN_ENV_FILE}" ]] ||
        fail "Smelterl plan did not produce expected artefact: ${ALLOY_SDK_PLAN_ENV_FILE}"
    log_info "Smelterl plan complete."
}

build_sdk_load_plan_metadata() {
    log_info "Loading target loop metadata from ${ALLOY_SDK_PLAN_ENV_FILE}."
    unset ALLOY_PLAN_PRODUCT ALLOY_PLAN_MAIN_TARGET ALLOY_PLAN_AUXILIARY_IDS \
        ALLOY_PLAN_TARGET_IDS ALLOY_PLAN_TARGET_KIND ALLOY_PLAN_TARGET_ROOT \
        ALLOY_PLAN_EXTRA_CONFIG || true
    # shellcheck disable=SC1090 # build_plan.env is generated by smelterl for the current build workspace.
    source "${ALLOY_SDK_PLAN_ENV_FILE}"

    [[ -n "${ALLOY_PLAN_PRODUCT:-}" ]] ||
        fail "Smelterl plan metadata is missing ALLOY_PLAN_PRODUCT: ${ALLOY_SDK_PLAN_ENV_FILE}"
    [[ "${ALLOY_PLAN_PRODUCT}" == "${ARG_PRODUCT_NUGGET}" ]] ||
        fail "Smelterl plan product '${ALLOY_PLAN_PRODUCT}' does not match requested product '${ARG_PRODUCT_NUGGET}'"
    [[ -n "${ALLOY_PLAN_MAIN_TARGET:-}" ]] ||
        fail "Smelterl plan metadata is missing ALLOY_PLAN_MAIN_TARGET: ${ALLOY_SDK_PLAN_ENV_FILE}"
    declare -p ALLOY_PLAN_TARGET_IDS >/dev/null 2>&1 ||
        fail "Smelterl plan metadata is missing ALLOY_PLAN_TARGET_IDS: ${ALLOY_SDK_PLAN_ENV_FILE}"
    [[ ${#ALLOY_PLAN_TARGET_IDS[@]} -gt 0 ]] ||
        fail "Smelterl plan metadata does not list any targets: ${ALLOY_SDK_PLAN_ENV_FILE}"

    local last_index=$(( ${#ALLOY_PLAN_TARGET_IDS[@]} - 1 ))
    [[ "${ALLOY_PLAN_TARGET_IDS[${last_index}]}" == "${ALLOY_PLAN_MAIN_TARGET}" ]] ||
        fail "Smelterl plan target order must end with main target '${ALLOY_PLAN_MAIN_TARGET}'"

    log_debug "Plan target order: ${ALLOY_PLAN_TARGET_IDS[*]}"
}

build_sdk_prepare_target_layout() {
    local target_id="$1"

    BUILD_SDK_TARGET_DIR="${ALLOY_SDK_TARGETS_DIR}/${target_id}"
    BUILD_SDK_TARGET_WORKSPACE_DIR="${BUILD_SDK_TARGET_DIR}/workspace"
    BUILD_SDK_TARGET_EXTERNAL_DIR="${BUILD_SDK_TARGET_DIR}/br2_external"
    BUILD_SDK_TARGET_CONFIGS_DIR="${BUILD_SDK_TARGET_EXTERNAL_DIR}/configs"
    BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR="${BUILD_SDK_TARGET_EXTERNAL_DIR}/board/${target_id}/scripts"
    BUILD_SDK_TARGET_CONTEXT_FILE="${BUILD_SDK_TARGET_DIR}/alloy_context.sh"
    BUILD_SDK_TARGET_EXTERNAL_DESC_FILE="${BUILD_SDK_TARGET_EXTERNAL_DIR}/external.desc"
    BUILD_SDK_TARGET_CONFIG_IN_FILE="${BUILD_SDK_TARGET_EXTERNAL_DIR}/Config.in"
    BUILD_SDK_TARGET_EXTERNAL_MK_FILE="${BUILD_SDK_TARGET_EXTERNAL_DIR}/external.mk"
    BUILD_SDK_TARGET_DEFCONFIG_FILE="${BUILD_SDK_TARGET_CONFIGS_DIR}/${target_id}_defconfig"

    mkdir -p \
        "${BUILD_SDK_TARGET_WORKSPACE_DIR}" \
        "${BUILD_SDK_TARGET_CONFIGS_DIR}" \
        "${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}"
}

build_sdk_link_target_hooks() {
    local target_id="$1"
    local wrapper_script="${ROOT_DIR}/scripts/buildroot/script_hook.sh"
    local context_link_target='../../../../alloy_context.sh'

    [[ -f "${wrapper_script}" ]] ||
        fail "Missing Buildroot hook wrapper script: ${wrapper_script}"

    ln -sfn "${wrapper_script}" "${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}/post-build.sh"
    ln -sfn "${wrapper_script}" "${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}/post-image.sh"
    ln -sfn "${wrapper_script}" "${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}/post-fakeroot.sh"
    ln -sfn "${context_link_target}" "${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}/alloy_context.sh"

    log_debug "Hook wrapper links prepared for target '${target_id}' in ${BUILD_SDK_TARGET_BOARD_SCRIPTS_DIR}."
}

build_sdk_generate_target() {
    local target_id="$1"
    local target_kind="auxiliary"
    local -a generate_args=(
        generate
        --plan "${ALLOY_SDK_PLAN_FILE}"
    )

    if [[ "${target_id}" == "${ALLOY_PLAN_MAIN_TARGET}" ]]; then
        target_kind="main"
    fi

    case "${target_kind}" in
        auxiliary)
            generate_args+=(--auxiliary "${target_id}")
            ;;
        main)
            ;;
        *)
            fail "Smelterl plan metadata has unsupported target kind '${target_kind}' for target '${target_id}'"
            ;;
    esac

    build_sdk_prepare_target_layout "${target_id}"
    build_sdk_link_target_hooks "${target_id}"

    generate_args+=(
        --output-external-desc "${BUILD_SDK_TARGET_EXTERNAL_DESC_FILE}"
        --output-config-in "${BUILD_SDK_TARGET_CONFIG_IN_FILE}"
        --output-external-mk "${BUILD_SDK_TARGET_EXTERNAL_MK_FILE}"
        --output-defconfig "${BUILD_SDK_TARGET_DEFCONFIG_FILE}"
        --output-context "${BUILD_SDK_TARGET_CONTEXT_FILE}"
    )

    log_info "Generating Buildroot inputs for ${target_kind} target '${target_id}'."
    log_debug "Target '${target_id}' workspace: ${BUILD_SDK_TARGET_WORKSPACE_DIR}"
    if ! "${ALLOY_SMELTERL}" "${generate_args[@]}"; then
        fail "Smelterl generate failed for target '${target_id}'"
    fi

    [[ -s "${BUILD_SDK_TARGET_EXTERNAL_DESC_FILE}" ]] ||
        fail "Smelterl generate did not produce expected artefact: ${BUILD_SDK_TARGET_EXTERNAL_DESC_FILE}"
    [[ -s "${BUILD_SDK_TARGET_CONFIG_IN_FILE}" ]] ||
        fail "Smelterl generate did not produce expected artefact: ${BUILD_SDK_TARGET_CONFIG_IN_FILE}"
    [[ -s "${BUILD_SDK_TARGET_EXTERNAL_MK_FILE}" ]] ||
        fail "Smelterl generate did not produce expected artefact: ${BUILD_SDK_TARGET_EXTERNAL_MK_FILE}"
    [[ -s "${BUILD_SDK_TARGET_DEFCONFIG_FILE}" ]] ||
        fail "Smelterl generate did not produce expected artefact: ${BUILD_SDK_TARGET_DEFCONFIG_FILE}"
    [[ -s "${BUILD_SDK_TARGET_CONTEXT_FILE}" ]] ||
        fail "Smelterl generate did not produce expected artefact: ${BUILD_SDK_TARGET_CONTEXT_FILE}"

    BUILD_SDK_GENERATED_TARGETS+=("${target_id}")
}

build_sdk_write_make_alloy_helper() {
    local target_id="$1"
    local buildroot_path="$2"
    local helper_path="${BUILD_SDK_TARGET_WORKSPACE_DIR}/make_alloy"
    local debug_level="${ALLOY_DEBUG:-0}"
    local -a helper_args=(
        "-C" "${buildroot_path}"
        "O=${BUILD_SDK_TARGET_WORKSPACE_DIR}"
        "BR2_EXTERNAL=${BUILD_SDK_TARGET_EXTERNAL_DIR}"
        "ALLOY_MOTHERLODE=${ALLOY_MOTHERLODE}"
        "ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}"
        "ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}"
        "ALLOY_ARTEFACT_DIR=${ALLOY_ARTEFACT_DIR}"
        "ALLOY_ROOT_DIR=${ALLOY_ROOT_DIR}"
        "ALLOY_SDK_STAGING_DIR=${ALLOY_SDK_STAGING_DIR}"
        "ALLOY_DEBUG=${ALLOY_DEBUG:-0}"
        "ALLOY_TRACE=${ALLOY_TRACE:-false}"
    )
    if [[ -n "${ALLOY_PRODUCT:-}" ]]; then
        helper_args+=("ALLOY_PRODUCT=${ALLOY_PRODUCT}")
    fi
    if [[ -n "${ALLOY_IS_AUXILIARY:-}" ]]; then
        helper_args+=("ALLOY_IS_AUXILIARY=${ALLOY_IS_AUXILIARY}")
    fi
    if [[ -n "${ALLOY_AUXILIARY:-}" ]]; then
        helper_args+=("ALLOY_AUXILIARY=${ALLOY_AUXILIARY}")
    fi
    if (( debug_level >= 3 )); then
        helper_args+=("V=1")
    fi

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -euo pipefail\n'
        printf 'exec make'
        local arg
        for arg in "${helper_args[@]}"; do
            printf ' %q' "${arg}"
        done
        printf ' "$@"\n'
    } > "${helper_path}"
    chmod +x "${helper_path}"
    log_debug "Generated make_alloy helper for target '${target_id}': ${helper_path}"
}

build_sdk_build_target() {
    local target_id="$1"
    local context_file="${ALLOY_SDK_TARGETS_DIR}/${target_id}/alloy_context.sh"
    local target_defconfig="${target_id}_defconfig"
    local buildroot_path
    local debug_level="${ALLOY_DEBUG:-0}"
    local -a make_base_args

    [[ -f "${context_file}" ]] ||
        fail "Target context is missing for Buildroot build execution: ${context_file}"

    unset ALLOY_CONFIG_BUILDROOT_PATH ALLOY_PRODUCT ALLOY_IS_AUXILIARY ALLOY_AUXILIARY || true
    # shellcheck disable=SC1090 # target context is generated by smelterl for this SDK build.
    source "${context_file}"

    buildroot_path="${ALLOY_CONFIG_BUILDROOT_PATH:-}"
    [[ -n "${buildroot_path}" ]] ||
        fail "Target context is missing ALLOY_CONFIG_BUILDROOT_PATH for target '${target_id}'"
    [[ -d "${buildroot_path}" ]] ||
        fail "Buildroot path does not exist for target '${target_id}': ${buildroot_path}"
    [[ -f "${buildroot_path}/Makefile" ]] ||
        fail "Buildroot path is missing Makefile for target '${target_id}': ${buildroot_path}"

    build_sdk_prepare_target_layout "${target_id}"
    [[ -s "${BUILD_SDK_TARGET_DEFCONFIG_FILE}" ]] ||
        fail "Missing generated defconfig for target '${target_id}': ${BUILD_SDK_TARGET_DEFCONFIG_FILE}"

    build_sdk_write_make_alloy_helper "${target_id}" "${buildroot_path}"

    make_base_args=(
        -C "${buildroot_path}"
        "O=${BUILD_SDK_TARGET_WORKSPACE_DIR}"
        "BR2_EXTERNAL=${BUILD_SDK_TARGET_EXTERNAL_DIR}"
        "ALLOY_MOTHERLODE=${ALLOY_MOTHERLODE}"
        "ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}"
        "ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}"
        "ALLOY_ARTEFACT_DIR=${ALLOY_ARTEFACT_DIR}"
        "ALLOY_ROOT_DIR=${ALLOY_ROOT_DIR}"
        "ALLOY_SDK_STAGING_DIR=${ALLOY_SDK_STAGING_DIR}"
        "ALLOY_DEBUG=${ALLOY_DEBUG:-0}"
        "ALLOY_TRACE=${ALLOY_TRACE:-false}"
    )
    if [[ -n "${ALLOY_PRODUCT:-}" ]]; then
        make_base_args+=("ALLOY_PRODUCT=${ALLOY_PRODUCT}")
    fi
    if [[ -n "${ALLOY_IS_AUXILIARY:-}" ]]; then
        make_base_args+=("ALLOY_IS_AUXILIARY=${ALLOY_IS_AUXILIARY}")
    fi
    if [[ -n "${ALLOY_AUXILIARY:-}" ]]; then
        make_base_args+=("ALLOY_AUXILIARY=${ALLOY_AUXILIARY}")
    fi
    if (( debug_level >= 3 )); then
        make_base_args+=("V=1")
    fi

    log_info "Running Buildroot defconfig for target '${target_id}'."
    if ! make "${make_base_args[@]}" "${target_defconfig}"; then
        fail "Buildroot defconfig failed for target '${target_id}'"
    fi

    log_info "Running Buildroot build for target '${target_id}'."
    if ! make "${make_base_args[@]}"; then
        fail "Buildroot build failed for target '${target_id}'"
    fi

    BUILD_SDK_BUILT_TARGETS+=("${target_id}")
}

build_sdk_run_target_legal_info() {
    local target_id="$1"
    local context_file="${ALLOY_SDK_TARGETS_DIR}/${target_id}/alloy_context.sh"
    local buildroot_path
    local debug_level="${ALLOY_DEBUG:-0}"
    local -a make_base_args

    [[ -f "${context_file}" ]] ||
        fail "Target context is missing for legal-info execution: ${context_file}"

    unset ALLOY_CONFIG_BUILDROOT_PATH ALLOY_PRODUCT ALLOY_IS_AUXILIARY ALLOY_AUXILIARY || true
    # shellcheck disable=SC1090 # target context is generated by smelterl for this SDK build.
    source "${context_file}"

    buildroot_path="${ALLOY_CONFIG_BUILDROOT_PATH:-}"
    [[ -n "${buildroot_path}" ]] ||
        fail "Target context is missing ALLOY_CONFIG_BUILDROOT_PATH for target '${target_id}'"
    [[ -d "${buildroot_path}" ]] ||
        fail "Buildroot path does not exist for target '${target_id}': ${buildroot_path}"
    [[ -f "${buildroot_path}/Makefile" ]] ||
        fail "Buildroot path is missing Makefile for target '${target_id}': ${buildroot_path}"

    build_sdk_prepare_target_layout "${target_id}"

    make_base_args=(
        -C "${buildroot_path}"
        "O=${BUILD_SDK_TARGET_WORKSPACE_DIR}"
        "BR2_EXTERNAL=${BUILD_SDK_TARGET_EXTERNAL_DIR}"
        "ALLOY_MOTHERLODE=${ALLOY_MOTHERLODE}"
        "ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}"
        "ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}"
        "ALLOY_ARTEFACT_DIR=${ALLOY_ARTEFACT_DIR}"
        "ALLOY_ROOT_DIR=${ALLOY_ROOT_DIR}"
        "ALLOY_SDK_STAGING_DIR=${ALLOY_SDK_STAGING_DIR}"
        "ALLOY_DEBUG=${ALLOY_DEBUG:-0}"
        "ALLOY_TRACE=${ALLOY_TRACE:-false}"
    )
    if [[ -n "${ALLOY_PRODUCT:-}" ]]; then
        make_base_args+=("ALLOY_PRODUCT=${ALLOY_PRODUCT}")
    fi
    if [[ -n "${ALLOY_IS_AUXILIARY:-}" ]]; then
        make_base_args+=("ALLOY_IS_AUXILIARY=${ALLOY_IS_AUXILIARY}")
    fi
    if [[ -n "${ALLOY_AUXILIARY:-}" ]]; then
        make_base_args+=("ALLOY_AUXILIARY=${ALLOY_AUXILIARY}")
    fi
    if (( debug_level >= 3 )); then
        make_base_args+=("V=1")
    fi

    log_info "Running Buildroot legal-info for target '${target_id}'."
    if ! make "${make_base_args[@]}" legal-info; then
        fail "Buildroot legal-info failed for target '${target_id}'"
    fi
}

build_sdk_run_target_pre_build_hooks() {
    local target_id="$1"
    local context_file="${ALLOY_SDK_TARGETS_DIR}/${target_id}/alloy_context.sh"

    [[ -f "${context_file}" ]] ||
        fail "Target context is missing for pre_build execution: ${context_file}"

    unset ALLOY_PRE_BUILD_HOOKS || true
    # shellcheck disable=SC1090 # target context is generated by smelterl for this SDK build.
    source "${context_file}"

    if ! declare -p ALLOY_PRE_BUILD_HOOKS >/dev/null 2>&1; then
        log_info "No pre_build hooks declared for target '${target_id}'."
        return 0
    fi

    local hook_entry nugget_id script_relpath nugget_key nugget_var_suffix
    local nugget_dir_var nugget_name_var nugget_desc_var nugget_version_var nugget_flavor_var
    local nugget_dir hook_script
    local -a hook_entries=("${ALLOY_PRE_BUILD_HOOKS[@]}")
    export ALLOY_HOOK_TYPE="pre_build"

    for hook_entry in "${hook_entries[@]}"; do
        [[ "${hook_entry}" == *:* ]] ||
            fail "Invalid hook entry in ALLOY_PRE_BUILD_HOOKS: ${hook_entry}"

        nugget_id="${hook_entry%%:*}"
        script_relpath="${hook_entry#*:}"
        [[ -n "${nugget_id}" ]] || fail "Invalid hook entry with empty nugget id: ${hook_entry}"
        [[ -n "${script_relpath}" ]] || fail "Invalid hook entry with empty script path: ${hook_entry}"

        nugget_key="${nugget_id}"
        if [[ -n "${BUILD_SDK_PRE_BUILD_RUN_BY_NUGGET[${nugget_key}]:-}" ]]; then
            log_debug "Skipping pre_build hook for nugget '${nugget_id}' in target '${target_id}' (already executed)."
            BUILD_SDK_PRE_BUILD_SKIPPED=$((BUILD_SDK_PRE_BUILD_SKIPPED + 1))
            continue
        fi

        nugget_var_suffix="${nugget_id^^}"
        nugget_var_suffix="${nugget_var_suffix//[^A-Z0-9]/_}"
        nugget_dir_var="ALLOY_NUGGET_${nugget_var_suffix}_DIR"
        nugget_name_var="ALLOY_NUGGET_${nugget_var_suffix}_NAME"
        nugget_desc_var="ALLOY_NUGGET_${nugget_var_suffix}_DESC"
        nugget_version_var="ALLOY_NUGGET_${nugget_var_suffix}_VERSION"
        nugget_flavor_var="ALLOY_NUGGET_${nugget_var_suffix}_FLAVOR"

        nugget_dir="${!nugget_dir_var:-}"
        [[ -n "${nugget_dir}" ]] ||
            fail "pre_build hook context is missing ${nugget_dir_var} for nugget '${nugget_id}'"

        hook_script="${nugget_dir}/${script_relpath}"
        if [[ ! -f "${hook_script}" ]]; then
            log_warn "Skipping missing pre_build hook script: ${hook_script}"
            BUILD_SDK_PRE_BUILD_RUN_BY_NUGGET["${nugget_key}"]="missing"
            BUILD_SDK_PRE_BUILD_MISSING=$((BUILD_SDK_PRE_BUILD_MISSING + 1))
            continue
        fi

        export ALLOY_NUGGET="${nugget_id}"
        export ALLOY_NUGGET_DIR="${nugget_dir}"
        export ALLOY_NUGGET_NAME="${!nugget_name_var:-}"
        export ALLOY_NUGGET_DESC="${!nugget_desc_var:-}"
        export ALLOY_NUGGET_VERSION="${!nugget_version_var:-}"
        export ALLOY_NUGGET_FLAVOR="${!nugget_flavor_var:-}"

        log_info "Running pre_build hook: ${nugget_id}:${script_relpath} (target '${target_id}')"
        if ! bash "${hook_script}"; then
            fail "pre_build hook failed: ${nugget_id}:${script_relpath}"
        fi

        BUILD_SDK_PRE_BUILD_RUN_BY_NUGGET["${nugget_key}"]="ran"
        BUILD_SDK_PRE_BUILD_RAN=$((BUILD_SDK_PRE_BUILD_RAN + 1))
    done
}

build_sdk_generate_targets() {
    declare -gA BUILD_SDK_PRE_BUILD_RUN_BY_NUGGET=()
    BUILD_SDK_PRE_BUILD_RAN=0
    BUILD_SDK_PRE_BUILD_SKIPPED=0
    BUILD_SDK_PRE_BUILD_MISSING=0
    BUILD_SDK_GENERATED_TARGETS=()
    BUILD_SDK_BUILT_TARGETS=()
    build_sdk_load_plan_metadata

    local target_id
    for target_id in "${ALLOY_PLAN_TARGET_IDS[@]}"; do
        build_sdk_generate_target "${target_id}"
        build_sdk_run_target_pre_build_hooks "${target_id}"
        build_sdk_build_target "${target_id}"
    done
    for target_id in "${ALLOY_PLAN_TARGET_IDS[@]}"; do
        build_sdk_run_target_legal_info "${target_id}"
    done

    log_info "Smelterl generate + Buildroot build complete for ${#BUILD_SDK_GENERATED_TARGETS[@]} targets."
    log_debug "pre_build summary: ran=${BUILD_SDK_PRE_BUILD_RAN}, skipped=${BUILD_SDK_PRE_BUILD_SKIPPED}, missing=${BUILD_SDK_PRE_BUILD_MISSING}"
}

build_sdk_print_summary() {
    local build_dir="$1"

    print_result "Initialized SDK build workspace for ${ARG_PRODUCT_NUGGET}."
    print_note "Smelterl executable: ${ALLOY_SMELTERL}"
    print_note "Build directory: ${build_dir}"
    print_note "Plan directory: ${ALLOY_SDK_PLAN_DIR}"
    print_note "Plan file: ${ALLOY_SDK_PLAN_FILE}"
    print_note "Plan environment file: ${ALLOY_SDK_PLAN_ENV_FILE}"
    print_note "Targets directory: ${ALLOY_SDK_TARGETS_DIR}"
    print_note "Generated targets: ${BUILD_SDK_GENERATED_TARGETS[*]}"
    print_note "Built targets: ${BUILD_SDK_BUILT_TARGETS[*]}"
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

    print_hint "Per-target Buildroot and legal-info execution is complete; manifest consolidation and SDK packing follow in later Phase 5 tasks."
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
require_command make || fail "make is required for Buildroot target execution"

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
build_sdk_ensure_smelterl
build_sdk_run_plan
build_sdk_generate_targets
build_sdk_print_summary "${build_dir}"
