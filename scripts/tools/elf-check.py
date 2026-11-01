#!/usr/bin/env python3
"""Validate target ELF payloads and linked dependencies in a firmware root.

Supported loader contract: Explicit/default Linux library directories and
absolute/$ORIGIN RUNPATH; no RPATH, loader cache, environment search paths or
hardware-capability overrides.
This checks linked dependencies, not runtime dlopen(), data files or all ABI use.
"""

import argparse
import json
import os
import re
import struct
import subprocess
from collections import deque
from pathlib import Path, PurePosixPath


def image_path(root, virtual):
    """Resolve symlinks as the device would, including image-absolute links."""
    pending = deque(PurePosixPath(virtual).parts)
    parts = []
    links = 0
    while pending:
        part = pending.popleft()
        if part in ("/", "", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        path = root.joinpath(*parts, part)
        if path.is_symlink():
            links += 1
            if links > 40:
                raise ValueError(f"Symlink loop in {virtual}")
            target = os.readlink(path)
            if target.startswith("/"):
                parts = []
            pending.extendleft(reversed(PurePosixPath(target).parts))
        else:
            parts.append(part)
    return root.joinpath(*parts)


class Checker:
    """Check ELF compatibility and dependencies within one target filesystem."""

    DEFAULT_LIBRARY_DIRS = ("/lib", "/usr/lib", "/lib64", "/usr/lib64")

    def __init__(self, args):
        self.root = args.root.resolve()
        self.arch = args.arch
        self.readelf = args.readelf
        self.defaults = tuple(
            getattr(args, "library_dir", None) or self.DEFAULT_LIBRARY_DIRS
        )
        self.allowed_runpath = getattr(args, "allow_runpath_dir", [])
        self.cache = {}
        self.visited = set()

    def validate_architecture(self, path, details):
        if self.arch.startswith("aarch64"):
            expected = ("AArch64", "ELF64")
        elif self.arch.startswith("arm"):
            expected = ("ARM", "ELF32")
        elif self.arch.startswith("x86_64"):
            expected = ("Advanced Micro Devices X86-64", "ELF64")
        else:
            raise ValueError(
                f"Unsupported ELF architecture contract: {self.arch}"
            )
        machine = re.search(r"^\s*Machine:\s*(.+)$", details, re.M)
        elf_class = re.search(r"^\s*Class:\s*(\S+)", details, re.M)
        if (
            not machine
            or not elf_class
            or (machine[1], elf_class[1]) != expected
            or "little endian" not in details
        ):
            raise ValueError(f"ELF architecture differs from {self.arch}: {path}")
        if self.arch.startswith("arm"):
            flags = re.search(r"^\s*Flags:\s*(.+)$", details, re.M)
            if (
                not flags
                or "Version5 EABI" not in flags[1]
                or "soft-float ABI" in flags[1]
            ):
                raise ValueError(f"Incompatible ARM ABI: {path}")
            if "gnueabihf" in self.arch and "hard-float ABI" not in flags[1]:
                raise ValueError(f"Expected hard-float ARM application: {path}")

    def architecture_scan(self):
        """Check every regular ELF file in the payload, regardless of mode."""
        for path in self.root.rglob("*"):
            if path.is_symlink() or not path.is_file():
                continue
            with path.open("rb") as stream:
                if stream.read(4) != b"\x7fELF":
                    continue
            details = subprocess.check_output(
                [self.readelf, "-h", str(path)],
                text=True,
                env=dict(os.environ, LC_ALL="C"),
            )
            self.validate_architecture(path, details)

    def elf(self, path):
        if path in self.cache:
            return self.cache[path]
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                raise ValueError(f"Expected target ELF: {path}")
        details = subprocess.check_output(
            [self.readelf, "-h", "-l", "-d", "--version-info", str(path)],
            text=True,
            env=dict(os.environ, LC_ALL="C"),
        )
        self.validate_architecture(path, details)
        needed = re.findall(r"\(NEEDED\).*?\[([^]]+)\]", details)
        interp = re.search(r"Requesting program interpreter:\s*([^]]+)", details)
        runpath = re.search(r"\(RUNPATH\).*?\[([^]]*)\]", details)
        if re.search(r"\(RPATH\)", details) or "NODEFLIB" in details:
            raise ValueError(f"Unsupported loader RPATH/NODEFLIB configuration: {path}")
        needs = {}
        definitions = set()
        current = None
        in_definitions = False
        for line in details.splitlines():
            if line.startswith("Version definition section"):
                in_definitions = True
            elif line.startswith("Version needs section"):
                in_definitions = False
            owner = re.search(r"File:\s*(\S+)", line)
            if owner:
                current = owner[1]
            version = re.search(r"Name:\s*(\S+)", line)
            if version:
                if in_definitions:
                    definitions.add(version[1])
                elif current:
                    needs.setdefault(current, set()).add(version[1])
        info = dict(
            needed=needed,
            interpreter=interp[1] if interp else None,
            runpath=runpath[1] if runpath else None,
            needs=needs,
            definitions=definitions,
        )
        self.cache[path] = info
        return info

    def payload(self, entrypoint):
        path = PurePosixPath(entrypoint)
        if (
            path.is_absolute()
            or not entrypoint
            or str(path) != entrypoint
            or any(part in (".", "..") for part in path.parts)
            or not re.fullmatch(r"[A-Za-z0-9_./+-]+", entrypoint)
        ):
            raise ValueError(f"Invalid native entrypoint: {entrypoint!r}")
        entry = (self.root / entrypoint).resolve()
        entry.relative_to(self.root)
        if not entry.is_file() or not os.access(entry, os.X_OK):
            raise ValueError(f"Native entrypoint is not executable: {entrypoint}")
        # The native adapter emits an ELF entrypoint; there is no shell launcher.
        self.elf(entry)
        for path in self.root.rglob("*"):
            if path.is_symlink():
                path.resolve().relative_to(self.root)
            elif path.is_file():
                with path.open("rb") as stream:
                    if stream.read(4) == b"\x7fELF":
                        self.elf(path)

    def dependencies(self, virtual, chain=()):
        if virtual in self.visited:
            return
        path = image_path(self.root, virtual)
        if not path.is_file():
            raise ValueError(" -> ".join((*chain, virtual, "missing")))
        info = self.elf(path)
        self.visited.add(virtual)
        chain = (*chain, virtual)
        if info["interpreter"]:
            interpreter = info["interpreter"]
            if not interpreter.startswith("/"):
                raise ValueError(f"Nonabsolute program interpreter: {virtual}")
            self.dependencies(interpreter, chain)
        directories = []
        if info["runpath"] is not None:
            origin = str(PurePosixPath(virtual).parent)
            for directory in info["runpath"].split(":"):
                directory = directory.replace("${ORIGIN}", origin).replace(
                    "$ORIGIN", origin
                )
                if not directory.startswith("/") or "$" in directory:
                    raise ValueError(
                        f"Unsupported library search path {directory!r} in {virtual}"
                    )
                # Never accept build-host installation paths as target search paths.
                if not any(
                    directory == prefix or directory.startswith(prefix + "/")
                    for prefix in (*self.defaults, *self.allowed_runpath)
                ):
                    raise ValueError(
                        f"Non-runtime library search path {directory!r} in {virtual}"
                    )
                directories.append(directory)
        directories.extend(self.defaults)
        for needed in info["needed"]:
            if "/" in needed:
                raise ValueError(
                    f"Unsupported pathname DT_NEEDED {needed!r} in {virtual}"
                )
            found = None
            for directory in directories:
                candidate = directory.rstrip("/") + "/" + needed
                if image_path(self.root, candidate).is_file():
                    found = candidate
                    break
            if found is None:
                raise ValueError(" -> ".join((*chain, needed, "missing")))
            provider = self.elf(image_path(self.root, found))
            missing = info["needs"].get(needed, set()) - provider["definitions"]
            if missing:
                raise ValueError(
                    f"{' -> '.join(chain)} -> {needed}: "
                    f"missing symbol versions {sorted(missing)}"
                )
            self.dependencies(found, chain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version="elf-check 1")
    commands = parser.add_subparsers(dest="mode", required=True)
    header = commands.add_parser(
        "header", help="Inspect an ELF header without executing it; output JSON"
    )
    header.add_argument("file", type=Path)
    architecture = commands.add_parser(
        "architecture", help="Validate architecture/ABI of every ELF in a payload"
    )
    architecture.add_argument("--root", type=Path, required=True)
    architecture.add_argument("--readelf", required=True)
    architecture.add_argument("--target-triple", dest="arch", required=True)
    for mode in ("payload", "rootfs"):
        command = commands.add_parser(
            mode,
            help="Validate ELF/ABI and contained paths"
            if mode == "payload"
            else "Validate linked dependencies inside an image root",
        )
        command.add_argument("--root", type=Path, required=True)
        command.add_argument("--entrypoint", required=mode == "payload")
        command.add_argument("--scan-dir", action="append", default=[])
        command.add_argument("--system-executable", action="append", default=[])
        command.add_argument("--readelf", required=True)
        command.add_argument("--target-triple", dest="arch", required=True)
        command.add_argument(
            "--library-dir",
            action="append",
            default=[],
            help="Override default Linux library directories (repeatable)",
        )
        command.add_argument(
            "--allow-runpath-dir",
            action="append",
            default=[],
            help="Additional permitted runtime RUNPATH prefix",
        )
    args = parser.parse_args()
    if args.mode == "header":
        with args.file.open("rb") as stream:
            data = stream.read(20)
        if (
            len(data) != 20
            or data[:4] != b"\x7fELF"
            or data[4] not in (1, 2)
            or data[5] not in (1, 2)
        ):
            raise ValueError("Invalid ELF header")
        machine = struct.unpack("<H" if data[5] == 1 else ">H", data[18:20])[0]
        print(
            json.dumps(
                dict(
                    format_version=1,
                    machine=machine,
                    architecture={62: "x86_64", 183: "aarch64", 40: "arm"}.get(
                        machine, "unknown"
                    ),
                    elf_class="ELF32" if data[4] == 1 else "ELF64",
                    endianness="little" if data[5] == 1 else "big",
                )
            )
        )
        return
    if args.mode == "architecture":
        if not args.root.is_dir():
            raise ValueError(f"Missing ELF scan root: {args.root}")
        Checker(args).architecture_scan()
        return
    for directory in args.library_dir + args.allow_runpath_dir:
        path = PurePosixPath(directory)
        if not path.is_absolute() or ".." in path.parts or str(path) != directory:
            raise ValueError(
                f"Expected normalized absolute runtime directory: {directory!r}"
            )
    checker = Checker(args)
    if args.mode == "payload":
        checker.payload(args.entrypoint or "")
    else:
        if image_path(checker.root, "/etc/ld.so.cache").is_file():
            raise ValueError(
                "ELF dependency checker does not support ld.so.cache; "
                "use default library directories/RUNPATH"
            )
        if args.entrypoint:
            entry = image_path(checker.root, args.entrypoint)
            if not entry.is_file() or not os.access(entry, os.X_OK):
                raise ValueError(
                    "Native entrypoint missing/not executable in final rootfs: "
                    f"{args.entrypoint}"
                )
            checker.elf(entry)
        for virtual in args.system_executable:
            program = image_path(checker.root, virtual)
            if not program.is_file() or not os.access(program, os.X_OK):
                raise ValueError(f"System executable missing/not executable: {virtual}")
            checker.dependencies(virtual)
        for virtual in args.scan_dir:
            project = image_path(checker.root, virtual)
            if not project.is_dir():
                raise ValueError(f"Missing ELF scan directory: {virtual}")
            for path in project.rglob("*"):
                if path.is_file() and not path.is_symlink():
                    with path.open("rb") as stream:
                        if stream.read(4) == b"\x7fELF":
                            checker.dependencies(
                                "/" + str(path.relative_to(checker.root))
                            )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"ERROR: ELF validation failed: {error}")
