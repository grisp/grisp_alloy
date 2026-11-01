# shellcheck shell=bash
# Source-only wrappers for Alloy's standalone build tools.
# Source this from a build script, then call alloy_tool_* functions.

_GRISP_ALLOY_TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/tools" && pwd -P)" || return 1

_alloy_python_tool() {
    local tool="$1"
    shift
    python3 "$_GRISP_ALLOY_TOOLS_DIR/$tool.py" "$@"
}

alloy_tool_record() { _alloy_python_tool record-tool "$@"; }
alloy_tool_tar() { _alloy_python_tool tar-tool "$@"; }
alloy_tool_cargo_artifact() { _alloy_python_tool cargo-artifact "$@"; }
alloy_tool_elf_check() { _alloy_python_tool elf-check "$@"; }
alloy_tool_erlinit_config() { _alloy_python_tool erlinit-config "$@"; }
