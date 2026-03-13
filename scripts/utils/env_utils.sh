#!/usr/bin/env bash

if [[ "${__ALLOY_ENV_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_ENV_UTILS_SH_LOADED=1

ENV_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${ENV_UTILS_DIR}/common.sh"

env_utils_prepend_path() {
    local dir_path="${1:-}"
    if [[ -z "${dir_path}" ]] || [[ ! -d "${dir_path}" ]]; then
        return 0
    fi

    case ":${PATH:-}:" in
        *":${dir_path}:"*) ;;
        *) PATH="${dir_path}${PATH:+:${PATH}}" ;;
    esac
    export PATH
}

env_utils_find_triplet() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "env_utils_find_triplet requires SDK_DIR"
        return 2
    fi

    if [[ -n "${ALLOY_CONFIG_TARGET_ARCH_TRIPLET:-}" ]]; then
        printf '%s\n' "${ALLOY_CONFIG_TARGET_ARCH_TRIPLET}"
        return 0
    fi

    local candidate
    shopt -s nullglob
    for candidate in "${sdk_dir}/host/bin/"*-gcc; do
        if [[ -x "${candidate}" ]]; then
            local tool_name="${candidate##*/}"
            printf '%s\n' "${tool_name%-gcc}"
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob

    log_error "Unable to determine target architecture triplet from ${sdk_dir}/host/bin"
    return 1
}

env_utils_find_first_executable() {
    local candidate
    for candidate in "$@"; do
        if [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    log_error "No executable found in candidate list"
    return 1
}

env_utils_require_executable() {
    local executable_path="${1:-}"
    local label="${2:-required executable}"

    if [[ -z "${executable_path}" ]]; then
        log_error "Missing ${label} path"
        return 2
    fi

    if [[ ! -x "${executable_path}" ]]; then
        log_error "Missing ${label}: ${executable_path}"
        return 1
    fi
}

env_utils_resolve_sysroot() {
    local sdk_dir="${1:-}"
    local target_triplet="${2:-}"

    if [[ -z "${sdk_dir}" ]] || [[ -z "${target_triplet}" ]]; then
        log_error "env_utils_resolve_sysroot requires SDK_DIR and target triplet"
        return 2
    fi

    local preferred_sysroot="${sdk_dir}/host/${target_triplet}/sysroot"
    if [[ -d "${preferred_sysroot}" ]]; then
        printf '%s\n' "${preferred_sysroot}"
        return 0
    fi

    local legacy_sysroot="${sdk_dir}/staging"
    if [[ -d "${legacy_sysroot}" ]]; then
        printf '%s\n' "${legacy_sysroot}"
        return 0
    fi

    log_error "SDK sysroot not found for ${target_triplet}: expected ${preferred_sysroot}"
    return 1
}

env_utils_detect_otp_version() {
    local target_erlang_dir="${1:-}"
    if [[ -z "${target_erlang_dir}" ]]; then
        log_error "env_utils_detect_otp_version requires TARGET_ERLANG"
        return 2
    fi

    local erts_dir
    shopt -s nullglob
    for erts_dir in "${target_erlang_dir}"/erts-*; do
        if [[ -d "${erts_dir}" ]]; then
            local erts_name="${erts_dir##*/}"
            printf '%s\n' "${erts_name#erts-}"
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob

    return 1
}

env_utils_read_elf_signature() {
    local file_path="${1:-}"
    local -n class_ref="$2"
    local -n machine_ref="$3"

    if [[ -z "${file_path}" ]]; then
        log_error "env_utils_read_elf_signature requires a file path"
        return 2
    fi

    local header_output
    if ! header_output="$("${READELF}" -h "${file_path}" 2>/dev/null)"; then
        return 1
    fi

    class_ref=""
    machine_ref=""

    local header_line
    while IFS= read -r header_line; do
        case "${header_line}" in
            *Class:*)
                class_ref="${header_line##*:}"
                class_ref="${class_ref#"${class_ref%%[![:space:]]*}"}"
                ;;
            *Machine:*)
                machine_ref="${header_line##*:}"
                machine_ref="${machine_ref#"${machine_ref%%[![:space:]]*}"}"
                ;;
        esac
    done <<< "${header_output}"

    if [[ -z "${machine_ref}" ]]; then
        return 1
    fi

    return 0
}

env_utils_expected_elf_signature_from_triplet() {
    local target_triplet="${1:-}"
    local -n class_ref="$2"
    local -n machine_ref="$3"

    if [[ -z "${target_triplet}" ]]; then
        log_error "env_utils_expected_elf_signature_from_triplet requires a target triplet"
        return 2
    fi

    class_ref=""
    machine_ref=""

    case "${target_triplet}" in
        aarch64*-linux* | aarch64*)
            class_ref="ELF64"
            machine_ref="AArch64"
            ;;
        arm*-linux* | arm*)
            class_ref="ELF32"
            machine_ref="ARM"
            ;;
        x86_64*-linux* | x86_64*)
            class_ref="ELF64"
            machine_ref="Advanced Micro Devices X86-64"
            ;;
        riscv64*-linux* | riscv64*)
            class_ref="ELF64"
            machine_ref="RISC-V"
            ;;
        *)
            log_error "Unable to map target triplet to ELF machine: ${target_triplet}"
            return 1
            ;;
    esac
}

env_utils_probe_expected_elf_signature() {
    # shellcheck disable=SC2034  # nameref is the output channel for the caller
    local -n out_class_ref="$1"
    # shellcheck disable=SC2034  # nameref is the output channel for the caller
    local -n out_machine_ref="$2"

    require_commands mktemp || return $?

    local probe_dir
    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/alloy-env-utils.XXXXXX")" || return 1

    local cleanup_status=0
    local probe_source="${probe_dir}/probe.c"
    local probe_binary="${probe_dir}/probe"
    printf 'int main(void) { return 0; }\n' > "${probe_source}"

    if ! "${CC}" -o "${probe_binary}" "${probe_source}" >/dev/null 2>&1; then
        cleanup_status=1
    elif ! env_utils_read_elf_signature "${probe_binary}" out_class_ref out_machine_ref; then
        cleanup_status=1
    fi

    rm -rf "${probe_dir}"
    return "${cleanup_status}"
}

env_utils_path_has_marker() {
    local file_path="${1:-}"
    local root_dir="${2:-}"
    local marker_name="${3:-.noarchcheck}"

    local current_dir
    current_dir="$(dirname "${file_path}")"
    root_dir="${root_dir%/}"

    while [[ -n "${current_dir}" ]]; do
        if [[ -e "${current_dir}/${marker_name}" ]]; then
            return 0
        fi
        if [[ "${current_dir}" == "${root_dir}" ]] || [[ "${current_dir}" == "/" ]]; then
            break
        fi
        current_dir="$(dirname "${current_dir}")"
    done

    return 1
}

validate_sdk_dir() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "validate_sdk_dir requires SDK_DIR"
        return 2
    fi

    if [[ ! -d "${sdk_dir}" ]]; then
        log_error "SDK directory not found: ${sdk_dir}"
        return 1
    fi

    local required_dir
    for required_dir in "${sdk_dir}/host" "${sdk_dir}/images"; do
        if [[ ! -d "${required_dir}" ]]; then
            log_error "Invalid SDK directory: missing ${required_dir}"
            return 1
        fi
    done

    return 0
}

setup_cross_env() {
    local sdk_dir="${1:-}"
    if [[ -z "${sdk_dir}" ]]; then
        log_error "setup_cross_env requires SDK_DIR"
        return 2
    fi

    validate_sdk_dir "${sdk_dir}" || return $?
    require_commands cc ld ar as || return $?

    local host_dir="${sdk_dir}/host"
    local host_bin="${host_dir}/bin"
    local host_usr_bin="${host_dir}/usr/bin"
    local target_triplet
    target_triplet="$(env_utils_find_triplet "${sdk_dir}")" || return $?

    local tool_prefix="${host_bin}/${target_triplet}-"
    local tool_var tool_binary tool_path
    local tool_spec
    for tool_spec in \
        "CC:gcc" \
        "CXX:g++" \
        "LD:ld" \
        "AR:ar" \
        "AS:as" \
        "NM:nm" \
        "STRIP:strip" \
        "OBJCOPY:objcopy" \
        "OBJDUMP:objdump" \
        "RANLIB:ranlib" \
        "READELF:readelf"; do
        tool_var="${tool_spec%%:*}"
        tool_binary="${tool_spec#*:}"
        tool_path="${tool_prefix}${tool_binary}"
        env_utils_require_executable "${tool_path}" "${tool_var}" || return $?
        export "${tool_var}=${tool_path}"
    done

    export CROSSCOMPILE_PREFIX="${target_triplet}-"
    export CROSSCOMPILE="${host_bin}/${target_triplet}"
    export CROSSCOMPILE_ARCH="${target_triplet}"

    env_utils_prepend_path "${host_bin}"
    env_utils_prepend_path "${host_usr_bin}"

    local sysroot_dir
    sysroot_dir="$(env_utils_resolve_sysroot "${sdk_dir}" "${target_triplet}")" || return $?
    export ALLOY_TARGET_SYSROOT="${sysroot_dir}"

    export CFLAGS="--sysroot=${sysroot_dir} -I${sysroot_dir}/usr/include"
    export CXXFLAGS="${CFLAGS}"
    export LDFLAGS="--sysroot=${sysroot_dir}"

    local pkg_config_path
    pkg_config_path="$(env_utils_find_first_executable \
        "${host_bin}/pkg-config" \
        "${host_usr_bin}/pkg-config")" || return $?
    export PKG_CONFIG="${pkg_config_path}"
    export PKG_CONFIG_SYSROOT_DIR="${sysroot_dir}"
    export PKG_CONFIG_LIBDIR="${sysroot_dir}/usr/lib/pkgconfig"

    local target_erlang_dir="${sdk_dir}/staging/usr/lib/erlang"
    if [[ ! -d "${target_erlang_dir}" ]]; then
        log_error "Target Erlang runtime not found: ${target_erlang_dir}"
        return 1
    fi
    export TARGET_ERLANG="${target_erlang_dir}"
    export ERL_LIBS="${TARGET_ERLANG}/lib"
    export REBAR_PLT_DIR="${TARGET_ERLANG}"

    local host_erlang_dir="${ALLOY_CONFIG_HOST_ERLANG_ROOT:-${host_dir}/usr/lib/erlang}"
    if [[ ! -d "${host_erlang_dir}" ]]; then
        log_error "Host Erlang runtime not found: ${host_erlang_dir}"
        return 1
    fi
    export HOST_ERLANG="${host_erlang_dir}"

    local host_rebar3_path="${ALLOY_CONFIG_HOST_REBAR3:-}"
    if [[ -z "${host_rebar3_path}" ]]; then
        host_rebar3_path="$(env_utils_find_first_executable \
            "${host_usr_bin}/rebar3" \
            "${host_bin}/rebar3")" || return $?
    fi
    env_utils_require_executable "${host_rebar3_path}" "HOST_REBAR3" || return $?
    export HOST_REBAR3="${host_rebar3_path}"

    export REBAR_TARGET_ARCH="${target_triplet}"
    export OTP_VERSION="${ALLOY_CONFIG_OTP_VERSION:-}"
    if [[ -z "${OTP_VERSION}" ]]; then
        OTP_VERSION="$(env_utils_detect_otp_version "${TARGET_ERLANG}" || true)"
        export OTP_VERSION
    fi

    local erts_dir=""
    local erl_interface_dir=""
    local candidate
    shopt -s nullglob
    for candidate in "${TARGET_ERLANG}"/erts-*; do
        if [[ -d "${candidate}" ]]; then
            erts_dir="${candidate}"
            break
        fi
    done
    for candidate in "${TARGET_ERLANG}"/lib/erl_interface-*; do
        if [[ -d "${candidate}" ]]; then
            erl_interface_dir="${candidate}"
            break
        fi
    done
    shopt -u nullglob

    if [[ -z "${erts_dir}" ]]; then
        log_error "ERTS directory not found under ${TARGET_ERLANG}"
        return 1
    fi
    if [[ -z "${erl_interface_dir}" ]]; then
        log_error "erl_interface directory not found under ${TARGET_ERLANG}/lib"
        return 1
    fi

    export ERTS_INCLUDE_DIR="${erts_dir}/include"
    export ERL_EI_INCLUDE_DIR="${erl_interface_dir}/include"
    export ERL_EI_LIBDIR="${erl_interface_dir}/lib"
    export ERL_INTERFACE_INCLUDE_DIR="${ERL_EI_INCLUDE_DIR}"
    export ERL_INTERFACE_LIB_DIR="${ERL_EI_LIBDIR}"
    export ERL_CFLAGS="-I${ERTS_INCLUDE_DIR} -I${ERL_EI_INCLUDE_DIR}"
    export ERL_LDFLAGS="-L${erts_dir}/lib -L${ERL_EI_LIBDIR} -lerts -lei"

    local native_cxx
    native_cxx="$(command -v c++ || command -v g++ || true)"
    if [[ -z "${native_cxx}" ]]; then
        log_error "Required command not found: c++"
        return 127
    fi

    CC_FOR_BUILD="$(command -v cc)"
    export CC_FOR_BUILD
    export CXX_FOR_BUILD="${native_cxx}"
    LD_FOR_BUILD="$(command -v ld)"
    export LD_FOR_BUILD
    AR_FOR_BUILD="$(command -v ar)"
    export AR_FOR_BUILD
    AS_FOR_BUILD="$(command -v as)"
    export AS_FOR_BUILD
    GCC_FOR_BUILD="$(command -v gcc || command -v cc)"
    export GCC_FOR_BUILD
    export CPPFLAGS_FOR_BUILD=""
    export CFLAGS_FOR_BUILD=""
    export CXXFLAGS_FOR_BUILD=""
    export LDFLAGS_FOR_BUILD=""

    return 0
}

validate_release_target_arch() {
    local release_dir="${1:-}"
    local overlay_dir="${2:-}"

    if [[ -z "${release_dir}" ]]; then
        log_error "validate_release_target_arch requires RELEASE_DIR"
        return 2
    fi
    if [[ ! -d "${release_dir}" ]]; then
        log_error "Release directory not found: ${release_dir}"
        return 1
    fi
    if [[ -n "${overlay_dir}" ]] && [[ ! -d "${overlay_dir}" ]]; then
        log_error "Overlay directory not found: ${overlay_dir}"
        return 1
    fi
    if [[ -z "${READELF:-}" ]]; then
        log_error "READELF is not set; call setup_cross_env first"
        return 2
    fi

    require_commands find mktemp || return $?

    local expected_class="" expected_machine=""
    if ! env_utils_probe_expected_elf_signature expected_class expected_machine; then
        env_utils_expected_elf_signature_from_triplet \
            "${ALLOY_CONFIG_TARGET_ARCH_TRIPLET:-${CROSSCOMPILE_ARCH:-}}" \
            expected_class expected_machine || return $?
    fi

    local search_root file_class file_machine file_path
    for search_root in "${release_dir}" "${overlay_dir}"; do
        if [[ -z "${search_root}" ]]; then
            continue
        fi

        while IFS= read -r -d '' file_path; do
            if env_utils_path_has_marker "${file_path}" "${search_root}"; then
                continue
            fi

            if ! env_utils_read_elf_signature "${file_path}" file_class file_machine; then
                continue
            fi

            if [[ "${file_machine}" != "${expected_machine}" ]] || \
               [[ -n "${expected_class}" && "${file_class}" != "${expected_class}" ]]; then
                log_error "ELF target mismatch: ${file_path} expected Machine=${expected_machine} Class=${expected_class:-unknown}, got Machine=${file_machine} Class=${file_class:-unknown}"
                return 1
            fi
        done < <(find "${search_root}" -type f -print0)
    done

    return 0
}
