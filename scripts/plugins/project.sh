#!/usr/bin/env bash
# project.sh - Project plugin entry point and contract
#
# This module loads all project-type plugins and provides:
#  1) project_setup      → loads plugins and registers supported types
#  2) project_detect     → auto-detects a project's type
#  3) project_build      → dispatches build to the detected type's handler
#  4) project_metadata   → asks the detected type for app/release metadata
#
# Plugin loading
#  - Plugins live under plugins/project/*.sh
#  - project_setup sources all *.sh files and collects their type names from
#    the filename (without .sh) into PROJECT_TYPES.
#
# Auto-detection
#  - project_detect iterates PROJECT_TYPES and calls project_detect_<type>
#    with the project directory.
#  - The first detector that returns success (exit code 0) is selected and the
#    type name is returned via the provided reference variable.
#
# Build dispatch
#  - project_build internally calls project_detect, then invokes
#    project_build_<type> with the same arguments.
#
# Plugin contract (for a plugin file plugins/project/<type>.sh)
#  - project_detect_<type> project_dir
#      Return 0 if project_dir matches <type>; return non-zero otherwise.
#  - project_build_<type> resref project_dir profile target_erlang
#      Build the project release and set resref to the absolute path of the
#      assembled release directory. Return non-zero on failure.
#  - project_metadata_<type> app_name_ref app_version_ref release_name_ref \
#                           release_version_ref release_dir project_dir
#      Populate the provided refs with the main app name/version and the
#      release name/version for the built artefacts.
#
# Notes
#  - Detectors should only check for their own type; they must not modify
#    global state or source other plugins.
#  - Keep detection order-independent where possible; if multiple types match,
#    the first one found wins according to filesystem order.

project_setup() {
    PROJECT_TYPES=()
    for p in $(ls "${GLB_SCRIPT_DIR}/plugins/project/"*.sh); do
        source "$p"
        PROJECT_TYPES+=("$(basename "$p" | sed 's/\.sh$//')")
    done
}

project_detect() {
    local -n resref="$1"
    local project_dir="$2"
    for t in "${PROJECT_TYPES[@]}"; do
        if project_detect_${t} "$project_dir"; then
            resref="$t"
            return 0
        fi
    done
    error 1 "Unknown project type for $(basename "$project_dir")"
}

project_build() {
    local project_dir="$2"
    local project_type
    project_detect project_type "$project_dir"
    project_build_${project_type} "$@"
}

project_metadata() {
    local project_dir="$6"
    local project_type
    project_detect project_type "$project_dir"
    project_metadata_${project_type} "$@"
}
