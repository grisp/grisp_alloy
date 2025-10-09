project_detect_erlang() {
    local project_dir="$1"
    [[ -f "$project_dir/rebar.config" ]]
}

project_build_erlang() {
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
		# First retrieve the dependencies without using the target ERTS
		env -u ERL_LIBS "$rebar3_cmd" as "$profile" get-deps
		# Then build the release using the target ERTS
		"$rebar3_cmd" as "$profile" release --system_libs "$target_erlang" --include-erts "$target_erlang"
	)

	resref="$( cd "$project_dir/_build/${profile}/rel"/* && pwd )"
}
