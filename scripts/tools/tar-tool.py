#!/usr/bin/env python3
"""Inspect tar paths or read bounded regular members without extracting a filesystem."""

import argparse
import base64
import fnmatch
import hashlib
import json
import posixpath
import re
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath


def write(path, content):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def check(args):
    with tarfile.open(args.archive) as archive:
        for member in archive:
            name = member.name
            if (
                name.startswith("/")
                or ".." in name.split("/")
                or not (
                    member.isfile()
                    or member.isdir()
                    or member.issym()
                    or member.islnk()
                )
            ):
                raise ValueError(f"Invalid archive member: {name!r}")
            if member.issym() or member.islnk():
                target = member.linkname
                resolved = posixpath.normpath(
                    posixpath.join(
                        posixpath.dirname(name) if member.issym() else "", target
                    )
                )
                if (
                    args.links == "reject"
                    or target.startswith("/")
                    or resolved == ".."
                    or resolved.startswith("../")
                ):
                    raise ValueError(
                        f"Escaping/disallowed archive link: {name!r} -> {target!r}"
                    )


def read(args):
    requests = args.member + args.optional_member
    aliases = [alias for alias, _ in requests]
    if (
        not requests
        or len(set(aliases)) != len(aliases)
        or any(not re.fullmatch(r"[A-Za-z0-9_-]+", alias) for alias in aliases)
    ):
        raise ValueError("Specify unique alphanumeric member aliases")
    if args.max_member_bytes < 0:
        raise ValueError("Member size limit cannot be negative")
    stat = args.archive.stat()
    stamp = [stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns]
    query = [
        str(args.archive.resolve()),
        stamp,
        args.member,
        args.optional_member,
        args.first_match,
        args.common_parent,
        args.max_member_bytes,
        1,
    ]
    cache = (
        args.cache_dir
        / (hashlib.sha256(json.dumps(query).encode()).hexdigest() + ".json")
        if args.cache_dir
        else None
    )
    members = None
    if cache is not None:
        try:
            stored = json.loads(cache.read_text())
            if isinstance(stored, dict) and all(
                isinstance(value, dict)
                and isinstance(value.get("member"), str)
                and isinstance(value.get("content"), str)
                for value in stored.values()
            ):
                members = stored
        except (OSError, ValueError):
            pass
    if members is None:
        print(f"Reading archive metadata: {args.archive}", file=sys.stderr)
        members = {}
        with tarfile.open(args.archive, "r|*") as archive:
            for member in archive:
                name = str(PurePosixPath(member.name))
                for alias, pattern in requests:
                    if not fnmatch.fnmatchcase(name, pattern):
                        continue
                    if alias in members:
                        if args.require_unique:
                            raise ValueError(
                                f"Multiple members match {pattern!r} in {args.archive}"
                            )
                        continue
                    if (
                        not member.isfile()
                        or member.size > args.max_member_bytes
                        or member.name.startswith("/")
                        or ".." in PurePosixPath(name).parts
                    ):
                        raise ValueError(
                            f"Invalid/nonregular/oversized member: {member.name!r}"
                        )
                    members[alias] = {
                        "member": name,
                        "content": base64.b64encode(
                            archive.extractfile(member).read()
                        ).decode(),
                    }
                if args.first_match and len(members) == len(requests):
                    break
        after = args.archive.stat()
        if stamp != [after.st_size, after.st_mtime_ns, after.st_ctime_ns]:
            raise ValueError("Archive changed during metadata read; retry")
        for alias, pattern in args.member:
            if alias not in members:
                raise ValueError(
                    f"Missing required member {pattern!r} in {args.archive}"
                )
        parents = {
            str(PurePosixPath(value["member"]).parent) for value in members.values()
        }
        if args.common_parent and len(parents) > 1:
            raise ValueError("Requested archive members do not share one parent")
        if cache is not None:
            try:
                args.cache_dir.mkdir(parents=True, exist_ok=True)
                write(cache, json.dumps(members).encode())
            except OSError:
                pass
    index = {"format_version": 1, "members": {}}
    after = args.archive.stat()
    if stamp != [after.st_size, after.st_mtime_ns, after.st_ctime_ns]:
        raise ValueError("Archive changed during metadata read; retry")
    for alias, pattern in args.member:
        if alias not in members:
            raise ValueError(f"Missing required member {pattern!r} in {args.archive}")
    for alias in aliases:
        item = members.get(alias)
        if item is None:
            index["members"][alias] = None
            continue
        destination = args.output_dir / alias
        if args.index and destination.resolve() == args.index.resolve():
            raise ValueError("Index output conflicts with a selected member output")
        write(destination, base64.b64decode(item["content"], validate=True))
        index["members"][alias] = {"member": item["member"], "file": str(destination)}
    encoded = json.dumps(index, indent=4).encode() + b"\n"
    if args.index:
        write(args.index, encoded)
    else:
        sys.stdout.write(encoded.decode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version="tar-tool 1")
    commands = parser.add_subparsers(dest="command", required=True)
    paths = commands.add_parser(
        "check-paths", help="Lexical path/link preflight; not an extraction sandbox"
    )
    paths.add_argument("archive", type=Path)
    paths.add_argument("--links", choices=("internal", "reject"), default="internal")
    paths.add_argument("--special-files", choices=("reject",), default="reject")
    metadata = commands.add_parser(
        "read",
        help="Copy selected regular members to named files and emit a JSON index",
    )
    metadata.add_argument("archive", type=Path)
    metadata.add_argument(
        "--member", nargs=2, action="append", default=[], metavar=("ALIAS", "PATTERN")
    )
    metadata.add_argument(
        "--optional-member",
        nargs=2,
        action="append",
        default=[],
        metavar=("ALIAS", "PATTERN"),
    )
    metadata.add_argument("--common-parent", action="store_true")
    mode = metadata.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--first-match",
        action="store_true",
        help="Stop after all requested matches; cannot prove global uniqueness",
    )
    mode.add_argument(
        "--require-unique",
        action="store_true",
        help="Scan the complete archive to reject duplicate matches",
    )
    metadata.add_argument("--max-member-bytes", type=int, default=65536)
    metadata.add_argument("--cache-dir", type=Path)
    metadata.add_argument("--output-dir", type=Path, required=True)
    metadata.add_argument("--index", type=Path)
    args = parser.parse_args()
    if args.command == "check-paths":
        check(args)
    else:
        read(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        raise SystemExit(f"ERROR: {error}")
