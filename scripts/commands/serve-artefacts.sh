#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ALLOY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
exec "${ROOT_DIR}/scripts/tools/artefact-server" "$@"
