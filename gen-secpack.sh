#!/usr/bin/env bash

set -euo pipefail

show_usage()
{
    cat <<EOF
USAGE: gen-secpack.sh OPTIONS TARGET OUTPUT_DIR
OPTIONS:
 -h | --help
    Show this.
 -d | --debug
    Print script debug information.
 -f | --force
    Remove OUTPUT_DIR before generating the security pack.
 -V | --force-vagrant
    Using the Vagrant VM even on Linux
 -P | --provision
    Re-provision the vagrant VM; use to reflect some changes to the VM
 -K | --keep-vagrant
    Keep the vagrant VM running after exiting
 --no-update-signing
    Do not generate GRiSP update package signing material.
 --external <DIR>
    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs.

Examples:
  ./gen-secpack.sh grisp2 /tmp/grisp2-secpack
  ./gen-secpack.sh --force private-target /tmp/private-target-dev-secpack
EOF
}

# shellcheck source=scripts/argparse.sh
source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 0
args_add f force ARG_FORCE flag true false
args_add V force-vagrant ARG_FORCE_VAGRANT flag true false
args_add P provision ARG_PROVISION_VAGRANT flag true false
args_add K keep-vagrant ARG_KEEP_VAGRANT flag true false
args_add "" no-update-signing ARG_NO_UPDATE_SIGNING flag true false
args_add "" external ARG_EXTERNAL_DIRS accum

if ! args_parse "$@"; then
    exit 1
fi

if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi

POSITIONALS=( "${POSITIONAL[@]}" )
if [[ ${#POSITIONALS[@]} -lt 2 ]]; then
    echo "ERROR: Missing target or output directory"
    show_usage
    exit 1
fi
if [[ ${#POSITIONALS[@]} -gt 2 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

ARG_TARGET="${POSITIONALS[0]}"
ARG_OUTPUT_DIR="${POSITIONALS[1]}"

# shellcheck source=scripts/common.sh
source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"
set_debug_level "$ARG_DEBUG"

if [[ -z "${GLB_TARGET_SYSTEM_DIR:-}" || ! -d "$GLB_TARGET_SYSTEM_DIR" ]]; then
    error 1 "Target ${ARG_TARGET} not supported"
fi

case "$ARG_OUTPUT_DIR" in
    /*) ;;
    *)
        error 1 "Output directory must be absolute: $ARG_OUTPUT_DIR"
        ;;
esac

case "$ARG_OUTPUT_DIR" in
    /|/tmp|/tmp/|/opt|/opt/|/opt/herrmann|/opt/herrmann/|"$GLB_TOP_DIR"|"$GLB_TOP_DIR"/|"$GLB_TARGET_SYSTEM_DIR"|"$GLB_TARGET_SYSTEM_DIR"/|"$GLB_TARGET_SYSTEM_DIR"/*)
        error 1 "Refusing unsafe output directory: $ARG_OUTPUT_DIR"
        ;;
esac

if [[ -e "$ARG_OUTPUT_DIR" && $ARG_FORCE != true ]]; then
    if find "$ARG_OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
        error 1 "Refusing to write into non-empty directory without --force: $ARG_OUTPUT_DIR"
    fi
fi

if [[ $ARG_FORCE_VAGRANT == true ]] || [[ $HOST_OS != "linux" ]]; then
    VAGRANT_SECPACK_BUILD_DIR="${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/secpack-gen/${GLB_TARGET_NAME}"
    VAGRANT_OUTPUT_DIR="${VAGRANT_SECPACK_BUILD_DIR}/output"

    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi
    vagrant ssh-config > .vagrant.ssh_config
    vagrant exec rm -rf "$VAGRANT_SECPACK_BUILD_DIR"
    vagrant exec mkdir -p "$VAGRANT_SECPACK_BUILD_DIR"

    NEW_ARGS=( )
    if [[ ${ARG_DEBUG_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--debug" )
    fi
    if [[ ${ARG_FORCE_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--force" )
    fi
    if [[ ${ARG_NO_UPDATE_SIGNING_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--no-update-signing" )
    fi
    VAGRANT_EXTERNAL_DIRS=( )
    alloy_vagrant_sync_external_roots VAGRANT_EXTERNAL_DIRS
    for external_dir in "${VAGRANT_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
    done
    NEW_ARGS+=( "$ARG_TARGET" "$VAGRANT_OUTPUT_DIR" )

    if [[ $ARG_KEEP_VAGRANT == false ]]; then
        trap 'cd "$GLB_TOP_DIR"; vagrant halt' EXIT
    fi

    vagrant exec "${GLB_VAGRANT_TOP_DIR}/gen-secpack.sh" "${NEW_ARGS[@]}"

    if [[ $ARG_FORCE == true ]]; then
        rm -rf "$ARG_OUTPUT_DIR"
    fi
    mkdir -p "$ARG_OUTPUT_DIR"
    rsync -a --delete -e "ssh -F ${GLB_TOP_DIR}/.vagrant.ssh_config" \
        "vagrant@default:${VAGRANT_OUTPUT_DIR}/" "$ARG_OUTPUT_DIR/"
    vagrant exec rm -rf "$VAGRANT_SECPACK_BUILD_DIR"
    exit 0
fi

if [[ $ARG_FORCE == true ]]; then
    rm -rf "$ARG_OUTPUT_DIR"
fi

TARGET_SECPACK_CONF="${GLB_TARGET_SYSTEM_DIR}/secpack.conf"
TARGET_SECPACK_SCRIPT="${GLB_TARGET_SYSTEM_DIR}/secpack.sh"

if [[ ! -f "$TARGET_SECPACK_CONF" ]]; then
    error 1 "Security-pack target config not found: $TARGET_SECPACK_CONF"
fi

SECPACK_GENERATE_UPDATE_SIGNING=true
SECPACK_GENERATE_SECUREBOOT=false
SECPACK_DESCRIPTION="$GLB_TARGET_NAME development security pack"
SECPACK_DEVELOPMENT_ONLY=true

# shellcheck source=/dev/null
source "$TARGET_SECPACK_CONF"

if [[ $ARG_NO_UPDATE_SIGNING == true ]]; then
    SECPACK_GENERATE_UPDATE_SIGNING=false
fi

if [[ -f "$TARGET_SECPACK_SCRIPT" ]]; then
    # shellcheck source=/dev/null
    source "$TARGET_SECPACK_SCRIPT"
fi

install_sdk
alloy_verify_sdk_context_strict

OPENSSL_BIN="${GLB_SDK_HOST_DIR}/bin/openssl"
if [[ ! -x "$OPENSSL_BIN" ]]; then
    OPENSSL_BIN="$(command -v openssl || true)"
fi
if [[ -z "$OPENSSL_BIN" || ! -x "$OPENSSL_BIN" ]]; then
    error 1 "openssl not found in SDK host tools or PATH"
fi

mkdir -p "$ARG_OUTPUT_DIR"
mkdir -p "$ARG_OUTPUT_DIR/overlay"
mkdir -p "$ARG_OUTPUT_DIR/scripts"

write_secpack_script()
{
    cat > "$ARG_OUTPUT_DIR/secpack" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

PACK_DIR="$(cd "$(dirname "$0")" && pwd -P)"

usage()
{
    cat >&2 <<USAGE
Usage:
  secpack generate-overlay <out-dir> <serial> <profile>
  secpack secureboot-env
  secpack secureboot-validate
USAGE
}

copy_dir_contents()
{
    local src="$1"
    local dst="$2"

    if [[ ! -d "$src" ]]; then
        return 0
    fi
    mkdir -p "$dst"
    ( cd "$src" && tar cf - . ) | ( cd "$dst" && tar xf - )
}

generate_overlay()
{
    local out_dir="$1"
    local serial="$2"
    local profile="$3"
    local cert_src
    local cert_dst

    case "$out_dir" in
        ""|/)
            echo "ERROR: Refusing unsafe overlay output directory: $out_dir" >&2
            return 1
            ;;
    esac

    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    copy_dir_contents "$PACK_DIR/overlay" "$out_dir"

    cert_src="$PACK_DIR/grisp_updater/verification/signature_cert.pem"
    if [[ -f "$cert_src" ]]; then
        cert_dst="$out_dir/etc/grisp_runtime/certificates"
        mkdir -p "$cert_dst"
        cp "$cert_src" "$cert_dst/grisp-updater-signature.pem"
    fi

    if [[ -x "$PACK_DIR/scripts/generate-overlay" ]]; then
        "$PACK_DIR/scripts/generate-overlay" "$out_dir" "$serial" "$profile"
    fi
}

secureboot_env()
{
    printf 'SECPACK_ROOT=%q\n' "$PACK_DIR"
    if [[ -d "$PACK_DIR/secureboot" ]]; then
        printf 'SECPACK_SECUREBOOT_DIR=%q\n' "$PACK_DIR/secureboot"
        printf 'SECPACK_SECUREBOOT_KEYS_DIR=%q\n' "$PACK_DIR/secureboot/keys"
        printf 'SECPACK_SECUREBOOT_CRTS_DIR=%q\n' "$PACK_DIR/secureboot/crts"
        printf 'SECPACK_SECUREBOOT_EFUSE_DIR=%q\n' "$PACK_DIR/secureboot/efuse"
    fi
}

secureboot_validate()
{
    if [[ -x "$PACK_DIR/scripts/secureboot-validate" ]]; then
        "$PACK_DIR/scripts/secureboot-validate"
        return $?
    fi

    if [[ -d "$PACK_DIR/secureboot" ]]; then
        if find "$PACK_DIR/secureboot" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
            echo "ERROR: secureboot material is present but no scripts/secureboot-validate helper exists." >&2
            return 1
        fi
    fi

    echo "No secureboot material configured for this security pack."
}

case "${1:-}" in
    generate-overlay)
        if [[ $# -ne 4 ]]; then
            usage
            exit 1
        fi
        generate_overlay "$2" "$3" "$4"
        ;;
    secureboot-env)
        if [[ $# -ne 1 ]]; then
            usage
            exit 1
        fi
        secureboot_env
        ;;
    secureboot-validate)
        if [[ $# -ne 1 ]]; then
            usage
            exit 1
        fi
        secureboot_validate
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
EOF
    chmod 700 "$ARG_OUTPUT_DIR/secpack"
}

generate_update_signing()
{
    local verify_dir="$ARG_OUTPUT_DIR/grisp_updater/verification"
    local key_file="$verify_dir/signature_key.pem"
    local cert_file="$verify_dir/signature_cert.pem"

    mkdir -p "$verify_dir"
    "$OPENSSL_BIN" genrsa -out "$key_file" 4096 2>/dev/null
    chmod 600 "$key_file"
    "$OPENSSL_BIN" req -new -x509 \
        -key "$key_file" \
        -out "$cert_file" \
        -days 3650 \
        -batch \
        -subj "/CN=${GLB_TARGET_NAME} Development Update Signing/O=GRiSP Alloy/OU=Security Pack" \
        2>/dev/null
}

write_metadata()
{
    cat > "$ARG_OUTPUT_DIR/SECURITY-PACK" <<EOF
target=${GLB_TARGET_NAME}
description=${SECPACK_DESCRIPTION}
generated=$(date -Iseconds)
development_only=${SECPACK_DEVELOPMENT_ONLY}
update_signing=${SECPACK_GENERATE_UPDATE_SIGNING}
secureboot=${SECPACK_GENERATE_SECUREBOOT}
EOF
}

write_readme()
{
    cat > "$ARG_OUTPUT_DIR/README.security-pack.txt" <<EOF
${SECPACK_DESCRIPTION}

Generated for target: ${GLB_TARGET_NAME}
Generated at: $(date -Iseconds)

Development-only: ${SECPACK_DEVELOPMENT_ONLY}

Do not commit this directory. For production use, private keys must be generated
and handled under the approved production key-custody process, and the pack must
be validated before use.

Use with firmware builds:
  ./build-firmware.sh ${GLB_TARGET_NAME} <project-artifact> --security-pack ${ARG_OUTPUT_DIR}

If update signing was generated, signed update packages can use:
  ./build-firmware.sh ${GLB_TARGET_NAME} <project-artifact> --security-pack ${ARG_OUTPUT_DIR} --generate-update --sign-update
EOF
}

write_secpack_script

if [[ "$SECPACK_GENERATE_UPDATE_SIGNING" == "true" ]]; then
    generate_update_signing
fi

if declare -f secpack_target_generate >/dev/null; then
    secpack_target_generate "$ARG_OUTPUT_DIR"
elif [[ "$SECPACK_GENERATE_SECUREBOOT" == "true" ]]; then
    error 1 "$GLB_TARGET_NAME enables secureboot generation but $TARGET_SECPACK_SCRIPT does not define secpack_target_generate"
fi

write_metadata
write_readme

chmod -R go-rwx "$ARG_OUTPUT_DIR"
find "$ARG_OUTPUT_DIR" -type d -exec chmod 700 {} +
find "$ARG_OUTPUT_DIR" -type f -exec chmod 600 {} +
chmod 700 "$ARG_OUTPUT_DIR/secpack"
find "$ARG_OUTPUT_DIR/scripts" -type f -exec chmod 700 {} + 2>/dev/null || true

if declare -f secpack_target_validate >/dev/null; then
    secpack_target_validate "$ARG_OUTPUT_DIR"
fi

echo "Security pack generated: $ARG_OUTPUT_DIR"
