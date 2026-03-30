#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

SECURITY_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/security_utils.sh"
# shellcheck source=scripts/utils/security_utils.sh
source "${SECURITY_UTILS_SCRIPT}"

security_utils_test_reset_env() {
    unset ALLOY_SECURITY_PACK || true
    unset SECPACK_TEST_CAPABILITIES_MODE || true
    unset SECPACK_TEST_CAPABILITIES_OUTPUT || true
    unset SECPACK_TEST_INFO_MODE || true
    unset SECPACK_TEST_INFO_OUTPUT || true
    unset SECPACK_TEST_ENV_MODE || true
    unset SECPACK_TEST_ENV_OUTPUT || true
    unset SECPACK_TEST_OVERLAY_MODE || true
    unset SECPACK_TEST_OVERLAY_MARKER || true
}

security_utils_test_make_secpack() {
    local temp_dir="$1"
    local pack_kind="${2:-file}"
    local pack_path script_path

    if [[ "${pack_kind}" == "directory" ]]; then
        pack_path="${temp_dir}/secpack-dir"
        script_path="${pack_path}/secpack"
        mkdir -p "${pack_path}"
    else
        pack_path="${temp_dir}/secpack-file"
        script_path="${pack_path}"
    fi

    cat > "${script_path}" <<'EOF'
#!/usr/bin/env bash
command_name="${1:-}"
shift || true

emit_mode_output() {
    local mode="$1"
    local output="${2-}"
    case "${mode}" in
        ok)
            printf '%b' "${output}"
            ;;
        empty)
            ;;
        unsupported)
            printf '%s\n' "unsupported" >&2
            exit 2
            ;;
        fail)
            printf '%s\n' "failed" >&2
            exit 1
            ;;
        *)
            printf 'unexpected mode: %s\n' "${mode}" >&2
            exit 1
            ;;
    esac
}

case "${command_name}" in
    capabilities)
        emit_mode_output "${SECPACK_TEST_CAPABILITIES_MODE:-ok}" "${SECPACK_TEST_CAPABILITIES_OUTPUT:-env\\n}"
        ;;
    info)
        emit_mode_output "${SECPACK_TEST_INFO_MODE:-ok}" "${SECPACK_TEST_INFO_OUTPUT:-name=test-pack\\n}"
        ;;
    env)
        emit_mode_output "${SECPACK_TEST_ENV_MODE:-ok}" "${SECPACK_TEST_ENV_OUTPUT:-signing_algorithm=hab4\\n}"
        ;;
    generate-overlay)
        output_dir="$1"
        case "${SECPACK_TEST_OVERLAY_MODE:-ok}" in
            ok)
                mkdir -p "${output_dir}/etc/ssl"
                printf '%s\n' "${SECPACK_TEST_OVERLAY_MARKER:-device-cert}" > "${output_dir}/etc/ssl/device.pem"
                ;;
            unsupported)
                printf '%s\n' "overlay unsupported" >&2
                exit 2
                ;;
            fail)
                printf '%s\n' "overlay failed" >&2
                exit 1
                ;;
            *)
                printf 'unexpected overlay mode: %s\n' "${SECPACK_TEST_OVERLAY_MODE}" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        printf 'unknown command: %s\n' "${command_name}" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "${script_path}"

    printf '%s\n' "${pack_path}"
}

test_security_utils_resolve_pack_accepts_file_entrypoint() {
    security_utils_test_reset_env
    local temp_dir pack_path resolved_path
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"

    resolved_path="$(security_resolve_pack "${pack_path}")"

    assert_equals "$(realpath "${pack_path}")" "${resolved_path}"
}

test_security_utils_resolve_pack_accepts_directory_entrypoint() {
    security_utils_test_reset_env
    local temp_dir pack_dir resolved_path
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_dir="$(security_utils_test_make_secpack "${temp_dir}" directory)"

    resolved_path="$(security_resolve_pack "${pack_dir}")"

    assert_equals "$(realpath "${pack_dir}/secpack")" "${resolved_path}"
}

test_security_utils_resolve_pack_rejects_bare_command_names() {
    security_utils_test_reset_env
    local output status
    output="$({ security_resolve_pack "secpack"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Security pack not found: secpack" "${output}"
}

test_security_utils_resolve_pack_rejects_missing_directory_entrypoint() {
    security_utils_test_reset_env
    local temp_dir output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    mkdir -p "${temp_dir}/pack"

    output="$({ security_resolve_pack "${temp_dir}/pack"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "does not contain a 'secpack' executable at its root" "${output}"
}

test_security_utils_resolve_pack_rejects_non_executable_file() {
    security_utils_test_reset_env
    local temp_dir pack_path output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="${temp_dir}/secpack-file"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${pack_path}"

    output="$({ security_resolve_pack "${pack_path}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Security pack is not executable: ${pack_path}" "${output}"
}

test_security_utils_resolve_pack_rejects_failed_capabilities_probe() {
    security_utils_test_reset_env
    local temp_dir pack_path output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    export SECPACK_TEST_CAPABILITIES_MODE="fail"

    output="$({ security_resolve_pack "${pack_path}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "does not appear to be a valid security pack" "${output}"
}

test_security_utils_resolve_pack_rejects_empty_capabilities_output() {
    security_utils_test_reset_env
    local temp_dir pack_path output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    export SECPACK_TEST_CAPABILITIES_MODE="empty"

    output="$({ security_resolve_pack "${pack_path}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "does not appear to be a valid security pack" "${output}"
}

test_security_utils_validate_kv_output_accepts_valid_pairs_and_ignores_other_lines() {
    security_utils_test_reset_env
    security_validate_kv_output "info" $'name=pack\nignored-line\nhash=a=b\n\n'
}

test_security_utils_validate_kv_output_rejects_invalid_keys() {
    security_utils_test_reset_env
    local output status
    output="$({ security_validate_kv_output "env" $'Bad-Key=value\n'; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "invalid key 'Bad-Key' in 'env' output" "${output}"
}

test_security_utils_security_info_filters_and_validates_output() {
    security_utils_test_reset_env
    local temp_dir pack_path output
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    export ALLOY_SECURITY_PACK="${pack_path}"
    export SECPACK_TEST_INFO_OUTPUT=$'name=demo\nignored-line\nhash=a=b\n\n'

    output="$(security_info)"

    assert_equals $'name=demo\nhash=a=b' "${output}"
}

test_security_utils_security_export_env_propagates_unsupported_status() {
    security_utils_test_reset_env
    local temp_dir pack_path output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    export ALLOY_SECURITY_PACK="${pack_path}"
    export SECPACK_TEST_ENV_MODE="unsupported"

    output="$({ security_export_env; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "unsupported" "${output}"
}

test_security_utils_security_generate_overlay_runs_pack_command() {
    security_utils_test_reset_env
    local temp_dir pack_path overlay_dir
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    overlay_dir="${temp_dir}/overlay"
    mkdir -p "${overlay_dir}"
    export ALLOY_SECURITY_PACK="${pack_path}"
    export SECPACK_TEST_OVERLAY_MARKER="signed-device-cert"

    security_generate_overlay "${overlay_dir}"

    assert_status_code 0 "test -f '${overlay_dir}/etc/ssl/device.pem'"
    assert_equals "signed-device-cert" "$(cat "${overlay_dir}/etc/ssl/device.pem")"
}

test_security_utils_security_generate_overlay_propagates_unsupported_status() {
    security_utils_test_reset_env
    local temp_dir pack_path overlay_dir output status
    temp_dir="$(harness_make_temp_dir "security-utils")"
    pack_path="$(security_utils_test_make_secpack "${temp_dir}" file)"
    overlay_dir="${temp_dir}/overlay"
    mkdir -p "${overlay_dir}"
    export ALLOY_SECURITY_PACK="${pack_path}"
    export SECPACK_TEST_OVERLAY_MODE="unsupported"

    output="$({ security_generate_overlay "${overlay_dir}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "overlay unsupported" "${output}"
}

test_security_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${SECURITY_UTILS_SCRIPT}\"; source \"${SECURITY_UTILS_SCRIPT}\"; type security_resolve_pack >/dev/null'"
}
