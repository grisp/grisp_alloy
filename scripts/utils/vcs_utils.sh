#!/usr/bin/env bash

if [[ "${__ALLOY_VCS_UTILS_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
__ALLOY_VCS_UTILS_SH_LOADED=1

VCS_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${VCS_UTILS_DIR}/common.sh"

vcs__is_supported_type() {
    [[ "$1" == "git" ]]
}

vcs__require_git() {
    require_command git || return $?
}

vcs__validate_allow_dirty() {
    case "${1:-}" in
        true|false)
            return 0
            ;;
        *)
            log_error "ALLOW_DIRTY must be true or false"
            return 2
            ;;
    esac
}

vcs__git_is_checkout() {
    local target_dir="$1"
    git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1
}

vcs__git_remote_url() {
    local target_dir="$1"
    git -C "${target_dir}" config --get remote.origin.url
}

vcs__git_fetch_origin() {
    local target_dir="$1"
    git -C "${target_dir}" fetch --tags --prune origin >/dev/null 2>&1
}

vcs__git_resolve_commit() {
    local target_dir="$1"
    local ref="$2"
    git -C "${target_dir}" rev-parse --verify "${ref}^{commit}" 2>/dev/null
}

vcs__git_current_commit() {
    local target_dir="$1"
    git -C "${target_dir}" rev-parse HEAD 2>/dev/null
}

vcs__git_is_dirty() {
    local target_dir="$1"
    [[ -n "$(git -C "${target_dir}" status --porcelain --untracked-files=normal 2>/dev/null)" ]]
}

vcs__git_checkout_commit() {
    local target_dir="$1"
    local commit="$2"
    git -C "${target_dir}" checkout --force --detach "${commit}" >/dev/null 2>&1
}

vcs__git_clone_target() {
    local url="$1"
    local target_dir="$2"

    mkdir -p "$(dirname "${target_dir}")" || return $?
    git clone "${url}" "${target_dir}" >/dev/null 2>&1
}

vcs__git_clone_and_checkout_ref() {
    local url="$1"
    local ref="$2"
    local target_dir="$3"

    vcs__git_clone_target "${url}" "${target_dir}" || {
        log_error "Failed to clone git repository ${url} into ${target_dir}"
        return 1
    }

    vcs__git_fetch_origin "${target_dir}" || {
        log_error "Failed to fetch origin for ${target_dir}"
        return 1
    }

    local desired_commit
    desired_commit="$(vcs__git_resolve_commit "${target_dir}" "${ref}")" || {
        log_error "Unable to resolve git ref '${ref}' in ${target_dir}"
        return 1
    }

    local current_commit
    current_commit="$(vcs__git_current_commit "${target_dir}")" || {
        log_error "Unable to determine current git commit in ${target_dir}"
        return 1
    }

    if [[ "${current_commit}" != "${desired_commit}" ]]; then
        vcs__git_checkout_commit "${target_dir}" "${desired_commit}" || {
            log_error "Failed to check out ${desired_commit} in ${target_dir}"
            return 1
        }
    fi
}

# vcs_clone_or_validate VCS_TYPE URL REF TARGET_DIR ALLOW_DIRTY
# Clone TARGET_DIR when missing, or validate and update an existing checkout to REF without discarding dirty changes.
# Env/side effects: requires `git` for `VCS_TYPE=git`; may fetch, clone, detach-checkout commits, or replace TARGET_DIR when the cached remote URL mismatches.
# Errors: returns 2 for invalid arguments/unsupported VCS types, 1 for clone/fetch/ref/cleanliness failures; logs actionable errors to stderr.
vcs_clone_or_validate() {
    local vcs_type="${1:-}"
    local url="${2:-}"
    local ref="${3:-}"
    local target_dir="${4:-}"
    local allow_dirty="${5:-}"

    if [[ -z "${vcs_type}" ]] || [[ -z "${url}" ]] || [[ -z "${ref}" ]] || [[ -z "${target_dir}" ]] || [[ -z "${allow_dirty}" ]]; then
        log_error "vcs_clone_or_validate requires VCS_TYPE, URL, REF, TARGET_DIR, and ALLOW_DIRTY"
        return 2
    fi
    if ! vcs__is_supported_type "${vcs_type}"; then
        log_error "Unsupported VCS type: ${vcs_type}"
        return 2
    fi
    vcs__validate_allow_dirty "${allow_dirty}" || return $?
    vcs__require_git || return $?

    if [[ ! -e "${target_dir}" ]]; then
        vcs__git_clone_and_checkout_ref "${url}" "${ref}" "${target_dir}" || return $?
        return 0
    fi

    if ! vcs__git_is_checkout "${target_dir}"; then
        log_error "Existing target is not a git checkout: ${target_dir}"
        return 1
    fi

    local current_url
    current_url="$(vcs__git_remote_url "${target_dir}")" || current_url=""
    if [[ "${current_url}" != "${url}" ]]; then
        rm -rf "${target_dir}"
        vcs__git_clone_and_checkout_ref "${url}" "${ref}" "${target_dir}" || return $?
        return 0
    fi

    vcs__git_fetch_origin "${target_dir}" || {
        log_error "Failed to fetch origin for ${target_dir}"
        return 1
    }

    local desired_commit
    desired_commit="$(vcs__git_resolve_commit "${target_dir}" "${ref}")" || {
        log_error "Unable to resolve git ref '${ref}' in ${target_dir}"
        return 1
    }

    local current_commit
    current_commit="$(vcs__git_current_commit "${target_dir}")" || {
        log_error "Unable to determine current git commit in ${target_dir}"
        return 1
    }

    if vcs__git_is_dirty "${target_dir}"; then
        if [[ "${allow_dirty}" != "true" ]]; then
            log_error "Git checkout is dirty: ${target_dir}"
            return 1
        fi
        if [[ "${current_commit}" != "${desired_commit}" ]]; then
            log_error "Git checkout is dirty and cannot switch to ref '${ref}' without discarding changes: ${target_dir}"
            return 1
        fi
        return 0
    fi

    if [[ "${current_commit}" != "${desired_commit}" ]]; then
        vcs__git_checkout_commit "${target_dir}" "${desired_commit}" || {
            log_error "Failed to check out ${desired_commit} in ${target_dir}"
            return 1
        }
    fi
}

# vcs_get_provenance TARGET_DIR
# Print repository provenance as `KEY=VALUE` lines (`NAME`, `URL`, `COMMIT`, `DESCRIBE`, `DIRTY`) for the git checkout containing TARGET_DIR.
# Env/side effects: requires `git`; reads repository metadata only and writes the provenance record to stdout.
# Errors: returns 2 for missing arguments, 1 when TARGET_DIR is not a usable git checkout or has no origin URL, and logs failures to stderr.
vcs_get_provenance() {
    local target_dir="${1:-}"
    if [[ -z "${target_dir}" ]]; then
        log_error "vcs_get_provenance requires TARGET_DIR"
        return 2
    fi

    vcs__require_git || return $?

    local repo_root
    repo_root="$(git -C "${target_dir}" rev-parse --show-toplevel 2>/dev/null)" || {
        log_error "Not a git checkout: ${target_dir}"
        return 1
    }

    local remote_url
    remote_url="$(vcs__git_remote_url "${repo_root}")" || remote_url=""
    if [[ -z "${remote_url}" ]]; then
        log_error "Git checkout has no origin remote URL: ${repo_root}"
        return 1
    fi

    local commit describe dirty_flag
    commit="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null)" || {
        log_error "Unable to determine current git commit in ${repo_root}"
        return 1
    }
    describe="$(git -C "${repo_root}" describe --tags --dirty --always 2>/dev/null)" || {
        log_error "Unable to describe git checkout at ${repo_root}"
        return 1
    }
    dirty_flag=false
    if vcs__git_is_dirty "${repo_root}"; then
        dirty_flag=true
    fi

    printf 'NAME=%s\n' "$(basename "${repo_root}")"
    printf 'URL=%s\n' "${remote_url}"
    printf 'COMMIT=%s\n' "${commit}"
    printf 'DESCRIBE=%s\n' "${describe}"
    printf 'DIRTY=%s\n' "${dirty_flag}"
}

# write_alloy_repo_info REPO_ROOT
# Write `.alloy_repo_info` at the git repository root for REPO_ROOT using the canonical provenance `KEY=VALUE` format.
# Env/side effects: requires `git`; creates or replaces `<repo>/.alloy_repo_info` when REPO_ROOT is inside a git checkout; does nothing for non-repository paths.
# Errors: returns 2 for missing arguments, otherwise propagates provenance/write failures; non-repository inputs return 0 without writing a file.
write_alloy_repo_info() {
    local repo_root="${1:-}"
    if [[ -z "${repo_root}" ]]; then
        log_error "write_alloy_repo_info requires REPO_ROOT"
        return 2
    fi

    vcs__require_git || return $?

    local resolved_root
    resolved_root="$(git -C "${repo_root}" rev-parse --show-toplevel 2>/dev/null)" || return 0

    local repo_info_path="${resolved_root}/.alloy_repo_info"
    local provenance
    provenance="$(vcs_get_provenance "${resolved_root}")" || return $?
    printf '%s\n' "${provenance}" > "${repo_info_path}"
}
