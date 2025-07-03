#!/usr/bin/env python3
"""
buildroot_config_tool.py - merge & diff Buildroot defconfig fragments

▸ merge : consolidate several partial defconfig files (+BR2_* env)
▸ diff  : update a partial defconfig with changes made in menuconfig
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set


class ConfigLine:
    """Represents a single line in a defconfig file"""
    def __init__(self, raw_line: str, line_number: int = 0):
        self.raw = raw_line.rstrip('\n\r')
        self.line_number = line_number
        self.is_comment = self.raw.startswith('#') or not self.raw.strip()
        self.is_blank = not self.raw.strip()

        if not self.is_comment and not self.is_blank:
            self.key, self.value = self._parse_config_line(self.raw)
        else:
            self.key = None
            self.value = None

    def _parse_config_line(self, line: str) -> Tuple[str, str]:
        """Parse a config line into key=value"""
        # Handle "# BR2_SOMETHING is not set" format
        if line.startswith('#') and 'is not set' in line:
            parts = line.split()
            if len(parts) >= 4:
                key = parts[1]
                return key, 'n'

        # Handle regular "KEY=VALUE" format
        if '=' in line:
            key, value = line.split('=', 1)
            return key.strip(), value.strip()

        raise ValueError(f"Cannot parse config line: {line}")

    def to_config_format(self) -> str:
        """Convert to standard config format"""
        if self.is_comment or self.is_blank:
            return self.raw

        if self.value == 'n':
            return f"# {self.key} is not set"
        else:
            return f"{self.key}={self.value}"


def load_config_simple(filepath: Path) -> Dict[str, str]:
    """Load config file into simple key-value dictionary"""
    config = {}

    if not filepath.exists():
        return config

    with open(filepath, 'r') as f:
        for line in f:
            try:
                config_line = ConfigLine(line)
                if config_line.key:
                    config[config_line.key] = config_line.value
            except ValueError:
                # Skip lines that can't be parsed
                continue

    return config


def load_config_with_structure(filepath: Path) -> List[ConfigLine]:
    """Load config file preserving structure (comments, blank lines)"""
    lines = []

    if not filepath.exists():
        return lines

    with open(filepath, 'r') as f:
        for line_no, line in enumerate(f, 1):
            try:
                lines.append(ConfigLine(line, line_no))
            except ValueError:
                # Treat unparseable lines as comments
                lines.append(ConfigLine(f"# {line.strip()}", line_no))

    return lines


def get_env_br2_vars() -> Dict[str, str]:
    """Get BR2_* environment variables"""
    env_vars = {}
    for key, value in os.environ.items():
        if key.startswith('BR2_'):
            env_vars[key] = value
    return env_vars


def merge_configs(output_file: Path, input_files: List[Path]) -> None:
    """Merge multiple defconfig files"""
    print(f"⇒ creating merged defconfig: {output_file}")

    # Load all configs
    final_values = {}
    final_origins = {}

    # BR2_* environment variables have highest priority
    env_vars = get_env_br2_vars()
    if env_vars:
        print("  • processing BR2_* environment variables")
        for key, value in env_vars.items():
            final_values[key] = value
            final_origins[key] = "environment"

    # Process files in order
    for filepath in input_files:
        if not filepath.exists():
            print(f"✖ {filepath} not found", file=sys.stderr)
            sys.exit(1)

        print(f"  • analyzing {filepath}")
        config = load_config_simple(filepath)

        for key, value in config.items():
            # Only update if not set by environment (env has highest priority)
            if key not in env_vars:
                final_values[key] = value
                final_origins[key] = str(filepath)

    # Write merged output
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        # Write environment variables first
        if env_vars:
            f.write("# " + "="*64 + "\n")
            f.write("# BR2_* Environment Variables (highest priority)\n")
            f.write("# " + "="*64 + "\n")
            for key, value in sorted(env_vars.items()):
                f.write(f"{key}={value}\n")
            f.write("\n")

        # Write each file's section
        for filepath in input_files:
            config = load_config_simple(filepath)
            if not config:
                continue

            f.write("# " + "="*64 + "\n")
            f.write(f"# Entries from {filepath}\n")
            f.write("# " + "="*64 + "\n")

            for key, value in sorted(config.items()):
                if final_origins[key] != str(filepath):
                    # This entry is overridden
                    if key in env_vars:
                        f.write(f"# {key}={value}  (overridden by environment)\n")
                    else:
                        f.write(f"# {key}={value}  (overridden by {final_origins[key]})\n")
                else:
                    # This is the final value
                    if value == 'n':
                        f.write(f"# {key} is not set\n")
                    else:
                        f.write(f"{key}={value}\n")
            f.write("\n")

    print(f"✓ merge done → {output_file}")


def diff_configs(output_file: Path, base_file: Path, new_file: Path,
                partial_file: Path, defaults_file: Optional[Path] = None) -> None:
    """Update partial defconfig with changes from menuconfig"""

    # Verify all files exist
    for filepath in [base_file, new_file, partial_file]:
        if not filepath.exists():
            print(f"✖ {filepath} not found", file=sys.stderr)
            sys.exit(1)

    if defaults_file and not defaults_file.exists():
        print(f"✖ defaults file {defaults_file} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Input files verified: base={base_file}, new={new_file}, partial={partial_file}")
    if defaults_file:
        print(f"Defaults file: {defaults_file}")

    # Backup existing output if it exists
    if output_file.exists():
        backup_file = output_file.with_suffix(output_file.suffix + '.old')
        output_file.rename(backup_file)
        print(f"⇒ Updating defconfig {output_file} (backup: {backup_file})")
    else:
        print(f"⇒ Creating defconfig {output_file} from {partial_file}")

    # Load all configs
    base_config = load_config_simple(base_file)
    new_config = load_config_simple(new_file)
    defaults_config = load_config_simple(defaults_file) if defaults_file else {}
    partial_lines = load_config_with_structure(partial_file)

    print(f"  • loading defaults from {defaults_file}" if defaults_file else "  • no defaults file")
    if defaults_file:
        print("  • defaults loaded successfully")

    # Compute differences
    changes = {}
    removals = {}
    new_entries = {}

    # Find changes and additions
    for key, value in new_config.items():
        if key not in base_config:
            new_entries[key] = value
        elif base_config[key] != value:
            changes[key] = value

    # Find removals
    for key, value in base_config.items():
        if key not in new_config:
            removals[key] = value

    print(f"Changes computed: {len(changes)} changed, {len(removals)} removed, {len(new_entries)} new")

    # Process partial file
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        # Process existing lines
        for line in partial_lines:
            if line.is_comment or line.is_blank:
                f.write(line.raw + '\n')
                continue

            key = line.key
            original_value = line.value

            # Check if this key exists in base config to determine how to handle it
            if key in base_config:
                # This key exists in base config, check for changes/removals
                if key in changes:
                    # This key has changed from base to new
                    new_value = changes[key]
                    if new_value == 'n':
                        f.write(f"# {key} is not set  (value changed)\n")
                    else:
                        f.write(f"{key}={new_value}\n")
                elif key in removals:
                    # This key was removed from base to new
                    if defaults_config.get(key) == original_value:
                        f.write(f"# {key}={original_value}  (now default, was explicitly set)\n")
                    else:
                        f.write(f"# {key}={original_value}  (not in new defconfig)\n")
                else:
                    # No change from base to new, keep original partial value
                    f.write(line.raw + '\n')
            else:
                # This key doesn't exist in base config, it's partial-specific
                # Keep it as-is unless it was explicitly changed in new
                if key in new_config:
                    # Key exists in new config, use the new value
                    new_value = new_config[key]
                    if new_value == 'n':
                        f.write(f"# {key} is not set  (updated from partial)\n")
                    else:
                        f.write(f"{key}={new_value}\n")
                else:
                    # Key doesn't exist in new config, keep partial value
                    f.write(line.raw + '\n')

        # Add new entries at the end
        if new_entries:
            f.write("\n")
            f.write("# " + "="*64 + "\n")
            f.write("# New entries added from menuconfig changes\n")
            f.write("# " + "="*64 + "\n")
            for key, value in sorted(new_entries.items()):
                if value == 'n':
                    f.write(f"# {key} is not set\n")
                else:
                    f.write(f"{key}={value}\n")

    print(f"✓ diff done → {output_file}")


def show_usage():
    """Show detailed usage information"""
    print("""USAGE: buildroot_config_tool.py {merge|diff} [OPTIONS] [FILES...]

COMMANDS:
  merge [-o output] <defconfig1> [defconfig2] ...
    Merge multiple defconfig files, with later files overriding earlier ones
    BR2_* environment variables take highest priority

  diff -o <output> [-d <defconfig.defaults>] <old.defconfig> <new.defconfig> <partial.defconfig>
    Update partial defconfig with changes from menuconfig
    NOTE: Both old and new defconfigs must be minimal defconfigs (not full .config files)

OPTIONS:
  -h, --help      Show this help
  -o, --output    Output file (required for diff, optional for merge)
  -d, --defaults  Defaults file (full .config format) to distinguish defaults from removals

EXAMPLES:
  ./buildroot_config_tool.py merge -o _build/system/build/defconfig system_common/defconfig system_grisp2/defconfig
  ./buildroot_config_tool.py diff -o system_grisp2/defconfig -d _build/system/build/defconfig.defaults _build/system/build/defconfig.ref _build/system/build/defconfig system_grisp2/defconfig

WORKFLOW:
  1. Merge partials: ./scripts/buildroot_config_tool.py merge -o _build/system/build/defconfig system_common/defconfig system_grisp2/defconfig
  2. Backup current: cp _build/system/build/defconfig _build/system/build/defconfig.ref
  3. Generate new .config: make defconfig
  4. Run menuconfig: make menuconfig
  5. Save new config: make savedefconfig
  6. Update partial:  ./scripts/buildroot_config_tool.py diff -o system_grisp2/defconfig _build/system/build/defconfig.ref _build/system/build/defconfig system_grisp2/defconfig

Optional defaults file (for better diff comments):
  Generate once for a given version of buildroot:
    1. rm -rf _build/system/temp
    2. make -C $PWD/_build/system/buildroot O=$PWD/_build/system/temp defconfig
    3. cp _build/system/temp/.config _build/system/build/defconfig.defaults
    4. rm -rf _build/system/temp
  Use with diff command:
    ./scripts/buildroot_config_tool.py diff -o system_grisp2/defconfig -d _build/system/build/defconfig.defaults _build/system/build/defconfig.ref _build/system/build/defconfig system_grisp2/defconfig
""")


def main():
    """Main entry point"""

    # Handle help separately first
    if len(sys.argv) == 1 or (len(sys.argv) >= 2 and sys.argv[1] in ['-h', '--help']):
        show_usage()
        sys.exit(0)

    # Use subparsers for cleaner command handling
    parser = argparse.ArgumentParser(description='Buildroot defconfig merge and diff tool')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Merge command
    merge_parser = subparsers.add_parser('merge', help='Merge multiple defconfig files')
    merge_parser.add_argument('-o', '--output', type=Path,
                             help='Output file (default: defconfig)')
    merge_parser.add_argument('files', nargs='+', type=Path,
                             help='Input defconfig files to merge')

    # Diff command
    diff_parser = subparsers.add_parser('diff', help='Update partial defconfig with changes')
    diff_parser.add_argument('-o', '--output', type=Path, required=True,
                            help='Output file (required)')
    diff_parser.add_argument('-d', '--defaults', type=Path,
                            help='Defaults file (full .config format)')
    diff_parser.add_argument('base_file', type=Path,
                            help='Base defconfig file')
    diff_parser.add_argument('new_file', type=Path,
                            help='New defconfig file')
    diff_parser.add_argument('partial_file', type=Path,
                            help='Partial defconfig file to update')

    args = parser.parse_args()

    # Validate command was provided
    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Execute commands
    if args.command == 'merge':
        # Set default output if not provided
        if not args.output:
            args.output = Path('defconfig')

        merge_configs(args.output, args.files)

    elif args.command == 'diff':
        diff_configs(args.output, args.base_file, args.new_file, args.partial_file, args.defaults)


if __name__ == '__main__':
    main()
