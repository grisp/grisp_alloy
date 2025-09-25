project_detect_elixir() {
    local project_dir="$1"
    [[ -f "$project_dir/mix.exs" ]]
}

project_build_elixir() {
    local -n resref="$1"
    local project_dir="$2"
    local profile="$3"
    local target_erlang="$4"
    local rel_path

    # Map rebar3-style profile to Mix env
    local mix_env="$profile"
    if [[ -z "$mix_env" || "$mix_env" == "default" ]]; then
        mix_env="prod"
    fi

    # Resolve mix command (host SDK only)
    local mix_cmd="${GLB_SDK_HOST_DIR}/usr/bin/mix"
    if [[ ! -x "$mix_cmd" ]]; then
        error 1 "mix not found in $mix_cmd"
    fi

    # Ensure UTF-8 VM and pass target ERTS location for projects that use it
    (
        cd "$project_dir"
        # Use host OTP for Mix/Hex (unset ERL_* that point to target libs)
        env -u ERL_LIBS -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS \
            -u MIX_TARGET LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
            ELIXIR_ERL_OPTIONS=+fnu \
            MIX_ENV="$mix_env" \
            "$mix_cmd" deps.get --only "$mix_env"

        env -u ERL_LIBS -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS \
            -u MIX_TARGET LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
            ELIXIR_ERL_OPTIONS=+fnu \
            MIX_ENV="$mix_env" \
            "$mix_cmd" compile

        # For release assembly, point include_erts at target ERTS
        env -u ERL_LIBS -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS \
            -u MIX_TARGET LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
            ELIXIR_ERL_OPTIONS=+fnu \
            ERTS_DIR="$target_erlang" \
            MIX_ENV="$mix_env" \
            "$mix_cmd" release --overwrite
    )

    # Locate release directory
    rel_path="$( cd "$project_dir/_build/${mix_env}/rel"/* && pwd )"

    # Replace embedded ERTS in the release with the target ERTS
    local target_erts_dir
    target_erts_dir="$( ls -d "$target_erlang"/erts-* 2>/dev/null | head -n1 )"
    if [[ -n "$target_erts_dir" && -d "$target_erts_dir" ]]; then
        rm -rf "${rel_path}/erts-"*
        cp -a "$target_erts_dir" "$rel_path/"
    fi

    # Replace OTP libraries with target versions
    # Mix includes host OTP libraries when include_erts=true,
    # but we need target versions
    local target_lib_dir="${target_erlang}/lib"
    local release_lib_dir="${rel_path}/lib"

    if [[ -d "$target_lib_dir" && -d "$release_lib_dir" ]]; then
        # Find all OTP libraries in the target installation
        local otp_libs=()
        for lib in "$release_lib_dir"/*; do
            if [[ -d "$lib" ]]; then
                local lib_name="$(basename "$lib")"
                # Skip non-OTP libraries (like user applications)
                # OTP libraries typically have names like stdlib-3.17
                if [[ "$lib_name" =~ ^(edoc|kernel|reltool|tftp|asn1|eldap|megaco|runtime_tools|tools|common_test|erl_interface|mnesia|sasl|wx|compiler|et|observer|snmp|xmerl|crypto|eunit|odbc|ssh|debugger|ftp|os_mon|ssl|dialyzer|inets|parsetools|stdlib|diameter|jinterface|public_key|syntax_tools)- ]]; then
                   otp_libs+=("$lib_name")
                fi
            fi
        done

        # Replace each OTP library in the release
        for lib_name in "${otp_libs[@]}"; do
            local target_lib="${target_lib_dir}/${lib_name}"
            local release_lib="${release_lib_dir}/${lib_name}"

            # Remove existing host version
            rm -rf "$release_lib"
            # Copy target version
            cp -a "$target_lib" "$release_lib"
        done
    fi

    resref="$rel_path"
}
