#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

SDK_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/sdk_utils.sh"
PREPARE_SDK_COMMAND="$(harness_repo_root)/scripts/commands/prepare-sdk.sh"
# shellcheck source=scripts/utils/sdk_utils.sh
source "${SDK_UTILS_SCRIPT}"

sdk_utils_test_make_sdk_root() {
    local temp_dir="$1"
    local sdk_dir="${temp_dir}/sdk"
    mkdir -p "${sdk_dir}/host" "${sdk_dir}/images" "${sdk_dir}/scripts"
    : > "${sdk_dir}/ALLOY_SDK_MANIFEST"
    printf 'prefix=%s/host\n' "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" > "${sdk_dir}/scripts/tool.env"
    printf 'scripts/tool.env\n' > "${sdk_dir}/.alloy_relocation_manifest"
    printf '%s\n' "${ALLOY_SDK_RELOCATION_PLACEHOLDER}" > "${sdk_dir}/.alloy_sdk_dir"
    printf '%s\n' "${sdk_dir}"
}

sdk_utils_test_make_sdk_command_fixture() {
    local temp_dir="$1"
    local sdk_dir
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    mkdir -p "${sdk_dir}/scripts/utils" "${sdk_dir}/scripts/commands"

    cp "$(harness_repo_root)/scripts/utils/console_utils.sh" "${sdk_dir}/scripts/utils/console_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/debug_utils.sh" "${sdk_dir}/scripts/utils/debug_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/common.sh" "${sdk_dir}/scripts/utils/common.sh"
    cp "$(harness_repo_root)/scripts/utils/file_utils.sh" "${sdk_dir}/scripts/utils/file_utils.sh"
    cp "$(harness_repo_root)/scripts/utils/sdk_utils.sh" "${sdk_dir}/scripts/utils/sdk_utils.sh"
    cp "${PREPARE_SDK_COMMAND}" "${sdk_dir}/scripts/commands/prepare-sdk.sh"
    chmod +x "${sdk_dir}/scripts/commands/prepare-sdk.sh"

    printf '%s\n' "${sdk_dir}"
}

test_sdk_utils_check_sdk_relocation_detects_placeholder_state() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    local output status
    output="$({ check_sdk_relocation "${sdk_dir}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_equals "" "${output}"
}

test_sdk_utils_relocate_sdk_rewrites_placeholder_and_updates_state() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    relocate_sdk "${sdk_dir}"

    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
    assert_status_code 0 "check_sdk_relocation '${sdk_dir}'"
}

test_sdk_utils_relocate_sdk_rewrites_stale_sdk_path() {
    local temp_dir sdk_dir old_root
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    old_root="/opt/grisp/sdk-old"
    printf 'prefix=%s/host\n' "${old_root}" > "${sdk_dir}/scripts/tool.env"
    printf '%s\n' "${old_root}" > "${sdk_dir}/.alloy_sdk_dir"

    relocate_sdk "${sdk_dir}"

    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
}

test_sdk_utils_sanitize_text_paths_writes_manifest_and_placeholder_state() {
    local temp_dir sdk_dir source_host source_images source_motherlode text_file manifest_file
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="${temp_dir}/packed-sdk"
    source_host="${temp_dir}/build/workspace/host"
    source_images="${temp_dir}/build/workspace/images"
    source_motherlode="${temp_dir}/build/motherlode"
    mkdir -p "${sdk_dir}/scripts" "${source_host}" "${source_images}" "${source_motherlode}"

    text_file="${sdk_dir}/scripts/paths.env"
    cat > "${text_file}" <<EOF
HOST=${source_host}/usr/lib
IMAGES=${source_images}/bundle
MOTHERLODE=${source_motherlode}/builtin
EOF

    sdk_utils_sanitize_text_paths "${sdk_dir}" "${source_host}" "${source_images}" "${source_motherlode}"

    manifest_file="${sdk_dir}/.alloy_relocation_manifest"
    assert_status_code 0 "[[ -s '${manifest_file}' ]]"
    assert_status_code 0 "grep -Fxq 'scripts/paths.env' '${manifest_file}'"
    assert_status_code 0 "grep -Fq 'HOST=@@ALLOY_SDK_DIR@@/host/usr/lib' '${text_file}'"
    assert_status_code 0 "grep -Fq 'IMAGES=@@ALLOY_SDK_DIR@@/images/bundle' '${text_file}'"
    assert_status_code 0 "grep -Fq 'MOTHERLODE=@@ALLOY_SDK_DIR@@/motherlode/builtin' '${text_file}'"
    assert_equals "@@ALLOY_SDK_DIR@@" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
}

test_sdk_utils_ensure_sdk_relocated_fails_when_sdk_root_is_not_writable() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"
    chmod 0555 "${sdk_dir}"

    local output status
    output="$({ ensure_sdk_relocated "${sdk_dir}"; } 2>&1)"
    status=$?

    chmod 0755 "${sdk_dir}"

    assert_equals "1" "${status}"
    assert_matches "SDK needs relocation but the SDK directory is not writable" "${output}"
    assert_matches "Run: alloy prepare sdk" "${output}"
}

test_sdk_utils_ensure_sdk_relocated_auto_relocates_writable_sdk() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_root "${temp_dir}")"

    local output
    output="$(ensure_sdk_relocated "${sdk_dir}")"

    assert_matches "Relocating SDK to ${sdk_dir}" "${output}"
    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
}

test_sdk_utils_prepare_sdk_command_relocates_sdk_fixture() {
    local temp_dir sdk_dir command_path
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_command_fixture "${temp_dir}")"
    command_path="${sdk_dir}/scripts/commands/prepare-sdk.sh"

    local output status
    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR "${command_path}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Relocating SDK to ${sdk_dir}" "${output}"
    assert_equals "prefix=${sdk_dir}/host" "$(cat "${sdk_dir}/scripts/tool.env")"
    assert_equals "${sdk_dir}" "$(cat "${sdk_dir}/.alloy_sdk_dir")"
}

test_sdk_utils_prepare_sdk_command_reports_already_relocated_sdk() {
    local temp_dir sdk_dir command_path
    temp_dir="$(harness_make_temp_dir "sdk-utils")"
    sdk_dir="$(sdk_utils_test_make_sdk_command_fixture "${temp_dir}")"
    printf 'prefix=%s/host\n' "${sdk_dir}" > "${sdk_dir}/scripts/tool.env"
    printf '%s\n' "${sdk_dir}" > "${sdk_dir}/.alloy_sdk_dir"
    command_path="${sdk_dir}/scripts/commands/prepare-sdk.sh"

    local output status
    output="$(env -u ALLOY_ROOT -u ALLOY_ROOT_DIR "${command_path}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "SDK is already relocated." "${output}"
}

test_sdk_utils_prepare_sdk_command_rejects_repository_mode() {
    local output status
    output="$("${PREPARE_SDK_COMMAND}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "prepare sdk is only available in sdk mode" "${output}"
}

test_sdk_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${SDK_UTILS_SCRIPT}\"; source \"${SDK_UTILS_SCRIPT}\"; type ensure_sdk_relocated >/dev/null'"
}

sdk_utils_test_make_fake_elf() {
    local file_path="$1"
    mkdir -p "$(dirname "${file_path}")"
    printf '\177ELFtest\n' > "${file_path}"
}

sdk_utils_test_set_fake_rpath() {
    local file_path="$1"
    local rpath_value="$2"
    printf '%s\n' "${rpath_value}" > "${file_path}.rpath"
}

sdk_utils_test_make_fake_patchelf() {
    local fake_dir="$1"
    local log_file="$2"
    mkdir -p "${fake_dir}"
    cat > "${fake_dir}/patchelf" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_PATCHELF_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "${FAKE_PATCHELF_LOG}"
fi

case "${1:-}" in
    --print-rpath)
        file_path="${2:?}"
        if [[ "${FAKE_PATCHELF_FAIL_NON_DYNAMIC:-}" == "true" ]] && [[ "${file_path}" == *.o ]]; then
            echo "${FAKE_PATCHELF_NON_DYNAMIC_ERROR:-patchelf: cannot find section '.dynamic'}" >&2
            exit 1
        fi
        if [[ -f "${file_path}.rpath" ]]; then
            cat "${file_path}.rpath"
        fi
        ;;
    --set-rpath)
        value="${2:?}"
        file_path="${3:?}"
        printf '%s\n' "${value}" > "${file_path}.rpath"
        ;;
    *)
        echo "unexpected fake patchelf invocation: $*" >&2
        exit 31
        ;;
esac
SCRIPT
    chmod +x "${fake_dir}/patchelf"
}

test_sdk_utils_verify_elf_rpaths_accepts_origin_relative_rpaths() {
    local temp_dir sdk_dir fake_bin fake_log elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-valid")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    fake_log="${temp_dir}/patchelf.log"
    mkdir -p "${sdk_dir}/host/bin" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${fake_log}"
    elf_path="${sdk_dir}/host/bin/tool"
    sdk_utils_test_make_fake_elf "${elf_path}"
    sdk_utils_test_set_fake_rpath "${elf_path}" '$ORIGIN/../lib:$ORIGIN'

    output="$(PATH="${fake_bin}:${PATH}" FAKE_PATCHELF_LOG="${fake_log}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_equals '$ORIGIN/../lib:$ORIGIN' "$(cat "${elf_path}.rpath")"
    assert_equals "" "${output}"
}

test_sdk_utils_verify_elf_rpaths_rewrites_absolute_entries() {
    local temp_dir sdk_dir fake_bin fake_log elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-fix")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    fake_log="${temp_dir}/patchelf.log"
    mkdir -p "${sdk_dir}/host/bin" "${sdk_dir}/host/usr/lib" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${fake_log}"
    elf_path="${sdk_dir}/host/bin/tool"
    sdk_utils_test_make_fake_elf "${elf_path}"
    sdk_utils_test_set_fake_rpath "${elf_path}" "${sdk_dir}/host/usr/lib:"'$ORIGIN'

    output="$(ALLOY_DEBUG=1 PATH="${fake_bin}:${PATH}" FAKE_PATCHELF_LOG="${fake_log}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_equals '$ORIGIN/../usr/lib:$ORIGIN' "$(cat "${elf_path}.rpath")"
    assert_matches "Rewriting ELF RPATH: ${elf_path}" "${output}"
    assert_status_code 0 "grep -Fq -- '--set-rpath \$ORIGIN/../usr/lib:\$ORIGIN ${elf_path}' '${fake_log}'"
}

test_sdk_utils_verify_elf_rpaths_rejects_unfixable_entries() {
    local temp_dir sdk_dir fake_bin fake_log elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-bad")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    fake_log="${temp_dir}/patchelf.log"
    mkdir -p "${sdk_dir}/host/bin" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${fake_log}"
    elf_path="${sdk_dir}/host/bin/tool"
    sdk_utils_test_make_fake_elf "${elf_path}"
    sdk_utils_test_set_fake_rpath "${elf_path}" "/opt/vendor/lib"

    output="$(PATH="${fake_bin}:${PATH}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Unfixable ELF RPATH entry for ${elf_path}: /opt/vendor/lib" "${output}"
}

test_sdk_utils_verify_elf_rpaths_skips_non_dynamic_object_files() {
    local temp_dir sdk_dir fake_bin elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-non-dynamic")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    mkdir -p "${sdk_dir}/host/lib/gcc/x86_64-buildroot-linux-gnu/13.3.0" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${temp_dir}/patchelf.log"
    elf_path="${sdk_dir}/host/lib/gcc/x86_64-buildroot-linux-gnu/13.3.0/crtbegin.o"
    sdk_utils_test_make_fake_elf "${elf_path}"

    output="$(ALLOY_DEBUG=2 FAKE_PATCHELF_FAIL_NON_DYNAMIC=true PATH="${fake_bin}:${PATH}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Skipping non-dynamic ELF for RPATH verification: ${elf_path}" "${output}"
}

test_sdk_utils_verify_elf_rpaths_skips_wrong_elf_type_object_files() {
    local temp_dir sdk_dir fake_bin elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-wrong-elf-type")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    mkdir -p "${sdk_dir}/host/lib/gcc/x86_64-buildroot-linux-gnu/13.3.0" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${temp_dir}/patchelf.log"
    elf_path="${sdk_dir}/host/lib/gcc/x86_64-buildroot-linux-gnu/13.3.0/crtbegin.o"
    sdk_utils_test_make_fake_elf "${elf_path}"

    output="$(ALLOY_DEBUG=2 FAKE_PATCHELF_FAIL_NON_DYNAMIC=true FAKE_PATCHELF_NON_DYNAMIC_ERROR='patchelf: wrong ELF type' PATH="${fake_bin}:${PATH}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Skipping non-dynamic ELF for RPATH verification: ${elf_path}" "${output}"
}

test_sdk_utils_verify_elf_rpaths_skips_target_sysroot_elfs() {
    local temp_dir sdk_dir fake_bin elf_path output status
    temp_dir="$(harness_make_temp_dir "sdk-utils-rpath-target-sysroot")"
    sdk_dir="${temp_dir}/sdk"
    fake_bin="${temp_dir}/bin"
    mkdir -p "${sdk_dir}/host/x86_64-buildroot-linux-gnu/sysroot/usr/lib/gconv" "${sdk_dir}/images" "${sdk_dir}/motherlode"
    sdk_utils_test_make_fake_patchelf "${fake_bin}" "${temp_dir}/patchelf.log"
    elf_path="${sdk_dir}/host/x86_64-buildroot-linux-gnu/sysroot/usr/lib/gconv/EUC-CN.so"
    sdk_utils_test_make_fake_elf "${elf_path}"
    sdk_utils_test_set_fake_rpath "${elf_path}" "/usr/lib/gconv"

    output="$(ALLOY_DEBUG=2 PATH="${fake_bin}:${PATH}" verify_elf_rpaths "${sdk_dir}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "Skipping target-sysroot ELF for RPATH verification: ${elf_path}" "${output}"
}
