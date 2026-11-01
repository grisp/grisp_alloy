# hello_erlang_rust

An Erlang OTP application with a Rust NIF, following the structure of
`hello_grisp`. At application startup it calls `hello_rust_nif:world/0` and prints:

```text
Hello from a Rust NIF on GRiSP Alloy!
```

The Erlang supervisor keeps the application running. This is a BEAM release:
the Rust library loads into BEAM through `erlang:load_nif/2`; it is not a separate
native application and does not use erlinit's native mode.

## Build for GRiSP2

Use an SDK built with `--enable-rust`, then run from the Alloy checkout:

```sh
./build-project.sh --sdk-lang rust grisp2 samples/hello_erlang_rust
./build-firmware.sh -i grisp2 hello_erlang_rust
```

`--sdk-lang rust` is optional: it adds Rust to the SDK selection requirements
and rejects an unsupported SDK before building. Project detection sees an
Erlang project; it does not inspect nested Cargo projects or Rebar hooks. Without
the option, SDK selection requires only Erlang. If the selected SDK lacks Rust,
the Cargo hook fails instead of falling back to the host Rust toolchain.

## Development profiles and local builds

Alloy's `--profile` selects a Rebar profile for this project. The sample's Cargo
profile defaults independently to `release`; set `CARGO_PROFILE` to choose `dev`
or a custom profile declared in `native/Cargo.toml`. For example, on a Linux host:

```sh
CARGO_PROFILE=dev ./build-project.sh --profile dev --sdk-lang rust grisp2 samples/hello_erlang_rust
```
