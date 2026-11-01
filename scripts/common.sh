# Common setup for all the scripts.
# For a script in the same directory, it should be sourced with:
#     source "$( dirname "$0" )/common.sh"
#
# If called from the grisp_limnux_builder repo, a target name is expected
# as the first parameter.

ARG_TARGET="${1:-}"

error() {
    local code="$1"
    shift
    local msg="$*"
    echo "ERROR: $msg ($code)" 1>&2
    exit $code
}

# "readlink -f" implementation for BSD
# This code was extracted from the Elixir shell scripts
readlink_f () {
    cd "$(dirname "$1")" > /dev/null
    filename="$(basename "$1")"
    if [[ -h "$filename" ]]; then
        readlink_f "$(readlink "$filename")"
    else
        echo "$(pwd -P)/$filename"
    fi
}

alloy_abspath() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        return 1
    fi
    if [[ -d "$path" ]]; then
        ( cd "$path" && pwd -P )
    else
        printf '%s/%s\n' "$( cd "$( dirname "$path" )" && pwd -P )" "$( basename "$path" )"
    fi
}

alloy_valid_name() {
    local name="$1"

    case "$name" in
        ""|*/*|*".."*|*[!A-Za-z0-9_.-]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

set_debug_level()
{
    local debug="$1"
    if [[ $debug -eq 0 ]]; then
        set +x
    elif [[ $debug -gt 0 ]]; then
        set -x
    fi
    export GLB_DEBUG="$debug"
}

enter_hidden() {
    if [[ $GLB_DEBUG -gt 0 ]]; then
        set +x
    fi
}

leave_hidden() {
    if [[ $GLB_DEBUG -gt 0 ]]; then
        set -x
    fi
}

read_defconfig_key() {
    enter_hidden
    local config="$1"
    local key="$2"
    echo "$( source $config && echo "${!key}" )"
    leave_hidden
}

trim() {
    local msg="$*"
    echo "$( echo "$msg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' )"
}

append_unique() {
    local var="$1"
    local value="$2"
    local item

    [[ -n "$value" ]] || return 0
    eval 'for item in "${'"$var"'[@]}"; do
        if [[ "$item" == "$value" ]]; then
            return 0
        fi
    done'
    eval "$var+=(\"\$value\")"
}

alloy_split_pathlist() {
    local var="$1"
    local pathlist="$2"
    local item
    local old_ifs="$IFS"

    IFS=:
    for item in $pathlist; do
        if [[ -n "$item" ]]; then
            append_unique "$var" "$item"
        fi
    done
    IFS="$old_ifs"
}

add_to_var() {
    local var="$1"
    local val="$2"
    if [[ -d $val ]]; then
        if [[ -z ${!var} ]]; then
            eval "${var}=\"${val}\""
        elif [[ ":${!var}:" != *":${val}:"* ]]; then
            eval "$var=\"${val}:\$${var}\""
        fi
    fi
}

checkpoint()
{
    local name="$1"
    local dir="$2"
    shift
    shift
    local args=("${@}")
    if [[ ! -f "${dir}/${name}" ]]; then
        "$name" "${args[@]}"
    fi
    touch "${dir}/${name}"
}

# Ensure SDK is installed (rootfs, toolchain, base packages).
# Pass `strict` to require exact source-tree provenance for the current checkout.
install_sdk() {
    local context_mode="${1:-}"
    case "$context_mode" in
        "" | strict) ;;
        *) error 1 "Invalid SDK context mode '$context_mode' (expected strict or omitted)" ;;
    esac
    if [[ ${GLB_IS_SDK:-false} != true ]]; then
        sdk_select "$context_mode"
    fi
    if [[ ! -d $GLB_SDK_DIR ]]; then
        echo "SDK not installed, trying to install it from artefacts..."
        if [[ ! -f "${SDK_SELECTED_ARCHIVE:-}" ]]; then
            error 1 "Selected SDK archive not found: ${SDK_SELECTED_ARCHIVE:-}"
        fi
        if [[ ! -d $GLB_SDK_BASE_DIR ]]; then
            mkdir -p "$GLB_SDK_BASE_DIR"
            chgrp "$USER" "$GLB_SDK_BASE_DIR"
            chmod 775 "$GLB_SDK_BASE_DIR"
        fi
        local members=( )
        if [[ -n ${SDK_SELECTED_ARCHIVE_ROOT:-} ]]; then
            members=( --wildcards "$SDK_SELECTED_ARCHIVE_ROOT/*" )
        fi
        tar -C "$GLB_SDK_BASE_DIR" --strip-components=1 -xzf \
            "$SDK_SELECTED_ARCHIVE" "${members[@]}"
        if [[ ! -d $GLB_SDK_DIR ]]; then
            error 1 "Selected SDK archive did not install the expected directory: $GLB_SDK_DIR"
        fi
    fi
    sdk_load_manifest "$context_mode"
    sdk_verify_context "$context_mode"
    if [[ -n ${SDK_SELECTED_BUILD_ID:-} && $SDK_BUILD_ID != "$SDK_SELECTED_BUILD_ID" ]]; then
        error 1 "Installed SDK identity differs from selected SDK; remove the incomplete installation and retry"
    fi
    local language
    for language in ${SDK_REQUIRED_LANGUAGES:-erlang}; do
        sdk_require_language "$language"
    done
}

alloy_git_vcs_tag() {
    local dir="$1"
    local desc

    if [[ ! -d "$dir" ]]; then
        printf '%s\n' unknown
        return 0
    fi
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '%s\n' unknown
        return 0
    fi
    desc="$(git -C "$dir" describe --tags --always --long 2>/dev/null || true)"
    if [[ -n "$desc" ]]; then
        printf '%s\n' "$desc"
    else
        git -C "$dir" rev-parse --short HEAD 2>/dev/null || printf '%s\n' unknown
    fi
}

alloy_tree_hash() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        printf '%s\n' missing
        return 0
    fi
    python3 - "$dir" <<'PY'
import hashlib
import os
import sys

base = os.path.abspath(sys.argv[1])
skip_dirs = {".git", ".vagrant", "_build", "_cache", "artefacts"}
skip_suffixes = (".md",)
skip_relpaths = {
    "scripts/test-hu-efuse.sh",
}
skip_prefixes = (
    "docs/",
    "scripts/testdata/",
)
digest = hashlib.sha256()

for root, dirs, files in os.walk(base):
    dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
    rel_root = os.path.relpath(root, base)
    for name in sorted(files):
        path = os.path.join(root, name)
        rel = name if rel_root == "." else os.path.join(rel_root, name)
        if rel in skip_relpaths:
            continue
        if rel.endswith(skip_suffixes):
            continue
        if any(rel.startswith(prefix) for prefix in skip_prefixes):
            continue
        digest.update(rel.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        if os.path.islink(path):
            digest.update(b"L")
            digest.update(os.readlink(path).encode("utf-8", "surrogateescape"))
        else:
            digest.update(b"F")
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
        digest.update(b"\0")

print(digest.hexdigest())
PY
}

alloy_file_hash() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        printf '%s\n' missing
        return 0
    fi
    python3 - "$path" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

alloy_external_roots() {
    local roots_var="$1"
    local root
    local abs

    eval "$roots_var=()"
    if declare -p ARG_EXTERNAL_DIRS >/dev/null 2>&1; then
        for root in "${ARG_EXTERNAL_DIRS[@]}"; do
            [[ -n "$root" ]] || continue
            if [[ ! -d "$root" ]]; then
                error 1 "External path is not a directory: $root"
            fi
            abs="$(alloy_abspath "$root")" || error 1 "Cannot resolve external path: $root"
            append_unique "$roots_var" "$abs"
        done
    fi
    if [[ -n "${GRISP_ALLOY_EXTERNAL_PATH:-}" ]]; then
        local env_roots=( )
        alloy_split_pathlist env_roots "$GRISP_ALLOY_EXTERNAL_PATH"
        for root in "${env_roots[@]}"; do
            [[ -n "$root" ]] || continue
            if [[ ! -d "$root" ]]; then
                error 1 "External path is not a directory: $root"
            fi
            abs="$(alloy_abspath "$root")" || error 1 "Cannot resolve external path: $root"
            append_unique "$roots_var" "$abs"
        done
    fi
}

alloy_target_markers_present() {
    local dir="$1"

    [[ -f "$dir/VERSION" ]] &&
        [[ -f "$dir/Config.in" ]] &&
        [[ -f "$dir/defconfig" ]] &&
        [[ -f "$dir/external.desc" ]] &&
        [[ -f "$dir/external.mk" ]]
}

alloy_ramfs_markers_present() {
    local dir="$1"

    [[ -f "$dir/VERSION" ]] &&
        [[ -f "$dir/Config.in" ]] &&
        [[ -f "$dir/defconfig" ]]
}

alloy_component_candidate() {
    local candidates_var="$1"
    local bundle_roots_var="$2"
    local sources_var="$3"
    local dir="$4"
    local bundle_root="$5"
    local source="$6"
    local existing

    dir="$(alloy_abspath "$dir")" || return 0
    bundle_root="$(alloy_abspath "$bundle_root")" || return 0
    if ! alloy_target_markers_present "$dir"; then
        return 0
    fi
    eval 'for existing in "${'"$candidates_var"'[@]}"; do
        if [[ "$existing" == "$dir" ]]; then
            return 0
        fi
    done'
    eval "$candidates_var+=(\"\$dir\")"
    eval "$bundle_roots_var+=(\"\$bundle_root\")"
    eval "$sources_var+=(\"\$source\")"
}

alloy_ramfs_candidate() {
    local candidates_var="$1"
    local bundle_roots_var="$2"
    local sources_var="$3"
    local dir="$4"
    local bundle_root="$5"
    local source="$6"
    local existing

    dir="$(alloy_abspath "$dir")" || return 0
    bundle_root="$(alloy_abspath "$bundle_root")" || return 0
    if ! alloy_ramfs_markers_present "$dir"; then
        return 0
    fi
    eval 'for existing in "${'"$candidates_var"'[@]}"; do
        if [[ "$existing" == "$dir" ]]; then
            return 0
        fi
    done'
    eval "$candidates_var+=(\"\$dir\")"
    eval "$bundle_roots_var+=(\"\$bundle_root\")"
    eval "$sources_var+=(\"\$source\")"
}

alloy_resolve_sdk_paths() {
    local version_path="${GLB_COMMON_SYSTEM_VER}/${GLB_TARGET_NAME}/${GLB_TARGET_SYSTEM_VER}"
    GLB_SDK_DIR="${GLB_SDK_BASE_DIR}/${version_path}${SDK_VARIANT_SUFFIX}"
    GLB_SDK_HOST_DIR="${GLB_SDK_DIR}/host"
    GLB_SDK_FILENAME="${GLB_SDK_NAME}-${GLB_COMMON_SYSTEM_VER}-${GLB_TARGET_NAME}-${GLB_TARGET_SYSTEM_VER}-${HOST_OS}-${HOST_ARCH}${SDK_ARCHIVE_SUFFIX}.tar.gz"
    GLB_SYSTEM_BUILD_DIR="${GLB_BUILD_DIR}/system/${version_path}/${SDK_LANGUAGE_SET}"
}

alloy_resolve_target_context() {
    local target="$1"
    local target_dir_name="system_${target}"
    local external_roots=( )
    local candidates=( )
    local candidate_bundles=( )
    local candidate_sources=( )
    local root
    local count
    local i
    local in_tree_dir

    if ! alloy_valid_name "$target"; then
        error 1 "Invalid target name: $target"
    fi

    alloy_external_roots external_roots
    GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE=""
    for root in "${external_roots[@]}"; do
        if [[ -z "$GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE" ]]; then
            GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE="$root"
        else
            GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE="${GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE}:$root"
        fi

        if [[ "$( basename "$root" )" == "$target_dir_name" ]]; then
            alloy_component_candidate candidates candidate_bundles candidate_sources \
                "$root" "$( dirname "$root" )" external
        fi
        alloy_component_candidate candidates candidate_bundles candidate_sources \
            "$root/$target_dir_name" "$root" external
    done

    count="${#candidates[@]}"
    if [[ "$count" -gt 1 ]]; then
        echo "ERROR: Multiple external target matches for '${target}':" 1>&2
        for ((i = 0; i < count; i += 1)); do
            echo "  ${candidates[$i]}" 1>&2
        done
        error 1 "Refusing ambiguous external target resolution"
    fi

    if [[ "$count" -eq 1 ]]; then
        GLB_TARGET_NAME="$target"
        GLB_TARGET_SYSTEM_DIR="${candidates[0]}"
        GLB_TARGET_BUNDLE_ROOT="${candidate_bundles[0]}"
        GLB_TARGET_SYSTEM_SOURCE="${candidate_sources[0]}"
    else
        in_tree_dir="$GLB_TOP_DIR/$target_dir_name"
        if [[ -d "$in_tree_dir" ]] && alloy_target_markers_present "$in_tree_dir"; then
            GLB_TARGET_NAME="$target"
            GLB_TARGET_SYSTEM_DIR="$in_tree_dir"
            GLB_TARGET_BUNDLE_ROOT="$GLB_TOP_DIR"
            GLB_TARGET_SYSTEM_SOURCE=in-tree
        else
            error 1 "Target ${target} not supported; no ${target_dir_name} found"
        fi
    fi

    GLB_COMMON_SYSTEM_DIR="$GLB_TOP_DIR/system_common"
    GLB_COMMON_SYSTEM_VER="$( cat "${GLB_COMMON_SYSTEM_DIR}/VERSION" )"
    GLB_TARGET_SYSTEM_VER="$( cat "${GLB_TARGET_SYSTEM_DIR}/VERSION" )"
    GLB_COMMON_SYSTEM_VCS="$(alloy_git_vcs_tag "$GLB_COMMON_SYSTEM_DIR")"
    GLB_TARGET_SYSTEM_VCS="$(alloy_git_vcs_tag "$GLB_TARGET_SYSTEM_DIR")"
    GLB_COMMON_SYSTEM_TREE_SHA256="$(alloy_tree_hash "$GLB_COMMON_SYSTEM_DIR")"
    GLB_TARGET_SYSTEM_TREE_SHA256="$(alloy_tree_hash "$GLB_TARGET_SYSTEM_DIR")"
    alloy_resolve_sdk_paths

    if [[ "${GLB_DEBUG:-0}" -gt 0 ]]; then
        echo "Resolved target ${GLB_TARGET_NAME}: ${GLB_TARGET_SYSTEM_DIR} (${GLB_TARGET_SYSTEM_SOURCE})"
        echo "Target bundle root: ${GLB_TARGET_BUNDLE_ROOT}"
        echo "External path: ${GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE:-<none>}"
    fi
}

alloy_resolve_ramfs_context() {
    local flavour="$1"
    local ramfs_dir_name="ramfs_${flavour}"
    local external_roots=( )
    local candidates=( )
    local candidate_bundles=( )
    local candidate_sources=( )
    local root
    local count
    local i
    local in_tree_dir

    if ! alloy_valid_name "$flavour"; then
        error 1 "Invalid ramfs flavour name: $flavour"
    fi

    alloy_external_roots external_roots
    GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE=""
    for root in "${external_roots[@]}"; do
        if [[ -z "$GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE" ]]; then
            GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE="$root"
        else
            GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE="${GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE}:$root"
        fi

        if [[ "$( basename "$root" )" == "$ramfs_dir_name" ]]; then
            alloy_ramfs_candidate candidates candidate_bundles candidate_sources \
                "$root" "$( dirname "$root" )" external
        fi
        alloy_ramfs_candidate candidates candidate_bundles candidate_sources \
            "$root/$ramfs_dir_name" "$root" external
    done

    count="${#candidates[@]}"
    if [[ "$count" -gt 1 ]]; then
        echo "ERROR: Multiple external ramfs matches for '${flavour}':" 1>&2
        for ((i = 0; i < count; i += 1)); do
            echo "  ${candidates[$i]}" 1>&2
        done
        error 1 "Refusing ambiguous external ramfs resolution"
    fi

    if [[ "$count" -eq 1 ]]; then
        GLB_RAMFS_FLAVOUR="$flavour"
        GLB_RAMFS_FLAVOUR_DIR="${candidates[0]}"
        GLB_RAMFS_BUNDLE_ROOT="${candidate_bundles[0]}"
        GLB_RAMFS_FLAVOUR_SOURCE="${candidate_sources[0]}"
    else
        in_tree_dir="$GLB_TOP_DIR/$ramfs_dir_name"
        if [[ -d "$in_tree_dir" ]] && alloy_ramfs_markers_present "$in_tree_dir"; then
            GLB_RAMFS_FLAVOUR="$flavour"
            GLB_RAMFS_FLAVOUR_DIR="$in_tree_dir"
            GLB_RAMFS_BUNDLE_ROOT="$GLB_TOP_DIR"
            GLB_RAMFS_FLAVOUR_SOURCE=in-tree
        else
            error 1 "Ramfs flavour ${flavour} not supported; no ${ramfs_dir_name} found"
        fi
    fi

    GLB_RAMFS_COMMON_DIR="$GLB_TOP_DIR/ramfs_common"
    GLB_RAMFS_COMMON_VER="$( cat "${GLB_RAMFS_COMMON_DIR}/VERSION" )"
    GLB_RAMFS_FLAVOUR_VER="$( cat "${GLB_RAMFS_FLAVOUR_DIR}/VERSION" )"
    GLB_RAMFS_COMMON_VCS="$(alloy_git_vcs_tag "$GLB_RAMFS_COMMON_DIR")"
    GLB_RAMFS_FLAVOUR_VCS="$(alloy_git_vcs_tag "$GLB_RAMFS_FLAVOUR_DIR")"
    GLB_RAMFS_COMMON_TREE_SHA256="$(alloy_tree_hash "$GLB_RAMFS_COMMON_DIR")"
    GLB_RAMFS_FLAVOUR_TREE_SHA256="$(alloy_tree_hash "$GLB_RAMFS_FLAVOUR_DIR")"

    if [[ "${GLB_DEBUG:-0}" -gt 0 ]]; then
        echo "Resolved ramfs ${GLB_RAMFS_FLAVOUR}: ${GLB_RAMFS_FLAVOUR_DIR} (${GLB_RAMFS_FLAVOUR_SOURCE})"
        echo "Ramfs bundle root: ${GLB_RAMFS_BUNDLE_ROOT}"
        echo "External path: ${GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE:-<none>}"
    fi
}

alloy_resolve_toolchain_defconfig() {
    local out_var="$1"
    local target="$2"
    local host_os="$3"
    local host_arch="$4"
    local filename="${target}_${host_os}_${host_arch}_defconfig"
    local external_roots=( )
    local candidates=( )
    local path
    local root
    local i
    local strict_bundle="${ALLOY_STRICT_EXTERNAL_BUNDLE:-false}"

    if [[ -n "${GLB_TARGET_SYSTEM_DIR:-}" ]]; then
        path="${GLB_TARGET_SYSTEM_DIR}/toolchain/configs/${filename}"
        if [[ -f "$path" ]]; then
            append_unique candidates "$(alloy_abspath "$path")"
        fi
    fi

    if [[ "$strict_bundle" == "true" && "${GLB_TARGET_SYSTEM_SOURCE:-}" == "external" ]]; then
        path="${GLB_TARGET_BUNDLE_ROOT}/toolchain/configs/${filename}"
        if [[ -f "$path" ]]; then
            append_unique candidates "$(alloy_abspath "$path")"
        fi
    else
        alloy_external_roots external_roots
        for root in "${external_roots[@]}"; do
            path="${root}/toolchain/configs/${filename}"
            if [[ -f "$path" ]]; then
                append_unique candidates "$(alloy_abspath "$path")"
            fi
        done
    fi

    if [[ "${#candidates[@]}" -gt 1 ]]; then
        echo "ERROR: Multiple external toolchain config matches for '${filename}':" 1>&2
        for path in "${candidates[@]}"; do
            echo "  $path" 1>&2
        done
        error 1 "Refusing ambiguous external toolchain config resolution"
    fi

    if [[ "${#candidates[@]}" -eq 1 ]]; then
        GLB_TOOLCHAIN_DEFCONFIG="${candidates[0]}"
        GLB_TOOLCHAIN_CONFIG_SOURCE=external
    elif [[ "$strict_bundle" == "true" && "${GLB_TARGET_SYSTEM_SOURCE:-}" == "external" ]]; then
        error 1 "Target ${GLB_TARGET_NAME} requires toolchain/configs/${filename} in its external bundle: ${GLB_TARGET_BUNDLE_ROOT}"
    else
        GLB_TOOLCHAIN_DEFCONFIG="${GLB_TOOLCHAIN_DIR}/configs/${filename}"
        GLB_TOOLCHAIN_CONFIG_SOURCE=in-tree
    fi
    GLB_TOOLCHAIN_DEFCONFIG_SHA256="$(alloy_file_hash "$GLB_TOOLCHAIN_DEFCONFIG")"

    eval "$out_var=\"\$GLB_TOOLCHAIN_DEFCONFIG\""
}

alloy_require_target_bundle_component() {
    local component="$1"
    local bundle_root="$2"
    local strict_bundle="${ALLOY_STRICT_EXTERNAL_BUNDLE:-false}"

    if [[ "$strict_bundle" != "true" || "${GLB_TARGET_SYSTEM_SOURCE:-}" != "external" ]]; then
        return 0
    fi
    if [[ "$(alloy_abspath "$bundle_root")" != "$(alloy_abspath "$GLB_TARGET_BUNDLE_ROOT")" ]]; then
        error 1 "Target ${GLB_TARGET_NAME} requires ${component} from its external bundle ${GLB_TARGET_BUNDLE_ROOT}, got ${bundle_root}"
    fi
}

alloy_firmware_misc_provenance() {
    printf 'alloy-provenance-v1:target-source=%s;common-tree-sha256=%s;target-tree-sha256=%s' \
        "${GLB_TARGET_SYSTEM_SOURCE:-}" \
        "${GLB_COMMON_SYSTEM_TREE_SHA256:-}" \
        "${GLB_TARGET_SYSTEM_TREE_SHA256:-}"
}

alloy_sanitize_path_component() {
    local name="$1"

    name="$( printf '%s' "$name" | sed -e 's/[^A-Za-z0-9_.-]/_/g' )"
    if [[ -n "$name" ]]; then
        printf '%s\n' "$name"
    else
        printf '%s\n' external
    fi
}

alloy_vagrant_sync_external_roots() {
    local out_var="$1"
    local external_roots=( )
    local root
    local index
    local guest_parent
    local guest_dir
    local guest_basename
    local rsync_excludes

    eval "$out_var=()"
    alloy_external_roots external_roots
    if [[ "${#external_roots[@]}" -eq 0 ]]; then
        return 0
    fi

    vagrant ssh-config > "${GLB_TOP_DIR}/.vagrant.ssh_config"
    vagrant exec mkdir -p "$GLB_VAGRANT_EXTERNAL_BUILD_DIR"
    rsync_excludes=(
        --exclude='.git/'
        --exclude='.vagrant/'
        --exclude='_build/'
        --exclude='_cache/'
        --exclude='artefacts/'
    )

    index=0
    for root in "${external_roots[@]}"; do
        guest_parent="${GLB_VAGRANT_EXTERNAL_BUILD_DIR}/$( printf '%02d' "$index" )"
        guest_basename="$( alloy_sanitize_path_component "$( basename "$root" )" )"
        guest_dir="${guest_parent}/${guest_basename}"

        vagrant exec mkdir -p "$guest_parent"
        vagrant exec rm -rf "$guest_dir"
        vagrant exec mkdir -p "$guest_dir"
        rsync -qaz --delete "${rsync_excludes[@]}" \
            -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" \
            "${root}/" "vagrant@default:${guest_dir}/"

        append_unique "$out_var" "$guest_dir"
        index=$(( index + 1 ))
    done
}

# OS and architecture detection
BUILD_ARCH="$(uname -m)"
BUILD_OS="$(uname -s)"
case "$BUILD_OS" in
    "CYGWIN_NT-6.1") BUILD_OS="cygwin";;
esac
BUILD_OS="$(echo "$BUILD_OS" | awk '{print tolower($0)}')"
HOST_ARCH="${HOST_ARCH:-$BUILD_ARCH}"
HOST_OS="${HOST_OS:-$BUILD_OS}"

# Command compatibility
case "$BUILD_OS" in
    linux)
        READLINK=readlink
        TAR=tar
        AWK=awk
        ;;
    darwin)
        READLINK=readlink
        TAR=tar
        AWK=awk
        ;;
    cygwin | freebsd)
        READLINK=readlink
        TAR=tar
        AWK=gawk
        ;;
    *)
        error 1 "Unsupported host OS: $BUILD_OS"
        ;;
esac

GLB_SCRIPT_DIR="$(readlink_f "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )"
GLB_TOP_DIR="$( cd "$GLB_SCRIPT_DIR" && cd .. && pwd )"
GLB_VAGRANT_TOP_DIR="/home/vagrant"
source "$GLB_SCRIPT_DIR/sdk-languages.sh"
sdk_languages_init "${ARG_SDK_LANGUAGES:-${GRISP_SDK_LANGUAGES:-erlang,elixir}}" || exit 1
SDK_REQUIRED_LANGUAGES=erlang
if declare -p ARG_SDK_LANGS >/dev/null 2>&1; then
    sdk_requirements_add "${ARG_SDK_LANGS[@]}"
fi
GLB_SDK_NAME="grisp_alloy_sdk"
GLB_SDK_PARENT_DIR="/opt"
GLB_SDK_BASE_DIR="${GLB_SDK_PARENT_DIR}/${GLB_SDK_NAME}"

if [[ $GLB_TOP_DIR == ${GLB_SDK_BASE_DIR}* ]]; then
    # running the sdk version
    GLB_IS_SDK=true
    GLB_SDK_DIR="$GLB_TOP_DIR"
    GLB_SDK_HOST_DIR="$GLB_SDK_DIR/host"
    if [[ -f "$GLB_SDK_DIR/ALLOY-SDK" ]]; then
        source "$GLB_SDK_DIR/ALLOY-SDK"
        GLB_TARGET_NAME="$SDK_TARGET_NAME"
        GLB_COMMON_SYSTEM_VER="$SDK_COMMON_SYSTEM_VERSION"
        GLB_TARGET_SYSTEM_VER="$SDK_TARGET_SYSTEM_VERSION"
        GLB_TARGET_SYSTEM_SOURCE="$SDK_TARGET_SYSTEM_SOURCE"
        GLB_COMMON_SYSTEM_TREE_SHA256="$SDK_COMMON_SYSTEM_TREE_SHA256"
        GLB_TARGET_SYSTEM_TREE_SHA256="$SDK_TARGET_SYSTEM_TREE_SHA256"
        sdk_languages_init "${SDK_LANGUAGES// /,}" || exit 1
    else
        SDK_RELATIVE_PATH="${GLB_TOP_DIR#"$GLB_SDK_BASE_DIR/"}"
        IFS=/ read -r GLB_COMMON_SYSTEM_VER GLB_TARGET_NAME GLB_TARGET_SYSTEM_VER <<< "$SDK_RELATIVE_PATH"
    fi
else
    # running the builder version
    GLB_IS_SDK=false
    GLB_ARTEFACTS_DIR="${GLB_TOP_DIR}/artefacts"
    GLB_VAGRANT_ARTEFACTS_DIR="${GLB_VAGRANT_TOP_DIR}/artefacts"
    GLB_CACHE_DIR="${GLB_TOP_DIR}/_cache"
    GLB_BUILD_DIR="${GLB_TOP_DIR}/_build"
    GLB_VAGRANT_BUILD_DIR="${GLB_VAGRANT_TOP_DIR}/_build"
    GLB_VAGRANT_EXTERNAL_BUILD_DIR="${GLB_VAGRANT_BUILD_DIR}/external"
    GLB_TOOLCHAIN_DIR="${GLB_TOP_DIR}/toolchain"
    GLB_TOOLCHAIN_CACHE_DIR="${GLB_CACHE_DIR}/toolchain"
    GLB_TOOLCHAIN_SCRIPT_DIR="${GLB_TOOLCHAIN_DIR}/scripts"
    GLB_TOOLCHAIN_PATCH_DIR="${GLB_TOOLCHAIN_DIR}/patches"
    GLB_TOOLCHAIN_BUILD_DIR="${GLB_BUILD_DIR}/toolchain"
    GLB_SYSTEM_DIR="${GLB_TOP_DIR}/system_common"
    GLB_SYSTEM_CACHE_DIR="${GLB_CACHE_DIR}/system"
    GLB_SYSTEM_SCRIPT_DIR="${GLB_SYSTEM_DIR}/scripts"
    GLB_SYSTEM_BUILD_DIR="${GLB_BUILD_DIR}/system"
    GLB_PROJECT_BUILD_DIR="${GLB_BUILD_DIR}/project"
    GLB_VAGRANT_PROJECT_BUILD_DIR="${GLB_VAGRANT_BUILD_DIR}/project"
    GLB_FIRMWARE_BUILD_DIR="${GLB_BUILD_DIR}/firmware"
    GLB_VAGRANT_FIRMWARE_BUILD_DIR="${GLB_VAGRANT_BUILD_DIR}/firmware"

    GLB_COMMON_SYSTEM_DIR="$GLB_TOP_DIR/system_common"
    GLB_COMMON_SYSTEM_VER="$( cat "${GLB_COMMON_SYSTEM_DIR}/VERSION" )"
    GLB_COMMON_SYSTEM_VCS="$(alloy_git_vcs_tag "$GLB_COMMON_SYSTEM_DIR")"

    if [[ -n $ARG_TARGET ]]; then
        alloy_resolve_target_context "$ARG_TARGET"
    fi
fi

GLB_DEBUG="${GLB_DEBUG:-0}"
set_debug_level "$GLB_DEBUG"
