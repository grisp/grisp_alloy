# shellcheck shell=bash
# Source this definition-only library after selecting an SDK with cross-env.sh.
# project_environment OUT TYPE builds a command array for a project's language
# without changing the caller's environment. grisp-env.sh also reuses the OTP
# assignment records to configure an interactive Erlang build shell.

# Assignment-only records shared with the sourceable grisp-env.sh interface.
_project_environment_otp_values() {
    local -n otp_values_ref="$1"
    local otp_root="$GLB_SDK_DIR/staging/usr/lib/erlang"
    local erts=("$otp_root"/erts-*)
    local ei=("$otp_root"/lib/erl_interface-*)
    if [[ ${#erts[@]} != 1 || ! -d ${erts[0]} || ${#ei[@]} != 1 || ! -d ${ei[0]} ]]; then
        echo "ERROR: Missing or ambiguous SDK OTP directories in $otp_root" >&2
        return 1
    fi
    otp_values_ref=(
        "HOST_ERLANG=$GLB_SDK_HOST_DIR/usr/lib/erlang"
        "TARGET_ERLANG=$otp_root"
        "REBAR_TARGET_ARCH=$CROSSCOMPILE_ARCH"
        "REBAR_PLT_DIR=$otp_root"
        "ERL_CFLAGS=-I${erts[0]}/include -I${ei[0]}/include"
        "ERL_LDFLAGS=-L${erts[0]}/lib -L${ei[0]}/lib -lerts -lei"
        "ERL_EI_LIBDIR=${ei[0]}/lib"
        "ERL_EI_INCLUDE_DIR=${ei[0]}/include"
        "ERTS_INCLUDE_DIR=${erts[0]}/include"
        "ERL_INTERFACE_LIB_DIR=${ei[0]}/lib"
        "ERL_INTERFACE_INCLUDE_DIR=${ei[0]}/include"
    )
}

_project_environment_erlang_values() {
    local -n erlang_values_ref="$1"
    _project_environment_otp_values "$1" || return $?
    erlang_values_ref+=("ERL_LIBS=$GLB_SDK_DIR/staging/usr/lib/erlang/lib")
}

_project_environment_erlang() {
    local -n erlang_env_ref="$1"
    local erlang_values=()
    _project_environment_erlang_values erlang_values || return $?
    erlang_env_ref+=(env "${erlang_values[@]}")
}

_project_environment_elixir() {
    local -n elixir_env_ref="$1"
    local otp_values=()
    _project_environment_otp_values otp_values || return $?
    elixir_env_ref+=(env -u ERL_LIBS -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS -u MIX_TARGET
        "LANG=en_US.UTF-8" "LC_ALL=en_US.UTF-8" "ELIXIR_ERL_OPTIONS=+fnu" "${otp_values[@]}")
}

# Append Cargo settings; MODE=preserve-c retains the ordinary C hook environment.
_project_environment_rust() {
    local -n rust_env_ref="$1"
    local mode="$2"
    local target="${SDK_RUST_TARGET:-}"
    local separator="" host_path=""
    local variable entry directory tool value suffix target_env_name target_pattern
    local paths=()
    target_pattern="${target//-/[-_]}"
    # A BEAM project may use Rust without declaring an extra SDK requirement.
    # Never let such a project silently build a host NIF with system Rust when
    # the chosen SDK has no Rust support: the hook then fails on the SDK paths.
    rust_env_ref+=(env)
    if [[ -z $target ]]; then
        rust_env_ref+=("CARGO=$GLB_SDK_HOST_DIR/bin/cargo" "RUSTC=$GLB_SDK_HOST_DIR/bin/rustc")
        return 0
    fi
    if [[ ! -x $GLB_SDK_HOST_DIR/bin/cargo || ! -x $GLB_SDK_HOST_DIR/bin/rustc ]]; then
        echo "ERROR: Selected SDK has no Rust compiler" >&2
        return 1
    fi
    IFS=: read -r -a paths <<< "$PATH"
    for directory in "${paths[@]}"; do
        [[ $directory != "$GLB_SDK_HOST_DIR/bin" && $directory != "$GLB_SDK_HOST_DIR/usr/bin" ]] || continue
        host_path="$host_path$separator$directory"
        separator=:
    done
    # NUL records also expose names containing hyphens, which Bash cannot
    # import as ordinary variables. Never split environment values.
    while IFS= read -r -d '' entry; do
        variable="${entry%%=*}"
        case "$variable" in
            CC | CXX | AR | CFLAGS | CXXFLAGS | CPPFLAGS | LDFLAGS | PKG_CONFIG | PKG_CONFIG_PATH | PKG_CONFIG_LIBDIR | PKG_CONFIG_SYSROOT_DIR | PKG_CONFIG_ALLOW_CROSS)
                [[ $mode == preserve-c ]] || rust_env_ref+=(-u "$variable")
                ;;
            RUSTFLAGS | CARGO_ENCODED_RUSTFLAGS | RUSTC | RUSTC_WRAPPER | RUSTC_WORKSPACE_WRAPPER)
                rust_env_ref+=(-u "$variable")
                echo "WARNING: Alloy overrides inherited $variable for SDK compilation" >&2
                ;;
            CC_* | CXX_* | AR_* | CFLAGS_* | CXXFLAGS_* | CPPFLAGS_* | PKG_CONFIG*)
                if [[ $variable =~ ^(CC|CXX|AR|CFLAGS|CXXFLAGS|CPPFLAGS|PKG_CONFIG[A-Za-z0-9_]*)_${target_pattern}$ ]]; then
                    rust_env_ref+=(-u "$variable")
                fi
                ;;
        esac
    done < <(env -0)
    rust_env_ref+=(-u HOST_PKG_CONFIG_LIBDIR)
    for variable in CC CXX AR; do
        case "$variable" in
            CC)
                tool=cc
                suffix=gcc
                ;;
            CXX)
                tool=c++
                suffix=g++
                ;;
            AR)
                tool='ar'
                suffix='ar'
                ;;
        esac
        if ! value="$(PATH="$host_path" type -P "$tool")"; then
            echo "ERROR: Host build tool missing: $tool" >&2
            return 1
        fi
        rust_env_ref+=("HOST_$variable=$value" "TARGET_$variable=$CROSSCOMPILE-$suffix")
    done
    for variable in CFLAGS CXXFLAGS CPPFLAGS; do
        rust_env_ref+=("HOST_$variable=" "TARGET_$variable=--sysroot=$GLB_SDK_DIR/staging")
    done
    value="$(PATH="$host_path" type -P pkg-config)" || value=pkg-config
    target_env_name="$(printf '%s' "$SDK_RUST_TARGET" | tr '[:lower:]-' '[:upper:]_')"
    rust_env_ref+=(
        "HOST_PKG_CONFIG=$value"
        "HOST_PKG_CONFIG_PATH="
        "HOST_PKG_CONFIG_SYSROOT_DIR="
        "TARGET_PKG_CONFIG=$GLB_SDK_HOST_DIR/bin/pkg-config"
        "TARGET_PKG_CONFIG_PATH="
        "TARGET_PKG_CONFIG_LIBDIR=$GLB_SDK_DIR/staging/usr/lib/pkgconfig:$GLB_SDK_DIR/staging/usr/share/pkgconfig"
        "TARGET_PKG_CONFIG_SYSROOT_DIR=$GLB_SDK_DIR/staging"
        "CARGO=$GLB_SDK_HOST_DIR/bin/cargo"
        "RUSTC=$GLB_SDK_HOST_DIR/bin/rustc"
        "RUSTDOC=$GLB_SDK_HOST_DIR/bin/rustdoc"
        "CARGO_BUILD_TARGET=$SDK_RUST_TARGET"
        # Match Buildroot's pkg-cargo.mk host/target split for Cargo 1.86.
        # Its unstable host configuration requires the test-only channel override.
        # Revisit these switches when updating SDK Cargo.
        "__CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS=nightly"
        "CARGO_UNSTABLE_HOST_CONFIG=true"
        "CARGO_UNSTABLE_TARGET_APPLIES_TO_HOST=true"
        "CARGO_TARGET_APPLIES_TO_HOST=false"
        "CARGO_TARGET_${target_env_name}_LINKER=$CROSSCOMPILE-gcc"
    )
}

# Apply the Erlang project environment to the current shell. Used by
# grisp-env.sh; project builds use the command-scoped environment below.
project_env_erlang() {
    local record
    local erlang_values=()
    _project_environment_erlang_values erlang_values || return $?
    for record in "${erlang_values[@]}"; do
        export "${record?}" || return $?
    done
    # Preserve the historical, non-exported shell convenience variables.
    ERTS_DIR="${ERTS_INCLUDE_DIR%/include}"
    ERL_INTERFACE_DIR="${ERL_INTERFACE_INCLUDE_DIR%/include}"
}

# Build OUT as an env command array for TYPE, retaining the caller's shell.
project_environment() {
    local -n project_env_ref="$1"
    local type="$2"
    local native_mode=preserve-c
    project_env_ref=()
    case "$type" in
        erlang) _project_environment_erlang "$1" || return $? ;;
        elixir) _project_environment_elixir "$1" || return $? ;;
        rust)
            if [[ -z ${SDK_RUST_TARGET:-} ]]; then
                echo "ERROR: Selected SDK has no Rust target" >&2
                return 1
            fi
            native_mode=""
            ;;
        c) ;;
        *)
            echo "ERROR: Unknown project environment '$type'" >&2
            return 1
            ;;
    esac
    # Compatibility with SDK common-system 0.2.0; remove when support ends.
    # Preserve the project's original tool environment for this SDK version.
    [[ ${SDK_COMPAT_V020:-false} != true ]] || return 0
    # All project types can invoke nested Cargo; only Rust removes the ordinary
    # C cross settings. Complete env segments preserve option/assignment order.
    _project_environment_rust "$1" "$native_mode"
}
