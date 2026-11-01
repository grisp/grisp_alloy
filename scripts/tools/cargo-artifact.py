#!/usr/bin/env python3
"""Interpret Cargo metadata and compiler messages without invoking a build."""

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version="cargo-artifact 1")
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser(
        "select",
        help="Select a root package and one binary from "
        "cargo metadata --format-version 1",
    )
    select.add_argument("--metadata", type=Path, required=True)
    select.add_argument("--manifest-path", type=Path, required=True)
    select.add_argument("--bin")
    select.add_argument(
        "--metadata-bin-pointer", help="Optional JSON pointer within package.metadata"
    )
    executable = commands.add_parser(
        "executable",
        help="Find exactly one successful reported binary within an output root",
    )
    executable.add_argument("--messages", type=Path, required=True)
    executable.add_argument("--package-id", required=True)
    executable.add_argument("--bin", required=True)
    executable.add_argument("--output-root", type=Path, required=True)
    for command in (select, executable):
        command.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.command == "select":
        metadata = json.loads(args.metadata.read_text())
        manifest_path = args.manifest_path.resolve()
        packages = [
            package
            for package in metadata["packages"]
            if Path(package["manifest_path"]).resolve() == manifest_path
        ]
        if len(packages) != 1:
            raise ValueError(
                "Expected one package at the specified manifest; "
                "virtual workspace roots have no package"
            )
        package = packages[0]
        binary = args.bin
        if not binary and args.metadata_bin_pointer:
            if not args.metadata_bin_pointer.startswith("/") or re.search(
                r"~(?![01])", args.metadata_bin_pointer
            ):
                raise ValueError("Metadata binary pointer must begin with /")
            value = package.get("metadata") or {}
            for key in args.metadata_bin_pointer[1:].split("/"):
                value = (
                    value.get(key.replace("~1", "/").replace("~0", "~"))
                    if isinstance(value, dict)
                    else None
                )
            binary = value
        binaries = [
            target["name"] for target in package["targets"] if "bin" in target["kind"]
        ]
        binary = (
            binary
            or package.get("default_run")
            or (binaries[0] if len(binaries) == 1 else None)
        )
        if not binary or binary not in binaries:
            raise ValueError(
                "Select one binary with --bin, package metadata, default-run, "
                "or a sole binary target"
            )
        result = dict(
            format_version=1,
            package_id=package["id"],
            name=package["name"],
            version=package["version"],
            binary=binary,
        )
    else:
        artifacts = []
        finished = False
        for line in args.messages.read_text().splitlines():
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if not isinstance(message, dict):
                continue
            if message.get("reason") == "build-finished":
                finished = message.get("success") is True
            if (
                message.get("reason") == "compiler-artifact"
                and message.get("package_id") == args.package_id
                and message.get("target", {}).get("name") == args.bin
                and "bin" in message["target"]["kind"]
                and message.get("executable")
            ):
                artifacts.append(Path(message["executable"]))
        if not finished or len(artifacts) != 1:
            raise ValueError(
                "Cargo did not report exactly one successful selected executable"
            )
        path = artifacts[0]
        if not path.is_absolute():
            raise ValueError("Reported executable must be absolute")
        path = path.resolve(strict=True)
        path.relative_to(args.output_root.resolve())
        if not path.is_file():
            raise ValueError("Reported executable is not a regular file")
        result = dict(format_version=1, executable=str(path))
    encoded = json.dumps(result, indent=4) + "\n"
    if args.output:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", dir=args.output.parent, delete=False
            ) as stream:
                temporary = Path(stream.name)
                stream.write(encoded)
            temporary.replace(args.output)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
    else:
        sys.stdout.write(encoded)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"ERROR: {error}")
