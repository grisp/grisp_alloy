#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    otp_version)
        printf '28.4\n'
        ;;
    *)
        printf 'unsupported feature_erlang export key: %s\n' "${1:-}" >&2
        exit 1
        ;;
esac
