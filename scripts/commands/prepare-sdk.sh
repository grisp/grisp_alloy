#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=scripts/utils/sdk_utils.sh
source "${SCRIPT_DIR}/../utils/sdk_utils.sh"

if [[ ! -f "${ALLOY_ROOT}/ALLOY_SDK_MANIFEST" ]]; then
    fail "prepare sdk is only available in sdk mode"
fi

if check_sdk_relocation "${ALLOY_ROOT}"; then
    print_result "SDK is already relocated."
    exit 0
fi

print_note "Relocating SDK to $(cd "${ALLOY_ROOT}" && pwd -P)..."
relocate_sdk "${ALLOY_ROOT}"
