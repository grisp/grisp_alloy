#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

BUILD_SDK_COMMAND="$(harness_repo_root)/scripts/commands/build-sdk.sh"

build_sdk_test_make_fixture() {
    local temp_dir="$1"
    local root_dir="${temp_dir}/fixture"
    mkdir -p "${root_dir}/scripts/commands" "${root_dir}/scripts/utils" "${root_dir}/scripts/tests/lib" "${root_dir}/scripts/buildroot"
    cp "${BUILD_SDK_COMMAND}" "${root_dir}/scripts/commands/build-sdk.sh"
    cp "$(harness_repo_root)/scripts/buildroot/script_hook.sh" "${root_dir}/scripts/buildroot/script_hook.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${root_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${root_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${root_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/vcs_utils.sh" "${root_dir}/scripts/utils/vcs_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/file_utils.sh" "${root_dir}/scripts/utils/file_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_utils.sh" "${root_dir}/scripts/utils/sdk_utils.sh"
    cp "$(harness_repo_root)/scripts/argparse.sh" "${root_dir}/scripts/argparse.sh"
    cp "$(harness_repo_root)/alloy" "${root_dir}/alloy"
    chmod +x "${root_dir}/alloy"
    chmod +x "${root_dir}/scripts/commands/build-sdk.sh"
    chmod +x "${root_dir}/scripts/buildroot/script_hook.sh"
    build_sdk_test_write_registry "${root_dir}/nuggets" builtin_feature
    mkdir -p "${root_dir}/smelterl/src"
    : > "${root_dir}/smelterl/rebar.config"
    cat > "${root_dir}/smelterl/src/smelterl.app.src" <<'EOF'
{application, smelterl, [
    {vsn, "9.8.7"}
]}.
EOF
    printf '%s\n' "${root_dir}"
}

build_sdk_test_git() {
    local git_home="$1"
    shift
    HOME="${git_home}" XDG_CONFIG_HOME="${git_home}/xdg" GIT_CONFIG_NOSYSTEM=1 git "$@"
}

build_sdk_test_write_registry() {
    local repo_dir="$1"
    local nugget_id="$2"

    mkdir -p "${repo_dir}/${nugget_id}"
    cat > "${repo_dir}/.nuggets" <<EOF
{nugget_registry, <<"1.0">>, [{nuggets, [<<"${nugget_id}/.nugget">>]}]}.
EOF
    cat > "${repo_dir}/${nugget_id}/.nugget" <<EOF
{nugget, <<"1.0">>, [{id, ${nugget_id}}, {category, feature}]}.
EOF
}

build_sdk_test_make_remote_nugget_repo() {
    local temp_dir="$1"
    local name="$2"
    local -n remote_ref="$3"

    local git_home="${temp_dir}/${name}-git-home"
    local work_dir="${temp_dir}/${name}-work"
    remote_ref="${temp_dir}/${name}.git"
    mkdir -p "${git_home}/xdg"

    build_sdk_test_git "${git_home}" init --bare "${remote_ref}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" init -b main "${work_dir}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${work_dir}" config user.name "Alloy Tests"
    build_sdk_test_git "${git_home}" -C "${work_dir}" config user.email "alloy-tests@example.com"
    build_sdk_test_git "${git_home}" -C "${work_dir}" remote add origin "${remote_ref}"
    build_sdk_test_write_registry "${work_dir}" "${name}_feature"
    printf '%s\n' "${name}" > "${work_dir}/remote-marker.txt"
    build_sdk_test_git "${git_home}" -C "${work_dir}" add .
    build_sdk_test_git "${git_home}" -C "${work_dir}" commit -m "initial" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${work_dir}" push -u origin main >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${remote_ref}" symbolic-ref HEAD refs/heads/main
}

build_sdk_test_repo_smelterl_version() {
    sed -n 's/^[[:space:]]*{vsn,[[:space:]]*"\([^"]\+\)".*/\1/p' \
        "$(harness_repo_root)/smelterl/src/smelterl.app.src" | head -n 1
}

build_sdk_test_prepare_cached_smelterl() {
    local artefact_dir="$1"
    local version="${2:-$(build_sdk_test_repo_smelterl_version)}"
    local smelterl_path="${artefact_dir}/tools/smelterl-${version}"

    mkdir -p "${artefact_dir}/tools"
    build_sdk_test_write_fake_smelterl "${smelterl_path}" "cached smelterl ${version}"
    chmod +x "${smelterl_path}"
}

build_sdk_test_write_fake_smelterl() {
    local smelterl_path="$1"
    local marker="$2"

    cat > "${smelterl_path}" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_SMELTERL_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "${FAKE_SMELTERL_LOG}"
fi

write_shell_array() {
    local name="$1"
    shift
    local value
    printf '%s=(' "${name}"
    for value in "$@"; do
        printf '%q ' "${value}"
    done
    printf ')\n'
}

write_assoc_array_entry() {
    local key="$1"
    local value="$2"
    printf "  [%q]=%q\n" "${key}" "${value}"
}

command_name="${1:-}"
[[ -n "${command_name}" ]] || exit 9
shift

case "${command_name}" in
    plan)
        product=""
        motherlode=""
        output_plan=""
        output_plan_env=""
        extra_config_count=0

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --product)
                    product="${2:?}"
                    shift 2
                    ;;
                --motherlode)
                    motherlode="${2:?}"
                    shift 2
                    ;;
                --output-plan)
                    output_plan="${2:?}"
                    shift 2
                    ;;
                --output-plan-env)
                    output_plan_env="${2:?}"
                    shift 2
                    ;;
                --extra-config)
                    extra_config_count=$((extra_config_count + 1))
                    shift 2
                    ;;
                *)
                    printf 'unexpected fake smelterl plan arg: %s\n' "$1" >&2
                    exit 10
                    ;;
            esac
        done

        [[ -n "${product}" ]] || exit 11
        [[ -d "${motherlode}" ]] || exit 12
        [[ -n "${output_plan}" ]] || exit 13
        [[ -n "${output_plan_env}" ]] || exit 14
        [[ "${extra_config_count}" -eq 8 ]] || exit 15

        aux_ids_raw="${FAKE_SMELTERL_AUXILIARY_IDS:-}"
        aux_ids=()
        if [[ -n "${aux_ids_raw}" ]]; then
            read -r -a aux_ids <<< "${aux_ids_raw}"
        fi
        target_ids=("${aux_ids[@]}" main)

        mkdir -p "$(dirname "${output_plan}")" "$(dirname "${output_plan_env}")"
        printf '{fake_build_plan, [{product, <<"%s">>}]}.\n' "${product}" > "${output_plan}"
        {
            printf 'ALLOY_PLAN_PRODUCT=%q\n' "${product}"
            printf 'ALLOY_PLAN_MAIN_TARGET=%q\n' 'main'
            write_shell_array "ALLOY_PLAN_AUXILIARY_IDS" "${aux_ids[@]}"
            write_shell_array "ALLOY_PLAN_TARGET_IDS" "${target_ids[@]}"
            printf 'declare -A ALLOY_PLAN_TARGET_KIND=(\n'
            target_id=""
            for target_id in "${aux_ids[@]}"; do
                write_assoc_array_entry "${target_id}" "auxiliary"
            done
            write_assoc_array_entry "main" "main"
            printf ')\n'
            printf 'declare -A ALLOY_PLAN_TARGET_ROOT=(\n'
            for target_id in "${aux_ids[@]}"; do
                write_assoc_array_entry "${target_id}" "${target_id}_root"
            done
            write_assoc_array_entry "main" "${product}"
            printf ')\n'
            printf 'declare -A ALLOY_PLAN_EXTRA_CONFIG=(\n'
            write_assoc_array_entry "ALLOY_BUILD_DIR" '${ALLOY_BUILD_DIR}'
            printf ')\n'
        } > "${output_plan_env}"
        ;;
    generate)
        plan_path=""
        auxiliary_target=""
        output_external_desc=""
        output_config_in=""
        output_external_mk=""
        output_defconfig=""
        output_context=""
        output_manifest=""
        export_legal=""
        include_sources="false"
        buildroot_legals=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan)
                    plan_path="${2:?}"
                    shift 2
                    ;;
                --auxiliary)
                    auxiliary_target="${2:?}"
                    shift 2
                    ;;
                --output-external-desc)
                    output_external_desc="${2:?}"
                    shift 2
                    ;;
                --output-config-in)
                    output_config_in="${2:?}"
                    shift 2
                    ;;
                --output-external-mk)
                    output_external_mk="${2:?}"
                    shift 2
                    ;;
                --output-defconfig)
                    output_defconfig="${2:?}"
                    shift 2
                    ;;
                --output-context)
                    output_context="${2:?}"
                    shift 2
                    ;;
                --output-manifest)
                    output_manifest="${2:?}"
                    shift 2
                    ;;
                --buildroot-legal)
                    buildroot_legals+=("${2:?}")
                    shift 2
                    ;;
                --export-legal)
                    export_legal="${2:?}"
                    shift 2
                    ;;
                --include-sources)
                    include_sources="true"
                    shift
                    ;;
                *)
                    printf 'unexpected fake smelterl generate arg: %s\n' "$1" >&2
                    exit 16
                    ;;
            esac
        done

        [[ -n "${plan_path}" ]] || exit 17
        [[ -f "${plan_path}" ]] || exit 18
        if [[ -z "${output_manifest}" ]]; then
            [[ -n "${output_external_desc}" ]] || exit 19
            [[ -n "${output_config_in}" ]] || exit 20
            [[ -n "${output_external_mk}" ]] || exit 21
            [[ -n "${output_defconfig}" ]] || exit 22
            [[ -n "${output_context}" ]] || exit 23
        fi

        target_id="main"
        if [[ -n "${auxiliary_target}" ]]; then
            target_id="${auxiliary_target}"
        fi

        if [[ -n "${output_context}" ]]; then
            sdk_root="$(cd "$(dirname "${output_context}")/../.." && pwd -P)"
        elif [[ -n "${output_manifest}" ]]; then
            sdk_root="$(cd "$(dirname "${output_manifest}")/.." && pwd -P)"
        else
            printf 'fake smelterl generate requires output context or manifest path\n' >&2
            exit 27
        fi
        buildroot_path="${FAKE_BUILDROOT_PATH:-${sdk_root}/fake-buildroot}"
        mkdir -p "${buildroot_path}"
        cat > "${buildroot_path}/Makefile" <<'MAKEFILE'
.PHONY: all
all:
	@mkdir -p "$(O)"
	@mkdir -p "$(O)/host/usr/lib" "$(O)/images" "$(O)/staging/usr"
	@if [ "$$FAKE_MAKE_STAGING_ABSOLUTE_SYMLINK" = "true" ]; then \
		mkdir -p "$(O)/host/x86_64-buildroot-linux-gnu/sysroot/usr"; \
		rm -rf "$(O)/staging"; \
		ln -s "$(O)/host/x86_64-buildroot-linux-gnu/sysroot" "$(O)/staging"; \
	fi
	@printf 'SDK_HOST_PATH=%s/host\n' "$(O)" > "$(O)/host/usr/lib/sdk-paths.env"
	@printf 'SDK_IMAGES_PATH=%s/images\n' "$(O)" > "$(O)/images/sdk-paths.env"
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'build goal=all O=%s BR2_EXTERNAL=%s V=%s\n' "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi

%_defconfig:
	@mkdir -p "$(O)"
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'defconfig goal=%s O=%s BR2_EXTERNAL=%s V=%s\n' "$@" "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi

%:
	@mkdir -p "$(O)"
	@if [ "$@" = "legal-info" ]; then mkdir -p "$(O)/legal-info"; fi
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'custom goal=%s O=%s BR2_EXTERNAL=%s V=%s\n' "$@" "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi
MAKEFILE
        mkdir -p "${buildroot_path}/utils"
        cat > "${buildroot_path}/utils/brmake" <<'BRMAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_BRMAKE_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "${FAKE_BRMAKE_LOG}"
fi
exec make "$@"
BRMAKE
        chmod +x "${buildroot_path}/utils/brmake"

        if [[ -n "${output_external_desc}" ]]; then
            mkdir -p \
                "$(dirname "${output_external_desc}")" \
                "$(dirname "${output_config_in}")" \
                "$(dirname "${output_external_mk}")" \
                "$(dirname "${output_defconfig}")" \
                "$(dirname "${output_context}")"
            printf 'name: %s\n' "${target_id}" > "${output_external_desc}"
            printf '# Config for %s\n' "${target_id}" > "${output_config_in}"
            printf '# external.mk for %s\n' "${target_id}" > "${output_external_mk}"
            printf 'BR2_%s=y\n' "${target_id^^}" > "${output_defconfig}"
            printf 'export ALLOY_PRODUCT=%q\n' "${target_id}" > "${output_context}"
            printf 'export ALLOY_CONFIG_BUILDROOT_PATH=%q\n' "${buildroot_path}" >> "${output_context}"
            if [[ "${target_id}" == "main" ]]; then
                printf 'export ALLOY_IS_AUXILIARY=%q\n' "false" >> "${output_context}"
            else
                printf 'export ALLOY_IS_AUXILIARY=%q\n' "true" >> "${output_context}"
                printf 'export ALLOY_AUXILIARY=%q\n' "${target_id}" >> "${output_context}"
            fi
            printf 'export ALLOY_SDK_OUTPUTS=()\n' >> "${output_context}"
        fi

        if [[ -n "${output_context}" ]] && [[ "${target_id}" != "main" ]] && [[ -n "${FAKE_SMELTERL_AUX_OUTPUTS:-}" ]]; then
            aux_output_spec=""
            IFS=';' read -r -a aux_specs <<< "${FAKE_SMELTERL_AUX_OUTPUTS}"
            for spec in "${aux_specs[@]}"; do
                spec_target="${spec%%:*}"
                spec_outputs="${spec#*:}"
                if [[ "${spec_target}" == "${target_id}" ]]; then
                    aux_output_spec="${spec_outputs}"
                    break
                fi
            done

            if [[ -n "${aux_output_spec}" ]]; then
                read -r -a aux_output_ids <<< "${aux_output_spec//,/ }"
                {
                    printf 'export ALLOY_SDK_OUTPUTS=('
                    for output_id in "${aux_output_ids[@]}"; do
                        printf '%q ' "${output_id}"
                    done
                    printf ')\n'
                    for output_id in "${aux_output_ids[@]}"; do
                        output_var_suffix="${output_id^^}"
                        output_var_suffix="${output_var_suffix//[^A-Z0-9]/_}"
                        printf 'export ALLOY_SDK_OUTPUT_%s_NAME=%q\n' "${output_var_suffix}" "${output_id} name"
                        printf 'export ALLOY_SDK_OUTPUT_%s_DESCRIPTION=%q\n' "${output_var_suffix}" "${output_id} description"
                    done
                } >> "${output_context}"

                if [[ "${FAKE_SMELTERL_REGISTER_AUX_OUTPUTS:-true}" == "true" ]]; then
                    target_workspace="$(dirname "${output_context}")/workspace"
                    mkdir -p "${target_workspace}/.sdk_outputs"
                    for output_id in "${aux_output_ids[@]}"; do
                        output_file="${target_workspace}/${target_id}-${output_id}.bin"
                        printf '%s\n' "${target_id}:${output_id}" > "${output_file}"
                        printf '%s\n' "${output_file}" > "${target_workspace}/.sdk_outputs/${output_id}"
                    done
                fi
            fi
        fi

        if [[ -n "${output_context}" ]] && [[ "${FAKE_SMELTERL_EMIT_PRE_BUILD:-false}" == "true" ]]; then
            hooks_root="${sdk_root}/pre-build-fixture"
            shared_nugget_dir="${hooks_root}/shared"
            target_nugget_id="target_${target_id}"
            target_nugget_dir="${hooks_root}/${target_nugget_id}"
            shared_var_suffix="SHARED"
            target_var_suffix="${target_nugget_id^^}"
            target_var_suffix="${target_var_suffix//[^A-Z0-9]/_}"

            mkdir -p "${shared_nugget_dir}/scripts" "${target_nugget_dir}/scripts"
            cat > "${shared_nugget_dir}/scripts/pre-build.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_PRE_BUILD_LOG:-}" ]]; then
    printf 'shared:%s:%s\n' "${ALLOY_PRODUCT:-}" "${ALLOY_NUGGET:-}" >> "${FAKE_PRE_BUILD_LOG}"
fi
HOOK
            chmod +x "${shared_nugget_dir}/scripts/pre-build.sh"

            cat > "${target_nugget_dir}/scripts/pre-build.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_PRE_BUILD_LOG:-}" ]]; then
    printf 'target:%s:%s\n' "${ALLOY_PRODUCT:-}" "${ALLOY_NUGGET:-}" >> "${FAKE_PRE_BUILD_LOG}"
fi
HOOK
            chmod +x "${target_nugget_dir}/scripts/pre-build.sh"

            {
                printf 'ALLOY_PRE_BUILD_HOOKS=(%q %q)\n' \
                    "shared:scripts/pre-build.sh" \
                    "${target_nugget_id}:scripts/pre-build.sh"
                printf 'export ALLOY_NUGGET_%s_DIR=%q\n' "${shared_var_suffix}" "${shared_nugget_dir}"
                printf 'export ALLOY_NUGGET_%s_NAME=%q\n' "${shared_var_suffix}" "Shared"
                printf 'export ALLOY_NUGGET_%s_DESC=%q\n' "${shared_var_suffix}" "Shared"
                printf 'export ALLOY_NUGGET_%s_VERSION=%q\n' "${shared_var_suffix}" "1.0.0"
                printf 'export ALLOY_NUGGET_%s_FLAVOR=%q\n' "${shared_var_suffix}" ""
                printf 'export ALLOY_NUGGET_%s_DIR=%q\n' "${target_var_suffix}" "${target_nugget_dir}"
                printf 'export ALLOY_NUGGET_%s_NAME=%q\n' "${target_var_suffix}" "${target_nugget_id}"
                printf 'export ALLOY_NUGGET_%s_DESC=%q\n' "${target_var_suffix}" "${target_nugget_id}"
                printf 'export ALLOY_NUGGET_%s_VERSION=%q\n' "${target_var_suffix}" "1.0.0"
                printf 'export ALLOY_NUGGET_%s_FLAVOR=%q\n' "${target_var_suffix}" ""
            } >> "${output_context}"
        fi

        if [[ -n "${output_manifest}" ]]; then
            [[ "${target_id}" == "main" ]] || exit 25
            mkdir -p "$(dirname "${output_manifest}")"
            printf '{sdk_manifest, <<"1.0">>, [{include_sources, %s}]}.\n' "${include_sources}" > "${output_manifest}"

            if [[ -n "${export_legal}" ]]; then
                legal_root="$(dirname "${output_manifest}")/${export_legal}"
                mkdir -p "${legal_root}"
                printf 'merged legal info\n' > "${legal_root}/README"
            fi

            legal_dir=""
            for legal_dir in "${buildroot_legals[@]}"; do
                [[ -d "${legal_dir}" ]] || exit 26
            done
        fi
        ;;
    *)
        printf 'fake smelterl does not support command: %s\n' "${command_name}" >&2
        exit 24
        ;;
esac

exit 0
SCRIPT
    printf '%s\n' "${marker}" >> "${smelterl_path}"
}

build_sdk_test_write_fake_rebar3() {
    local bin_dir="$1"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/rebar3" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_REBAR3_LOG:?}"
case "${1:-}" in
    clean)
        rm -rf _build/default/bin/smelterl
        ;;
    escriptize)
        mkdir -p _build/default/bin
        cat > _build/default/bin/smelterl <<'FAKE_SMELTERL'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_SMELTERL_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "${FAKE_SMELTERL_LOG}"
fi

write_shell_array() {
    local name="$1"
    shift
    local value
    printf '%s=(' "${name}"
    for value in "$@"; do
        printf '%q ' "${value}"
    done
    printf ')\n'
}

write_assoc_array_entry() {
    local key="$1"
    local value="$2"
    printf "  [%q]=%q\n" "${key}" "${value}"
}

command_name="${1:-}"
[[ -n "${command_name}" ]] || exit 9
shift

case "${command_name}" in
    plan)
        product=""
        motherlode=""
        output_plan=""
        output_plan_env=""
        extra_config_count=0

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --product)
                    product="${2:?}"
                    shift 2
                    ;;
                --motherlode)
                    motherlode="${2:?}"
                    shift 2
                    ;;
                --output-plan)
                    output_plan="${2:?}"
                    shift 2
                    ;;
                --output-plan-env)
                    output_plan_env="${2:?}"
                    shift 2
                    ;;
                --extra-config)
                    extra_config_count=$((extra_config_count + 1))
                    shift 2
                    ;;
                *)
                    printf 'unexpected fake smelterl plan arg: %s\n' "$1" >&2
                    exit 10
                    ;;
            esac
        done

        [[ -n "${product}" ]] || exit 11
        [[ -d "${motherlode}" ]] || exit 12
        [[ -n "${output_plan}" ]] || exit 13
        [[ -n "${output_plan_env}" ]] || exit 14
        [[ "${extra_config_count}" -eq 8 ]] || exit 15

        aux_ids_raw="${FAKE_SMELTERL_AUXILIARY_IDS:-}"
        aux_ids=()
        if [[ -n "${aux_ids_raw}" ]]; then
            read -r -a aux_ids <<< "${aux_ids_raw}"
        fi
        target_ids=("${aux_ids[@]}" main)

        mkdir -p "$(dirname "${output_plan}")" "$(dirname "${output_plan_env}")"
        printf '{fake_build_plan, [{product, <<"%s">>}]}.\n' "${product}" > "${output_plan}"
        {
            printf 'ALLOY_PLAN_PRODUCT=%q\n' "${product}"
            printf 'ALLOY_PLAN_MAIN_TARGET=%q\n' 'main'
            write_shell_array "ALLOY_PLAN_AUXILIARY_IDS" "${aux_ids[@]}"
            write_shell_array "ALLOY_PLAN_TARGET_IDS" "${target_ids[@]}"
            printf 'declare -A ALLOY_PLAN_TARGET_KIND=(\n'
            target_id=""
            for target_id in "${aux_ids[@]}"; do
                write_assoc_array_entry "${target_id}" "auxiliary"
            done
            write_assoc_array_entry "main" "main"
            printf ')\n'
            printf 'declare -A ALLOY_PLAN_TARGET_ROOT=(\n'
            for target_id in "${aux_ids[@]}"; do
                write_assoc_array_entry "${target_id}" "${target_id}_root"
            done
            write_assoc_array_entry "main" "${product}"
            printf ')\n'
            printf 'declare -A ALLOY_PLAN_EXTRA_CONFIG=(\n'
            write_assoc_array_entry "ALLOY_BUILD_DIR" '${ALLOY_BUILD_DIR}'
            printf ')\n'
        } > "${output_plan_env}"
        ;;
    generate)
        plan_path=""
        auxiliary_target=""
        output_external_desc=""
        output_config_in=""
        output_external_mk=""
        output_defconfig=""
        output_context=""
        output_manifest=""
        export_legal=""
        include_sources="false"
        buildroot_legals=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan)
                    plan_path="${2:?}"
                    shift 2
                    ;;
                --auxiliary)
                    auxiliary_target="${2:?}"
                    shift 2
                    ;;
                --output-external-desc)
                    output_external_desc="${2:?}"
                    shift 2
                    ;;
                --output-config-in)
                    output_config_in="${2:?}"
                    shift 2
                    ;;
                --output-external-mk)
                    output_external_mk="${2:?}"
                    shift 2
                    ;;
                --output-defconfig)
                    output_defconfig="${2:?}"
                    shift 2
                    ;;
                --output-context)
                    output_context="${2:?}"
                    shift 2
                    ;;
                --output-manifest)
                    output_manifest="${2:?}"
                    shift 2
                    ;;
                --buildroot-legal)
                    buildroot_legals+=("${2:?}")
                    shift 2
                    ;;
                --export-legal)
                    export_legal="${2:?}"
                    shift 2
                    ;;
                --include-sources)
                    include_sources="true"
                    shift
                    ;;
                *)
                    printf 'unexpected fake smelterl generate arg: %s\n' "$1" >&2
                    exit 16
                    ;;
            esac
        done

        [[ -n "${plan_path}" ]] || exit 17
        [[ -f "${plan_path}" ]] || exit 18
        if [[ -z "${output_manifest}" ]]; then
            [[ -n "${output_external_desc}" ]] || exit 19
            [[ -n "${output_config_in}" ]] || exit 20
            [[ -n "${output_external_mk}" ]] || exit 21
            [[ -n "${output_defconfig}" ]] || exit 22
            [[ -n "${output_context}" ]] || exit 23
        fi

        target_id="main"
        if [[ -n "${auxiliary_target}" ]]; then
            target_id="${auxiliary_target}"
        fi

        if [[ -n "${output_context}" ]]; then
            sdk_root="$(cd "$(dirname "${output_context}")/../.." && pwd -P)"
        elif [[ -n "${output_manifest}" ]]; then
            sdk_root="$(cd "$(dirname "${output_manifest}")/.." && pwd -P)"
        else
            printf 'fake smelterl generate requires output context or manifest path\n' >&2
            exit 27
        fi
        buildroot_path="${FAKE_BUILDROOT_PATH:-${sdk_root}/fake-buildroot}"
        mkdir -p "${buildroot_path}"
        cat > "${buildroot_path}/Makefile" <<'MAKEFILE'
.PHONY: all
all:
	@mkdir -p "$(O)"
	@mkdir -p "$(O)/host/usr/lib" "$(O)/images" "$(O)/staging/usr"
	@if [ "$$FAKE_MAKE_STAGING_ABSOLUTE_SYMLINK" = "true" ]; then \
		mkdir -p "$(O)/host/x86_64-buildroot-linux-gnu/sysroot/usr"; \
		rm -rf "$(O)/staging"; \
		ln -s "$(O)/host/x86_64-buildroot-linux-gnu/sysroot" "$(O)/staging"; \
	fi
	@printf 'SDK_HOST_PATH=%s/host\n' "$(O)" > "$(O)/host/usr/lib/sdk-paths.env"
	@printf 'SDK_IMAGES_PATH=%s/images\n' "$(O)" > "$(O)/images/sdk-paths.env"
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'build goal=all O=%s BR2_EXTERNAL=%s V=%s\n' "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi

%_defconfig:
	@mkdir -p "$(O)"
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'defconfig goal=%s O=%s BR2_EXTERNAL=%s V=%s\n' "$@" "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi

%:
	@mkdir -p "$(O)"
	@if [ "$@" = "legal-info" ]; then mkdir -p "$(O)/legal-info"; fi
	@if [ -n "$$FAKE_MAKE_LOG" ]; then printf 'custom goal=%s O=%s BR2_EXTERNAL=%s V=%s\n' "$@" "$(O)" "$(BR2_EXTERNAL)" "$(V)" >> "$$FAKE_MAKE_LOG"; fi
MAKEFILE
        mkdir -p "${buildroot_path}/utils"
        cat > "${buildroot_path}/utils/brmake" <<'BRMAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_BRMAKE_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "${FAKE_BRMAKE_LOG}"
fi
exec make "$@"
BRMAKE
        chmod +x "${buildroot_path}/utils/brmake"

        if [[ -n "${output_external_desc}" ]]; then
            mkdir -p \
                "$(dirname "${output_external_desc}")" \
                "$(dirname "${output_config_in}")" \
                "$(dirname "${output_external_mk}")" \
                "$(dirname "${output_defconfig}")" \
                "$(dirname "${output_context}")"
            printf 'name: %s\n' "${target_id}" > "${output_external_desc}"
            printf '# Config for %s\n' "${target_id}" > "${output_config_in}"
            printf '# external.mk for %s\n' "${target_id}" > "${output_external_mk}"
            printf 'BR2_%s=y\n' "${target_id^^}" > "${output_defconfig}"
            printf 'export ALLOY_PRODUCT=%q\n' "${target_id}" > "${output_context}"
            printf 'export ALLOY_CONFIG_BUILDROOT_PATH=%q\n' "${buildroot_path}" >> "${output_context}"
            if [[ "${target_id}" == "main" ]]; then
                printf 'export ALLOY_IS_AUXILIARY=%q\n' "false" >> "${output_context}"
            else
                printf 'export ALLOY_IS_AUXILIARY=%q\n' "true" >> "${output_context}"
                printf 'export ALLOY_AUXILIARY=%q\n' "${target_id}" >> "${output_context}"
            fi
        fi

        if [[ -n "${output_manifest}" ]]; then
            [[ "${target_id}" == "main" ]] || exit 25
            mkdir -p "$(dirname "${output_manifest}")"
            printf '{sdk_manifest, <<"1.0">>, [{include_sources, %s}]}.\n' "${include_sources}" > "${output_manifest}"

            if [[ -n "${export_legal}" ]]; then
                legal_root="$(dirname "${output_manifest}")/${export_legal}"
                mkdir -p "${legal_root}"
                printf 'merged legal info\n' > "${legal_root}/README"
            fi

            legal_dir=""
            for legal_dir in "${buildroot_legals[@]}"; do
                [[ -d "${legal_dir}" ]] || exit 26
            done
        fi
        ;;
    *)
        printf 'fake smelterl does not support command: %s\n' "${command_name}" >&2
        exit 24
        ;;
esac

exit 0
FAKE_SMELTERL
        printf '%s\n' "${FAKE_REBAR3_OUTPUT:-built smelterl}" >> _build/default/bin/smelterl
        chmod +x _build/default/bin/smelterl
        ;;
    *)
        exit 9
        ;;
esac
SCRIPT
    chmod +x "${bin_dir}/rebar3"
}

test_build_sdk_command_help_shows_canonical_usage() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" --help 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Usage: alloy build sdk PRODUCT_NUGGET \\[OPTIONS\\]" "${output}"
    assert_matches "Global options accepted anywhere" "${output}"
    assert_matches "-d, -dd, -ddd" "${output}"
    assert_matches "--debug\\[=N\\]" "${output}"
    assert_matches "--clean-package PKG" "${output}"
    assert_status_code 1 "printf '%s\n' '${output}' | grep -F -- '-c PKG'"
}

test_build_sdk_command_requires_product_nugget() {
    local output status

    output="$(env -u ALLOY_MODE -u ALLOY_BUILD_DIR \
        "${BUILD_SDK_COMMAND}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Missing PRODUCT_NUGGET" "${output}"
}

test_build_sdk_command_rejects_sdk_mode() {
    local output status

    output="$(ALLOY_MODE=sdk "${BUILD_SDK_COMMAND}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_direct_invocation_infers_sdk_mode_from_manifest_and_rejects_it() {
    local temp_dir root_dir command_path output status
    temp_dir="$(harness_make_temp_dir "build-sdk-sdk-mode")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    : > "${root_dir}/ALLOY_SDK_MANIFEST"

    output="$(env -u ALLOY_MODE -u ALLOY_ROOT -u ALLOY_ROOT_DIR \
        -u ALLOY_BUILD_DIR -u ALLOY_ARTEFACT_DIR -u ALLOY_CACHE_DIR \
        "${command_path}" demo 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "build sdk is only available in repository mode" "${output}"
}

test_build_sdk_command_creates_expected_layout_and_reports_sources() {
    local temp_dir build_root artefact_dir env_source cli_source smelterl_log output status
    temp_dir="$(harness_make_temp_dir "build-sdk-layout")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    smelterl_log="${temp_dir}/smelterl.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    env_source="${temp_dir}/env_one"
    cli_source="${temp_dir}/local_one"
    build_sdk_test_write_registry "${env_source}" env_one_feature
    build_sdk_test_write_registry "${cli_source}" local_one_feature

    output="$(FAKE_SMELTERL_LOG="${smelterl_log}" \
        ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        ALLOY_NUGGET_PATH="${env_source}" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n "${cli_source}" \
        --include-sources \
        --allow-dirty 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/plan' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/staging' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/motherlode' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/plan/build_plan.term' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/plan/build_plan.env' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets/main/workspace' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/staging/.alloy_relocation_manifest' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/staging/.alloy_sdk_dir' ]]"
    assert_status_code 0 "[[ \"\$(cat '${build_root}/sdk/demo_product/staging/.alloy_sdk_dir')\" == '@@ALLOY_SDK_DIR@@' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/br2_external/external.desc' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/br2_external/Config.in' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/br2_external/external.mk' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/br2_external/configs/main_defconfig' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/alloy_context.sh' ]]"
    assert_status_code 0 "[[ -L '${build_root}/sdk/demo_product/targets/main/br2_external/board/main/scripts/post-build.sh' ]]"
    assert_status_code 0 "[[ -L '${build_root}/sdk/demo_product/targets/main/br2_external/board/main/scripts/post-image.sh' ]]"
    assert_status_code 0 "[[ -L '${build_root}/sdk/demo_product/targets/main/br2_external/board/main/scripts/post-fakeroot.sh' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${build_root}/sdk/demo_product/targets/main/br2_external/board/main/scripts/post-build.sh')\" == '$(harness_repo_root)/scripts/buildroot/script_hook.sh' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${build_root}/sdk/demo_product/targets/main/br2_external/board/main/scripts/alloy_context.sh')\" == '../../../../alloy_context.sh' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/builtin/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/env_one/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/local_one/.nuggets' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${artefact_dir}/tools/smelterl')\" == smelterl-* ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
    assert_matches "Smelterl executable: ${artefact_dir}/tools/smelterl-" "${output}"
    assert_matches "Additional command-line nugget sources: 1" "${output}"
    assert_matches "Additional environment nugget sources: 1" "${output}"
    assert_matches "Plan file: ${build_root}/sdk/demo_product/plan/build_plan.term" "${output}"
    assert_matches "Plan environment file: ${build_root}/sdk/demo_product/plan/build_plan.env" "${output}"
    assert_matches "Generated targets: main" "${output}"
    assert_matches "Generated SDK artefact: ${artefact_dir}/sdk/sdk-demo_product-" "${output}"
    assert_matches "Staged nugget repositories: 3" "${output}"
    assert_matches "Dirty VCS checkouts are allowed" "${output}"
    assert_matches "Legal-info source export was requested" "${output}"
    assert_status_code 0 "grep -Fq -- '--output-manifest ${build_root}/sdk/demo_product/staging/ALLOY_SDK_MANIFEST --export-legal legal-info --buildroot-legal ${build_root}/sdk/demo_product/targets/main/workspace/legal-info --include-sources' '${smelterl_log}'"
}

test_build_sdk_command_summary_paths_are_relative_only_within_cwd() {
    local temp_dir workspace build_root artefact_dir output status
    temp_dir="$(harness_make_temp_dir "build-sdk-summary-paths")"
    workspace="${temp_dir}/workspace"
    mkdir -p "${workspace}"
    build_root="${workspace}/build"
    artefact_dir="${temp_dir}_artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(
        cd "${workspace}" &&
            ALLOY_BUILD_DIR="${build_root}" \
            ALLOY_ARTEFACT_DIR="${artefact_dir}" \
            "${BUILD_SDK_COMMAND}" demo_product 2>&1
    )"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Build directory: build/sdk/demo_product" "${output}"
    assert_matches "Plan directory: build/sdk/demo_product/plan" "${output}"
    assert_matches "Staged SDK manifest: build/sdk/demo_product/staging/ALLOY_SDK_MANIFEST" "${output}"
    assert_matches "Smelterl executable: ${artefact_dir}/tools/smelterl-" "${output}"
    assert_matches "Generated SDK artefact: ${artefact_dir}/sdk/sdk-demo_product-" "${output}"
}

test_build_sdk_command_debug_logs_use_relative_paths_within_cwd() {
    local temp_dir workspace build_root artefact_dir output status
    temp_dir="$(harness_make_temp_dir "build-sdk-debug-relative-paths")"
    workspace="${temp_dir}/workspace"
    mkdir -p "${workspace}"
    build_root="${workspace}/build"
    artefact_dir="${workspace}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(
        cd "${workspace}" &&
            ALLOY_DEBUG=2 \
            ALLOY_BUILD_DIR="${build_root}" \
            ALLOY_ARTEFACT_DIR="${artefact_dir}" \
            "${BUILD_SDK_COMMAND}" demo_product 2>&1
    )"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "DEBUG: SDK build workspace root: build/sdk/demo_product" "${output}"
    assert_matches "INFO: Staging nugget repositories into build/sdk/demo_product/motherlode\\." "${output}"
    assert_matches "DEBUG: Stage target for builtin: build/sdk/demo_product/motherlode/builtin" "${output}"
    assert_matches "DEBUG: Smelterl executable path: artefacts/tools/smelterl-" "${output}"
    assert_matches "DEBUG: Plan term output: build/sdk/demo_product/plan/build_plan.term" "${output}"
    assert_matches "DEBUG: Plan environment output: build/sdk/demo_product/plan/build_plan.env" "${output}"
}

test_build_sdk_command_invokes_smelterl_plan_with_expected_artifacts() {
    local temp_dir build_root artefact_dir smelterl_log output status
    temp_dir="$(harness_make_temp_dir "build-sdk-plan")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    smelterl_log="${temp_dir}/smelterl.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(FAKE_SMELTERL_LOG="${smelterl_log}" \
        ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/plan/build_plan.term' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/plan/build_plan.env' ]]"
    assert_status_code 0 "grep -Fq -- 'plan --product demo_product' '${smelterl_log}'"
    assert_status_code 0 "grep -Fq -- '--motherlode ${build_root}/sdk/demo_product/motherlode' '${smelterl_log}'"
    assert_status_code 0 "grep -Fq -- '--output-plan ${build_root}/sdk/demo_product/plan/build_plan.term' '${smelterl_log}'"
    assert_status_code 0 "grep -Fq -- '--output-plan-env ${build_root}/sdk/demo_product/plan/build_plan.env' '${smelterl_log}'"
    assert_status_code 0 "grep -Fq -- 'ALLOY_SDK_DIR=\${ALLOY_SDK_DIR}' '${smelterl_log}'"
    assert_status_code 0 "grep -Fq -- 'ALLOY_FIRMWARE_WORK_DIR=\${ALLOY_FIRMWARE_WORK_DIR}' '${smelterl_log}'"
    assert_status_code 1 "grep -Fq -- 'ALLOY_MOTHERLODE=' '${smelterl_log}'"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
}

test_build_sdk_command_generates_auxiliaries_before_main_from_shared_plan() {
    local temp_dir build_root artefact_dir smelterl_log output status
    local plan_path aux_beta_line aux_alpha_line main_line
    temp_dir="$(harness_make_temp_dir "build-sdk-generate-loop")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    smelterl_log="${temp_dir}/smelterl.log"
    plan_path="${build_root}/sdk/demo_product/plan/build_plan.term"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(FAKE_SMELTERL_LOG="${smelterl_log}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta aux_alpha" \
        ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets/aux_beta/workspace' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/targets/aux_alpha/workspace' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/aux_beta/br2_external/configs/aux_beta_defconfig' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/aux_alpha/br2_external/configs/aux_alpha_defconfig' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/targets/main/br2_external/configs/main_defconfig' ]]"
    assert_status_code 0 "[[ -L '${build_root}/sdk/demo_product/targets/aux_beta/br2_external/board/aux_beta/scripts/post-build.sh' ]]"
    assert_status_code 0 "[[ -L '${build_root}/sdk/demo_product/targets/aux_alpha/br2_external/board/aux_alpha/scripts/post-image.sh' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${build_root}/sdk/demo_product/targets/aux_beta/br2_external/board/aux_beta/scripts/alloy_context.sh')\" == '../../../../alloy_context.sh' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${build_root}/sdk/demo_product/targets/aux_alpha/br2_external/board/aux_alpha/scripts/post-fakeroot.sh')\" == '$(harness_repo_root)/scripts/buildroot/script_hook.sh' ]]"
    assert_matches "Generated targets: aux_beta aux_alpha main" "${output}"

    aux_beta_line="$(grep -nF -- "generate --plan ${plan_path} --auxiliary aux_beta" "${smelterl_log}" | cut -d: -f1)"
    aux_alpha_line="$(grep -nF -- "generate --plan ${plan_path} --auxiliary aux_alpha" "${smelterl_log}" | cut -d: -f1)"
    main_line="$(grep -nF -- "generate --plan ${plan_path} --output-external-desc ${build_root}/sdk/demo_product/targets/main/br2_external/external.desc" "${smelterl_log}" | cut -d: -f1)"

    assert_status_code 0 "[[ -n '${aux_beta_line}' ]]"
    assert_status_code 0 "[[ -n '${aux_alpha_line}' ]]"
    assert_status_code 0 "[[ -n '${main_line}' ]]"
    assert_status_code 0 "[[ ${aux_beta_line} -lt ${aux_alpha_line} ]]"
    assert_status_code 0 "[[ ${aux_alpha_line} -lt ${main_line} ]]"
}

test_build_sdk_command_runs_pre_build_hooks_once_per_nugget_across_targets() {
    local temp_dir build_root artefact_dir pre_build_log output status
    local shared_count target_count shared_line aux_beta_target_line aux_alpha_target_line main_target_line
    temp_dir="$(harness_make_temp_dir "build-sdk-pre-build-dedup")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    pre_build_log="${temp_dir}/pre-build.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(FAKE_SMELTERL_EMIT_PRE_BUILD=true \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta aux_alpha" \
        FAKE_PRE_BUILD_LOG="${pre_build_log}" \
        ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -s '${pre_build_log}' ]]"
    shared_count="$(grep -c '^shared:' "${pre_build_log}")"
    target_count="$(grep -c '^target:' "${pre_build_log}")"
    assert_equals "1" "${shared_count}"
    assert_equals "3" "${target_count}"
    assert_status_code 0 "grep -Fxq 'shared:aux_beta:shared' '${pre_build_log}'"
    assert_status_code 0 "grep -Fxq 'target:aux_beta:target_aux_beta' '${pre_build_log}'"
    assert_status_code 0 "grep -Fxq 'target:aux_alpha:target_aux_alpha' '${pre_build_log}'"
    assert_status_code 0 "grep -Fxq 'target:main:target_main' '${pre_build_log}'"

    shared_line="$(grep -n '^shared:aux_beta:shared$' "${pre_build_log}" | cut -d: -f1)"
    aux_beta_target_line="$(grep -n '^target:aux_beta:target_aux_beta$' "${pre_build_log}" | cut -d: -f1)"
    aux_alpha_target_line="$(grep -n '^target:aux_alpha:target_aux_alpha$' "${pre_build_log}" | cut -d: -f1)"
    main_target_line="$(grep -n '^target:main:target_main$' "${pre_build_log}" | cut -d: -f1)"
    assert_status_code 0 "[[ ${shared_line} -lt ${aux_beta_target_line} ]]"
    assert_status_code 0 "[[ ${aux_beta_target_line} -lt ${aux_alpha_target_line} ]]"
    assert_status_code 0 "[[ ${aux_alpha_target_line} -lt ${main_target_line} ]]"
    assert_matches "Generated targets: aux_beta aux_alpha main" "${output}"
}

test_build_sdk_command_runs_buildroot_make_and_legal_info_per_target_with_isolated_context() {
    local temp_dir build_root artefact_dir make_log brmake_log smelterl_log output status
    local aux_beta_defconfig_line aux_beta_build_line aux_alpha_defconfig_line aux_alpha_build_line main_defconfig_line main_build_line
    local aux_beta_legal_line aux_alpha_legal_line main_legal_line consolidation_line
    temp_dir="$(harness_make_temp_dir "build-sdk-buildroot-loop")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    make_log="${temp_dir}/make.log"
    brmake_log="${temp_dir}/brmake.log"
    smelterl_log="${temp_dir}/smelterl.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta aux_alpha" \
        FAKE_SMELTERL_LOG="${smelterl_log}" \
        FAKE_BRMAKE_LOG="${brmake_log}" \
        FAKE_MAKE_LOG="${make_log}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -s '${make_log}' ]]"
    assert_status_code 0 "[[ -s '${brmake_log}' ]]"
    assert_status_code 0 "grep -Fq 'defconfig goal=aux_beta_defconfig O=${build_root}/sdk/demo_product/targets/aux_beta/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_beta/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'build goal=all O=${build_root}/sdk/demo_product/targets/aux_beta/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_beta/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'defconfig goal=aux_alpha_defconfig O=${build_root}/sdk/demo_product/targets/aux_alpha/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_alpha/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'build goal=all O=${build_root}/sdk/demo_product/targets/aux_alpha/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_alpha/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'defconfig goal=main_defconfig O=${build_root}/sdk/demo_product/targets/main/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/main/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'build goal=all O=${build_root}/sdk/demo_product/targets/main/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/main/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'custom goal=legal-info O=${build_root}/sdk/demo_product/targets/aux_beta/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_beta/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'custom goal=legal-info O=${build_root}/sdk/demo_product/targets/aux_alpha/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_alpha/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'custom goal=legal-info O=${build_root}/sdk/demo_product/targets/main/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/main/br2_external' '${make_log}'"
    assert_status_code 0 "grep -Fq 'generate --plan ${build_root}/sdk/demo_product/plan/build_plan.term --output-manifest ${build_root}/sdk/demo_product/staging/ALLOY_SDK_MANIFEST --export-legal legal-info --buildroot-legal ${build_root}/sdk/demo_product/targets/aux_beta/workspace/legal-info --buildroot-legal ${build_root}/sdk/demo_product/targets/aux_alpha/workspace/legal-info --buildroot-legal ${build_root}/sdk/demo_product/targets/main/workspace/legal-info' '${smelterl_log}'"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/staging/ALLOY_SDK_MANIFEST' ]]"
    assert_status_code 0 "[[ -s '${build_root}/sdk/demo_product/staging/legal-info/README' ]]"

    aux_beta_defconfig_line="$(grep -nF 'defconfig goal=aux_beta_defconfig' "${make_log}" | cut -d: -f1)"
    aux_beta_build_line="$(grep -nF 'build goal=all O='"${build_root}/sdk/demo_product/targets/aux_beta/workspace" "${make_log}" | cut -d: -f1)"
    aux_alpha_defconfig_line="$(grep -nF 'defconfig goal=aux_alpha_defconfig' "${make_log}" | cut -d: -f1)"
    aux_alpha_build_line="$(grep -nF 'build goal=all O='"${build_root}/sdk/demo_product/targets/aux_alpha/workspace" "${make_log}" | cut -d: -f1)"
    main_defconfig_line="$(grep -nF 'defconfig goal=main_defconfig' "${make_log}" | cut -d: -f1)"
    main_build_line="$(grep -nF 'build goal=all O='"${build_root}/sdk/demo_product/targets/main/workspace" "${make_log}" | cut -d: -f1)"
    aux_beta_legal_line="$(grep -nF 'custom goal=legal-info O='"${build_root}/sdk/demo_product/targets/aux_beta/workspace" "${make_log}" | cut -d: -f1)"
    aux_alpha_legal_line="$(grep -nF 'custom goal=legal-info O='"${build_root}/sdk/demo_product/targets/aux_alpha/workspace" "${make_log}" | cut -d: -f1)"
    main_legal_line="$(grep -nF 'custom goal=legal-info O='"${build_root}/sdk/demo_product/targets/main/workspace" "${make_log}" | cut -d: -f1)"
    consolidation_line="$(grep -nF 'generate --plan '"${build_root}/sdk/demo_product/plan/build_plan.term"' --output-manifest '"${build_root}/sdk/demo_product/staging/ALLOY_SDK_MANIFEST" "${smelterl_log}" | cut -d: -f1)"

    assert_status_code 0 "[[ ${aux_beta_defconfig_line} -lt ${aux_beta_build_line} ]]"
    assert_status_code 0 "[[ ${aux_beta_build_line} -lt ${aux_alpha_defconfig_line} ]]"
    assert_status_code 0 "[[ ${aux_alpha_defconfig_line} -lt ${aux_alpha_build_line} ]]"
    assert_status_code 0 "[[ ${aux_alpha_build_line} -lt ${main_defconfig_line} ]]"
    assert_status_code 0 "[[ ${main_defconfig_line} -lt ${main_build_line} ]]"
    assert_status_code 0 "[[ ${main_build_line} -lt ${aux_beta_legal_line} ]]"
    assert_status_code 0 "[[ ${aux_beta_legal_line} -lt ${aux_alpha_legal_line} ]]"
    assert_status_code 0 "[[ ${aux_alpha_legal_line} -lt ${main_legal_line} ]]"
    assert_status_code 0 "[[ -n '${consolidation_line}' ]]"
    assert_matches "Built targets: aux_beta aux_alpha main" "${output}"
}

test_build_sdk_command_removes_stale_staging_legal_info_before_main_consolidation() {
    local temp_dir build_root artefact_dir stale_dir stale_manifest output status
    temp_dir="$(harness_make_temp_dir "build-sdk-stale-legal-info")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    stale_dir="${build_root}/sdk/demo_product/staging/legal-info"
    stale_manifest="${build_root}/sdk/demo_product/staging/ALLOY_SDK_MANIFEST"
    mkdir -p "${stale_dir}"
    printf 'stale\n' > "${stale_dir}/README"
    printf '{stale_manifest, []}.\n' > "${stale_manifest}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -s '${stale_dir}/README' ]]"
    assert_status_code 0 "grep -Fxq 'merged legal info' '${stale_dir}/README'"
    assert_status_code 1 "grep -Fxq 'stale' '${stale_dir}/README'"
    assert_status_code 0 "[[ -s '${stale_manifest}' ]]"
    assert_status_code 1 "grep -Fq 'stale_manifest' '${stale_manifest}'"
}

test_build_sdk_command_collects_and_stages_auxiliary_sdk_outputs() {
    local temp_dir build_root artefact_dir output status main_context
    temp_dir="$(harness_make_temp_dir "build-sdk-aux-outputs-valid")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta aux_alpha" \
        FAKE_SMELTERL_AUX_OUTPUTS="aux_beta:initramfs,bundle;aux_alpha:debug" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Staged auxiliary sdk outputs: 3" "${output}"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/staging/auxiliary/aux_beta/outputs/initramfs/aux_beta-initramfs.bin' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/staging/auxiliary/aux_beta/outputs/bundle/aux_beta-bundle.bin' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/staging/auxiliary/aux_alpha/outputs/debug/aux_alpha-debug.bin' ]]"

    main_context="${build_root}/sdk/demo_product/targets/main/alloy_context.sh"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_AUX_BETA_INITRAMFS=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_AUX_BETA_BUNDLE=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_AUX_ALPHA_DEBUG=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_INITRAMFS=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_BUNDLE=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_DEBUG=' '${main_context}'"
}

test_build_sdk_command_fails_when_declared_auxiliary_sdk_output_is_missing() {
    local temp_dir build_root artefact_dir output status
    temp_dir="$(harness_make_temp_dir "build-sdk-aux-outputs-missing")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta" \
        FAKE_SMELTERL_AUX_OUTPUTS="aux_beta:initramfs" \
        FAKE_SMELTERL_REGISTER_AUX_OUTPUTS=false \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Missing sdk output registry for auxiliary target 'aux_beta'" "${output}"
}

test_build_sdk_command_skips_global_alias_for_duplicate_auxiliary_sdk_output_ids() {
    local temp_dir build_root artefact_dir output status main_context
    temp_dir="$(harness_make_temp_dir "build-sdk-aux-outputs-duplicate")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta aux_alpha" \
        FAKE_SMELTERL_AUX_OUTPUTS="aux_beta:initramfs;aux_alpha:initramfs" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    main_context="${build_root}/sdk/demo_product/targets/main/alloy_context.sh"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_AUX_BETA_INITRAMFS=' '${main_context}'"
    assert_status_code 0 "grep -Fq 'ALLOY_SDK_OUTPUT_AUX_ALPHA_INITRAMFS=' '${main_context}'"
    assert_status_code 1 "grep -Fq 'ALLOY_SDK_OUTPUT_INITRAMFS=' '${main_context}'"
}

test_build_sdk_command_make_alloy_helper_reuses_target_context() {
    local temp_dir build_root artefact_dir make_log helper_path output status
    temp_dir="$(harness_make_temp_dir "build-sdk-make-alloy-helper")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    make_log="${temp_dir}/make.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_SMELTERL_AUXILIARY_IDS="aux_beta" \
        FAKE_MAKE_LOG="${make_log}" \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    helper_path="${build_root}/sdk/demo_product/targets/aux_beta/workspace/make_alloy"
    assert_status_code 0 "[[ -x '${helper_path}' ]]"

    : > "${make_log}"
    FAKE_MAKE_LOG="${make_log}" "${helper_path}" menuconfig >/dev/null 2>&1

    assert_status_code 0 "grep -Fq 'custom goal=menuconfig O=${build_root}/sdk/demo_product/targets/aux_beta/workspace BR2_EXTERNAL=${build_root}/sdk/demo_product/targets/aux_beta/br2_external' '${make_log}'"
}

test_build_sdk_command_packs_with_absolute_staging_symlink_target() {
    local temp_dir build_root artefact_dir output status packed_sdk
    temp_dir="$(harness_make_temp_dir "build-sdk-pack-staging-symlink")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_MAKE_STAGING_ABSOLUTE_SYMLINK=true \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    packed_sdk="${build_root}/sdk/demo_product/staging"
    assert_status_code 0 "[[ -L '${packed_sdk}/staging' ]]"
    assert_status_code 0 "[[ -d '${packed_sdk}/host' ]]"
}

test_build_sdk_command_stages_mixed_sources_with_conflict_safe_names() {
    local temp_dir build_root artefact_dir env_source cli_source remote_repo output status
    temp_dir="$(harness_make_temp_dir "build-sdk-stage")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    env_source="${temp_dir}/env/shared"
    cli_source="${temp_dir}/cli/shared"
    build_sdk_test_write_registry "${env_source}" env_feature
    build_sdk_test_write_registry "${cli_source}" cli_feature
    printf 'env\n' > "${env_source}/source-marker.txt"
    printf 'cli\n' > "${cli_source}/source-marker.txt"
    build_sdk_test_make_remote_nugget_repo "${temp_dir}" remote_nuggets remote_repo

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        ALLOY_NUGGET_PATH="${env_source}" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n "${cli_source}" \
        -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/builtin/.nuggets' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/shared/source-marker.txt' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/shared_2/source-marker.txt' ]]"
    assert_status_code 0 "[[ -f '${build_root}/sdk/demo_product/motherlode/remote_nuggets/remote-marker.txt' ]]"
    assert_status_code 0 "[[ -d '${build_root}/sdk/demo_product/motherlode/remote_nuggets/.git' ]]"
    assert_matches "Staged nugget repositories: 4" "${output}"
}

test_build_sdk_command_debug_level_one_reports_staging_progress() {
    local temp_dir build_root artefact_dir local_source remote_repo brmake_log output status
    temp_dir="$(harness_make_temp_dir "build-sdk-debug-one")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    brmake_log="${temp_dir}/brmake.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    local_source="${temp_dir}/local_nuggets"
    build_sdk_test_write_registry "${local_source}" local_feature
    build_sdk_test_make_remote_nugget_repo "${temp_dir}" remote_nuggets remote_repo

    output="$(ALLOY_DEBUG=1 ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        FAKE_BRMAKE_LOG="${brmake_log}" \
        "${BUILD_SDK_COMMAND}" demo_product \
        -n "${local_source}" \
        -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "INFO: Staging nugget repositories into" "${output}"
    assert_matches "INFO: Staging builtin nugget repository as 'builtin'" "${output}"
    assert_matches "INFO: Staging local nugget repository .* as 'local_nuggets'" "${output}"
    assert_matches "INFO: Staging VCS nugget repository as 'remote_nuggets' \\(ref 'main'\\)" "${output}"
    assert_matches "INFO: Nugget staging complete: 3 repositories staged" "${output}"
    assert_matches "INFO: Using cached smelterl executable ${artefact_dir}/tools/smelterl-" "${output}"
    assert_status_code 1 "[[ -s '${brmake_log}' ]]"
    assert_status_code 1 "printf '%s\n' '${output}' | grep -Fq 'pre_build summary:'"
}

test_build_sdk_command_debug_level_two_reports_staging_targets() {
    local temp_dir build_root artefact_dir local_source output status
    temp_dir="$(harness_make_temp_dir "build-sdk-debug-two")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    local_source="${temp_dir}/local_nuggets"
    build_sdk_test_write_registry "${local_source}" local_feature

    output="$(ALLOY_DEBUG=2 ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "${local_source}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "DEBUG: SDK build workspace root: ${build_root}/sdk/demo_product" "${output}"
    assert_matches "DEBUG: Stage target for builtin: ${build_root}/sdk/demo_product/motherlode/builtin" "${output}"
    assert_matches "DEBUG: Stage target for local_nuggets: ${build_root}/sdk/demo_product/motherlode/local_nuggets" "${output}"
    assert_matches "DEBUG: Smelterl executable path: ${artefact_dir}/tools/smelterl-" "${output}"
    assert_matches "DEBUG: pre_build summary: ran=0, skipped=0, missing=0" "${output}"
}

test_build_sdk_command_rejects_missing_local_nugget_source() {
    local temp_dir build_root output status
    temp_dir="$(harness_make_temp_dir "build-sdk-missing-source")"
    build_root="${temp_dir}/build"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "${temp_dir}/missing" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Local nugget source does not exist" "${output}"
}

test_build_sdk_command_rejects_dirty_local_vcs_source_by_default() {
    local temp_dir build_root local_source git_home output status
    temp_dir="$(harness_make_temp_dir "build-sdk-dirty-local")"
    build_root="${temp_dir}/build"
    local_source="${temp_dir}/local_repo"
    git_home="${temp_dir}/git-home"
    mkdir -p "${git_home}/xdg"

    build_sdk_test_git "${git_home}" init -b main "${local_source}" >/dev/null 2>&1
    build_sdk_test_git "${git_home}" -C "${local_source}" config user.name "Alloy Tests"
    build_sdk_test_git "${git_home}" -C "${local_source}" config user.email "alloy-tests@example.com"
    build_sdk_test_write_registry "${local_source}" local_feature
    build_sdk_test_git "${git_home}" -C "${local_source}" add .
    build_sdk_test_git "${git_home}" -C "${local_source}" commit -m "initial" >/dev/null 2>&1
    printf 'dirty\n' >> "${local_source}/local_feature/.nugget"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "${local_source}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Local nugget source is dirty" "${output}"
}

test_build_sdk_command_allows_dirty_existing_vcs_stage_only_when_requested() {
    local temp_dir build_root artefact_dir remote_repo staged_repo output status
    temp_dir="$(harness_make_temp_dir "build-sdk-dirty-vcs")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    build_sdk_test_make_remote_nugget_repo "${temp_dir}" remote_nuggets remote_repo

    ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "git+file://${remote_repo}#main" >/dev/null
    staged_repo="${build_root}/sdk/demo_product/motherlode/remote_nuggets"
    printf 'dirty\n' >> "${staged_repo}/remote-marker.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?
    assert_equals "2" "${status}"
    assert_matches "Git checkout is dirty" "${output}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product --allow-dirty \
        -n "git+file://${remote_repo}#main" 2>&1)"
    status=$?
    assert_equals "0" "${status}"
    assert_matches "Dirty VCS checkouts are allowed" "${output}"
}

test_build_sdk_command_clean_removes_existing_workspace() {
    local temp_dir build_root artefact_dir workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'stale\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product -c 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 1 "[[ -e '${workspace}/stale.txt' ]]"
    assert_status_code 0 "[[ -d '${workspace}/plan' ]]"
    assert_matches "Initialized SDK build workspace for demo_product" "${output}"
}

test_build_sdk_command_short_c_with_value_is_rejected_as_extra_positional() {
    local temp_dir build_root workspace output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package")"
    build_root="${temp_dir}/build"
    workspace="${build_root}/sdk/demo_product"
    mkdir -p "${workspace}"
    printf 'keep\n' > "${workspace}/stale.txt"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        "${BUILD_SDK_COMMAND}" demo_product -c busybox 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_status_code 0 "[[ -e '${workspace}/stale.txt' ]]"
    assert_matches "Unexpected positional arguments: busybox" "${output}"
}

test_build_sdk_command_long_clean_package_is_supported() {
    local temp_dir build_root artefact_dir output status
    temp_dir="$(harness_make_temp_dir "build-sdk-clean-package-long")"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}"

    output="$(ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${BUILD_SDK_COMMAND}" demo_product --clean-package busybox 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Queued clean-package requests: busybox" "${output}"
}

test_build_sdk_command_uses_cached_smelterl_without_rebar3() {
    local temp_dir root_dir command_path build_root artefact_dir fake_bin output status
    temp_dir="$(harness_make_temp_dir "build-sdk-smelterl-cached")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    fake_bin="${temp_dir}/bin"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}" "9.8.7"
    mkdir -p "${fake_bin}"
    printf '#!/usr/bin/env bash\nexit 88\n' > "${fake_bin}/rebar3"
    chmod +x "${fake_bin}/rebar3"

    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR \
        PATH="${fake_bin}:${PATH}" ALLOY_BUILD_DIR="${build_root}" \
        ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${command_path}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ \"\$(readlink '${artefact_dir}/tools/smelterl')\" == 'smelterl-9.8.7' ]]"
    assert_matches "Smelterl executable: ${artefact_dir}/tools/smelterl-9.8.7" "${output}"
}

test_build_sdk_command_builds_missing_smelterl_artifact() {
    local temp_dir root_dir command_path build_root artefact_dir fake_bin rebar_log output status
    temp_dir="$(harness_make_temp_dir "build-sdk-smelterl-build")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    fake_bin="${temp_dir}/bin"
    rebar_log="${temp_dir}/rebar.log"
    build_sdk_test_write_fake_rebar3 "${fake_bin}"

    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR \
        PATH="${fake_bin}:${PATH}" FAKE_REBAR3_LOG="${rebar_log}" \
        FAKE_REBAR3_OUTPUT="built smelterl" \
        ALLOY_BUILD_DIR="${build_root}" ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${command_path}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "[[ -x '${artefact_dir}/tools/smelterl-9.8.7' ]]"
    assert_status_code 0 "[[ \"\$(readlink '${artefact_dir}/tools/smelterl')\" == 'smelterl-9.8.7' ]]"
    assert_status_code 0 "grep -Fxq 'escriptize' '${rebar_log}'"
    assert_matches "Smelterl executable: ${artefact_dir}/tools/smelterl-9.8.7" "${output}"
    assert_status_code 0 "grep -Fxq 'built smelterl' '${artefact_dir}/tools/smelterl-9.8.7'"
}

test_build_sdk_command_dev_mode_rebuilds_smelterl_artifact() {
    local temp_dir root_dir command_path build_root artefact_dir fake_bin rebar_log output status
    temp_dir="$(harness_make_temp_dir "build-sdk-smelterl-dev")"
    root_dir="$(build_sdk_test_make_fixture "${temp_dir}")"
    command_path="${root_dir}/scripts/commands/build-sdk.sh"
    build_root="${temp_dir}/build"
    artefact_dir="${temp_dir}/artefacts"
    fake_bin="${temp_dir}/bin"
    rebar_log="${temp_dir}/rebar.log"
    build_sdk_test_prepare_cached_smelterl "${artefact_dir}" "9.8.7"
    build_sdk_test_write_fake_rebar3 "${fake_bin}"

    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR \
        PATH="${fake_bin}:${PATH}" FAKE_REBAR3_LOG="${rebar_log}" \
        FAKE_REBAR3_OUTPUT="rebuilt smelterl" \
        ALLOY_DEV_MODE=true ALLOY_BUILD_DIR="${build_root}" ALLOY_ARTEFACT_DIR="${artefact_dir}" \
        "${command_path}" demo_product 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_status_code 0 "grep -Fxq 'clean' '${rebar_log}'"
    assert_status_code 0 "grep -Fxq 'escriptize' '${rebar_log}'"
    assert_status_code 0 "[[ \"\$(readlink '${artefact_dir}/tools/smelterl')\" == 'smelterl-9.8.7' ]]"
    assert_status_code 0 "grep -Fxq 'rebuilt smelterl' '${artefact_dir}/tools/smelterl-9.8.7'"
    assert_matches "Smelterl executable: ${artefact_dir}/tools/smelterl-9.8.7" "${output}"
}

test_build_sdk_command_rejects_invalid_allow_dirty_env_value() {
    local output status

    output="$(ALLOY_ALLOW_DIRTY=maybe \
        "${BUILD_SDK_COMMAND}" demo_product 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "ALLOY_ALLOW_DIRTY must be true or false" "${output}"
}
