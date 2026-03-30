#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

MANIFEST_TOOL="$(harness_repo_root)/scripts/tools/manifest-tool"

manifest_tool_test_resolve_escript() {
    if [[ -n "${ALLOY_TEST_ESCRIPT:-}" ]] && [[ -x "${ALLOY_TEST_ESCRIPT}" ]]; then
        printf '%s\n' "${ALLOY_TEST_ESCRIPT}"
        return 0
    fi

    local escript_path
    escript_path="$(command -v escript)"

    if [[ "${escript_path}" == *"/.asdf/shims/escript" ]]; then
        local asdf_installs_dir="${HOME}/.asdf/installs/erlang"
        if [[ -d "${asdf_installs_dir}" ]]; then
            local concrete_escript
            concrete_escript="$(find "${asdf_installs_dir}" -mindepth 3 -maxdepth 3 -path '*/bin/escript' | LC_ALL=C sort | tail -n 1)"
            if [[ -n "${concrete_escript}" ]] && [[ -x "${concrete_escript}" ]]; then
                printf '%s\n' "${concrete_escript}"
                return 0
            fi
        fi
    fi

    printf '%s\n' "${escript_path}"
}

manifest_tool_test_run() {
    local escript_bin
    escript_bin="$(manifest_tool_test_resolve_escript)"
    "${escript_bin}" "${MANIFEST_TOOL}" "$@"
}

manifest_tool_test_write_manifest() {
    local file_path="$1"
    local body="$2"
    mkdir -p "$(dirname "${file_path}")"
    cat > "${file_path}" <<EOF
%% coding: utf-8
${body}
EOF
}

test_manifest_tool_validate_root_accepts_sdk_manifest() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]}.' 

    output="$(manifest_tool_test_run validate-root --manifest "${manifest_path}")"

    assert_equals "sdk_manifest" "${output}"
}

test_manifest_tool_validate_root_accepts_project_manifest() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"my_app">>}]}.' 

    output="$(manifest_tool_test_run validate-root --manifest "${manifest_path}")"

    assert_equals "project_manifest" "${output}"
}

test_manifest_tool_validate_root_accepts_firmware_manifest() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [{firmware_variant, plain}]}.' 

    output="$(manifest_tool_test_run validate-root --manifest "${manifest_path}")"

    assert_equals "firmware_manifest" "${output}"
}

test_manifest_tool_validate_root_rejects_unknown_root_tag() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/UNKNOWN_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{unknown_manifest, <<"1.0">>, [{id, demo}]}.' 

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "sdk_manifest, project_manifest, or firmware_manifest" "${output}"
}

test_manifest_tool_validate_root_rejects_non_binary_version() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, "1.0", [{product, demo}]}.' 

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "version must be a binary" "${output}"
}

test_manifest_tool_validate_root_rejects_non_list_fields() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, {id, my_app}}.' 

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "fields must be a list" "${output}"
}

test_manifest_tool_validate_root_rejects_non_tuple_field_entries() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [not_a_tuple]}.' 

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "fields must contain only tuples" "${output}"
}

test_manifest_tool_validate_root_rejects_malformed_term_files() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]'

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "3" "${status}"
    assert_matches "Failed to parse manifest" "${output}"
}

test_manifest_tool_validate_root_rejects_multiple_terms() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    mkdir -p "$(dirname "${manifest_path}")"
    cat > "${manifest_path}" <<'EOF'
%% coding: utf-8
{sdk_manifest, <<"1.0">>, [{product, demo}]}.
{project_manifest, <<"1.0">>, [{id, demo}]}.
EOF

    output="$({ manifest_tool_test_run validate-root --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "3" "${status}"
    assert_matches "expected exactly one Erlang term" "${output}"
}

test_manifest_tool_validate_root_requires_manifest_argument() {
    local output status
    output="$({ manifest_tool_test_run validate-root; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "requires --manifest PATH" "${output}"
}
