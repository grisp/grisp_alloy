#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/lib/test_helpers.sh
source "${SCRIPT_DIR}/lib/test_helpers.sh"

ARTEFACT_SERVER_TOOL="$(harness_repo_root)/scripts/tools/artefact-server"

artefact_server_test_pick_port() {
    echo "$((RANDOM % 10000 + 20000))"
}

artefact_server_test_stop_server() {
    local server_pid="${1:-}"
    if [[ -n "${server_pid}" ]]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
    fi
}

artefact_server_test_wait_ready() {
    local url="$1"
    local server_pid="$2"
    local log_file="$3"
    local -a curl_args=()
    if [[ "${url}" == https://* ]]; then
        curl_args+=(-k)
    fi
    local attempt

    for attempt in $(seq 1 50); do
        if curl -fsS "${curl_args[@]}" "${url}" >/dev/null 2>&1; then
            return 0
        fi

        if ! kill -0 "${server_pid}" 2>/dev/null; then
            cat "${log_file}" >&2
            return 1
        fi

        sleep 0.1
    done

    cat "${log_file}" >&2
    return 1
}

artefact_server_test_start_server() {
    local root_dir="$1"
    local ready_url_template="$2"
    local log_file="$3"
    shift 3

    local port server_pid ready_url
    local attempt
    for attempt in $(seq 1 20); do
        port="$(artefact_server_test_pick_port)"
        ready_url="${ready_url_template//__PORT__/${port}}"

        "${ARTEFACT_SERVER_TOOL}" --root "${root_dir}" --port "${port}" "$@" >"${log_file}" 2>&1 &
        server_pid=$!

        if artefact_server_test_wait_ready "${ready_url}" "${server_pid}" "${log_file}"; then
            printf '%s %s\n' "${server_pid}" "${port}"
            return 0
        fi

        artefact_server_test_stop_server "${server_pid}"
    done

    return 1
}

artefact_server_test_make_tls_material() {
    local cert_file="$1"
    local key_file="$2"
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${key_file}" \
        -out "${cert_file}" \
        -subj "/CN=localhost" \
        -days 1 >/dev/null 2>&1
}

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

test_artefact_server_serves_regular_file_over_http() {
    harness_require_command curl

    local temp_dir artefact_dir payload_file log_file
    temp_dir="$(harness_make_temp_dir "artefact-server-http")"
    artefact_dir="${temp_dir}/artefacts"
    payload_file="${artefact_dir}/firmware.txt"
    log_file="${temp_dir}/server.log"
    mkdir -p "${artefact_dir}"
    printf 'http-payload\n' > "${payload_file}"

    local server_pid="" port response
    trap 'artefact_server_test_stop_server "${server_pid}"; trap - RETURN' RETURN
    read -r server_pid port < <(
        artefact_server_test_start_server "${artefact_dir}" "http://127.0.0.1:__PORT__/" "${log_file}"
    )

    response="$(curl -fsS "http://127.0.0.1:${port}/firmware.txt")"
    assert_equals "http-payload" "${response}"
}

test_artefact_server_serves_regular_file_over_https() {
    harness_require_command curl
    harness_require_command openssl

    local temp_dir artefact_dir cert_file key_file payload_file log_file
    temp_dir="$(harness_make_temp_dir "artefact-server-https")"
    artefact_dir="${temp_dir}/artefacts"
    cert_file="${temp_dir}/server.pem"
    key_file="${temp_dir}/server.key"
    payload_file="${artefact_dir}/release.txt"
    log_file="${temp_dir}/server.log"
    mkdir -p "${artefact_dir}"
    printf 'https-payload\n' > "${payload_file}"
    artefact_server_test_make_tls_material "${cert_file}" "${key_file}"

    local server_pid="" port response
    trap 'artefact_server_test_stop_server "${server_pid}"; trap - RETURN' RETURN
    read -r server_pid port < <(
        artefact_server_test_start_server \
            "${artefact_dir}" \
            "https://127.0.0.1:__PORT__/" \
            "${log_file}" \
            --certfile "${cert_file}" \
            --keyfile "${key_file}"
    )

    response="$(curl -kfsS "https://127.0.0.1:${port}/release.txt")"
    assert_equals "https-payload" "${response}"
}

test_artefact_server_serves_tar_member_over_http() {
    harness_require_command curl
    harness_require_command tar

    local temp_dir artefact_dir tar_input_dir log_file response
    temp_dir="$(harness_make_temp_dir "artefact-server-tar")"
    artefact_dir="${temp_dir}/artefacts"
    tar_input_dir="${temp_dir}/tar-input"
    log_file="${temp_dir}/server.log"
    mkdir -p "${artefact_dir}" "${tar_input_dir}/nested"
    printf 'tar-payload\n' > "${tar_input_dir}/nested/info.txt"
    tar -C "${tar_input_dir}" -cf "${artefact_dir}/bundle.tar" nested

    local server_pid="" port
    trap 'artefact_server_test_stop_server "${server_pid}"; trap - RETURN' RETURN
    read -r server_pid port < <(
        artefact_server_test_start_server "${artefact_dir}" "http://127.0.0.1:__PORT__/" "${log_file}"
    )

    response="$(curl -fsS "http://127.0.0.1:${port}/bundle/nested/info.txt")"
    assert_equals "tar-payload" "${response}"
}
