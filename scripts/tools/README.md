# Standalone build tools

These commands operate on records, archives and external tool formats. Each
script can be copied and run alone, imports only the Python standard library,
and has no checkout, SDK layout or application-policy dependency. Python 3.8+
is required. ELF dependency checks additionally require GNU `readelf`, supplied
explicitly with `--readelf`. None of these tools executes target binaries.

## Alloy Bash integration

Alloy shell scripts can source `scripts/tools.sh` and call the matching wrapper
function. The wrappers preserve each command's arguments and exit status while
using `python3` from the build host's `PATH`:

```sh
source "$GLB_SCRIPT_DIR/tools.sh"
alloy_tool_cargo_artifact executable --messages _build/cargo-messages.jsonl \
  --package-id "$package_id" --bin "$binary" --output-root "$build_dir" \
  --output _build/cargo-artifact.json
```

Available functions are `alloy_tool_record`, `alloy_tool_tar`,
`alloy_tool_cargo_artifact`, `alloy_tool_elf_check`, and
`alloy_tool_erlinit_config`. The wrappers are an Alloy convenience layer; the
Python command-line interfaces remain independently usable as documented
below.

Use `python3 <tool>.py --help`, `<subcommand> --help`, or `--version`. Exit codes
are 0 for success, 1 for invalid data/validation/I/O failure, and 2 for usage
errors. Diagnostics go to stderr. Stdout contains only the requested result;
validators are silent on success. Paths are explicit. Output parent directories
must exist; tools do not create application layouts. `--output` and member/index
writes use a temporary file in the destination directory followed by rename.
Caches are optional and are not a source of authentication.
