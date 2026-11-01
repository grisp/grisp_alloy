# hello_rust

A dependency-free foreground Rust application. It prints a greeting and a
heartbeat every five seconds. The main program must remain running: erlinit
reboots the device if the primary application exits, including exit status zero.
`--once` is available for manual execution, not normal boot.

Build an SDK with Rust support. `build-project.sh` detects the Rust project and
selects the unique matching SDK, which may also support Elixir. Firmware builds
use that SDK's exact build ID from the project manifest:

```sh
./build-toolchain.sh grisp2
./build-sdk.sh --enable-rust grisp2
./build-project.sh grisp2 samples/hello_rust
./build-firmware.sh -i grisp2 hello_rust
```

The committed Cargo.lock is required; builds use `--locked`.
