#!/usr/bin/env python3
"""Build/query JSON and literal assignment records; see README.md for the CLI."""

import argparse
import hashlib
import json
import re
import shlex
import sys
import tempfile
from pathlib import Path


def pointer(value):
    if not value.startswith("/") or re.search(r"~(?![01])", value):
        raise ValueError(f"Invalid JSON pointer: {value!r}")
    return [part.replace("~1", "/").replace("~0", "~") for part in value[1:].split("/")]


def lookup(data, path):
    for part in pointer(path):
        if isinstance(data, list) and part.isdecimal():
            data = data[int(part)]
        else:
            data = data[part]
    return data


def store(data, path, value):
    parts = pointer(path)
    for part in parts[:-1]:
        data = data.setdefault(part, {})
        if not isinstance(data, dict):
            raise ValueError(f"Conflicting JSON destination: {path}")
    if parts[-1] in data:
        raise ValueError(f"Duplicate JSON destination: {path}")
    data[parts[-1]] = value


def assignments(paths, keys):
    result = {}
    for path in paths:
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, separator, raw = line.partition("=")
            if keys and key not in keys:
                continue
            if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                raise ValueError(f"Invalid literal assignment in {path}: {line!r}")
            quote = None
            escaped = False
            for char in raw:
                if escaped:
                    escaped = False
                elif char == "\\" and quote != "'":
                    escaped = True
                elif char in "'\"" and (quote is None or quote == char):
                    quote = char if quote is None else None
                elif quote != "'" and (
                    char in "$`" or (quote is None and char in ";|&<>()")
                ):
                    raise ValueError(
                        f"Only literal assignment values are supported: {key} in {path}"
                    )
            words = shlex.split(raw)
            if len(words) > 1 or key in result:
                raise ValueError(f"Duplicate/invalid assignment for {key} in {path}")
            result[key] = words[0] if words else ""
    return result


def emit(text, output):
    if output is None:
        sys.stdout.write(text)
    else:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=output.parent, delete=False
            ) as stream:
                temporary = Path(stream.name)
                stream.write(text)
            temporary.replace(output)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version="record-tool 1")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser(
        "object", help="Construct an object from typed JSON-pointer fields"
    )
    create.add_argument(
        "--string", nargs=2, action="append", default=[], metavar=("POINTER", "VALUE")
    )
    create.add_argument(
        "--strings0", type=Path, help="Alternating NUL-terminated pointer/string values"
    )
    create.add_argument(
        "--json", nargs=2, action="append", default=[], metavar=("POINTER", "JSON")
    )
    create.add_argument(
        "--json-file", nargs=2, action="append", default=[], metavar=("POINTER", "FILE")
    )
    create.add_argument("--format", choices=("json", "sh"), default="json")
    get = commands.add_parser(
        "get", help="Project required/optional values to caller-named bindings"
    )
    get.add_argument("input", type=Path)
    get.add_argument(
        "--bind", nargs=2, action="append", default=[], metavar=("NAME", "POINTER")
    )
    get.add_argument(
        "--optional-bind",
        nargs=2,
        action="append",
        default=[],
        metavar=("NAME", "POINTER"),
        help="Bind an absent pointer to an empty string",
    )
    get.add_argument("--format", choices=("json", "sh"), default="json")
    read = commands.add_parser(
        "import-assignments", help="Read literal records, never execute shell code"
    )
    read.add_argument("inputs", nargs="+", type=Path)
    read.add_argument(
        "--key", action="append", default=[], help="Read only this key (repeatable)"
    )
    digest = commands.add_parser(
        "hash", help="SHA-256 of recursively sorted JSON with the specified encoding"
    )
    digest.add_argument("input", type=Path)
    digest.add_argument("--encoding", choices=("json-sorted-v1",), required=True)
    for command in (create, get, read, digest):
        command.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.command == "object":
        data = {}
        fields = list(args.string)
        if args.strings0:
            raw = args.strings0.read_bytes()
            values = raw.decode("utf-8").split("\0")
            if values.pop() != "" or len(values) % 2:
                raise ValueError(
                    "--strings0 requires complete NUL-terminated pointer/value pairs"
                )
            fields.extend(zip(values[::2], values[1::2]))
        for path, value in fields:
            store(data, path, value)
        for path, value in args.json:
            store(data, path, json.loads(value))
        for path, file in args.json_file:
            store(data, path, json.loads(Path(file).read_text()))
    elif args.command == "get":
        source = json.loads(args.input.read_text())
        data = {}
        for optional, bindings in ((False, args.bind), (True, args.optional_bind)):
            for name, path in bindings:
                if name in data:
                    raise ValueError(f"Duplicate binding: {name}")
                try:
                    data[name] = lookup(source, path)
                except (KeyError, IndexError):
                    if not optional:
                        raise ValueError(f"Missing required pointer: {path}")
                    data[name] = ""
    elif args.command == "import-assignments":
        data = assignments(args.inputs, args.key)
    else:
        data = json.loads(args.input.read_text())
        encoded = json.dumps(
            data, sort_keys=True, ensure_ascii=True, allow_nan=False
        ).encode()
        emit(hashlib.sha256(encoded).hexdigest() + "\n", args.output)
        return
    if getattr(args, "format", "json") == "sh":
        lines = []
        for name, value in data.items():
            if (
                not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name)
                or not isinstance(value, str)
                or "\0" in value
            ):
                raise ValueError(
                    "Shell output requires valid binding names and NUL-free strings"
                )
            lines.append(f"{name}={shlex.quote(value)}\n")
        emit("".join(lines), args.output)
    else:
        emit(
            json.dumps(data, indent=4, ensure_ascii=True, allow_nan=False) + "\n",
            args.output,
        )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"ERROR: {error}")
