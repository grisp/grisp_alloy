#!/usr/bin/env bash
set -euo pipefail

hook_name="$(basename "${0}")"
hook_type="${hook_name%.sh}"
hook_type="${hook_type//-/_}"

cat >&2 <<EOF
ERROR: Buildroot hook wrapper stub invoked (${hook_name}, type=${hook_type}).
ERROR: Full hook dispatch is tracked in Task 5.6a.
EOF
exit 2
