#!/usr/bin/env bash

if [[ "${__ALLOY_FILE_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_FILE_UTILS_SH_LOADED=1

FILE_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${FILE_UTILS_DIR}/common.sh"

# normalize_path PATH
# Print a lexical normalization of PATH, collapsing `.` segments, duplicate separators, and resolvable `..`.
# Env/side effects: does not touch the filesystem and does not resolve symlinks.
# Errors: returns 2 and logs when PATH is empty.
normalize_path() {
    local input_path="${1:-}"
    if [[ -z "${input_path}" ]]; then
        log_error "normalize_path requires a path argument"
        return 2
    fi

    local is_absolute=false
    if [[ "${input_path}" == /* ]]; then
        is_absolute=true
    fi

    local -a parts=()
    local token
    local old_ifs="${IFS}"
    local -a raw_parts=()
    IFS='/' read -r -a raw_parts <<< "${input_path}"
    IFS="${old_ifs}"

    for token in "${raw_parts[@]}"; do
        case "${token}" in
            ""|".")
                continue
                ;;
            "..")
                if [[ ${#parts[@]} -gt 0 ]] && [[ "${parts[${#parts[@]}-1]}" != ".." ]]; then
                    unset 'parts[${#parts[@]}-1]'
                elif [[ "${is_absolute}" == false ]]; then
                    parts+=("..")
                fi
                ;;
            *)
                parts+=("${token}")
                ;;
        esac
    done

    local normalized=""
    if [[ "${is_absolute}" == true ]]; then
        normalized="/"
    fi

    if [[ ${#parts[@]} -gt 0 ]]; then
        local joined
        joined="$(IFS='/'; echo "${parts[*]}")"
        if [[ "${is_absolute}" == true ]]; then
            normalized="/${joined}"
        else
            normalized="${joined}"
        fi
    elif [[ "${is_absolute}" == false ]]; then
        normalized="."
    fi

    printf '%s\n' "${normalized}"
}

# relative_path FROM TO
# Print the relative path from FROM to TO after lexical normalization.
# Env/side effects: none.
# Errors: returns 2 and logs for missing arguments or mixed absolute/relative inputs; propagates normalize_path failures.
relative_path() {
    local from_path="${1:-}"
    local to_path="${2:-}"
    if [[ -z "${from_path}" ]] || [[ -z "${to_path}" ]]; then
        log_error "relative_path requires FROM and TO path arguments"
        return 2
    fi

    local from_norm to_norm
    from_norm="$(normalize_path "${from_path}")" || return $?
    to_norm="$(normalize_path "${to_path}")" || return $?

    local from_abs=false
    local to_abs=false
    [[ "${from_norm}" == /* ]] && from_abs=true
    [[ "${to_norm}" == /* ]] && to_abs=true
    if [[ "${from_abs}" != "${to_abs}" ]]; then
        log_error "relative_path requires both paths to be both absolute or both relative"
        return 2
    fi

    local from_trim="${from_norm#/}"
    local to_trim="${to_norm#/}"
    local -a from_parts=()
    local -a to_parts=()
    local old_ifs="${IFS}"

    if [[ -n "${from_trim}" ]] && [[ "${from_trim}" != "." ]]; then
        IFS='/' read -r -a from_parts <<< "${from_trim}"
    fi
    if [[ -n "${to_trim}" ]] && [[ "${to_trim}" != "." ]]; then
        IFS='/' read -r -a to_parts <<< "${to_trim}"
    fi
    IFS="${old_ifs}"

    local common=0
    while [[ ${common} -lt ${#from_parts[@]} ]] \
        && [[ ${common} -lt ${#to_parts[@]} ]] \
        && [[ "${from_parts[$common]}" == "${to_parts[$common]}" ]]; do
        common=$((common + 1))
    done

    local -a result_parts=()
    local idx
    for ((idx=common; idx<${#from_parts[@]}; idx++)); do
        result_parts+=("..")
    done
    for ((idx=common; idx<${#to_parts[@]}; idx++)); do
        result_parts+=("${to_parts[$idx]}")
    done

    if [[ ${#result_parts[@]} -eq 0 ]]; then
        printf '.\n'
        return 0
    fi

    local result
    result="$(IFS='/'; echo "${result_parts[*]}")"
    printf '%s\n' "${result}"
}

# display_path_for_root ROOT_DIR PATH_VALUE
# Print PATH_VALUE for user-facing output: keep relative inputs unchanged, convert absolute paths under ROOT_DIR
# to a relative path, and keep absolute paths outside ROOT_DIR unchanged.
# Env/side effects: none.
# Errors: returns 2 and logs for missing arguments or invalid ROOT_DIR normalization failures.
display_path_for_root() {
    local root_dir="${1:-}"
    local path_value="${2:-}"
    if [[ -z "${root_dir}" ]] || [[ -z "${path_value}" ]]; then
        log_error "display_path_for_root requires ROOT_DIR and PATH_VALUE arguments"
        return 2
    fi

    # Keep relative inputs as provided by the caller.
    if [[ "${path_value}" != /* ]]; then
        printf '%s\n' "${path_value}"
        return 0
    fi

    local root_norm path_norm
    root_norm="$(normalize_path "${root_dir}")" || return $?
    path_norm="$(normalize_path "${path_value}")" || return $?

    if [[ "${root_norm}" != /* ]]; then
        log_error "display_path_for_root requires ROOT_DIR to resolve to an absolute path"
        return 2
    fi

    if [[ "${path_norm}" == "${root_norm}" ]]; then
        printf '.\n'
        return 0
    fi

    if [[ "${root_norm}" == "/" ]]; then
        relative_path "/" "${path_norm}"
        return $?
    fi

    if [[ "${path_norm}" == "${root_norm}/"* ]]; then
        relative_path "${root_norm}" "${path_norm}"
        return $?
    fi

    printf '%s\n' "${path_norm}"
}

# copy_with_exclusions SRC DEST [EXCLUDE_PATTERN...]
# Copy SRC into DEST, skipping any entries matched by the optional rsync-style exclusion patterns.
# Env/side effects: creates DEST when needed and writes files there; requires rsync on PATH.
# Errors: returns 2 for missing arguments or missing SRC, 127 when rsync is unavailable, and otherwise propagates copy failures.
copy_with_exclusions() {
    local src="${1:-}"
    local dest="${2:-}"
    shift 2 || true
    local excludes=("$@")

    if [[ -z "${src}" ]] || [[ -z "${dest}" ]]; then
        log_error "copy_with_exclusions requires SRC and DEST arguments"
        return 2
    fi
    if [[ ! -e "${src}" ]]; then
        log_error "Source path does not exist: ${src}"
        return 2
    fi

    require_command rsync || return $?

    mkdir -p "${dest}" || return $?

    if [[ -f "${src}" ]]; then
        local base_name
        base_name="$(basename "${src}")"
        local pattern
        for pattern in "${excludes[@]}"; do
            [[ -n "${pattern}" ]] || continue
            # shellcheck disable=SC2053  # intentional glob-pattern matching for excludes
            if [[ "${base_name}" == ${pattern} ]]; then
                return 0
            fi
        done
        cp -a "${src}" "${dest}/"
        return 0
    fi

    local -a rsync_args=(-a --checksum)
    local pattern
    for pattern in "${excludes[@]}"; do
        [[ -n "${pattern}" ]] || continue
        rsync_args+=(--exclude "${pattern}")
    done
    rsync "${rsync_args[@]}" "${src%/}/" "${dest%/}/"
}

# merge_directories SRC DEST
# Overlay the contents of SRC onto DEST using copy_with_exclusions semantics without exclusion patterns.
# Env/side effects: creates or updates files under DEST.
# Errors: returns 2 for invalid arguments or missing SRC directory; otherwise propagates copy_with_exclusions failures.
merge_directories() {
    local src="${1:-}"
    local dest="${2:-}"
    if [[ -z "${src}" ]] || [[ -z "${dest}" ]]; then
        log_error "merge_directories requires SRC and DEST arguments"
        return 2
    fi
    if [[ ! -d "${src}" ]]; then
        log_error "Source directory does not exist: ${src}"
        return 2
    fi

    copy_with_exclusions "${src}" "${dest}"
}

# make_symlink_relative LINK_FILE LINK_TARGET
# Create or replace LINK_FILE with a symlink whose target is stored relative to LINK_FILE's directory.
# Env/side effects: creates parent directories for LINK_FILE and rewrites the symlink on disk.
# Errors: returns 2 and logs for missing arguments; propagates path-normalization, relative-path, and ln failures.
make_symlink_relative() {
    local link_file="${1:-}"
    local link_target="${2:-}"
    if [[ -z "${link_file}" ]] || [[ -z "${link_target}" ]]; then
        log_error "make_symlink_relative requires LINK_FILE and LINK_TARGET arguments"
        return 2
    fi

    local link_dir
    link_dir="$(dirname "${link_file}")"
    mkdir -p "${link_dir}" || return $?

    local cwd
    cwd="$(pwd -P)"
    local abs_link_dir
    if [[ "${link_dir}" == /* ]]; then
        abs_link_dir="$(normalize_path "${link_dir}")"
    else
        abs_link_dir="$(normalize_path "${cwd}/${link_dir}")"
    fi

    local abs_target
    if [[ "${link_target}" == /* ]]; then
        abs_target="$(normalize_path "${link_target}")"
    else
        abs_target="$(normalize_path "${abs_link_dir}/${link_target}")"
    fi

    local relative_target
    relative_target="$(relative_path "${abs_link_dir}" "${abs_target}")" || return $?

    ln -sfn "${relative_target}" "${link_file}"
}
