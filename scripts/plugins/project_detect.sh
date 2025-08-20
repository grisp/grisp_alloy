project_detect() {
    local -n resref="$1"
    local project_dir="$2"
    if [[ -f "$project_dir/rebar.config" ]]; then
        source "${GLB_SCRIPT_DIR}/plugins/project_erlang.sh"
        resref="erlang"
    elif [[ -f "$project_dir/mix.exs" ]]; then
        source "${GLB_SCRIPT_DIR}/plugins/project_elixir.sh"
        resref="elixir"
    else
        error 1 "Unknown project type for $(basename "$project_dir")"
    fi
}
