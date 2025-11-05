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
    local target_erts_dir
    local otp_dir
    local otp_app
    local dst

    target_erts_dir="$( ls -d "$target_erlang"/erts-* 2>/dev/null | head -n1 )"

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
            ERTS_DIR="$target_erts_dir" \
            ERL_LIB_DIR="$target_erlang" \
            ERL_SYSTEM_LIB_DIR="$target_erlang/lib" \
            MIX_ENV="$mix_env" \
            "$mix_cmd" release --overwrite
    )

    # Locate release directory
    rel_path="$( cd "$project_dir/_build/${mix_env}/rel"/* && pwd )"

    # Replace embedded ERTS in the release with the target ERTS
    if [[ -n "$target_erts_dir" && -d "$target_erts_dir" ]]; then
        rm -rf "${rel_path}/erts-"*
        cp -a "$target_erts_dir" "$rel_path/"
    fi

    # Replace OTP libraries with target versions (copy only ebin and priv)
    local target_lib_dir="${target_erlang}/lib"
    local release_lib_dir="${rel_path}/lib"

    if [[ -d "$target_lib_dir" && -d "$release_lib_dir" ]]; then
        for otp_dir in "${target_lib_dir}"/*; do
            otp_app="$(basename "$otp_dir")" # e.g., crypto-5.6

            # Replace only if an app with this base name exists in the release
            if compgen -G "${release_lib_dir}/${otp_app%%-*}-*" > /dev/null; then
                rm -rf "${release_lib_dir}/${otp_app%%-*}-"*
                dst="${release_lib_dir}/${otp_app}"
                mkdir -p "$dst"
                if [[ -d "${otp_dir}/ebin" ]]; then
                    cp -a "${otp_dir}/ebin" "$dst/"
                fi
                if [[ -d "${otp_dir}/priv" ]]; then
                    cp -a "${otp_dir}/priv" "$dst/"
                fi
            fi
        done
    fi

    resref="$rel_path"
}

project_metadata_elixir() {
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

    # Prefer app name from mix.exs (project app: :name)
    local cand=""
    if [[ -f "$project_dir/mix.exs" ]]; then
        cand="$( grep -E "app:[[:space:]]*:[A-Za-z0-9_]+" "$project_dir/mix.exs" | head -n1 | sed -E 's/.*app:[[:space:]]*:([A-Za-z0-9_]+).*/\1/' )"
    fi
    if [[ -n "$cand" ]] && compgen -G "${release_dir}/lib/${cand}-*" > /dev/null; then
        app_name_ref="$cand"
    else
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
