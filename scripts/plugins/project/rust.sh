# shellcheck shell=bash
source "$(dirname "${BASH_SOURCE[0]}")/../../tools.sh" || return $?
source "$(dirname "${BASH_SOURCE[0]}")/../../project-env.sh" || return $?

project_detect_rust() {
    [[ -f "$1/Cargo.toml" && ! -f "$1/rebar.config" && ! -f "$1/mix.exs" ]]
}

_project_cargo_build() (
    local project="$1"
    local profile="$2"
    local cargo="$GLB_SDK_HOST_DIR/bin/cargo"
    local rustc="$GLB_SDK_HOST_DIR/bin/rustc"
    local entry
    local cargo_env=()
    [[ -f "$project/Cargo.lock" ]] || error 1 "Application requires a committed Cargo.lock"
    [[ -x $cargo && -x $rustc && -n $SDK_RUST_TARGET ]] ||
        error 1 "Selected SDK has no Rust compiler/target std"
    [[ $profile =~ ^[A-Za-z0-9_-]+$ && $profile != test && $profile != bench ]] ||
        error 1 "Unsupported Cargo build profile: $profile"
    for entry in rust-toolchain rust-toolchain.toml; do
        [[ ! -f $project/$entry ]] || echo "WARNING: Alloy uses SDK rustc, independent of $entry" >&2
    done
    project_environment cargo_env rust || exit $?
    cargo_env+=("CARGO_TARGET_DIR=$project/_build/cargo")
    mkdir -p "$project/_build" || exit 1
    cd "$project" || exit 1
    "${cargo_env[@]}" "$rustc" -V || exit $?
    "${cargo_env[@]}" "$cargo" metadata --format-version 1 --no-deps --locked \
        > _build/cargo-metadata.json || exit $?
    alloy_tool_cargo_artifact select --metadata _build/cargo-metadata.json \
        --manifest-path "$project/Cargo.toml" --metadata-bin-pointer /alloy/bin \
        --output _build/cargo-selection.json || exit $?
    alloy_tool_record get _build/cargo-selection.json --bind RUST_NAME /name \
        --bind RUST_VERSION /version --bind RUST_BINARY /binary --bind RUST_PACKAGE_ID /package_id \
        --format sh --output _build/cargo-selection.sh || exit $?
    source _build/cargo-selection.sh
    [[ $RUST_NAME =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ && $RUST_BINARY =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
        error 1 "Invalid application/binary name"
    "${cargo_env[@]}" "$cargo" build --locked --package "$RUST_NAME" --bin "$RUST_BINARY" \
        --target "$SDK_RUST_TARGET" --profile "$profile" --message-format=json-render-diagnostics \
        > _build/cargo-messages.jsonl || exit $?
    alloy_tool_cargo_artifact executable --messages _build/cargo-messages.jsonl \
        --package-id "$RUST_PACKAGE_ID" --bin "$RUST_BINARY" --output-root "$project/_build/cargo" \
        --output _build/cargo-artifact.json || exit $?
    alloy_tool_record get _build/cargo-artifact.json --bind RUST_EXECUTABLE /executable \
        --format sh --output _build/cargo-executable.sh || exit $?
    source _build/cargo-executable.sh
    rm -rf _build/alloy-release || exit 1
    mkdir -p _build/alloy-release/bin || exit 1
    cp "$RUST_EXECUTABLE" "_build/alloy-release/bin/$RUST_BINARY" || exit 1
    chmod 755 "_build/alloy-release/bin/$RUST_BINARY"
)

project_build_rust() {
    local -n rust_release_ref="$1"
    PROJECT_BUILD_PROFILE="$3"
    [[ $PROJECT_BUILD_PROFILE != default ]] || PROJECT_BUILD_PROFILE=release
    _project_cargo_build "$2" "$PROJECT_BUILD_PROFILE" || return $?
    # Reuse the single validated projection; metadata/runtime hooks need no new processes.
    source "$2/_build/cargo-selection.sh"
    rust_release_ref="$2/_build/alloy-release"
}

project_metadata_rust() {
    local -n rust_app_name="$1"
    local -n rust_app_version="$2"
    local -n rust_release_name="$3"
    local -n rust_release_version="$4"
    rust_app_name="$RUST_NAME"
    rust_app_version="$RUST_VERSION"
    rust_release_name="$RUST_NAME"
    rust_release_version="$RUST_VERSION"
}

project_runtime_rust() {
    local -n rust_runtime="$1"
    local -n rust_entrypoint="$2"
    rust_runtime=native
    rust_entrypoint="bin/$RUST_BINARY"
}
