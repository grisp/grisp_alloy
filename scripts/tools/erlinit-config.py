#!/usr/bin/env python3
"""Validate native erlinit configuration independently of application layout."""

import argparse
import shlex
from pathlib import Path


def validate(text, executable, working_directory):
    if any(len(line.encode()) > 255 for line in text.splitlines()):
        raise ValueError("erlinit configuration exceeds its 255-byte line limit")
    # cfgloader.c recognizes double quotes only, with no shell escape syntax.
    lexer = shlex.shlex(text, posix=True)
    lexer.whitespace_split = True
    lexer.quotes = '"'
    lexer.escape = ""
    tokens = list(lexer)
    values = {}
    for index, token in enumerate(tokens):
        name, separator, value = token.partition("=")
        if name.startswith("-") and not name.startswith("--") and len(name) > 2:
            raise ValueError(
                "Combined/attached short options are unsupported in native init "
                f"config: {name}"
            )
        if name in (
            "-s",
            "--alternate-exec",
            "-b",
            "--boot",
            "-r",
            "--release-path",
            "--release-include-erts",
        ):
            raise ValueError(
                f"BEAM launch option conflicts with native primary: {name}"
            )
        if name in ("--native-exec", "--working-directory"):
            if name in values:
                raise ValueError(f"Duplicate native init option: {name}")
            if not separator:
                if index + 1 == len(tokens):
                    raise ValueError(f"Missing argument for {name}")
                value = tokens[index + 1]
            values[name] = value
    if (
        values.get("--native-exec") != executable
        or values.get("--working-directory") != working_directory
    ):
        raise ValueError(
            "Effective erlinit configuration does not match "
            "the requested executable/cwd"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version="erlinit-config 1")
    commands = parser.add_subparsers(dest="mode", required=True)
    command = commands.add_parser(
        "validate-native",
        help="Validate erlinit native launch arguments, quoting and line limits",
    )
    command.add_argument("--config", type=Path, required=True)
    command.add_argument("--executable", required=True)
    command.add_argument("--working-directory", required=True)
    args = parser.parse_args()
    validate(args.config.read_text(), args.executable, args.working_directory)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(f"ERROR: Native init configuration: {error}")
