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

project_metadata_erlang() {
    local -n app_name_ref="$1"
    local -n app_version_ref="$2"
    local -n release_name_ref="$3"
    local -n release_version_ref="$4"
    local release_dir="$5"
    local project_dir="$6"

    release_name_ref="$( basename "$release_dir" )"

    local rel_dir
    rel_dir="$( find "${release_dir}/releases" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 )"
    if [[ -n "$rel_dir" ]]; then
        release_version_ref="$( basename "$rel_dir" )"
    else
        release_version_ref=""
    fi

    # Determine app name from .app.src present in src/
    app_name_ref=""
    shopt -s nullglob
    for appsrc in "$project_dir"/src/*.app.src; do
        local cand
        cand="$( sed -n 's/^[[:space:]]*{[[:space:]]*application[[:space:]]*,[[:space:]]*\([^,[:space:]]\+\).*/\1/p' "$appsrc" | head -n1 )"
        if [[ -n "$cand" ]] && compgen -G "${release_dir}/lib/${cand}-*" > /dev/null; then
            app_name_ref="$cand"
            break
        fi
    done
    shopt -u nullglob
    if [[ -z "$app_name_ref" ]]; then
        app_name_ref="$release_name_ref"
    fi

    # Determine app version from lib/<app>-<ver>
    local app_rel_dir
    app_rel_dir=$( echo "${release_dir}/lib/${app_name_ref}-"* )
    if [[ -d "$app_rel_dir" ]]; then
        app_version_ref="$( echo "$app_rel_dir" | sed "s|^.*/${app_name_ref}-\(.*\)$|\1|" )"
    else
        app_version_ref=""
    fi
}
