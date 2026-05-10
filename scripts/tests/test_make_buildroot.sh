#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

MAKE_BUILDROOT_SCRIPT="$(harness_repo_root)/scripts/buildroot/make_buildroot.sh"

make_buildroot_test_fake_make_bin() {
    local temp_dir="$1"
    local bin_dir="${temp_dir}/bin"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/make" <<'FAKEMAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'noise line\n'
printf '>>> useful line\n'
printf '\033[47m>>>   Finalizing host directory\033[0m\n'
printf '[alloy:hook] INFO: hook line\n'
FAKEMAKE
    chmod +x "${bin_dir}/make"
    printf '%s\n' "${bin_dir}"
}

test_make_buildroot_filters_console_but_keeps_full_log() {
    local temp_dir bin_dir output status workspace
    temp_dir="$(harness_make_temp_dir "make-buildroot-filter")"
    workspace="${temp_dir}/workspace"
    bin_dir="$(make_buildroot_test_fake_make_bin "${temp_dir}")"

    output="$(PATH="${bin_dir}:$PATH" ALLOY_BUILDROOT_DEBUG=0 "${MAKE_BUILDROOT_SCRIPT}" "O=${workspace}" 2>&1)"
    status=$?

    assert_equals "0" "${status}"
    assert_matches "\[buildroot\] useful line" "${output}"
    assert_matches "\[buildroot\] Finalizing host directory" "${output}"
    assert_matches "\[buildroot\] \[alloy:hook\] INFO: hook line" "${output}"
    if printf '%s\n' "${output}" | grep -Fq 'noise line'; then
        echo "filtered noise line should not be shown on console in debug=0" >&2
        return 1
    fi
    if printf '%s\n' "${output}" | grep -Fq '>>>   Finalizing host directory'; then
        echo "Buildroot >>> marker should be stripped in filtered output" >&2
        return 1
    fi
    if printf '%s\n' "${output}" | grep -Eq $'\\[buildroot\\].*Finalizing host directory.*\\033\\['; then
        echo "ANSI sequences should be stripped from filtered >>> lines" >&2
        return 1
    fi
    assert_status_code 0 "grep -Fq 'noise line' '${workspace}/br.log'"
    assert_status_code 0 "grep -Fq '>>> useful line' '${workspace}/br.log'"
}

test_make_buildroot_nonzero_status_is_propagated() {
    local temp_dir workspace status
    temp_dir="$(harness_make_temp_dir "make-buildroot-status")"
    workspace="${temp_dir}/workspace"

    mkdir -p "${temp_dir}/bin"
    cat > "${temp_dir}/bin/make" <<'FAKEMAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '>>> failing line\n'
exit 7
FAKEMAKE
    chmod +x "${temp_dir}/bin/make"

    PATH="${temp_dir}/bin:$PATH" ALLOY_BUILDROOT_DEBUG=1 "${MAKE_BUILDROOT_SCRIPT}" "O=${workspace}" >/dev/null 2>&1
    status=$?

    assert_equals "7" "${status}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_tests "$0"
fi
