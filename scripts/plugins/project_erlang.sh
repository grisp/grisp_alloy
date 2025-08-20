project_build() {
	local -n resref="$1"
	local project_dir="$2"
	local profile="$3"
	local target_erlang="$4"

    local rebar3_cmd="${GLB_SDK_HOST_DIR}/usr/bin/rebar3"
    if [[ ! -x "$rebar3_cmd" ]]; then
        error 1 "rebar3 not found in $rebar3_cmd"
    fi

	(
		cd "$project_dir"
		"$rebar3_cmd" as "$profile" release --system_libs "$target_erlang" --include-erts "$target_erlang"
	)

	resref="$( cd "$project_dir/_build/${profile}/rel"/* && pwd )"
}
