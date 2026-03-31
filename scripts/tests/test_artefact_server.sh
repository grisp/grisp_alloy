#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

ARTEFACT_SERVER_TOOL="$(harness_repo_root)/scripts/tools/artefact-server"

test_artefact_server_help_shows_canonical_usage() {
    local output
    output="$("${ARTEFACT_SERVER_TOOL}" --help 2>&1)"

    assert_matches "Usage: artefact-server \\[OPTIONS\\]" "${output}"
    assert_matches "--certfile FILE" "${output}"
    assert_matches "--security-pack PATH" "${output}"
    assert_matches "--identity IDENTITY" "${output}"
}

test_artefact_server_rejects_identity_without_security_pack() {
    local output status
    output="$("${ARTEFACT_SERVER_TOOL}" --identity prod-server 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "--identity is only valid with --security-pack" "${output}"
}

test_artefact_server_rejects_partial_manual_tls_configuration() {
    local output status
    output="$("${ARTEFACT_SERVER_TOOL}" --certfile server.pem 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "--certfile and --keyfile must be provided together" "${output}"
}

test_artefact_server_rejects_cacertfile_without_manual_tls() {
    local output status
    output="$("${ARTEFACT_SERVER_TOOL}" --cacertfile devices.pem 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "--cacertfile requires --certfile and --keyfile" "${output}"
}

test_artefact_server_rejects_manual_tls_with_security_pack() {
    local output status
    output="$("${ARTEFACT_SERVER_TOOL}" --security-pack ./secpack --certfile server.pem --keyfile server.key 2>&1)"
    status=$?

    assert_equals "1" "${status}"
    assert_matches "--security-pack is mutually exclusive with --certfile/--keyfile/--cacertfile" "${output}"
}
