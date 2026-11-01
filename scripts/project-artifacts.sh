# shellcheck shell=bash
# Shared runtime contract. Artifacts are trusted build outputs (Bash manifests).
source "$(dirname "${BASH_SOURCE[0]}")/tools.sh" || return $?

project_archive_basename() {
    local profile="${4:-default}"
    local encoded=""
    local char code index
    local LC_ALL=C
    if [[ -n $profile && $profile != default ]]; then
        for ((index = 0; index < ${#profile}; index++)); do
            char="${profile:$index:1}"
            case "$char" in
                [-a-zA-Z0-9._~]) encoded="$encoded$char" ;;
                *)
                    printf -v code '%02X' "'$char"
                    encoded="$encoded%$code"
                    ;;
            esac
        done
        encoded="-$encoded"
    fi
    printf '%s-%s-%s%s\n' "$1" "$2" "$3" "$encoded"
}

project_manifest_reset() {
    local variable
    for variable in "${!PROJECT_@}"; do
        case "$variable" in
            PROJECT_MANIFEST_* | PROJECT_APP_* | PROJECT_RELEASE_* | \
                PROJECT_TYPE | PROJECT_RUNTIME | PROJECT_ENTRYPOINT | PROJECT_PROFILE | \
                PROJECT_TARGET_* | PROJECT_COMMON_* | PROJECT_CROSSCOMPILE_ARCH | \
                PROJECT_ERTS_VERSION | PROJECT_VCS_* | PROJECT_RUST_* | \
                PROJECT_CARGO_VERSION | PROJECT_BUILD_PROFILE | PROJECT_SDK_*)
                unset "$variable"
                ;;
        esac
    done
}

project_manifest_normalize() {
    local variable
    case "${PROJECT_MANIFEST_VERSION:-1}" in
        1)
            case "${PROJECT_TYPE:-}" in
                erlang | elixir) PROJECT_RUNTIME=beam ;;
                *) error 1 "Invalid legacy project type '${PROJECT_TYPE:-}'" ;;
            esac
            PROJECT_ENTRYPOINT=""
            ;;
        2)
            case "${PROJECT_RUNTIME:-}" in
                beam | native) ;;
                *) error 1 "Unsupported project runtime '${PROJECT_RUNTIME:-}'" ;;
            esac
            case "${PROJECT_TYPE:-}:$PROJECT_RUNTIME" in
                rust:beam | erlang:native | elixir:native) error 1 "Project type/runtime conflict" ;;
            esac
            if [[ -n $SDK_BUILD_ID && -z ${PROJECT_SDK_BUILD_ID:-} ]]; then
                error 1 "Version-2 project manifest is missing SDK identity"
            fi
            ;;
        *) error 1 "Unsupported project manifest version '$PROJECT_MANIFEST_VERSION'" ;;
    esac
    for variable in PROJECT_APP_NAME PROJECT_APP_VERSION PROJECT_RELEASE_NAME PROJECT_RELEASE_VERSION; do
        [[ -n ${!variable:-} ]] || error 1 "Missing $variable in project manifest"
    done
    if ! alloy_valid_name "$PROJECT_APP_NAME" || [[ $PROJECT_APP_NAME != [A-Za-z0-9]* ]]; then
        error 1 "Invalid application name '$PROJECT_APP_NAME'"
    fi
    if ! alloy_valid_name "$PROJECT_RELEASE_NAME" || [[ $PROJECT_RELEASE_NAME != [A-Za-z0-9]* ]]; then
        error 1 "Invalid release name '$PROJECT_RELEASE_NAME'"
    fi
    case "$PROJECT_RELEASE_VERSION$PROJECT_APP_VERSION" in
        *[!A-Za-z0-9_.+-]*) error 1 "Invalid project version" ;;
    esac
    if [[ -n ${PROJECT_SDK_BUILD_ID:-} && $PROJECT_SDK_BUILD_ID != "$SDK_BUILD_ID" ]]; then
        error 1 "Project SDK identity differs from selected SDK; rebuild the project with this SDK"
    fi
}

project_validate_payload() {
    local release="$1"
    local erts=("$1"/erts-*)
    [[ -d $release ]] || error 1 "Missing project release directory: $release"
    PROJECT_ERTS_VERSION=""
    if [[ $PROJECT_RUNTIME == beam ]]; then
        [[ ${#erts[@]} == 1 && -d ${erts[0]} ]] || error 1 "Missing or ambiguous release erts directory"
        [[ -d "$release/lib/$PROJECT_APP_NAME-$PROJECT_APP_VERSION" ]] ||
            error 1 "Missing release path lib/$PROJECT_APP_NAME-$PROJECT_APP_VERSION"
        [[ -d "$release/releases/$PROJECT_RELEASE_VERSION" ]] ||
            error 1 "Missing release path releases/$PROJECT_RELEASE_VERSION"
        PROJECT_ERTS_VERSION="${erts[0]##*/erts-}"
        [[ -n $PROJECT_ERTS_VERSION ]] || error 1 "Missing release erts directory"
        alloy_tool_elf_check architecture --root "$release" \
            --target-triple "$CROSSCOMPILE_ARCH" \
            --readelf "$CROSSCOMPILE-readelf" ||
            error 1 "Invalid BEAM ELF architecture or ABI"
    else
        [[ -n ${PROJECT_ENTRYPOINT:-} ]] || error 1 "Missing native PROJECT_ENTRYPOINT"
        alloy_tool_elf_check payload --root "$release" \
            --entrypoint "$PROJECT_ENTRYPOINT" --target-triple "$CROSSCOMPILE_ARCH" \
            --readelf "$CROSSCOMPILE-readelf" || error 1 "Invalid native project payload"
    fi
}

project_native_init_validate() {
    local config="$1"
    local root="$2"
    local entrypoint="$3"
    local init_binary="${4:-}"
    alloy_tool_erlinit_config validate-native --config "$config" \
        --executable "$root/$entrypoint" --working-directory "$root" || return $?
    if [[ -n $init_binary ]]; then
        if [[ ! -f $init_binary || -L $init_binary ]] ||
            ! LC_ALL=C grep -aqF -- '--native-exec' "$init_binary"; then
            error 1 "Effective /sbin/init does not provide the native erlinit contract"
        fi
    fi
}

project_native_init_generate() {
    local config="$1"
    local root="$2"
    local entrypoint="$3"
    local output="$4"
    local temporary
    mkdir -p "${output%/*}" || return 1
    temporary="$(mktemp "$output.tmp.XXXXXX")" || return 1
    if ! awk '
        { marker=$0; sub(/^[[:space:]]+/, "", marker); sub(/[[:space:]]+$/, "", marker) }
        marker == "# BEGIN ALLOY BEAM OPTIONS" { begin++; inside=1; next }
        marker == "# END ALLOY BEAM OPTIONS" { end++; if (!inside) bad=1; inside=0; next }
        !inside { print }
        END { if (begin != 1 || end != 1 || inside || bad) exit 1 }
        ' "$config" > "$temporary"; then
        rm -f "$temporary"
        error 1 "SDK erlinit.config lacks a unique ALLOY BEAM OPTIONS block; rebuild SDK"
    fi
    printf '%s\n' "--native-exec $root/$entrypoint" "--working-directory $root" >> "$temporary"
    if project_native_init_validate "$temporary" "$root" "$entrypoint"; then
        mv "$temporary" "$output"
    else
        rm -f "$temporary"
        return 1
    fi
}

# Append a pointer/value pair to project_write_firmware_metadata's local fields file.
_project_json_field() { printf '%s\0%s\0' "$1" "$2" >> "$fields"; }

project_write_firmware_metadata() {
    # Adapter for the firmware driver's scalar globals and parallel project
    # arrays. The generic record tool owns escaping, not this firmware schema.
    local output="$1"
    local fields index app path previous
    local status=0
    local seen=()
    fields="$(mktemp)" || return 1
    _project_json_field /architecture "$CROSSCOMPILE_ARCH"
    _project_json_field /serial "$ARG_SERIAL"
    _project_json_field /firmware_profile "$GLB_FIRMWARE_PROFILE"
    _project_json_field /firmware_provisioning_mode "$GLB_FIRMWARE_PROVISIONING_MODE"
    _project_json_field /target "$GLB_TARGET_NAME"
    _project_json_field /target_source "$GLB_TARGET_SYSTEM_SOURCE"
    _project_json_field /system_common_version "$GLB_COMMON_SYSTEM_VER"
    _project_json_field /system_common_vcs "$GLB_VCS_TAG"
    _project_json_field /system_common_tree_sha256 "$GLB_COMMON_SYSTEM_TREE_SHA256"
    _project_json_field /system_target_version "$GLB_TARGET_SYSTEM_VER"
    _project_json_field /system_target_vcs "$GLB_VCS_TAG"
    _project_json_field /system_target_tree_sha256 "$GLB_TARGET_SYSTEM_TREE_SHA256"
    _project_json_field /firmware_name "$FIRMWARE_NAME"
    _project_json_field /firmware_ver "$FIRMWARE_VER"
    _project_json_field /sdk_build_id "$SDK_BUILD_ID"
    _project_json_field /sdk_languages "$GRISP_SDK_LANGUAGES"
    _project_json_field /primary_root "${PROJECT_ROOTS[0]}"
    _project_json_field /primary_runtime "${PROJ_RUNTIMES[0]}"
    for index in "${!APP_NAMES[@]}"; do
        app="${APP_NAMES[index]}"
        for previous in "${seen[@]}"; do
            if [[ $previous == "$app" ]]; then
                rm -f "$fields"
                error 1 "Duplicate application identity: $app"
            fi
        done
        seen+=("$app")
        app="${app//\~/~0}"
        app="${app//\//~1}"
        path="/projects/$app"
        _project_json_field "$path/root" "${PROJECT_ROOTS[index]}"
        _project_json_field "$path/app_ver" "${APP_VERS[index]}"
        _project_json_field "$path/rel_name" "${REL_NAMES[index]}"
        _project_json_field "$path/rel_ver" "${REL_VERS[index]}"
        _project_json_field "$path/type" "${PROJ_TYPES[index]}"
        _project_json_field "$path/profile" "${PROJ_PROFILES[index]}"
        _project_json_field "$path/erts_ver" "${ERTS_VERS[index]}"
        _project_json_field "$path/vcs" "${PROJ_VCS_TAGS[index]}"
        _project_json_field "$path/runtime" "${PROJ_RUNTIMES[index]}"
        _project_json_field "$path/entrypoint" "${PROJ_ENTRYPOINTS[index]}"
    done
    alloy_tool_record object --strings0 "$fields" --output "$output" || status=$?
    rm -f "$fields"
    return "$status"
}
