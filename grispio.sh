#!/usr/bin/env bash

# grispio.sh - Interface to the grisp.io cloud platform
#
# Commands:
#   authenticate    Obtain and locally store an encrypted API token
#   upload          Upload a software update package (.tar)
#   delete          Delete a software update package by name/prefix/path
#   deploy          Deploy a software update package to a device
#   validate        Validate a software update on a device
#   reboot          Reboot a device
#
# Conventions:
# - Arguments parsed with scripts/argparse.sh (GNU-like)
# - Common helpers/paths from scripts/common.sh
# - Encrypted token stored at ${GLB_TOP_DIR}/.grispio.token
# - Token encryption: OpenSSL AES-256-CBC with PBKDF2 and salt
#
# Defaults:
# - Host: app.grisp.io  (override: -H | --host)
# - Port: 443           (override: -P | --port)
# - TLS:  verify by default (override: --insecure)
# - Token name (authenticate): grisp_alloy_client_token (override: --token-name)
#
# Notes:
# - Device option (-D | --device) is required for deploy and validate

set -e

# Capture raw args for subcommand routing
ARGS=( "$@" )

show_usage()
{
    echo "USAGE: grispio.sh [GLOBAL_OPTIONS] COMMAND [ARGS]"
    echo
    echo "GLOBAL OPTIONS:"
    echo " -h | --help"
    echo "    Show this help"
	echo " -d | --debug"
	echo "    Print scripts debug information"
    echo " -H | --host <HOST>"
    echo "    API host (default: app.grisp.io)"
    echo " -P | --port <PORT>"
    echo "    API port (default: 443)"
    echo "     | --insecure"
    echo "    Do not verify TLS certificate (curl -k)"
    echo " -s | --secret <LOCAL_SECRET>"
    echo "    Local password used to encrypt/decrypt the stored token"
    echo " -u | --username <USERNAME>"
    echo "    grisp.io username (authenticate)"
    echo " -p | --password <PASSWORD>"
    echo "    grisp.io password (authenticate)"
    echo " -t | --token-name <NAME>"
    echo "    Token name for authenticate (default: grisp_alloy_client_token)"
	echo " -D | --device <PLATFORM:SERIAL>"
	echo "    Device as PLATFORM:SERIAL (deploy, validate)"
    echo
    echo "COMMANDS:"
    echo "  authenticate"
    echo "     Authenticate to grisp.io and store encrypted API token locally"
    echo
    echo "  upload <PACKAGE_PATH|PREFIX>"
    echo "     Upload a software update package (.tar). If a prefix is given,"
    echo "     search ./artefacts for a single matching .tar file."
    echo
    echo "  delete <PACKAGE_NAME|PACKAGE_PATH|PREFIX>"
    echo "     Delete a software update package. Accepts a full name ending with"
    echo "     .tar (path or not), or a prefix in ./artefacts (must be unique)."
    echo
    echo "  deploy <PACKAGE_NAME|PACKAGE_PATH|PREFIX> -D <PLATFORM:SERIAL>"
    echo "     Deploy a software update package to a device."
    echo
	echo "  reboot -D <PLATFORM:SERIAL>"
	echo "     Reboot a device."
	echo
    echo "  validate -D <PLATFORM:SERIAL>"
    echo "     Validate a software update on a given device."
    echo
    echo "Examples:"
    echo "  grispio.sh authenticate -u alice --token-name cli_token"
    echo "  grispio.sh upload artefacts/my_app-1.0.0-grisp2.tar"
    echo "  grispio.sh upload my_app-1.0.0-grisp2"
	echo "  grispio.sh deploy my_app -D kontron-albl-imx8mm:00000000"
	echo "  grispio.sh reboot -D kontron-albl-imx8mm:00000000"
	echo "  grispio.sh validate -D kontron-albl-imx8mm:00000000"
    echo "  grispio.sh delete my_app-1.0.0-grisp2.tar"
}

# Parse global arguments
source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 0
args_add H host ARG_HOST value "app.grisp.io"
args_add P port ARG_PORT value "443"
args_add "" insecure ARG_INSECURE flag true false
args_add s secret ARG_SECRET value ""
args_add u username ARG_USERNAME value ""
args_add p password ARG_PASSWORD value ""
args_add t token-name ARG_TOKEN_NAME value "grisp_alloy_client_token"
args_add D device ARG_DEVICE value ""

if ! args_parse "$@"; then
    exit 1
fi
if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi

# Remaining positional tokens (first should be command)
RAW_TOKENS=( "${POSITIONAL[@]}" )
set --
if [[ ${#RAW_TOKENS[@]} -lt 1 ]]; then
    echo "ERROR: Missing command"
    show_usage
    exit 1
fi
COMMAND="${RAW_TOKENS[0]}"
RAW_TOKENS=( "${RAW_TOKENS[@]:1}" )

# Load common helpers and environment
source "$( dirname "$0" )/scripts/common.sh"
set_debug_level "${ARG_DEBUG}"

TOKEN_FILE="${GLB_TOP_DIR}/.grispio.token"
API_SCHEME="https"

# ---- helpers ----

build_base_url()
{
    local host="$1"
    local port="$2"
    echo "${API_SCHEME}://${host}:${port}"
}

prompt_if_empty()
{
    local var_name="$1"
    local prompt="$2"
    local silent="${3:-false}"
    local current_val=""
    eval "current_val=\${$var_name}"
    if [[ -z "$current_val" ]]; then
        if [[ "$silent" == "true" ]]; then
            enter_hidden
            read -s -p "$prompt" current_val
			echo 1>&2
            leave_hidden
        else
            read -p "$prompt" current_val
        fi
        eval "$var_name=\$current_val"
    fi
}

require_cmd()
{
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        error 1 "Missing required command: $name"
    fi
}

encrypt_and_store_token()
{
    local token="$1"
    local secret="$2"
    require_cmd openssl
    local tmp_payload
    tmp_payload="$(mktemp)"
    # Add header marker for decryption validation
    {
        echo "GRISPIO_TOKENv1"
        echo "$token"
    } > "$tmp_payload"
    enter_hidden
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$secret" -in "$tmp_payload" -out "$TOKEN_FILE"
    leave_hidden
    rm -f "$tmp_payload"
    chmod 600 "$TOKEN_FILE" || true
}

decrypt_token()
{
    local secret="$1"
    require_cmd openssl
    if [[ ! -f "$TOKEN_FILE" ]]; then
        echo ""
        return 2
    fi
    local tmp_out
    tmp_out="$(mktemp)"
    set +e
    enter_hidden
	openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$secret" -in "$TOKEN_FILE" -out "$tmp_out" 2>/dev/null
    local rc=$?
    leave_hidden
    set -e
    if [[ $rc -ne 0 ]]; then
        rm -f "$tmp_out"
        echo ""
        return 3
    fi
    local header
    header="$( head -n1 "$tmp_out" | tr -d '\r' )"
    if [[ "$header" != "GRISPIO_TOKENv1" ]]; then
        rm -f "$tmp_out"
        echo ""
        return 4
    fi
    local token
    token="$( sed -n '2p' "$tmp_out" | tr -d '\r' )"
    rm -f "$tmp_out"
    echo "$token"
    return 0
}

require_token()
{
    local secret="$ARG_SECRET"
    if [[ -z "$secret" ]]; then
        prompt_if_empty ARG_SECRET "Local secret: " true
        secret="$ARG_SECRET"
    fi
    local token
    token="$( decrypt_token "$secret" )" || true
    if [[ -z "$token" ]]; then
        if [[ ! -f "$TOKEN_FILE" ]]; then
            error 1 "Missing token. Run 'grispio.sh authenticate' first."
        fi
        error 1 "Invalid local secret."
    fi
    echo "$token"
}

basic_auth_header()
{
    local user="$1"
    local pass="$2"
    require_cmd base64
    # Base64 without newlines
    local b64
    b64="$( printf '%s:%s' "$user" "$pass" | base64 | tr -d '\n' )"
    echo "Authorization: Basic $b64"
}

bearer_auth_header()
{
    local token="$1"
    echo "Authorization: Bearer $token"
}

curl_flags_common()
{
    local flags=( )
    if [[ ${GLB_DEBUG:-0} -gt 0 ]]; then
        flags+=( -v )
    else
        flags+=( -sS )
    fi
    if [[ $ARG_INSECURE == true ]]; then
        flags+=( -k )
    fi
    # Prefer HTTP/1.1 for better compatibility with some local/self-signed setups
    flags+=( --http1.1 )
    echo "${flags[@]}"
}

extract_json_token()
{
    # Read JSON from stdin and extract value of "token"
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}

is_tar_with_manifest()
{
    local file="$1"
    if [[ "${file##*.}" != "tar" ]]; then
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    # Use TAR from common.sh environment if available
    local TAR_CMD="${TAR:-tar}"
    set +e
    local listing
    listing="$("$TAR_CMD" -tf "$file" 2>/dev/null)" || true
    set -e
    if echo "$listing" | awk '{print}' | grep -qx "MANIFEST"; then
        return 0
    fi
    if echo "$listing" | awk '{print}' | grep -qx "./MANIFEST"; then
        return 0
    fi
    return 1
}

find_artifact_tar_by_prefix()
{
    local prefix="$1"
    local matches=( )
    # List matches under artefacts dir
    matches=( $( ls -1 "${GLB_ARTEFACTS_DIR}/${prefix}"*.tar 2>/dev/null || true ) )
    if [[ ${#matches[@]} -eq 1 ]]; then
        echo "${matches[0]}"
        return 0
    elif [[ ${#matches[@]} -gt 1 ]]; then
        echo "WARNING: Multiple artefacts found for prefix '${prefix}':" 1>&2
        for m in "${matches[@]}"; do
            # Print relative to artefacts dir
            echo "  artefacts/$( basename "$m" )" 1>&2
        done
        return 2
    else
        return 1
    fi
}

resolve_upload_tar()
{
    local spec="$1"
    # If a file path exists, use it
    if [[ -f "$spec" ]]; then
        echo "$( cd "$( dirname "$spec" )" && pwd )/$( basename "$spec" )"
        return 0
    fi
    # Else try prefix under artefacts
    local found
    found="$( find_artifact_tar_by_prefix "$spec" )" || {
        local code=$?
        if [[ $code -eq 2 ]]; then
            error 1 "Multiple project options error"
        fi
        error 1 "No artefact matching prefix '${spec}'"
    }
    echo "$found"
}

resolve_package_name_for_name_path_prefix()
{
    local spec="$1"
    # If spec ends with .tar and contains path, use basename as package name
    if [[ "$spec" == *.tar ]]; then
        echo "$( basename "$spec" )"
        return 0
    fi
    # If path to an existing file (without .tar checked above), use basename if it ends with .tar
    if [[ -f "$spec" ]]; then
        echo "$( basename "$spec" )"
        return 0
    fi
    # Treat as prefix inside artefacts
    local found
    found="$( find_artifact_tar_by_prefix "$spec" )" || {
        local code=$?
        if [[ $code -eq 2 ]]; then
            error 1 "Multiple project options error"
        fi
        error 1 "No artefact matching prefix '${spec}'"
    }
    echo "$( basename "$found" )"
}

# ---- package name conversion/validation ----

is_path_under_artefacts()
{
	local path="$1"
	local abs="$( cd "$( dirname "$path" )" && pwd )/$( basename "$path" )"
	[[ "$abs" == "$GLB_ARTEFACTS_DIR/"* ]]
}

artefact_tar_to_api_name()
{
	# Convert APP-VERSION-PLATFORM.tar -> PLATFORM.APP.VERSION.tar
	local base="$1"
	base="${base%.tar}"
	# split by '-' into array
	local IFS='-'
	read -r -a parts <<< "$base"
	local n="${#parts[@]}"
	if [[ "$n" -lt 3 ]]; then
		return 1
	fi
	# find first segment that starts with a digit -> version index
	local vi=-1
	local i=0
	while [[ $i -lt $n ]]; do
		if [[ "${parts[$i]}" =~ ^[0-9] ]]; then
			vi=$i
			break
		fi
		i=$((i+1))
	done
	# must have at least one part for app before version and at least one part for platform after version
	if [[ $vi -le 0 || $vi -ge $((n-1)) ]]; then
		return 1
	fi
	# join helpers
	local app=""
	for ((i=0; i<vi; i++)); do
		if [[ -n "$app" ]]; then app+="-"; fi
		app+="${parts[$i]}"
	done
	local version="${parts[$vi]}"
	local platform=""
	for ((i=vi+1; i<n; i++)); do
		if [[ -n "$platform" ]]; then platform+="-"; fi
		platform+="${parts[$i]}"
	done
	echo "${platform}.${app}.${version}.tar"
	return 0
}

validate_api_pkg_name()
{
	# Accept PLATFORM.APP.VERSION[.PROFILE].tar (segments allow [A-Za-z0-9._-])
	local name="$1"
	if [[ "$name" =~ ^[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+(\.[A-Za-z0-9._-]+)?\.tar$ ]]; then
		return 0
	fi
	return 1
}

parse_device_spec()
{
	# Input: PLATFORM:SERIAL -> sets DEV_PLATFORM, DEV_SERIAL
	local spec="$1"
	if [[ "$spec" =~ ^([^:]+):([A-Za-z0-9]+)$ ]]; then
		DEV_PLATFORM="${BASH_REMATCH[1]}"
		DEV_SERIAL="${BASH_REMATCH[2]}"
		return 0
	fi
	return 1
}

pkg_platform_from_api_name()
{
	# PLATFORM.APP.VERSION(.PROFILE).tar -> PLATFORM
	local name="$1"
	name="${name%.tar}"
	echo "${name%%.*}"
}

get_api_pkg_name_for_tar_path()
{
	local tar_path="$1"
	local base="$( basename "$tar_path" )"
	if is_path_under_artefacts "$tar_path"; then
		local api_name
		api_name="$( artefact_tar_to_api_name "$base" )" || error 1 "Cannot convert artefact name '$base' to API package format"
		echo "$api_name"
		return 0
	fi
	# Not under artefacts: expect already API format
	if ! validate_api_pkg_name "$base"; then
		error 1 "Package file name must be PLATFORM.APP.VERSION[.PROFILE].tar (got '$base')"
	fi
	echo "$base"
}

resolve_api_package_name_for_name_path_prefix()
{
	local spec="$1"
	# If explicit .tar
	if [[ "$spec" == *.tar ]]; then
		if [[ -f "$spec" ]]; then
			# Path to file → convert if under artefacts; else validate
			get_api_pkg_name_for_tar_path "$spec"
			return 0
		fi
		# Plain name → validate
		if ! validate_api_pkg_name "$( basename "$spec" )"; then
			error 1 "Package name must be PLATFORM.APP.VERSION[.PROFILE].tar (got '$( basename "$spec" )')"
		fi
		echo "$( basename "$spec" )"
		return 0
	fi
	# Treat as prefix inside artefacts
	local found
	found="$( find_artifact_tar_by_prefix "$spec" )" || {
		local code=$?
		if [[ $code -eq 2 ]]; then
			error 1 "Multiple project options error"
		fi
		error 1 "No artefact matching prefix '${spec}'"
	}
	local base="$( basename "$found" )"
	local api_name
	api_name="$( artefact_tar_to_api_name "$base" )" || error 1 "Cannot convert artefact name '$base' to API package format"
	echo "$api_name"
}

# ---- command handlers ----

cmd_authenticate()
{
    prompt_if_empty ARG_SECRET "Local secret (to encrypt token): " true
    prompt_if_empty ARG_USERNAME "grisp.io username: " false
    prompt_if_empty ARG_PASSWORD "grisp.io password: " true

    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local url="${base_url}/eresu/api/auth"
    local auth_header
    auth_header="$( basic_auth_header "$ARG_USERNAME" "$ARG_PASSWORD" )"

    local tmp_body
    tmp_body="$(mktemp)"
    local http_code
	set +e
	http_code="$( curl $(curl_flags_common) -X POST \
        -H "$auth_header" \
        -H "content-type: application/json" \
        -d "{\"name\":\"${ARG_TOKEN_NAME}\"}" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	local curl_rc=$?
	set -e

    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "000" ]]; then
            echo "ERROR: Authentication request failed (network/TLS). Check host/port and certificate settings." 1>&2
        else
            echo "ERROR: Authentication failed (HTTP $http_code)" 1>&2
        fi
        cat "$tmp_body" 1>&2 || true
        rm -f "$tmp_body"
        exit 1
    fi

    local token
    token="$( cat "$tmp_body" | extract_json_token )"
    rm -f "$tmp_body"
    if [[ -z "$token" ]]; then
        error 1 "Failed to parse token from response"
    fi
    encrypt_and_store_token "$token" "$ARG_SECRET"
    echo "Authentication successful. Token stored in $( basename "$TOKEN_FILE" )."
}

cmd_upload()
{
    if [[ ${#RAW_TOKENS[@]} -lt 1 ]]; then
        error 1 "Missing package path or prefix"
    fi
    local spec="${RAW_TOKENS[0]}"
    local tar_path
    tar_path="$( resolve_upload_tar "$spec" )"
    if ! is_tar_with_manifest "$tar_path"; then
        error 1 "Invalid package: must be a .tar containing MANIFEST at root"
    fi
    local token
    token="$( require_token )"

    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local pkg_name
    pkg_name="$( get_api_pkg_name_for_tar_path "$tar_path" )"
    local url="${base_url}/grisp-manager/api/update-package/${pkg_name}"

	local http_code
	local tmp_body
	tmp_body="$(mktemp)"
	set +e
	http_code="$( curl $(curl_flags_common) -X PUT \
        -H "$( bearer_auth_header "$token" )" \
        -H "Expect:" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${tar_path}" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	set -e
	if [[ "$http_code" != "200" && "$http_code" != "201" && "$http_code" != "204" ]]; then
		echo "ERROR: Upload failed (HTTP $http_code)" 1>&2
		cat "$tmp_body" 1>&2 || true
		rm -f "$tmp_body"
		exit 1
	fi
	rm -f "$tmp_body"
	echo "Upload successful: ${pkg_name}"
}

cmd_delete()
{
    if [[ ${#RAW_TOKENS[@]} -lt 1 ]]; then
        error 1 "Missing package name/path/prefix"
    fi
    local spec="${RAW_TOKENS[0]}"
    local pkg_name
    pkg_name="$( resolve_api_package_name_for_name_path_prefix "$spec" )"
    local token
    token="$( require_token )"

    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local url="${base_url}/grisp-manager/api/update-package/${pkg_name}"

    local http_code
	local tmp_body
	tmp_body="$(mktemp)"
	set +e
	http_code="$( curl $(curl_flags_common) -X DELETE \
        -H "$( bearer_auth_header "$token" )" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	set -e
	if [[ "$http_code" != "200" && "$http_code" != "204" ]]; then
		if [[ "$http_code" == "400" ]]; then
			echo "ERROR: Delete failed (HTTP 400)" 1>&2
			cat "$tmp_body" 1>&2 || true
			rm -f "$tmp_body"
			exit 1
		fi
		rm -f "$tmp_body"
		error 1 "Delete failed (HTTP $http_code)"
	fi
	rm -f "$tmp_body"
	echo "Delete successful: ${pkg_name}"
}

cmd_deploy()
{
    if [[ ${#RAW_TOKENS[@]} -lt 1 ]]; then
        error 1 "Missing package name/path/prefix"
    fi
    if [[ -z "$ARG_DEVICE" ]]; then
        error 1 "Missing required -D | --device"
    fi
    local spec="${RAW_TOKENS[0]}"
    local pkg_name
    pkg_name="$( resolve_api_package_name_for_name_path_prefix "$spec" )"
    local token
    token="$( require_token )"

    # parse device PLATFORM:SERIAL
    if ! parse_device_spec "$ARG_DEVICE"; then
        error 1 "Invalid device format. Expected PLATFORM:SERIAL"
    fi
    # verify device platform matches package platform
    local pkg_platform
    pkg_platform="$( pkg_platform_from_api_name "$pkg_name" )"
    if [[ "$pkg_platform" != "$DEV_PLATFORM" ]]; then
        error 1 "Device platform '$DEV_PLATFORM' does not match package platform '$pkg_platform'"
    fi

    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local url="${base_url}/grisp-manager/api/deploy-update/${pkg_name}?serial_number=${DEV_SERIAL}&platform=${DEV_PLATFORM}"

	local http_code
	local tmp_body
	tmp_body="$(mktemp)"
	set +e
	http_code="$( curl $(curl_flags_common) -X POST \
        -H "$( bearer_auth_header "$token" )" \
        -H "Expect:" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	set -e
	if [[ "$http_code" != "200" && "$http_code" != "202" && "$http_code" != "204" ]]; then
		echo "ERROR: Deploy failed (HTTP $http_code)" 1>&2
		cat "$tmp_body" 1>&2 || true
		rm -f "$tmp_body"
		exit 1
	fi
	rm -f "$tmp_body"
	echo "Deploy triggered: ${pkg_name} -> device ${DEV_PLATFORM}:${DEV_SERIAL}"
}

cmd_validate()
{
    if [[ -z "$ARG_DEVICE" ]]; then
        error 1 "Missing required -D | --device"
    fi
    local token
    token="$( require_token )"
    if ! parse_device_spec "$ARG_DEVICE"; then
        error 1 "Invalid device format. Expected PLATFORM:SERIAL"
    fi
    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local url="${base_url}/grisp-manager/api/validate-update?serial_number=${DEV_SERIAL}&platform=${DEV_PLATFORM}"
    local http_code
	local tmp_body
	tmp_body="$(mktemp)"
	set +e
	http_code="$( curl $(curl_flags_common) -X POST \
        -H "$( bearer_auth_header "$token" )" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	set -e
	if [[ "$http_code" != "200" && "$http_code" != "202" && "$http_code" != "204" ]]; then
		if [[ "$http_code" == "400" ]]; then
			echo "ERROR: Validate failed (HTTP 400)" 1>&2
			cat "$tmp_body" 1>&2 || true
			rm -f "$tmp_body"
			exit 1
		fi
		rm -f "$tmp_body"
		error 1 "Validate failed (HTTP $http_code)"
	fi
	rm -f "$tmp_body"
	echo "Validate triggered for device ${DEV_PLATFORM}:${DEV_SERIAL}"
}

cmd_reboot()
{
    if [[ -z "$ARG_DEVICE" ]]; then
        error 1 "Missing required -D | --device"
    fi
    local token
    token="$( require_token )"
    if ! parse_device_spec "$ARG_DEVICE"; then
        error 1 "Invalid device format. Expected PLATFORM:SERIAL"
    fi
    local base_url
    base_url="$( build_base_url "$ARG_HOST" "$ARG_PORT" )"
    local url="${base_url}/grisp-manager/api/reboot-device?serial_number=${DEV_SERIAL}&platform=${DEV_PLATFORM}"
    local http_code
	local tmp_body
	tmp_body="$(mktemp)"
	set +e
	http_code="$( curl $(curl_flags_common) -X POST \
        -H "$( bearer_auth_header "$token" )" \
        -w "%{http_code}" -o "$tmp_body" \
		"$url" )"
	set -e
	if [[ "$http_code" != "200" && "$http_code" != "202" && "$http_code" != "204" ]]; then
		if [[ "$http_code" == "400" ]]; then
			echo "ERROR: Reboot failed (HTTP 400)" 1>&2
			cat "$tmp_body" 1>&2 || true
			rm -f "$tmp_body"
			exit 1
		fi
		rm -f "$tmp_body"
        error 1 "Reboot failed (HTTP $http_code)"
    fi
	rm -f "$tmp_body"
    echo "Reboot triggered for device ${DEV_PLATFORM}:${DEV_SERIAL}"
}

# ---- dispatch ----

case "$COMMAND" in
    authenticate) cmd_authenticate ;;
    upload)       cmd_upload ;;
    delete)       cmd_delete ;;
    deploy)       cmd_deploy ;;
    validate)     cmd_validate ;;
    reboot)       cmd_reboot ;;
    *)
        echo "ERROR: Unknown command '$COMMAND'" 1>&2
        show_usage
        exit 1
        ;;
esac

exit 0
