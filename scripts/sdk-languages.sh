# shellcheck shell=bash
# SDK metadata and language selection.
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh" || return $?
SDK_CONTEXT_MAP=(
    SDK_TARGET_NAME:GLB_TARGET_NAME
    SDK_COMMON_SYSTEM_VERSION:GLB_COMMON_SYSTEM_VER
    SDK_TARGET_SYSTEM_VERSION:GLB_TARGET_SYSTEM_VER
    SDK_TARGET_SYSTEM_SOURCE:GLB_TARGET_SYSTEM_SOURCE
    SDK_COMMON_SYSTEM_TREE_SHA256:GLB_COMMON_SYSTEM_TREE_SHA256
    SDK_TARGET_SYSTEM_TREE_SHA256:GLB_TARGET_SYSTEM_TREE_SHA256
)
SDK_DIAGNOSTIC_MAP=(
    SDK_TARGET_SYSTEM_DIR:GLB_TARGET_SYSTEM_DIR
    SDK_TARGET_BUNDLE_ROOT:GLB_TARGET_BUNDLE_ROOT
    SDK_TARGET_SYSTEM_VCS:GLB_TARGET_SYSTEM_VCS
    SDK_COMMON_SYSTEM_VCS:GLB_COMMON_SYSTEM_VCS
    SDK_RAMFS_FLAVOUR:GLB_RAMFS_FLAVOUR
    SDK_RAMFS_FLAVOUR_DIR:GLB_RAMFS_FLAVOUR_DIR
    SDK_RAMFS_BUNDLE_ROOT:GLB_RAMFS_BUNDLE_ROOT
    SDK_RAMFS_FLAVOUR_SOURCE:GLB_RAMFS_FLAVOUR_SOURCE
    SDK_RAMFS_FLAVOUR_VERSION:GLB_RAMFS_FLAVOUR_VER
    SDK_RAMFS_FLAVOUR_VCS:GLB_RAMFS_FLAVOUR_VCS
    SDK_RAMFS_FLAVOUR_TREE_SHA256:GLB_RAMFS_FLAVOUR_TREE_SHA256
    SDK_RAMFS_COMMON_VERSION:GLB_RAMFS_COMMON_VER
    SDK_RAMFS_COMMON_VCS:GLB_RAMFS_COMMON_VCS
    SDK_RAMFS_COMMON_TREE_SHA256:GLB_RAMFS_COMMON_TREE_SHA256
    SDK_EXTERNAL_PATH:GLB_ALLOY_EXTERNAL_PATH_EFFECTIVE
    SDK_TOOLCHAIN_DEFCONFIG:GLB_TOOLCHAIN_DEFCONFIG
    SDK_TOOLCHAIN_CONFIG_SOURCE:GLB_TOOLCHAIN_CONFIG_SOURCE
    SDK_STRICT_EXTERNAL_BUNDLE:ALLOY_STRICT_EXTERNAL_BUNDLE
)
SDK_METADATA_KEYS=(
    SDK_MANIFEST_VERSION
    SDK_LANGUAGES
    SDK_LANGUAGE_SET
    SDK_BUILD_ID
    SDK_HOST_OS
    SDK_HOST_ARCH
    SDK_RUST_TARGET
    SDK_RUST_VERSION
    SDK_CARGO_VERSION
    SDK_NATIVE_RUNTIME
    SDK_TOOLCHAIN_CONFIG_SHA256
)
for sdk_mapping in "${SDK_CONTEXT_MAP[@]}" "${SDK_DIAGNOSTIC_MAP[@]}"; do
    SDK_METADATA_KEYS+=("${sdk_mapping%%:*}")
done
unset sdk_mapping

# Clean up the caller's local sdk_work directory before reporting an error.
_sdk_fail() {
    [[ -z ${sdk_work:-} ]] || rm -rf "$sdk_work"
    error 1 "$*"
}

# Import literal records into the META_* locals declared by the calling function.
# Only the record tool's quoted output is sourced; the input file is parsed data.
_sdk_import_metadata() {
    local file="$1"
    local key
    local options=()
    local bindings=()
    shift
    for key in "$@"; do
        options+=(--key "$key")
        bindings+=(--optional-bind "META_$key" "/$key")
    done
    alloy_tool_record import-assignments "$file" "${options[@]}" \
        --output "$sdk_work/record.json" || _sdk_fail "Cannot read SDK metadata: $file"
    alloy_tool_record get "$sdk_work/record.json" "${bindings[@]}" \
        --format sh --output "$sdk_work/record.sh" || _sdk_fail "Invalid SDK metadata: $file"
    source "$sdk_work/record.sh"
}

_sdk_read_metadata() { _sdk_import_metadata "$1" "${SDK_METADATA_KEYS[@]}"; }

# Validate the caller's META_SDK_* locals, setting its local reason on failure.
_sdk_metadata_reason() {
    local context_mode="${1:-}"
    local language
    local languages="" canonical=""
    local language_items=()
    [[ $META_SDK_MANIFEST_VERSION == 1 ]] || reason="unsupported SDK manifest version"
    [[ $META_SDK_TARGET_NAME == "$GLB_TARGET_NAME" && $META_SDK_COMMON_SYSTEM_VERSION == "$GLB_COMMON_SYSTEM_VER" &&
        $META_SDK_TARGET_SYSTEM_VERSION == "$GLB_TARGET_SYSTEM_VER" ]] ||
        reason="SDK target/system versions differ"
    read -r -a language_items <<< "$META_SDK_LANGUAGES"
    for language in "${language_items[@]}"; do
        languages="${languages:+$languages,}$language"
    done
    canonical="$(sdk_languages_canonical "$languages" 2> /dev/null)" ||
        reason="invalid SDK language capabilities"
    [[ ${canonical//,/-} == "$META_SDK_LANGUAGE_SET" && $canonical == "$languages" ]] ||
        reason="invalid SDK language capabilities"
    [[ $META_SDK_BUILD_ID =~ ^[0-9a-f]{64}$ ]] || reason="invalid SDK build ID"
    [[ -z ${SDK_REQUIRED_BUILD_ID:-} || $META_SDK_BUILD_ID == "$SDK_REQUIRED_BUILD_ID" ]] ||
        reason="different SDK build ID"
    for language in ${SDK_REQUIRED_LANGUAGES:-erlang}; do
        case " $META_SDK_LANGUAGES " in
            *" $language "*) ;;
            *) reason="missing language support: $language" ;;
        esac
    done
    [[ $META_SDK_HOST_ARCH == "$HOST_ARCH" ]] || reason="different SDK host architecture"
    [[ $META_SDK_HOST_OS == "$HOST_OS" ]] || reason="different SDK host OS"
    [[ $META_SDK_TARGET_SYSTEM_SOURCE == "$GLB_TARGET_SYSTEM_SOURCE" && -n $META_SDK_COMMON_SYSTEM_TREE_SHA256 &&
        -n $META_SDK_TARGET_SYSTEM_TREE_SHA256 ]] ||
        reason="SDK provenance missing or differs; rebuild the SDK"
    if [[ $context_mode == strict ]]; then
        [[ $META_SDK_COMMON_SYSTEM_TREE_SHA256 == "$GLB_COMMON_SYSTEM_TREE_SHA256" ]] ||
            reason="provenance differs: SDK_COMMON_SYSTEM_TREE_SHA256"
        [[ $META_SDK_TARGET_SYSTEM_TREE_SHA256 == "$GLB_TARGET_SYSTEM_TREE_SHA256" ]] ||
            reason="provenance differs: SDK_TARGET_SYSTEM_TREE_SHA256"
    fi
    case " $META_SDK_LANGUAGES " in
        *' rust '*)
            [[ -n $META_SDK_RUST_TARGET && -n $META_SDK_RUST_VERSION && -n $META_SDK_CARGO_VERSION &&
                $META_SDK_NATIVE_RUNTIME == erlinit-native-v1 ]] ||
                reason="incomplete Rust SDK contract; rebuild the SDK"
            ;;
    esac
}

# Add a candidate to sdk_select's local arrays, deduplicating by build identity.
_sdk_consider() {
    local path="$1"
    local installed="$2"
    local archive_root="$3"
    local context_mode="${4:-}"
    local reason=""
    local index canonical
    _sdk_metadata_reason "$context_mode"
    if [[ -n $reason ]]; then
        rejected="${rejected}  $path: $reason"$'\n'
        return
    fi
    canonical="${META_SDK_LANGUAGES// /,}"
    index=0
    while [[ $index -lt ${#ids[@]} && ${ids[index]} != "$META_SDK_BUILD_ID" ]]; do
        index=$((index + 1))
    done
    if [[ $index -eq ${#ids[@]} ]]; then
        ids+=("$META_SDK_BUILD_ID")
        sets+=("$canonical")
        dirs+=("")
        archives+=("")
        roots+=("")
    fi
    [[ ${sets[index]} == "$canonical" ]] || _sdk_fail "Conflicting capabilities for SDK $META_SDK_BUILD_ID"
    if [[ $installed == true ]]; then
        [[ -n ${dirs[index]} ]] || dirs[index]="$path"
    elif [[ -z ${archives[index]} ]]; then
        archives[index]="$path"
        roots[index]="$archive_root"
    fi
}

_sdk_display_location() {
    local path="$1"
    case "$path" in
        "$GLB_ARTEFACTS_DIR"/*)
            printf 'artefacts/%s' "${path#"$GLB_ARTEFACTS_DIR"/}"
            ;;
        *) printf '%s' "$path" ;;
    esac
}

_sdk_candidate_details() {
    local languages="$1"
    local installed="$2"
    local archive="$3"
    printf '  [%s]:\n' "$languages"
    if [[ -n $archive ]]; then
        printf '    available from %s\n' "$(_sdk_display_location "$archive")"
    fi
    if [[ -n $installed ]]; then
        printf '    installed at %s\n' "$installed"
    fi
}

# Compatibility with SDK common-system 0.2.0.
# Remove these adapters, discovery branches and tests when 0.2.0 support ends.
_sdk_read_v020_context() {
    local directory="$1"
    local mapping key old_key
    local old_keys=(GRISP_COMMON_SYSTEM_VER GRISP_TARGET_NAME GRISP_TARGET_SYSTEM_VER)
    for mapping in "${SDK_CONTEXT_MAP[@]}"; do
        old_keys+=("${mapping#*:}")
    done
    for key in "${old_keys[@]}"; do
        local "META_$key="
    done
    for key in "${SDK_METADATA_KEYS[@]}"; do
        printf -v "META_$key" '%s' ""
    done
    if [[ -f $directory/ALLOY-RESOLVER-CONTEXT ]]; then
        _sdk_import_metadata "$directory/ALLOY-RESOLVER-CONTEXT" "${old_keys[@]}"
        for mapping in "${SDK_CONTEXT_MAP[@]}"; do
            key="META_${mapping%%:*}"
            old_key="META_${mapping#*:}"
            [[ -n ${!old_key} ]] || _sdk_fail "Incomplete 0.2.0 SDK context: ${mapping#*:}"
            printf -v "$key" '%s' "${!old_key}"
        done
    else
        # Pre-resolver SDKs have VERSIONS and the same fixed installation layout.
        if [[ -f $directory/VERSIONS ]]; then
            _sdk_import_metadata "$directory/VERSIONS" "${old_keys[@]}"
            for key in META_GRISP_COMMON_SYSTEM_VER META_GRISP_TARGET_NAME META_GRISP_TARGET_SYSTEM_VER; do
                [[ -n ${!key} ]] || _sdk_fail "Incomplete 0.2.0 SDK VERSIONS: ${key#META_}"
            done
        fi
        META_SDK_COMMON_SYSTEM_VERSION="${META_GRISP_COMMON_SYSTEM_VER:-0.2.0}"
        META_SDK_TARGET_NAME="${META_GRISP_TARGET_NAME:-$GLB_TARGET_NAME}"
        META_SDK_TARGET_SYSTEM_VERSION="${META_GRISP_TARGET_SYSTEM_VER:-$GLB_TARGET_SYSTEM_VER}"
        META_SDK_TARGET_SYSTEM_SOURCE=in-tree
        [[ $GLB_TARGET_SYSTEM_SOURCE != external ]] ||
            _sdk_fail "External 0.2.0 SDK requires ALLOY-RESOLVER-CONTEXT"
    fi
    [[ $META_SDK_COMMON_SYSTEM_VERSION == 0.2.0 && $META_SDK_TARGET_NAME == "$GLB_TARGET_NAME" &&
        $META_SDK_TARGET_SYSTEM_VERSION == "$GLB_TARGET_SYSTEM_VER" &&
        $META_SDK_TARGET_SYSTEM_SOURCE == "$GLB_TARGET_SYSTEM_SOURCE" ]] ||
        _sdk_fail "0.2.0 SDK target/version/source mismatch"
    if [[ $GLB_TARGET_SYSTEM_SOURCE == external ]]; then
        [[ $META_SDK_TARGET_SYSTEM_TREE_SHA256 == "$GLB_TARGET_SYSTEM_TREE_SHA256" ]] ||
            _sdk_fail "0.2.0 SDK external target provenance differs"
    fi
    META_SDK_LANGUAGES='erlang elixir'
    META_SDK_LANGUAGE_SET='erlang-elixir'
}

_sdk_check_v020_host() {
    local tool
    local SDK_TOOL_ARCH
    for tool in "$GLB_SDK_HOST_DIR/bin/fwup" "$GLB_SDK_HOST_DIR/bin/mksquashfs"; do
        [[ -f $tool ]] || continue
        alloy_tool_elf_check header "$tool" > "$sdk_work/header.json" ||
            _sdk_fail "Cannot inspect 0.2.0 SDK host tools"
        alloy_tool_record get "$sdk_work/header.json" --bind SDK_TOOL_ARCH /architecture \
            --format sh --output "$sdk_work/header.sh" || _sdk_fail "Invalid 0.2.0 SDK host tool"
        source "$sdk_work/header.sh"
        [[ $HOST_OS == linux && $SDK_TOOL_ARCH == "$HOST_ARCH" ]] ||
            _sdk_fail "0.2.0 SDK host architecture differs"
        return 0
    done
    _sdk_fail "Cannot identify 0.2.0 SDK host architecture"
}

_sdk_select_v020() {
    local quiet="${1:-false}"
    [[ -z ${SDK_REQUIRED_BUILD_ID:-} && ${SDK_REQUIRED_COMMON_VERSION:-0.2.0} == 0.2.0 ]] || return 1
    case " ${SDK_REQUIRED_LANGUAGES:-erlang} " in
        *' rust '*) return 1 ;;
    esac
    local directory="$GLB_SDK_BASE_DIR/0.2.0/$GLB_TARGET_NAME/$GLB_TARGET_SYSTEM_VER"
    local archive="$GLB_ARTEFACTS_DIR/$GLB_SDK_NAME-0.2.0-$GLB_TARGET_NAME-$GLB_TARGET_SYSTEM_VER-$HOST_OS-$HOST_ARCH.tar.gz"
    local root="$GLB_SDK_NAME/0.2.0/$GLB_TARGET_NAME/$GLB_TARGET_SYSTEM_VER"
    [[ -d $directory || -f $archive ]] || return 1
    SDK_SELECTED_DIR="$directory"
    SDK_SELECTED_ARCHIVE=""
    SDK_SELECTED_ARCHIVE_ROOT=""
    if [[ -d $directory ]]; then
        [[ ! -f $directory/ALLOY-SDK ]] || _sdk_fail "Unexpected new manifest in 0.2.0 SDK"
        _sdk_read_v020_context "$directory"
        GLB_SDK_HOST_DIR="$directory/host"
        _sdk_check_v020_host
    else
        alloy_tool_tar read "$archive" \
            --optional-member context "$root/ALLOY-RESOLVER-CONTEXT" --optional-member VERSIONS "$root/VERSIONS" \
            --optional-member manifest "$root/ALLOY-SDK" --common-parent --first-match \
            --output-dir "$sdk_work" --index "$sdk_work/index.json" --cache-dir "$GLB_CACHE_DIR/sdk-metadata" ||
            _sdk_fail "Cannot inspect 0.2.0 SDK archive"
        [[ ! -e $sdk_work/manifest ]] || _sdk_fail "Unexpected new manifest in 0.2.0 SDK"
        [[ ! -f $sdk_work/context ]] || mv "$sdk_work/context" "$sdk_work/ALLOY-RESOLVER-CONTEXT"
        _sdk_read_v020_context "$sdk_work"
        [[ ! -e $directory ]] || _sdk_fail "Incomplete SDK installation at $directory"
        SDK_SELECTED_ARCHIVE="$archive"
        SDK_SELECTED_ARCHIVE_ROOT="$root"
    fi
    SDK_SELECTED_BUILD_ID=""
    SDK_SELECTED_LANGUAGES=erlang,elixir
    SDK_COMPAT_V020=true
    sdk_languages_init "$SDK_SELECTED_LANGUAGES" || return 1
    GLB_SDK_DIR="$directory"
    GLB_SDK_HOST_DIR="$directory/host"
    [[ $quiet == true ]] ||
        echo "Selected SDK: $directory (0.2.0 compatibility; languages: erlang,elixir)"
}

# Select one installed SDK or archive satisfying SDK_REQUIRED_* and target context.
# Optional `strict` mode also requires exact common/target source-tree hashes.
sdk_select() {
    local context_mode="${1:-}"
    local sdk_work manifest directory path key index
    local archive_root root_name root_common root_target root_version extra
    local SDK_MEMBER
    local rejected=""
    local ids=()
    local sets=()
    local dirs=()
    local archives=()
    local roots=()
    local occupied=()
    # Metadata bindings are local to selection and shared with its helper calls.
    for key in "${SDK_METADATA_KEYS[@]}"; do
        local "META_$key"
    done
    sdk_work="$(mktemp -d)" || error 1 "Cannot create SDK selection workspace"
    SDK_COMPAT_V020=false
    SDK_SELECTED_ARCHIVE_ROOT=""
    # A 0.2.0 version pin excludes current-version candidates, leaving only
    # the compatibility SDK as a possible match.
    if [[ -n ${SDK_REQUIRED_COMMON_VERSION:-} &&
        $SDK_REQUIRED_COMMON_VERSION != "$GLB_COMMON_SYSTEM_VER" ]]; then
        if _sdk_select_v020; then
            rm -rf "$sdk_work"
            return 0
        fi
        _sdk_fail "No matching 0.2.0 SDK available"
    fi
    for manifest in "$GLB_SDK_BASE_DIR/$GLB_COMMON_SYSTEM_VER/$GLB_TARGET_NAME"/*/ALLOY-SDK; do
        [[ -f $manifest ]] || continue
        directory="${manifest%/ALLOY-SDK}"
        _sdk_read_metadata "$manifest"
        occupied+=("$(cd "$directory" && pwd -P)")
        _sdk_consider "$directory" true "" "$context_mode"
    done
    local prefix="$GLB_SDK_NAME-$GLB_COMMON_SYSTEM_VER-$GLB_TARGET_NAME-$GLB_TARGET_SYSTEM_VER-$HOST_OS-$HOST_ARCH"
    for path in "$GLB_ARTEFACTS_DIR/$prefix"*.tar.gz; do
        [[ -f $path ]] || continue
        case "${path#"$GLB_ARTEFACTS_DIR/$prefix"}" in
            .tar.gz | -*) ;;
            *) continue ;;
        esac
        rm -f "$sdk_work/manifest" "$sdk_work/provenance"
        alloy_tool_tar read "$path" --member manifest '*/ALLOY-SDK' --first-match \
            --output-dir "$sdk_work" --index "$sdk_work/index.json" --cache-dir "$GLB_CACHE_DIR/sdk-metadata" ||
            _sdk_fail "Cannot inspect SDK archive: $path"
        alloy_tool_record get "$sdk_work/index.json" \
            --bind SDK_MEMBER /members/manifest/member --format sh --output "$sdk_work/member.sh" ||
            _sdk_fail "Cannot read SDK archive root"
        source "$sdk_work/member.sh"
        archive_root="${SDK_MEMBER%/*}"
        IFS=/ read -r root_name root_common root_target root_version extra <<< "$archive_root"
        [[ $root_name == "$GLB_SDK_NAME" && $root_common == "$GLB_COMMON_SYSTEM_VER" && $root_target == "$GLB_TARGET_NAME" &&
            -n $root_version && -z $extra ]] || _sdk_fail "Unexpected SDK archive root in $path"
        _sdk_read_metadata "$sdk_work/manifest"
        META_SDK_HOST_ARCH="${META_SDK_HOST_ARCH:-$HOST_ARCH}"
        META_SDK_HOST_OS="${META_SDK_HOST_OS:-$HOST_OS}"
        _sdk_consider "$path" false "$archive_root" "$context_mode"
    done
    if [[ ${#ids[@]} -gt 0 ]] && _sdk_select_v020 true; then
        local details=""
        local legacy_installed=""
        local legacy_archive="$GLB_ARTEFACTS_DIR/$GLB_SDK_NAME-0.2.0-$GLB_TARGET_NAME-$GLB_TARGET_SYSTEM_VER-$HOST_OS-$HOST_ARCH.tar.gz"
        local candidate_details
        [[ ! -d $SDK_SELECTED_DIR ]] || legacy_installed="$SDK_SELECTED_DIR"
        [[ -f $SDK_SELECTED_ARCHIVE ]] && legacy_archive="$SDK_SELECTED_ARCHIVE"
        [[ -f $legacy_archive ]] || legacy_archive=""
        for ((index = 0; index < ${#ids[@]}; index++)); do
            candidate_details="$(_sdk_candidate_details \
                "${sets[index]}" "${dirs[index]}" "${archives[index]}")"
            details+="$candidate_details"$'\n'
        done
        candidate_details="$(_sdk_candidate_details \
            erlang,elixir "$legacy_installed" "$legacy_archive")"
        details+="$candidate_details"$'\n'
        _sdk_fail "Ambiguous SDK selection: multiple SDKs support the required languages."$'\n'"${details}Narrow SDK requirements where supported, or keep only the intended SDK available."
    fi
    if [[ ${#ids[@]} -eq 0 ]] && _sdk_select_v020; then
        rm -rf "$sdk_work"
        return 0
    fi
    if [[ ${#ids[@]} -eq 0 ]]; then
        _sdk_fail "No SDK supports requested languages '${SDK_REQUIRED_LANGUAGES// /,}' for $GLB_TARGET_NAME${SDK_REQUIRED_BUILD_ID:+ with build ID $SDK_REQUIRED_BUILD_ID}. Build a matching SDK first."$'\n'"$rejected"
    elif [[ ${#ids[@]} -gt 1 ]]; then
        local details=""
        local candidate_details
        for ((index = 0; index < ${#ids[@]}; index++)); do
            candidate_details="$(_sdk_candidate_details \
                "${sets[index]}" "${dirs[index]}" "${archives[index]}")"
            details+="$candidate_details"$'\n'
        done
        _sdk_fail "Ambiguous SDK selection: multiple SDKs support the required languages."$'\n'"${details}Narrow SDK requirements where supported, or keep only the intended SDK available."
    fi
    SDK_SELECTED_BUILD_ID="${ids[0]}"
    SDK_SELECTED_LANGUAGES="${sets[0]}"
    SDK_SELECTED_ARCHIVE=""
    SDK_SELECTED_DIR="${dirs[0]}"
    if [[ -z $SDK_SELECTED_DIR ]]; then
        SDK_SELECTED_ARCHIVE="${archives[0]}"
        SDK_SELECTED_DIR="${GLB_SDK_BASE_DIR%/*}/${roots[0]}"
        for directory in "${occupied[@]}"; do
            [[ $directory != "$SDK_SELECTED_DIR" ]] ||
                _sdk_fail "Selected SDK would overwrite a different installed SDK at $directory; move it aside first"
        done
        [[ ! -e $SDK_SELECTED_DIR ]] ||
            _sdk_fail "Incomplete SDK installation at $SDK_SELECTED_DIR; move it aside before retrying"
    fi
    rm -rf "$sdk_work"
    sdk_languages_init "$SDK_SELECTED_LANGUAGES" || exit 1
    alloy_resolve_sdk_paths
    GLB_SDK_DIR="$SDK_SELECTED_DIR"
    GLB_SDK_HOST_DIR="$GLB_SDK_DIR/host"
    echo "Selected SDK: $GLB_SDK_DIR (languages: $GRISP_SDK_LANGUAGES; build: $SDK_SELECTED_BUILD_ID)"
}

sdk_languages_canonical() {
    local selection="$1"
    local item
    local erlang=false elixir=false rust=false
    local seen=","
    local language_items=()
    case "$selection" in
        "" | ,* | *, | *,,* | *$'\n'*)
            echo "ERROR: Invalid SDK language set '$selection'" >&2
            return 1
            ;;
    esac
    IFS=, read -r -a language_items <<< "$selection"
    for item in "${language_items[@]}"; do
        case "$seen" in
            *",$item,"*)
                echo "ERROR: Duplicate SDK language '$item'" >&2
                return 1
                ;;
        esac
        case "$item" in
            erlang) erlang=true ;;
            elixir) elixir=true ;;
            rust) rust=true ;;
            *)
                echo "ERROR: Unknown SDK language '$item'" >&2
                return 1
                ;;
        esac
        seen="${seen}${item},"
    done
    if [[ $erlang != true ]]; then
        echo "ERROR: Every Alloy SDK requires erlang (optional languages: elixir, rust)" >&2
        return 1
    fi
    printf erlang
    [[ $elixir != true ]] || printf ',elixir'
    [[ $rust != true ]] || printf ',rust'
    printf '\n'
}

sdk_languages_init() {
    GRISP_SDK_LANGUAGES="$(sdk_languages_canonical "$1")" || return 1
    SDK_LANGUAGE_SET="${GRISP_SDK_LANGUAGES//,/-}"
    SDK_VARIANT_SUFFIX=""
    if [[ $SDK_LANGUAGE_SET != erlang-elixir ]]; then
        SDK_VARIANT_SUFFIX="-langs-${SDK_LANGUAGE_SET}"
    fi
    # Keep installed paths stable; new SDK archive names show every language.
    SDK_ARCHIVE_SUFFIX="-${GRISP_SDK_LANGUAGES//,/_}"
    export GRISP_SDK_LANGUAGES
}

sdk_requirements_add() {
    local language
    SDK_REQUIRED_LANGUAGES="${SDK_REQUIRED_LANGUAGES:-erlang}"
    for language in "$@"; do
        case "$language" in
            erlang | elixir | rust) ;;
            *) error 1 "Unknown SDK language requirement '$language' (valid: erlang, elixir, rust)" ;;
        esac
        case " $SDK_REQUIRED_LANGUAGES " in
            *" $language "*) ;;
            *) SDK_REQUIRED_LANGUAGES="$SDK_REQUIRED_LANGUAGES $language" ;;
        esac
    done
}

sdk_language_enabled() {
    case ",${GRISP_SDK_LANGUAGES}," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Populate SDK_* globals from the selected SDK's manifest or 0.2.0 context.
sdk_load_manifest() {
    local context_mode="${1:-}"
    local sdk_work key value
    local reason=""
    local wanted="$GRISP_SDK_LANGUAGES"
    for key in "${SDK_METADATA_KEYS[@]}"; do
        local "META_$key="
    done
    sdk_work="$(mktemp -d)" || error 1 "Cannot create SDK metadata workspace"
    if [[ -f $GLB_SDK_DIR/ALLOY-SDK ]]; then
        SDK_COMPAT_V020=false
        _sdk_read_metadata "$GLB_SDK_DIR/ALLOY-SDK"
        _sdk_metadata_reason "$context_mode"
        [[ -z $reason ]] || _sdk_fail "Invalid SDK: $reason"
        [[ ${META_SDK_LANGUAGES// /,} == "$wanted" ]] ||
            _sdk_fail "SDK language set does not match selected '$wanted'"
    else
        [[ ${SDK_COMPAT_V020:-false} == true || ${GLB_COMMON_SYSTEM_VER:-} == 0.2.0 ]] ||
            _sdk_fail "SDK manifest missing; rebuild the SDK"
        _sdk_read_v020_context "$GLB_SDK_DIR"
        _sdk_check_v020_host
        SDK_COMPAT_V020=true
        # The selected 0.2.0 SDK is the frozen runtime; retain builder VCS separately.
        GLB_COMMON_SYSTEM_VER=0.2.0
        GLB_COMMON_SYSTEM_TREE_SHA256="$META_SDK_COMMON_SYSTEM_TREE_SHA256"
        GLB_TARGET_SYSTEM_TREE_SHA256="$META_SDK_TARGET_SYSTEM_TREE_SHA256"
    fi
    for key in "${SDK_METADATA_KEYS[@]}"; do
        value="META_$key"
        printf -v "$key" '%s' "${!value}"
    done
    SDK_SUPPORTED_LANGUAGES="$SDK_LANGUAGES"
    rm -rf "$sdk_work"
}

# Verify target/version/source context; strict also checks source tree hashes.
sdk_verify_context() {
    [[ $SDK_TARGET_NAME == "$GLB_TARGET_NAME" && $SDK_TARGET_SYSTEM_VERSION == "$GLB_TARGET_SYSTEM_VER" &&
        $SDK_COMMON_SYSTEM_VERSION == "$GLB_COMMON_SYSTEM_VER" && $SDK_TARGET_SYSTEM_SOURCE == "$GLB_TARGET_SYSTEM_SOURCE" ]] ||
        error 1 "SDK target/version/source context differs"
    if [[ ${1:-} == strict ]]; then
        [[ $SDK_COMMON_SYSTEM_TREE_SHA256 == "$GLB_COMMON_SYSTEM_TREE_SHA256" &&
            $SDK_TARGET_SYSTEM_TREE_SHA256 == "$GLB_TARGET_SYSTEM_TREE_SHA256" ]] ||
            error 1 "SDK source provenance differs"
    fi
}

sdk_require_language() {
    case " $SDK_SUPPORTED_LANGUAGES " in
        *" $1 "*) return 0 ;;
        *) error 1 "Language '$1' not supported by the SDK (languages: $SDK_SUPPORTED_LANGUAGES); build an SDK with --enable-$1" ;;
    esac
}

sdk_language_config() {
    if sdk_language_enabled elixir; then
        echo 'BR2_PACKAGE_HOST_ELIXIR=y'
    else
        echo '# BR2_PACKAGE_HOST_ELIXIR is not set'
    fi
    if sdk_language_enabled rust; then
        echo 'BR2_PACKAGE_HOST_RUSTC=y'
        echo 'BR2_PACKAGE_HOST_RUST_BIN=y'
    else
        echo '# BR2_PACKAGE_HOST_RUSTC is not set'
    fi
}

sdk_check_language_config() {
    local config="$1"
    local key
    grep -q '^BR2_PACKAGE_ERLANG=y$' "$config" || error 1 "Every Alloy SDK requires target Erlang"
    for key in elixir rust; do
        if sdk_language_enabled "$key"; then
            case "$key" in
                elixir) key=BR2_PACKAGE_HOST_ELIXIR ;;
                rust) key=BR2_PACKAGE_HOST_RUST_BIN ;;
            esac
            grep -q "^${key}=y$" "$config" ||
                error 1 "Buildroot cannot provide requested SDK capability: $key"
        fi
    done
    if sdk_language_enabled rust; then
        grep -q '^BR2_PACKAGE_HOST_RUSTC_TARGET_ARCH_SUPPORTS=y$' "$config" ||
            error 1 "Buildroot cannot provide Rust std for the selected target"
    fi
    if ! sdk_language_enabled elixir && grep -q '^BR2_PACKAGE_HOST_ELIXIR=y$' "$config"; then
        error 1 "Target configuration requires Elixir despite --disable-elixir"
    fi
}

_sdk_tool() {
    local directory
    for directory in "$GLB_SDK_HOST_DIR/bin" "$GLB_SDK_HOST_DIR/usr/bin"; do
        if [[ -x $directory/$1 ]]; then
            printf '%s\n' "$directory/$1"
            return
        fi
    done
    _sdk_fail "SDK tool missing: $1"
}

_sdk_output() {
    case "${1##*/}" in
        erl | elixir) env -u ERL_LIBS -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS -u MIX_TARGET \
            PATH="$GLB_SDK_HOST_DIR/bin:$GLB_SDK_HOST_DIR/usr/bin:$PATH" "$@" ;;
        *) "$@" ;;
    esac
}

# Append an identity/diagnostic field to sdk_write_manifest's local workspace.
_sdk_field() { printf '%s\0%s\0' "/$1" "$2" >> "$sdk_work/cap.fields"; }

# Inspect built host/target tools and write the selected SDK's ALLOY-SDK record.
sdk_write_manifest() {
    local sdk_work sdk tool key value line otp details target libc sysroot
    local version host init_hash build_id
    local gcc=""
    local config_arch="" config_abi="" config_glibc="" config_support=""
    local found=false
    sdk_work="$(mktemp -d)" || error 1 "Cannot create SDK metadata workspace"
    sdk="$(cd "$GLB_SDK_DIR" && pwd -P)" || _sdk_fail "SDK directory missing"
    : > "$sdk_work/cap.fields"
    : > "$sdk_work/config.fields"
    for tool in erl erlc rebar3 mksquashfs fwup; do
        _sdk_tool "$tool" > /dev/null || _sdk_fail "Missing SDK $tool"
    done
    for target in "$sdk/staging/usr/lib/erlang"/erts-*; do
        [[ ! -d $target ]] || found=true
    done
    [[ $found == true ]] || _sdk_fail "SDK target ERTS missing"
    for tool in "$GLB_SDK_HOST_DIR/bin"/*-gcc; do
        [[ -f $tool ]] || continue
        [[ -z $gcc ]] || _sdk_fail "SDK must contain exactly one target GCC driver"
        gcc="$tool"
    done
    [[ -n $gcc ]] || _sdk_fail "SDK cross-compiler missing"
    while IFS= read -r line || [[ -n $line ]]; do
        case "$line" in
            BR2_*=*) ;;
            *) continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        while [[ $value == \"* ]]; do
            value="${value#\"}"
        done
        while [[ $value == *\" ]]; do
            value="${value%\"}"
        done
        case "$key" in
            BR2_TOOLCHAIN_USES_GLIBC) config_glibc="$value" ;;
            BR2_PACKAGE_HOST_RUSTC_ARCH) config_arch="$value" ;;
            BR2_PACKAGE_HOST_RUSTC_ABI) config_abi="$value" ;;
            BR2_PACKAGE_HOST_RUSTC_TARGET_ARCH_SUPPORTS) config_support="$value" ;;
        esac
        case "$key" in
            BR2_HOST_DIR | BR2_DL_DIR | BR2_CCACHE_DIR) continue ;;
        esac
        value="${value//"$sdk"/<SDK>}"
        value="${value//"$GLB_TARGET_SYSTEM_DIR"/<TARGET>}"
        value="${value//"$GLB_TOP_DIR"/<ALLOY>}"
        printf '%s\0%s\0' "/$key" "$value" >> "$sdk_work/config.fields"
    done < "$sdk/.config"
    _sdk_field SDK_MANIFEST_VERSION 1
    _sdk_field SDK_LANGUAGES "${GRISP_SDK_LANGUAGES//,/ }"
    _sdk_field SDK_LANGUAGE_SET "$SDK_LANGUAGE_SET"
    _sdk_field SDK_HOST_OS "$(uname -s | tr '[:upper:]' '[:lower:]')"
    host="$(uname -m)"
    [[ $host != arm64 ]] || host=aarch64
    _sdk_field SDK_HOST_ARCH "$host"
    for key in "${SDK_CONTEXT_MAP[@]}"; do
        value="${key#*:}"
        _sdk_field "${key%%:*}" "${!value:-}"
    done
    _sdk_field SDK_BUILDROOT_VERSION "${BR2_VERSION:-unknown}"
    _sdk_field SDK_TOOLCHAIN_CONFIG_SHA256 "${GLB_TOOLCHAIN_DEFCONFIG_SHA256:-}"
    value="$(_sdk_output "$gcc" -dumpmachine)" || _sdk_fail "Cannot query SDK GCC target"
    _sdk_field SDK_CROSSCOMPILE_ARCH "$value"
    value="$(_sdk_output "$gcc" -dumpfullversion)" || _sdk_fail "Cannot query SDK GCC version"
    _sdk_field SDK_GCC_VERSION "$value"
    tool="$(_sdk_tool erl)" || _sdk_fail "SDK erl missing"
    otp="$(_sdk_output "$tool" -noshell -eval 'io:put_chars(erlang:system_info(otp_release)),halt().')" ||
        _sdk_fail "Cannot query SDK OTP"
    if [[ -f $GLB_SDK_HOST_DIR/usr/lib/erlang/releases/$otp/OTP_VERSION ]]; then
        otp="$(cat "$GLB_SDK_HOST_DIR/usr/lib/erlang/releases/$otp/OTP_VERSION")"
    fi
    _sdk_field SDK_ERLANG_VERSION "$otp"
    tool="$(_sdk_tool unsquashfs)" || _sdk_fail "SDK unsquashfs missing"
    "$tool" -cat "$sdk/images/rootfs.squashfs" sbin/init > "$sdk_work/init" ||
        _sdk_fail "Cannot read SDK init"
    value=""
    if LC_ALL=C grep -aqF -- '--native-exec' "$sdk_work/init"; then
        value=erlinit-native-v1
    fi
    _sdk_field SDK_NATIVE_RUNTIME "$value"
    if sdk_language_enabled rust; then
        [[ $value == erlinit-native-v1 ]] || _sdk_fail "Rust SDK requires native-init support"
    fi
    if command -v sha256sum > /dev/null; then
        init_hash="$(sha256sum "$sdk_work/init")"
    else
        init_hash="$(shasum -a 256 "$sdk_work/init")"
    fi
    _sdk_field SDK_INIT_SHA256 "${init_hash%% *}"
    if sdk_language_enabled elixir; then
        _sdk_tool mix > /dev/null || _sdk_fail "SDK mix missing"
        tool="$(_sdk_tool elixir)" || _sdk_fail "SDK elixir missing"
        details="$(_sdk_output "$tool" --version)" || _sdk_fail "Cannot query SDK Elixir"
        version="$(printf '%s\n' "$details" | awk '$1 == "Elixir" { print $2 }')"
        [[ -n $version && $version != *$'\n'* ]] || _sdk_fail "Cannot determine SDK Elixir version"
        _sdk_field SDK_ELIXIR_VERSION "$version"
    fi
    if sdk_language_enabled rust; then
        [[ $config_support == y && -n $config_arch ]] ||
            _sdk_fail "Buildroot does not support Rust std for this target"
        libc=musl
        [[ $config_glibc != y ]] || libc=gnu
        target="$config_arch-unknown-linux-$libc$config_abi"
        tool="$(_sdk_tool rustc)" || _sdk_fail "SDK rustc missing"
        sysroot="$(_sdk_output "$tool" --print sysroot)" || _sdk_fail "Cannot query Rust sysroot"
        found=false
        for value in "$sysroot/lib/rustlib/$target/lib"/libstd-*.rlib; do
            [[ ! -f $value ]] || found=true
        done
        [[ $found == true ]] || _sdk_fail "SDK Rust standard library missing for $target"
        details="$(_sdk_output "$tool" -vV)" || _sdk_fail "Cannot query SDK rustc"
        host="$(printf '%s\n' "$details" | sed -n 's/^host: //p')"
        version="$(printf '%s\n' "$details" | sed -n 's/^release: //p')"
        [[ -n $host && -n $version ]] || _sdk_fail "Invalid rustc version details"
        _sdk_field SDK_RUST_TARGET "$target"
        _sdk_field SDK_RUST_HOST "$host"
        _sdk_field SDK_RUST_VERSION "$version"
        tool="$(_sdk_tool cargo)" || _sdk_fail "SDK cargo missing"
        details="$(_sdk_output "$tool" -V)" || _sdk_fail "Cannot query SDK Cargo"
        version="$(printf '%s\n' "$details" | awk '{print $2}')"
        _sdk_field SDK_CARGO_VERSION "$version"
    fi
    alloy_tool_record object --strings0 "$sdk_work/cap.fields" --output "$sdk_work/cap.json" ||
        _sdk_fail "Cannot encode SDK capabilities"
    alloy_tool_record object --strings0 "$sdk_work/config.fields" --output "$sdk_work/config.json" ||
        _sdk_fail "Cannot encode SDK config"
    alloy_tool_record object --json-file /config "$sdk_work/config.json" --json-file /capabilities "$sdk_work/cap.json" \
        --string /common "$GLB_COMMON_SYSTEM_TREE_SHA256" --string /target "$GLB_TARGET_SYSTEM_TREE_SHA256" \
        --output "$sdk_work/identity.json" || _sdk_fail "Cannot encode SDK identity"
    build_id="$(alloy_tool_record hash "$sdk_work/identity.json" --encoding json-sorted-v1)" ||
        _sdk_fail "Cannot hash SDK identity"
    _sdk_field SDK_BUILD_ID "$build_id"
    # Original build-host paths are diagnostics, not build-identity inputs.
    for key in "${SDK_DIAGNOSTIC_MAP[@]}"; do
        value="${key#*:}"
        if [[ ${key%%:*} == SDK_STRICT_EXTERNAL_BUNDLE ]]; then
            _sdk_field "${key%%:*}" "${!value:-false}"
        else
            _sdk_field "${key%%:*}" "${!value:-}"
        fi
    done
    alloy_tool_record object --strings0 "$sdk_work/cap.fields" --format sh --output "$sdk/ALLOY-SDK" ||
        _sdk_fail "Cannot write SDK manifest"
    chmod 644 "$sdk/ALLOY-SDK"
    rm -rf "$sdk_work"
}
