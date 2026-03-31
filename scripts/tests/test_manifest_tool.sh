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

manifest_tool_test_hash_manifest() {
    local manifest_path="$1"
    manifest_tool_test_run hash --manifest "${manifest_path}"
}

test_manifest_tool_shows_usage_when_no_command_is_provided() {
    local output status
    output="$({ manifest_tool_test_run; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Usage: manifest-tool <command> \\[options\\]" "${output}"
    assert_matches "Commands:" "${output}"
    assert_matches "validate-root" "${output}"
    assert_matches "get" "${output}"
    assert_matches "verify" "${output}"
    assert_matches "hash" "${output}"
}

test_manifest_tool_help_flag_shows_usage() {
    local output
    output="$(manifest_tool_test_run --help)"

    assert_matches "Usage: manifest-tool <command> \\[options\\]" "${output}"
    assert_matches "Read a top-level field" "${output}"
    assert_matches "Merge an SDK manifest" "${output}"
    assert_matches "Verify the embedded integrity hash" "${output}"
    assert_matches "Validate the manifest root tuple shape" "${output}"
    assert_matches "Recompute and update the integrity hash" "${output}"
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

test_manifest_tool_get_reads_binary_field_as_plain_output() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{target_arch, <<"arm-buildroot-linux-gnueabihf">>}]}.' 

    output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field target_arch)"

    assert_equals "arm-buildroot-linux-gnueabihf" "${output}"
}

test_manifest_tool_get_reads_atom_field_as_plain_output() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}]}.' 

    output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field id)"

    assert_equals "my_app" "${output}"
}

test_manifest_tool_get_reads_integer_field_as_plain_output() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{priority, 42}]}.' 

    output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field priority)"

    assert_equals "42" "${output}"
}

test_manifest_tool_get_reads_atom_lists_as_plain_output() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [{variants, [plain, secure, encrypted]}]}.' 

    output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field variants)"

    assert_equals "plain secure encrypted" "${output}"
}

test_manifest_tool_get_reads_nested_fields_in_erlang_format() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [{capabilities, [{variants, [plain, secure]}]}]}.' 

    output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field capabilities --format erlang)"

    assert_equals "[{variants,[plain,secure]}]" "${output}"
}

test_manifest_tool_get_rejects_nested_plain_output() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [{capabilities, [{variants, [plain, secure]}]}]}.' 

    output="$({ manifest_tool_test_run get --manifest "${manifest_path}" --field capabilities; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "use --format erlang" "${output}"
}

test_manifest_tool_get_reports_missing_fields() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}]}.' 

    output="$({ manifest_tool_test_run get --manifest "${manifest_path}" --field target_arch; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "Field not found: target_arch" "${output}"
}

test_manifest_tool_get_rejects_unknown_formats() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]}.' 

    output="$({ manifest_tool_test_run get --manifest "${manifest_path}" --field product --format json; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "unsupported format 'json'" "${output}"
}

test_manifest_tool_get_preserves_parse_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]'

    output="$({ manifest_tool_test_run get --manifest "${manifest_path}" --field product; } 2>&1)"
    status=$?

    assert_equals "3" "${status}"
    assert_matches "Failed to parse manifest" "${output}"
}

test_manifest_tool_get_preserves_structural_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, "1.0", [{id, my_app}]}.' 

    output="$({ manifest_tool_test_run get --manifest "${manifest_path}" --field id; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "version must be a binary" "${output}"
}

test_manifest_tool_hash_writes_known_sdk_manifest_digest() {
    local temp_dir manifest_path integrity_output file_content
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}, {target_arch, <<"arm-buildroot-linux-gnueabihf">>}]}.' 

    manifest_tool_test_run hash --manifest "${manifest_path}"

    integrity_output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field integrity --format erlang)"
    assert_equals "[{digest_algorithm,sha256},{canonical_form,basic_term_canon},{digest,<<\"80b19c71322c5126c11f2757bdf857a03d4328c302b6de5fad8e66d0cd128d64\">>}]" "${integrity_output}"

    file_content="$(cat "${manifest_path}")"
    assert_matches "^%% coding: utf-8" "${file_content}"
}

test_manifest_tool_hash_replaces_existing_integrity_section() {
    local temp_dir manifest_path integrity_output integrity_count
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {integrity, [{digest_algorithm, sha256}, {canonical_form, basic_term_canon}, {digest, <<"stale">>}]}, {name, <<"demo">>}]}.' 

    manifest_tool_test_run hash --manifest "${manifest_path}"

    integrity_output="$(manifest_tool_test_run get --manifest "${manifest_path}" --field integrity --format erlang)"
    assert_equals "[{digest_algorithm,sha256},{canonical_form,basic_term_canon},{digest,<<\"e775a31afd09fac6c3f57b6bacdafc827dba75450b2d13d63227d065588ec1cf\">>}]" "${integrity_output}"

    integrity_count="$(grep -c "{integrity," "${manifest_path}")"
    assert_equals "1" "${integrity_count}"
}

test_manifest_tool_hash_preserves_field_order_in_digest() {
    local temp_dir first_manifest second_manifest first_integrity second_integrity
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    first_manifest="${temp_dir}/ALLOY_PROJECT_MANIFEST.first"
    second_manifest="${temp_dir}/ALLOY_PROJECT_MANIFEST.second"
    manifest_tool_test_write_manifest "${first_manifest}" '{project_manifest, <<"1.0">>, [{name, <<"demo">>}, {id, my_app}]}.' 
    manifest_tool_test_write_manifest "${second_manifest}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"demo">>}]}.' 

    manifest_tool_test_run hash --manifest "${first_manifest}"
    manifest_tool_test_run hash --manifest "${second_manifest}"

    first_integrity="$(manifest_tool_test_run get --manifest "${first_manifest}" --field integrity --format erlang)"
    second_integrity="$(manifest_tool_test_run get --manifest "${second_manifest}" --field integrity --format erlang)"

    assert_equals "[{digest_algorithm,sha256},{canonical_form,basic_term_canon},{digest,<<\"d1cdc6b96cf8d6251333ba686c43f2e60864bfe19577ec2b4c54565c7d4265ee\">>}]" "${first_integrity}"
    assert_equals "[{digest_algorithm,sha256},{canonical_form,basic_term_canon},{digest,<<\"e775a31afd09fac6c3f57b6bacdafc827dba75450b2d13d63227d065588ec1cf\">>}]" "${second_integrity}"
}

test_manifest_tool_hash_requires_manifest_argument() {
    local output status
    output="$({ manifest_tool_test_run hash; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "hash requires --manifest PATH" "${output}"
}

test_manifest_tool_hash_preserves_parse_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]'

    output="$({ manifest_tool_test_run hash --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "3" "${status}"
    assert_matches "Failed to parse manifest" "${output}"
}

test_manifest_tool_hash_preserves_structural_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, "1.0", [{id, my_app}]}.' 

    output="$({ manifest_tool_test_run hash --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "version must be a binary" "${output}"
}

test_manifest_tool_verify_accepts_valid_manifest() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}, {target_arch, <<"arm-buildroot-linux-gnueabihf">>}]}.' 
    manifest_tool_test_hash_manifest "${manifest_path}"

    output="$(manifest_tool_test_run verify --manifest "${manifest_path}")"

    assert_matches "manifest=sdk_manifest" "${output}"
    assert_matches "version=1.0" "${output}"
    assert_matches "integrity=PASS" "${output}"
}

test_manifest_tool_verify_integrity_only_accepts_valid_manifest() {
    local temp_dir manifest_path output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"demo">>}]}.' 
    manifest_tool_test_hash_manifest "${manifest_path}"

    output="$(manifest_tool_test_run verify --manifest "${manifest_path}" --integrity-only)"

    assert_matches "manifest=project_manifest" "${output}"
    assert_matches "version=1.0" "${output}"
    assert_matches "integrity=PASS" "${output}"
}

test_manifest_tool_verify_detects_tampered_manifest() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"demo">>}]}.' 
    manifest_tool_test_hash_manifest "${manifest_path}"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"tampered">>}, {integrity, [{digest_algorithm, sha256}, {canonical_form, basic_term_canon}, {digest, <<"e775a31afd09fac6c3f57b6bacdafc827dba75450b2d13d63227d065588ec1cf">>}]}]}.' 

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "integrity=FAIL" "${output}"
    assert_matches "Digest mismatch" "${output}"
}

test_manifest_tool_verify_rejects_missing_integrity_section() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_FIRMWARE_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{firmware_manifest, <<"1.0">>, [{firmware_variant, plain}]}.' 

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Manifest is missing integrity section" "${output}"
}

test_manifest_tool_verify_rejects_unsupported_digest_algorithm() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"demo">>}, {integrity, [{digest_algorithm, sha3_256}, {canonical_form, basic_term_canon}, {digest, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>}]}]}.' 

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Unsupported digest algorithm: sha3_256" "${output}"
}

test_manifest_tool_verify_rejects_unsupported_canonical_form() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, <<"1.0">>, [{id, my_app}, {name, <<"demo">>}, {integrity, [{digest_algorithm, sha256}, {canonical_form, future_canon}, {digest, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>}]}]}.' 

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "Unsupported canonical form: future_canon" "${output}"
}

test_manifest_tool_verify_requires_manifest_argument() {
    local output status
    output="$({ manifest_tool_test_run verify; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "verify requires --manifest PATH" "${output}"
}

test_manifest_tool_verify_preserves_parse_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_SDK_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{sdk_manifest, <<"1.0">>, [{product, demo}]'

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "3" "${status}"
    assert_matches "Failed to parse manifest" "${output}"
}

test_manifest_tool_verify_preserves_structural_errors() {
    local temp_dir manifest_path output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    manifest_path="${temp_dir}/ALLOY_PROJECT_MANIFEST"
    manifest_tool_test_write_manifest "${manifest_path}" '{project_manifest, "1.0", [{id, my_app}]}.' 

    output="$({ manifest_tool_test_run verify --manifest "${manifest_path}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "version must be a binary" "${output}"
}

test_manifest_tool_merge_builds_firmware_manifest_and_rewrites_repo_conflicts() {
    local temp_dir sdk_manifest project_alpha_manifest project_beta_manifest output_manifest verify_output repositories_output projects_output security_output parameters_output variant_output
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    sdk_manifest="${temp_dir}/sdk/ALLOY_SDK_MANIFEST"
    project_alpha_manifest="${temp_dir}/projects/alpha/ALLOY_PROJECT_MANIFEST"
    project_beta_manifest="${temp_dir}/projects/beta/ALLOY_PROJECT_MANIFEST"
    output_manifest="${temp_dir}/firmware/ALLOY_FIRMWARE_MANIFEST"

    manifest_tool_test_write_manifest "${sdk_manifest}" '{sdk_manifest, <<"1.0">>, [{product, <<"grisp2_vanilla">>}, {product_version, <<"1.0.0">>}, {build_environment, [{smelterl_repository, sdk_repo}]}, {repositories, [{sdk_repo, [{name, <<"sdk_repo">>}, {type, git}, {url, <<"https://example.com/sdk.git">>}, {commit, <<"sdk-commit">>}, {describe, <<"sdk-v1">>}, {dirty, false}]}, {shared_repo, [{name, <<"shared_repo">>}, {type, git}, {url, <<"https://example.com/shared.git">>}, {commit, <<"shared-commit">>}, {describe, <<"shared-v1">>}, {dirty, false}]}]}, {nuggets, [{nugget, platform_demo, [{repository, sdk_repo}]}, {nugget, feature_shared, [{repository, shared_repo}]}]}]}.' 
    manifest_tool_test_hash_manifest "${sdk_manifest}"

    manifest_tool_test_write_manifest "${project_alpha_manifest}" '{project_manifest, <<"1.0">>, [{id, alpha}, {name, <<"alpha">>}, {version, <<"2.0.0">>}, {repository, project_alpha}, {repositories, [{project_alpha, [{name, <<"project_alpha">>}, {type, git}, {url, <<"https://example.com/project-alpha.git">>}, {commit, <<"alpha-commit">>}, {describe, <<"alpha-v2">>}, {dirty, false}]}, {shared_repo, [{name, <<"shared_repo">>}, {type, git}, {url, <<"https://example.com/shared.git">>}, {commit, <<"shared-commit">>}, {describe, <<"shared-v1">>}, {dirty, false}]}]}, {dependencies, [{shared_dep, [{type, git}, {repository, shared_repo}, {ref, <<"shared-v1">>}]}]}]}.' 
    manifest_tool_test_hash_manifest "${project_alpha_manifest}"

    manifest_tool_test_write_manifest "${project_beta_manifest}" '{project_manifest, <<"1.0">>, [{id, beta}, {name, <<"beta">>}, {version, <<"3.1.0">>}, {repository, sdk_repo}, {repositories, [{sdk_repo, [{name, <<"project_beta">>}, {type, git}, {url, <<"https://example.com/project-beta.git">>}, {commit, <<"beta-commit">>}, {describe, <<"beta-v3">>}, {dirty, false}]}]}, {dependencies, [{beta_dep, [{type, git}, {repository, sdk_repo}, {ref, <<"beta-v3">>}]}]}]}.' 
    manifest_tool_test_hash_manifest "${project_beta_manifest}"

    manifest_tool_test_run merge \
        --sdk-manifest "${sdk_manifest}" \
        --project-manifests "${temp_dir}/projects/*/ALLOY_PROJECT_MANIFEST" \
        --firmware-info firmware_variant=secure \
        --firmware-info firmware_name=demo_firmware \
        --firmware-info firmware_version=9.9.9 \
        --firmware-info security_pack_name=acme_secpack \
        --firmware-info security_pack_version=2.0 \
        --firmware-info param_serial_number:string=SN123 \
        --firmware-info param_retry_count:integer=3 \
        --firmware-info param_factory_mode:boolean=true \
        --firmware-info project_root_alpha=/srv/alloy/alpha \
        --firmware-info project_root_beta=/srv/alloy/beta \
        --output "${output_manifest}"

    verify_output="$(manifest_tool_test_run verify --manifest "${output_manifest}")"
    variant_output="$(manifest_tool_test_run get --manifest "${output_manifest}" --field firmware_variant)"
    security_output="$(manifest_tool_test_run get --manifest "${output_manifest}" --field security_pack --format erlang)"
    parameters_output="$(manifest_tool_test_run get --manifest "${output_manifest}" --field parameters --format erlang)"
    repositories_output="$(manifest_tool_test_run get --manifest "${output_manifest}" --field repositories --format erlang)"
    projects_output="$(manifest_tool_test_run get --manifest "${output_manifest}" --field projects --format erlang)"

    assert_matches "manifest=firmware_manifest" "${verify_output}"
    assert_matches "integrity=PASS" "${verify_output}"
    assert_equals "secure" "${variant_output}"
    assert_equals "[{<<\"name\">>,<<\"acme_secpack\">>},{<<\"version\">>,<<\"2.0\">>}]" "${security_output}"
    assert_equals "[{serial_number,<<\"SN123\">>},{retry_count,3},{factory_mode,true}]" "${parameters_output}"
    assert_matches "\\{sdk_repo,\\[\\{name,<<\"sdk_repo\">>\\},\\{type,git\\},\\{url,<<\"https://example.com/sdk.git\">>" "${repositories_output}"
    assert_matches "\\{shared_repo,\\[\\{name,<<\"shared_repo\">>\\},\\{type,git\\},\\{url,<<\"https://example.com/shared.git\">>" "${repositories_output}"
    assert_matches "\\{sdk_repo2,\\[\\{name,<<\"project_beta\">>\\},\\{type,git\\},\\{url,<<\"https://example.com/project-beta.git\">>" "${repositories_output}"
    assert_matches "\\{project_root,<<\"/srv/alloy/alpha\">>\\}" "${projects_output}"
    assert_matches "\\{project_root,<<\"/srv/alloy/beta\">>\\}" "${projects_output}"
    assert_matches "\\{repository,sdk_repo2\\}" "${projects_output}"
}

test_manifest_tool_merge_rejects_tampered_project_manifest() {
    local temp_dir sdk_manifest project_manifest output_manifest output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    sdk_manifest="${temp_dir}/sdk/ALLOY_SDK_MANIFEST"
    project_manifest="${temp_dir}/projects/app/ALLOY_PROJECT_MANIFEST"
    output_manifest="${temp_dir}/firmware/ALLOY_FIRMWARE_MANIFEST"

    manifest_tool_test_write_manifest "${sdk_manifest}" '{sdk_manifest, <<"1.0">>, [{product, <<"grisp2_vanilla">>}, {product_version, <<"1.0.0">>}, {repositories, []}]}.' 
    manifest_tool_test_hash_manifest "${sdk_manifest}"

    manifest_tool_test_write_manifest "${project_manifest}" '{project_manifest, <<"1.0">>, [{id, app}, {name, <<"app">>}, {version, <<"1.0.0">>}, {repositories, []}]}.' 
    manifest_tool_test_hash_manifest "${project_manifest}"
    manifest_tool_test_write_manifest "${project_manifest}" '{project_manifest, <<"1.0">>, [{id, app}, {name, <<"tampered">>}, {version, <<"1.0.0">>}, {repositories, []}, {integrity, [{digest_algorithm, sha256}, {canonical_form, basic_term_canon}, {digest, <<"17a3d0c7e81ec7b76885e5f5d3b75f847bcf9783df82b295673eee1268db15bf">>}]}]}.' 

    output="$({ manifest_tool_test_run merge \
        --sdk-manifest "${sdk_manifest}" \
        --project-manifests "${temp_dir}/projects/*/ALLOY_PROJECT_MANIFEST" \
        --firmware-info firmware_variant=plain \
        --firmware-info project_root_app=/srv/alloy/app \
        --output "${output_manifest}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "integrity verification failed" "${output}"
    assert_matches "${project_manifest}" "${output}"
}

test_manifest_tool_merge_requires_project_root_for_each_project() {
    local temp_dir sdk_manifest project_manifest output_manifest output status
    temp_dir="$(harness_make_temp_dir "manifest-tool")"
    sdk_manifest="${temp_dir}/sdk/ALLOY_SDK_MANIFEST"
    project_manifest="${temp_dir}/projects/app/ALLOY_PROJECT_MANIFEST"
    output_manifest="${temp_dir}/firmware/ALLOY_FIRMWARE_MANIFEST"

    manifest_tool_test_write_manifest "${sdk_manifest}" '{sdk_manifest, <<"1.0">>, [{product, <<"grisp2_vanilla">>}, {product_version, <<"1.0.0">>}, {repositories, []}]}.' 
    manifest_tool_test_hash_manifest "${sdk_manifest}"

    manifest_tool_test_write_manifest "${project_manifest}" '{project_manifest, <<"1.0">>, [{id, app}, {name, <<"app">>}, {version, <<"1.0.0">>}, {repositories, []}]}.' 
    manifest_tool_test_hash_manifest "${project_manifest}"

    output="$({ manifest_tool_test_run merge \
        --sdk-manifest "${sdk_manifest}" \
        --project-manifests "${temp_dir}/projects/*/ALLOY_PROJECT_MANIFEST" \
        --firmware-info firmware_variant=plain \
        --output "${output_manifest}"; } 2>&1)"
    status=$?

    assert_equals "2" "${status}"
    assert_matches "project_root_app" "${output}"
}
