#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

ENV_UTILS_SCRIPT="$(harness_repo_root)/scripts/utils/env_utils.sh"
# shellcheck source=scripts/utils/env_utils.sh
source "${ENV_UTILS_SCRIPT}"

env_utils_test_make_exec() {
    local file_path="$1"
    local script_body="${2:-}"
    mkdir -p "$(dirname "${file_path}")"
    cat > "${file_path}" <<EOF
#!/usr/bin/env bash
${script_body}
EOF
    chmod +x "${file_path}"
}

env_utils_test_write_fake_elf() {
    local file_path="$1"
    local elf_class="$2"
    local elf_machine="$3"
    mkdir -p "$(dirname "${file_path}")"
    printf '\177ELF\nClass: %s\nMachine: %s\n' "${elf_class}" "${elf_machine}" > "${file_path}"
}

env_utils_test_make_sdk() {
    local temp_dir="$1"
    local target_triplet="${2:-arm-buildroot-linux-gnueabihf}"
    local elf_class="${3:-ELF32}"
    local elf_machine="${4:-ARM}"
    local sdk_dir="${temp_dir}/sdk"
    local host_bin="${sdk_dir}/host/bin"
    local host_usr_bin="${sdk_dir}/host/usr/bin"

    mkdir -p \
        "${host_bin}" \
        "${host_usr_bin}" \
        "${sdk_dir}/host/usr/lib/erlang" \
        "${sdk_dir}/host/${target_triplet}/sysroot/usr/include" \
        "${sdk_dir}/host/${target_triplet}/sysroot/usr/lib/pkgconfig" \
        "${sdk_dir}/images" \
        "${sdk_dir}/staging/usr/lib/erlang/erts-13.2/include" \
        "${sdk_dir}/staging/usr/lib/erlang/erts-13.2/lib" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/erl_interface-5.4/include" \
        "${sdk_dir}/staging/usr/lib/erlang/lib/erl_interface-5.4/lib"

    env_utils_test_make_exec "${host_bin}/${target_triplet}-gcc" "$(cat <<EOF
output=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o)
            output="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
printf '\177ELF\nClass: %s\nMachine: %s\n' "${elf_class}" "${elf_machine}" > "\${output}"
EOF
)"

    local tool_name
    for tool_name in g++ ld ar as nm strip objcopy objdump ranlib; do
        env_utils_test_make_exec "${host_bin}/${target_triplet}-${tool_name}" 'exit 0'
    done

    env_utils_test_make_exec "${host_bin}/${target_triplet}-readelf" "$(cat <<'EOF'
if [[ "$1" != "-h" ]]; then
    exit 2
fi
file_path="$2"
if [[ ! -f "${file_path}" ]]; then
    exit 1
fi
if ! grep -aq "^Class:" "${file_path}"; then
    exit 1
fi
elf_class="$(grep -a "^Class:" "${file_path}" | head -n1 | cut -d: -f2- | sed "s/^[[:space:]]*//")"
elf_machine="$(grep -a "^Machine:" "${file_path}" | head -n1 | cut -d: -f2- | sed "s/^[[:space:]]*//")"
cat <<EOHDR
ELF Header:
  Class:                             ${elf_class}
  Machine:                           ${elf_machine}
EOHDR
EOF
)"

    env_utils_test_make_exec "${host_bin}/pkg-config" 'exit 0'
    env_utils_test_make_exec "${host_usr_bin}/rebar3" 'exit 0'

    printf '%s\n' "${sdk_dir}"
}

test_env_utils_validate_sdk_dir_requires_expected_structure() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="${temp_dir}/sdk"
    mkdir -p "${sdk_dir}/host"

    local output status
    output="$({ validate_sdk_dir "${sdk_dir}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "missing ${sdk_dir}/images" "${output}"
}

test_env_utils_setup_cross_env_exports_expected_variables() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="$(env_utils_test_make_sdk "${temp_dir}")"

    export ALLOY_CONFIG_TARGET_ARCH_TRIPLET="arm-buildroot-linux-gnueabihf"
    export ALLOY_CONFIG_HOST_ERLANG_ROOT="${sdk_dir}/host/usr/lib/erlang"
    export ALLOY_CONFIG_HOST_REBAR3="${sdk_dir}/host/usr/bin/rebar3"
    export ALLOY_CONFIG_OTP_VERSION="26.2"

    setup_cross_env "${sdk_dir}"

    assert_equals "${sdk_dir}/host/bin/arm-buildroot-linux-gnueabihf-gcc" "${CC}"
    assert_equals "arm-buildroot-linux-gnueabihf-" "${CROSSCOMPILE_PREFIX}"
    assert_equals "${sdk_dir}/host/arm-buildroot-linux-gnueabihf/sysroot" "${ALLOY_TARGET_SYSROOT}"
    assert_equals "${sdk_dir}/host/usr/lib/erlang" "${HOST_ERLANG}"
    assert_equals "${sdk_dir}/host/usr/bin/rebar3" "${HOST_REBAR3}"
    assert_equals "${sdk_dir}/staging/usr/lib/erlang" "${TARGET_ERLANG}"
    assert_equals "26.2" "${OTP_VERSION}"
    assert_matches "${sdk_dir}/host/usr/bin:${sdk_dir}/host/bin" "${PATH}"
}

test_env_utils_setup_cross_env_falls_back_to_scanning_host_bin_for_triplet() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="$(env_utils_test_make_sdk "${temp_dir}")"

    unset ALLOY_CONFIG_TARGET_ARCH_TRIPLET || true
    unset ALLOY_CONFIG_HOST_ERLANG_ROOT || true
    unset ALLOY_CONFIG_HOST_REBAR3 || true
    unset ALLOY_CONFIG_OTP_VERSION || true

    setup_cross_env "${sdk_dir}"

    assert_equals "arm-buildroot-linux-gnueabihf" "${CROSSCOMPILE_ARCH}"
    assert_equals "13.2" "${OTP_VERSION}"
}

test_env_utils_setup_cross_env_requires_native_build_tools() {
    local temp_dir sdk_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="$(env_utils_test_make_sdk "${temp_dir}")"
    local temp_path_dir="${temp_dir}/path-bin"
    mkdir -p "${temp_path_dir}"
    ln -s "$(command -v dirname)" "${temp_path_dir}/dirname"

    local output status
    output="$(PATH="${temp_path_dir}" /bin/bash -c "source \"${ENV_UTILS_SCRIPT}\"; setup_cross_env \"${sdk_dir}\"" 2>&1)"
    status=$?

    assert_equals "127" "${status}"
    assert_matches "Required command not found: cc" "${output}"
}

test_env_utils_validate_release_target_arch_accepts_matching_release_and_overlay() {
    local temp_dir sdk_dir release_dir overlay_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="$(env_utils_test_make_sdk "${temp_dir}")"
    release_dir="${temp_dir}/release"
    overlay_dir="${temp_dir}/overlay"
    mkdir -p "${release_dir}/bin" "${overlay_dir}/lib"

    setup_cross_env "${sdk_dir}"
    env_utils_test_write_fake_elf "${release_dir}/bin/app" "ELF32" "ARM"
    env_utils_test_write_fake_elf "${overlay_dir}/lib/libnif.so" "ELF32" "ARM"
    printf 'plain-text\n' > "${overlay_dir}/README"

    validate_release_target_arch "${release_dir}" "${overlay_dir}"
}

test_env_utils_validate_release_target_arch_rejects_wrong_machine() {
    local temp_dir sdk_dir release_dir overlay_dir
    temp_dir="$(harness_make_temp_dir "env-utils")"
    sdk_dir="$(env_utils_test_make_sdk "${temp_dir}")"
    release_dir="${temp_dir}/release"
    overlay_dir="${temp_dir}/overlay"
    mkdir -p "${release_dir}/bin" "${overlay_dir}/lib"

    setup_cross_env "${sdk_dir}"
    env_utils_test_write_fake_elf "${release_dir}/bin/app" "ELF32" "ARM"
    env_utils_test_write_fake_elf "${overlay_dir}/lib/libnif.so" "ELF64" "AArch64"

    local output status
    output="$({ validate_release_target_arch "${release_dir}" "${overlay_dir}"; } 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "ELF target mismatch" "${output}"
    assert_matches "AArch64" "${output}"
}

test_env_utils_is_safe_to_source_multiple_times() {
    assert_status_code 0 "bash -c 'source \"${ENV_UTILS_SCRIPT}\"; source \"${ENV_UTILS_SCRIPT}\"; type validate_sdk_dir >/dev/null'"
}
