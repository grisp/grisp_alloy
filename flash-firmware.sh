#!/usr/bin/env bash

# flash-firmware.sh - Flash a GRiSP Alloy firmware archive through target UUU
#
# The board must already be stopped in U-Boot and running:
#
#   fastboot 0
#
# This script takes a normal .fw archive, derives the temporary artifacts needed
# by UUU, and renders the target-provided UUU fastboot template. The full eMMC
# image is generated through the firmware's fwup "complete" task, and bootloader
# artifacts are extracted from firmware resources, so raw layout details stay
# owned by the firmware archive and target configuration rather than this script.

set -eo pipefail

show_usage()
{
    echo "USAGE: flash-firmware.sh OPTIONS TARGET (FIRMWARE_PREFIX | FIRMWARE_PATH)"
    echo "OPTIONS:"
    echo " -h | --help"
    echo "    Show this"
    echo " -d | --debug"
    echo "    Print script debug information"
    echo " -y | --yes"
    echo "    Do not ask for confirmation before flashing"
    echo " -k | --keep-temp"
    echo "    Keep generated image, bootloader, and UUU script"
    echo " -n | --dry-run"
    echo "    Generate temporary files and print commands, but do not flash"
    echo " -V | --force-vagrant"
    echo "    Using the Vagrant VM even on Linux"
    echo " -P | --provision"
    echo "    Re-provision the vagrant VM; use to reflect some changes to the VM"
    echo " -K | --keep-vagrant"
    echo "    Keep the Vagrant VM running after exiting"
    echo " --skip-emmc"
    echo "    Do not render the target eMMC flashing section"
    echo " --flash-bootloader"
    echo "    Flash the linked bootloader chain: eMMC second stage and SPI NOR first stage"
    echo " --uuu <PATH>"
    echo "    UUU executable (default: first uuu in PATH)"
    echo " --fwup <PATH>"
    echo "    fwup executable (default: target SDK fwup)"
    echo " --external <DIR>"
    echo "    Add external Alloy bundle root containing system_*, ramfs_*, or toolchain/configs."
    echo
    echo "Examples:"
    echo "  flash-firmware.sh private-target hello_grisp"
    echo "  flash-firmware.sh private-target artefacts/hello_grisp-0.0.1-private-target.fw"
    echo "  flash-firmware.sh --flash-bootloader private-target hello_grisp"
    echo "  flash-firmware.sh --skip-emmc --flash-bootloader private-target hello_grisp"
}

source "$( dirname "$0" )/scripts/argparse.sh"
args_init
args_add h help ARG_SHOW_HELP flag true false
args_add d debug ARG_DEBUG flag 1 0
args_add y yes ARG_ASSUME_YES flag true false
args_add k keep-temp ARG_KEEP_TEMP flag true false
args_add n dry-run ARG_DRY_RUN flag true false
args_add V force-vagrant ARG_FORCE_VAGRANT flag true false
args_add P provision ARG_PROVISION_VAGRANT flag true false
args_add K keep-vagrant ARG_KEEP_VAGRANT flag true false
args_add '' skip-emmc ARG_SKIP_EMMC flag true false
args_add '' flash-bootloader ARG_FLASH_BOOTLOADER flag true false
args_add '' uuu ARG_UUU value ""
args_add '' fwup ARG_FWUP value ""
args_add '' external ARG_EXTERNAL_DIRS accum

if ! args_parse "$@"; then
    exit 1
fi

if [[ $ARG_SHOW_HELP == true ]]; then
    show_usage
    exit 0
fi

POSITIONALS=( "${POSITIONAL[@]}" )
if [[ ${#POSITIONALS[@]} -lt 2 ]]; then
    echo "ERROR: Missing target or firmware reference"
    show_usage
    exit 1
fi
if [[ ${#POSITIONALS[@]} -gt 2 ]]; then
    echo "ERROR: Too many arguments"
    show_usage
    exit 1
fi

ARG_TARGET="${POSITIONALS[0]}"
ARG_FIRMWARE_REF="${POSITIONALS[1]}"

source "$( dirname "$0" )/scripts/common.sh" "$ARG_TARGET"
set_debug_level "$ARG_DEBUG"

if [[ -z "${GLB_TARGET_NAME:-}" ]]; then
    error 1 "Unknown target '${ARG_TARGET}'"
fi
if [[ $ARG_SKIP_EMMC == true && $ARG_FLASH_BOOTLOADER == false ]]; then
    error 1 "Nothing to do: --skip-emmc requires --flash-bootloader"
fi

UUU_CONF="${GLB_TARGET_SYSTEM_DIR}/uuu.conf"
if [[ ! -f "$UUU_CONF" ]]; then
    error 1 "Flashing not supported for target '$GLB_TARGET_NAME': ${UUU_CONF} missing"
fi
source "$UUU_CONF"

UUU_TEMPLATE_FILE="${GLB_TARGET_SYSTEM_DIR}/${UUU_TEMPLATE:-}"
if [[ -z "${UUU_TEMPLATE:-}" || ! -f "$UUU_TEMPLATE_FILE" ]]; then
    error 1 "Target '$GLB_TARGET_NAME' has invalid UUU_TEMPLATE in ${UUU_CONF}"
fi

if [[ -n "${GLB_FLASH_PREP_ONLY:-}" && -z "${GLB_FLASH_PREP_DIR:-}" ]]; then
    error 1 "GLB_FLASH_PREP_ONLY requires GLB_FLASH_PREP_DIR"
fi

if [[ ($ARG_FORCE_VAGRANT == true || $HOST_OS != "linux") && -z "${GLB_FLASH_PREP_ONLY:-}" ]]; then
    cd "$GLB_TOP_DIR"
    vagrant up
    if [[ $ARG_PROVISION_VAGRANT == true ]]; then
        vagrant provision
    fi

    HOST_PREP_DIR="$(mktemp -d "${GLB_ARTEFACTS_DIR}/flash-prep.XXXXXX")"
    VAGRANT_PREP_DIR="${GLB_VAGRANT_ARTEFACTS_DIR}/$(basename "$HOST_PREP_DIR")"
    HOST_SSH_CONFIG="${HOST_PREP_DIR}/ssh_config"

    cleanup_host_flash_prep() {
        local status=$?
        trap - EXIT

        if [[ $ARG_KEEP_TEMP == true || $ARG_DRY_RUN == true ]]; then
            if [[ -d "$HOST_PREP_DIR" ]]; then
                echo "Keeping temporary files in $HOST_PREP_DIR"
            fi
        else
            rm -rf "$HOST_PREP_DIR"
        fi

        if [[ $ARG_KEEP_VAGRANT == false ]]; then
            cd "$GLB_TOP_DIR" || true
            vagrant halt || true
        fi

        exit "$status"
    }
    trap cleanup_host_flash_prep EXIT

    NEW_ARGS=( )
    if [[ ${ARG_DEBUG_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--debug" )
    fi
    if [[ ${ARG_ASSUME_YES_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--yes" )
    fi
    if [[ ${ARG_KEEP_TEMP_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--keep-temp" )
    fi
    if [[ ${ARG_DRY_RUN_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--dry-run" )
    fi
    if [[ ${ARG_SKIP_EMMC_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--skip-emmc" )
    fi
    if [[ ${ARG_FLASH_BOOTLOADER_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--flash-bootloader" )
    fi
    if [[ ${ARG_FWUP_OPT} -gt 0 ]]; then
        NEW_ARGS+=( "--fwup" "$ARG_FWUP" )
    fi
    VAGRANT_EXTERNAL_DIRS=( )
    alloy_vagrant_sync_external_roots VAGRANT_EXTERNAL_DIRS
    for external_dir in "${VAGRANT_EXTERNAL_DIRS[@]}"; do
        NEW_ARGS+=( "--external" "$external_dir" )
    done
    NEW_ARGS+=( "$ARG_TARGET" )

    if [[ -f "$ARG_FIRMWARE_REF" ]]; then
        vagrant ssh-config > "$HOST_SSH_CONFIG"
        local_host_fw="$(cd "$(dirname "$ARG_FIRMWARE_REF")" && pwd -P)/$(basename "$ARG_FIRMWARE_REF")"
        if [[ "$local_host_fw" == ${GLB_ARTEFACTS_DIR}/* ]]; then
            rel_fw_path="${local_host_fw#"${GLB_ARTEFACTS_DIR}"/}"
            NEW_ARGS+=( "${GLB_VAGRANT_ARTEFACTS_DIR}/${rel_fw_path}" )
        else
            vagrant exec mkdir -p "$GLB_VAGRANT_FIRMWARE_BUILD_DIR/uploads"
            rsync -qav -e "ssh -F ${HOST_SSH_CONFIG}" \
                "$local_host_fw" "vagrant@default:${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/uploads/"
            NEW_ARGS+=( "${GLB_VAGRANT_FIRMWARE_BUILD_DIR}/uploads/$(basename "$local_host_fw")" )
        fi
    else
        NEW_ARGS+=( "$ARG_FIRMWARE_REF" )
    fi

    vagrant exec -- env GLB_FLASH_PREP_ONLY=true GLB_FLASH_PREP_DIR="${VAGRANT_PREP_DIR}" \
        "${GLB_VAGRANT_TOP_DIR}/flash-firmware.sh" "${NEW_ARGS[@]}"

    if [[ ! -f "${HOST_PREP_DIR}/flash-metadata.env" ]]; then
        error 1 "Vagrant flash preparation did not produce ${HOST_PREP_DIR}/flash-metadata.env"
    fi
    # shellcheck source=/dev/null
    source "${HOST_PREP_DIR}/flash-metadata.env"

    UUU_FILE="${HOST_PREP_DIR}/$(basename "$UUU_FILE")"
    IMAGE_PREFIX_FILE="${HOST_PREP_DIR}/$(basename "$IMAGE_PREFIX_FILE")"
    IMAGE_SUFFIX_FILE="${HOST_PREP_DIR}/$(basename "$IMAGE_SUFFIX_FILE")"
    UBOOT_FILE="${HOST_PREP_DIR}/$(basename "$UBOOT_FILE")"
    NOR_BOOT_FILE="${HOST_PREP_DIR}/$(basename "$NOR_BOOT_FILE")"

    UUU="${ARG_UUU}"
    if [[ -z "$UUU" ]]; then
        UUU="$(command -v uuu || true)"
        if [[ -z "$UUU" && -x /opt/homebrew/bin/uuu ]]; then
            UUU=/opt/homebrew/bin/uuu
        fi
    fi
    if [[ -z "$UUU" || ! -x "$UUU" ]]; then
        error 1 "uuu not found on host. Install NXP mfgtools/uuu or pass --uuu <PATH>"
    fi

    if [[ $ARG_DRY_RUN == true ]]; then
        echo "Dry run enabled; generated UUU script:"
        sed 's/^/  /' "$UUU_FILE"
        echo
        echo "Run on host hardware with:"
        echo "  $UUU $UUU_FILE"
        exit 0
    fi

    echo "The board must be connected to the host through USB OTG and already running 'fastboot 0'."
    if ! sudo "$UUU" -lsusb 2>/dev/null | grep -q 'FB:'; then
        error 1 "No UUU Fastboot device detected on host. Start U-Boot fastboot with: fastboot 0"
    fi

    if [[ $ARG_ASSUME_YES == false ]]; then
        echo "This will overwrite:"
        if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
            echo "  - eMMC bootloader at sector ${bootloader_sector}"
            echo "  - SPI NOR first-stage bootloader"
        fi
        if [[ $ARG_SKIP_EMMC == false ]]; then
            echo "  - eMMC user area covered by the generated image, excluding bootloader reserved sectors ${bootloader_sector}..$((bootloader_after_sector - 1))"
            if [[ "$gpt_action" == rewrite ]]; then
                echo "  - eMMC GPT rewritten so the backup header lands at the physical device end"
            elif [[ "$gpt_action" == repair ]]; then
                echo "  - eMMC backup GPT header repaired to the physical device end"
            fi
        fi
        read -r -p "Continue? [y/N] " answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) error 130 "Aborted" ;;
        esac
    fi

    echo "Flashing with host UUU..."
    sudo "$UUU" "$UUU_FILE"
    echo "Done"
    exit 0
fi

install_sdk

FWUP="${ARG_FWUP}"
if [[ -z "$FWUP" ]]; then
    FWUP="${GLB_SDK_HOST_DIR}/bin/fwup"
fi
if [[ ! -x "$FWUP" ]]; then
    error 1 "fwup not found or not executable: $FWUP"
fi

UUU="${ARG_UUU}"
if [[ -z "$UUU" && -z "${GLB_FLASH_PREP_ONLY:-}" ]]; then
    UUU="$(command -v uuu || true)"
fi
if [[ -z "${GLB_FLASH_PREP_ONLY:-}" && ( -z "$UUU" || ! -x "$UUU" ) ]]; then
    error 1 "uuu not found. Install NXP mfgtools/uuu or pass --uuu <PATH>"
fi

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || error 1 "Required command not found: $cmd"
}

file_size() {
    local path="$1"
    wc -c < "$path" | tr -d '[:space:]'
}

compare_file_region() {
    local reference_file="$1"
    local target_file="$2"
    local byte_count="$3"
    local target_offset="$4"

    python3 - "$reference_file" "$target_file" "$byte_count" "$target_offset" <<'PY'
from pathlib import Path
import sys

reference = Path(sys.argv[1]).read_bytes()
target = Path(sys.argv[2]).read_bytes()
count = int(sys.argv[3])
offset = int(sys.argv[4])

if reference[:count] == target[offset:offset + count]:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

shell_quote() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

require_cmd unzip
require_cmd sed
require_cmd mktemp
require_cmd python3
require_cmd cmp

fw_metadata_key() {
    local fw="$1"
    local key="$2"
    local value
    value="$("$FWUP" -m --metadata-key "$key" -i "$fw" 2>/dev/null || true)"
    if [[ "$value" == "(null)" ]]; then
        value=""
    fi
    echo "$value"
}

resolve_firmware() {
    local spec="$1"
    local path
    local matches
    local filtered=( )
    local platform

    if [[ -f "$spec" ]]; then
        path="$( cd "$( dirname "$spec" )" && pwd )/$( basename "$spec" )"
        if [[ "$path" != *.fw ]]; then
            error 1 "Firmware path does not end in .fw: $path"
        fi
        platform="$( fw_metadata_key "$path" meta-platform )"
        if [[ "$platform" != "$GLB_TARGET_NAME" ]]; then
            error 1 "Firmware platform '$platform' does not match target '$GLB_TARGET_NAME'"
        fi
        echo "$path"
        return 0
    fi

    matches=( $( ls -1 "${GLB_ARTEFACTS_DIR}/${spec}"*.fw 2>/dev/null || true ) )
    if [[ ${#matches[@]} -eq 0 ]]; then
        error 1 "No firmware matching prefix '${spec}' in ${GLB_ARTEFACTS_DIR}"
    fi

    for path in "${matches[@]}"; do
        platform="$( fw_metadata_key "$path" meta-platform )"
        if [[ "$platform" == "$GLB_TARGET_NAME" ]]; then
            filtered+=( "$path" )
        fi
    done

    if [[ ${#filtered[@]} -eq 1 ]]; then
        echo "${filtered[0]}"
    elif [[ ${#filtered[@]} -eq 0 ]]; then
        error 1 "No firmware for target '$GLB_TARGET_NAME' matches prefix '${spec}'"
    else
        echo "WARNING: Multiple firmware archives found for prefix '${spec}' and target '${GLB_TARGET_NAME}':" 1>&2
        for path in "${filtered[@]}"; do
            echo "  $( basename "$path" )" 1>&2
        done
        error 1 "Multiple firmware options error"
    fi
}

FIRMWARE_FILE="$( resolve_firmware "$ARG_FIRMWARE_REF" )"
FIRMWARE_BASE="$( basename "$FIRMWARE_FILE" .fw )"
FIRMWARE_VERSION="$( fw_metadata_key "$FIRMWARE_FILE" meta-version )"
FIRMWARE_UUID="$( fw_metadata_key "$FIRMWARE_FILE" meta-uuid )"
FIRMWARE_MISC="$( fw_metadata_key "$FIRMWARE_FILE" meta-misc )"

if [[ "${GLB_TARGET_SYSTEM_SOURCE:-}" == "external" ]]; then
    EXPECTED_FIRMWARE_MISC="$(alloy_firmware_misc_provenance)"
    if [[ "$FIRMWARE_MISC" != "$EXPECTED_FIRMWARE_MISC" ]]; then
        error 1 "Firmware provenance does not match external target ${GLB_TARGET_NAME}; rebuild firmware with the same --external or GRISP_ALLOY_EXTERNAL_PATH context"
    fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grisp-alloy-uuu.XXXXXX")"
cleanup() {
    if [[ $ARG_KEEP_TEMP == true ]]; then
        echo "Keeping temporary files in $TMP_DIR"
    else
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

IMAGE_FILE="${TMP_DIR}/${FIRMWARE_BASE}.img"
IMAGE_PREFIX_FILE="${TMP_DIR}/${FIRMWARE_BASE}.pre-bootloader.img"
IMAGE_SUFFIX_FILE="${TMP_DIR}/${FIRMWARE_BASE}.post-bootloader.img"
UBOOT_FILE="${TMP_DIR}/flash.bin"
NOR_BOOT_FILE="${TMP_DIR}/spi-nor-spl.bin"
META_CONF_FILE="${TMP_DIR}/meta.conf"
UUU_FILE="${TMP_DIR}/flash.uuu"

echo "Firmware: $( basename "$FIRMWARE_FILE" )"
echo "Target:   $GLB_TARGET_NAME"
if [[ -n "$FIRMWARE_VERSION" ]]; then
    echo "Version:  $FIRMWARE_VERSION"
fi
if [[ -n "$FIRMWARE_UUID" ]]; then
    echo "UUID:     $FIRMWARE_UUID"
fi
echo

unzip -p "$FIRMWARE_FILE" meta.conf > "$META_CONF_FILE"

fw_resource_raw_write_sector() {
    local task="$1"
    local resource="$2"

    python3 - "$META_CONF_FILE" "$task" "$resource" <<'PY'
import re
import sys

path, task_name, resource_name = sys.argv[1:4]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

def extract_block(s, pattern):
    match = re.search(pattern, s)
    if not match:
        return None

    open_brace = s.find("{", match.end() - 1)
    if open_brace < 0:
        return None

    depth = 0
    in_string = False
    escaped = False
    for idx in range(open_brace, len(s)):
        ch = s[idx]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return s[open_brace + 1:idx]

    return None

task = extract_block(text, rf'task\s+"{re.escape(task_name)}"\s*\{{')
if task is None:
    sys.exit(f"task not found: {task_name}")

resource = extract_block(task, rf'on-resource\s+"{re.escape(resource_name)}"\s*\{{')
if resource is None:
    sys.exit(f"resource not found in task {task_name}: {resource_name}")

match = re.search(r'"raw_write"\s*,\s*"([0-9]+)"', resource)
if not match:
    sys.exit(f"raw_write offset not found for {task_name}/{resource_name}")

print(match.group(1))
PY
}

if [[ $ARG_SKIP_EMMC == false ]]; then
    echo "Generating small eMMC image from .fw..."
    rm -f "$IMAGE_FILE"
    touch "$IMAGE_FILE"
    "$FWUP" -a -d "$IMAGE_FILE" -t complete -i "$FIRMWARE_FILE"
fi

if [[ $ARG_SKIP_EMMC == false || $ARG_FLASH_BOOTLOADER == true ]]; then
    echo "Extracting bootloader from .fw..."
    if [[ -z "${UUU_BOOTLOADER_RESOURCE:-}" ]]; then
        error 1 "Target '$GLB_TARGET_NAME' does not define UUU_BOOTLOADER_RESOURCE"
    fi
    if ! unzip -Z1 "$FIRMWARE_FILE" | grep -qx "$UUU_BOOTLOADER_RESOURCE"; then
        error 1 "Firmware archive does not contain target bootloader resource: ${UUU_BOOTLOADER_RESOURCE}"
    fi
    unzip -p "$FIRMWARE_FILE" "$UUU_BOOTLOADER_RESOURCE" > "$UBOOT_FILE"
    if [[ ! -s "$UBOOT_FILE" ]]; then
        error 1 "Failed to extract ${UUU_BOOTLOADER_RESOURCE} from $( basename "$FIRMWARE_FILE" )"
    fi
    uboot_size="$(file_size "$UBOOT_FILE")"
    bootloader_resource_name="$(basename "$UUU_BOOTLOADER_RESOURCE")"
    bootloader_sector="$(fw_resource_raw_write_sector "${UUU_BOOTLOADER_FWUP_TASK:-complete}" "$bootloader_resource_name")"
    if [[ -z "$bootloader_sector" || ! "$bootloader_sector" =~ ^[0-9]+$ ]]; then
        error 1 "Could not determine eMMC bootloader sector from firmware metadata"
    fi
    bootloader_sectors=$(( (uboot_size + 511) / 512 ))
    bootloader_sector_hex="$(printf '0x%x' "$bootloader_sector")"
    bootloader_sectors_hex="$(printf '0x%x' "$bootloader_sectors")"
    bootloader_exclusion_sectors="${UUU_MMC_BOOTLOADER_RESERVED_SECTORS:-$bootloader_sectors}"
    if [[ -z "$bootloader_exclusion_sectors" || ! "$bootloader_exclusion_sectors" =~ ^[0-9]+$ ]]; then
        error 1 "UUU_MMC_BOOTLOADER_RESERVED_SECTORS must be a decimal sector count"
    fi
    if [[ "$bootloader_exclusion_sectors" -lt "$bootloader_sectors" ]]; then
        error 1 "Bootloader reserved sector count ${bootloader_exclusion_sectors} is smaller than bootloader size ${bootloader_sectors}"
    fi

    if [[ $ARG_SKIP_EMMC == false ]]; then
        bootloader_byte_offset=$((bootloader_sector * 512))
        if ! compare_file_region "$UBOOT_FILE" "$IMAGE_FILE" "$uboot_size" "$bootloader_byte_offset"; then
            error 1 "Generated eMMC image does not contain ${UUU_BOOTLOADER_RESOURCE} at metadata sector ${bootloader_sector}"
        fi
    fi

    if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
        : "${UUU_NOR_BOOTLOADER_RESOURCE:?Target UUU config must define UUU_NOR_BOOTLOADER_RESOURCE for --flash-bootloader}"
        if ! unzip -Z1 "$FIRMWARE_FILE" | grep -qx "$UUU_NOR_BOOTLOADER_RESOURCE"; then
            error 1 "Firmware archive does not contain target SPI NOR bootloader resource: ${UUU_NOR_BOOTLOADER_RESOURCE}"
        fi
        unzip -p "$FIRMWARE_FILE" "$UUU_NOR_BOOTLOADER_RESOURCE" > "$NOR_BOOT_FILE"
        if [[ ! -s "$NOR_BOOT_FILE" ]]; then
            error 1 "Failed to extract ${UUU_NOR_BOOTLOADER_RESOURCE} from $( basename "$FIRMWARE_FILE" )"
        fi
        nor_first_stage_size="$(file_size "$NOR_BOOT_FILE")"
        : "${UUU_SPI_WRITE_OFFSET:?Target UUU config must define UUU_SPI_WRITE_OFFSET for --flash-bootloader}"
        : "${UUU_SPI_SIZE:?Target UUU config must define UUU_SPI_SIZE for --flash-bootloader}"
        : "${UUU_SPI_ERASE_BLOCK_SIZE:?Target UUU config must define UUU_SPI_ERASE_BLOCK_SIZE for --flash-bootloader}"
        nor_end=$((UUU_SPI_WRITE_OFFSET + nor_first_stage_size))
        if [[ "$nor_end" -gt "$UUU_SPI_SIZE" ]]; then
            error 1 "SPI NOR first stage is too large: end ${nor_end} > SPI size ${UUU_SPI_SIZE}"
        fi
        nor_erase_size=$(( ((nor_end + UUU_SPI_ERASE_BLOCK_SIZE - 1) / UUU_SPI_ERASE_BLOCK_SIZE) * UUU_SPI_ERASE_BLOCK_SIZE ))
        nor_erase_size_hex="$(printf '0x%x' "$nor_erase_size")"
        nor_first_stage_size_hex="$(printf '0x%x' "$nor_first_stage_size")"
    fi
fi

image_sectors=0
image_sectors_hex=0
image_prefix_sectors=0
image_prefix_sectors_hex=0
image_suffix_sectors=0
image_suffix_sectors_hex=0
image_suffix_sparse_sectors=0
image_suffix_sparse_sectors_hex=0
image_suffix_offset=0
image_suffix_offset_hex=0
gpt_action="none"
if [[ $ARG_SKIP_EMMC == false ]]; then
    image_size="$(file_size "$IMAGE_FILE")"
    image_sectors=$(( (image_size + 511) / 512 ))
    image_sectors_hex="$(printf '0x%x' "$image_sectors")"
    rewrite_gpt="${UUU_MMC_REWRITE_GPT:-false}"
    repair_gpt="${UUU_MMC_REPAIR_GPT:-false}"
    case "$rewrite_gpt" in
        true|false) ;;
        *) error 1 "UUU_MMC_REWRITE_GPT must be 'true' or 'false'" ;;
    esac
    case "$repair_gpt" in
        true|false) ;;
        *) error 1 "UUU_MMC_REPAIR_GPT must be 'true' or 'false'" ;;
    esac
    if [[ "$rewrite_gpt" == true ]]; then
        : "${UUU_MMC_GPT_PARTITIONS:?Target UUU config must define UUU_MMC_GPT_PARTITIONS when UUU_MMC_REWRITE_GPT=true}"
        if [[ "$UUU_MMC_GPT_PARTITIONS" == *"'"* ]]; then
            error 1 "UUU_MMC_GPT_PARTITIONS must not contain single quotes"
        fi
        gpt_action="rewrite"
    elif [[ "$repair_gpt" == true ]]; then
        gpt_action="repair"
    fi

    bootloader_after_sector=$((bootloader_sector + bootloader_exclusion_sectors))
    bootloader_after_byte_offset=$((bootloader_after_sector * 512))
    if [[ "$bootloader_after_byte_offset" -ge "$image_size" ]]; then
        error 1 "Generated eMMC image is smaller than the bootloader exclusion range"
    fi

    image_prefix_sectors="$bootloader_sector"
    image_prefix_sectors_hex="$(printf '0x%x' "$image_prefix_sectors")"
    image_suffix_offset=$((UUU_MMC_RAW_OFFSET + bootloader_after_sector))
    image_suffix_offset_hex="$(printf '0x%x' "$image_suffix_offset")"

    dd if="$IMAGE_FILE" of="$IMAGE_PREFIX_FILE" bs=512 count="$image_prefix_sectors" 2>/dev/null
    dd if="$IMAGE_FILE" of="$IMAGE_SUFFIX_FILE" bs=512 skip="$bootloader_after_sector" conv=sparse 2>/dev/null

    image_suffix_size="$(file_size "$IMAGE_SUFFIX_FILE")"
    image_suffix_sectors=$(( (image_suffix_size + 511) / 512 ))
    image_suffix_sectors_hex="$(printf '0x%x' "$image_suffix_sectors")"
    # UUU -raw2sparse rounds raw files to Android sparse blocks. Expose that
    # rounded size to U-Boot fastboot so the sparse decoder does not reject the
    # final padded chunk.
    image_suffix_sparse_sectors=$(( ((image_suffix_size + 4095) / 4096) * 8 ))
    image_suffix_sparse_sectors_hex="$(printf '0x%x' "$image_suffix_sparse_sectors")"
fi

bootloader_section=""
if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
    : "${UUU_MMC_DEV:?Target UUU config must define UUU_MMC_DEV}"
    : "${UUU_MMC_HW_PART:?Target UUU config must define UUU_MMC_HW_PART}"
    : "${UUU_MMC_BOOTLOADER_RAW_PARTITION:?Target UUU config must define UUU_MMC_BOOTLOADER_RAW_PARTITION}"
    bootloader_section="$(cat <<EOF
FB: ucmd setenv fastboot_dev mmc
FB: ucmd setenv mmcdev ${UUU_MMC_DEV}
FB: ucmd mmc dev ${UUU_MMC_DEV}
FB: ucmd setenv fastboot_raw_partition_${UUU_MMC_BOOTLOADER_RAW_PARTITION} ${bootloader_sector_hex} ${bootloader_sectors_hex} mmcpart ${UUU_MMC_HW_PART}
FB: flash ${UUU_MMC_BOOTLOADER_RAW_PARTITION} $( basename "$UBOOT_FILE" )
EOF
)"

    : "${UUU_FASTBOOT_BUF_ADDR:?Target UUU config must define UUU_FASTBOOT_BUF_ADDR for --flash-bootloader}"
    bootloader_section="${bootloader_section}
FB: download -f $( basename "$NOR_BOOT_FILE" )
FB: ucmd sf probe
FB[-t 30000]: ucmd sf erase 0x0 ${nor_erase_size_hex}
FB[-t 30000]: ucmd sf write ${UUU_FASTBOOT_BUF_ADDR} ${UUU_SPI_WRITE_OFFSET} \${filesize}"
fi

emmc_section=""
if [[ $ARG_SKIP_EMMC == false ]]; then
    : "${UUU_MMC_DEV:?Target UUU config must define UUU_MMC_DEV}"
    : "${UUU_MMC_HW_PART:?Target UUU config must define UUU_MMC_HW_PART}"
    : "${UUU_MMC_RAW_PARTITION:?Target UUU config must define UUU_MMC_RAW_PARTITION}"
    : "${UUU_MMC_RAW_OFFSET:?Target UUU config must define UUU_MMC_RAW_OFFSET}"
    emmc_section="$(cat <<EOF
FB: ucmd setenv fastboot_dev mmc
FB: ucmd setenv mmcdev ${UUU_MMC_DEV}
FB: ucmd mmc dev ${UUU_MMC_DEV}
FB: ucmd setenv fastboot_raw_partition_${UUU_MMC_RAW_PARTITION}_pre_bootloader ${UUU_MMC_RAW_OFFSET} ${image_prefix_sectors_hex} mmcpart ${UUU_MMC_HW_PART}
FB: flash ${UUU_MMC_RAW_PARTITION}_pre_bootloader $( basename "$IMAGE_PREFIX_FILE" )
FB: ucmd setenv fastboot_raw_partition_${UUU_MMC_RAW_PARTITION}_post_bootloader ${image_suffix_offset_hex} ${image_suffix_sparse_sectors_hex} mmcpart ${UUU_MMC_HW_PART}
FB: flash -raw2sparse ${UUU_MMC_RAW_PARTITION}_post_bootloader $( basename "$IMAGE_SUFFIX_FILE" )
EOF
)"
    if [[ "$gpt_action" == rewrite ]]; then
        emmc_section="${emmc_section}
FB: ucmd setenv gpt_parts '${UUU_MMC_GPT_PARTITIONS}'
FB: ucmd gpt write mmc ${UUU_MMC_DEV} \${gpt_parts}
FB: ucmd mmc rescan"
    elif [[ "$gpt_action" == repair ]]; then
        emmc_section="${emmc_section}
FB: ucmd gpt repair mmc ${UUU_MMC_DEV}
FB: ucmd mmc rescan"
    fi
fi

python3 - "$UUU_TEMPLATE_FILE" "$UUU_FILE" "$bootloader_section" "$emmc_section" <<'PY'
import sys
template_path, output_path, bootloader, emmc = sys.argv[1:5]
with open(template_path, "r", encoding="utf-8") as f:
    text = f.read()
text = text.replace("{{BOOTLOADER}}", bootloader.rstrip())
text = text.replace("{{EMMC}}", emmc.rstrip())
lines = [line for line in text.splitlines() if line.strip()]
with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY

echo "Generated UUU script: $UUU_FILE"
if [[ $ARG_SKIP_EMMC == false ]]; then
    echo "eMMC image: $( basename "$IMAGE_FILE" ) ($(file_size "$IMAGE_FILE") bytes, ${image_sectors} sectors)"
    echo "eMMC image flashing excludes bootloader reserved sectors ${bootloader_sector}..$((bootloader_after_sector - 1))"
    if [[ "$gpt_action" == rewrite ]]; then
        echo "eMMC GPT will be rewritten on target so the backup header lands at the physical device end"
    elif [[ "$gpt_action" == repair ]]; then
        echo "eMMC GPT backup header will be repaired to the physical device end"
    fi
fi
if [[ $ARG_SKIP_EMMC == false || $ARG_FLASH_BOOTLOADER == true ]]; then
    if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
        echo "eMMC bootloader: $( basename "$UBOOT_FILE" ) ($(file_size "$UBOOT_FILE") bytes, sector ${bootloader_sector}, ${bootloader_sectors} sectors)"
    else
        echo "Bootloader: not flashed; existing eMMC bootloader is preserved"
    fi
    if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
        echo "SPI NOR first stage: $( basename "$NOR_BOOT_FILE" ) ($(file_size "$NOR_BOOT_FILE") bytes, erase ${nor_erase_size_hex})"
    fi
fi
echo

if [[ "${GLB_FLASH_PREP_ONLY:-}" == "true" ]]; then
    mkdir -p "$GLB_FLASH_PREP_DIR"
    cp "$UUU_FILE" "$GLB_FLASH_PREP_DIR/"
    if [[ $ARG_SKIP_EMMC == false ]]; then
        cp "$IMAGE_PREFIX_FILE" "$IMAGE_SUFFIX_FILE" "$GLB_FLASH_PREP_DIR/"
    fi
    if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
        cp "$UBOOT_FILE" "$NOR_BOOT_FILE" "$GLB_FLASH_PREP_DIR/"
    fi
    cat > "${GLB_FLASH_PREP_DIR}/flash-metadata.env" <<EOF
UUU_FILE=${GLB_FLASH_PREP_DIR}/$(basename "$UUU_FILE")
IMAGE_PREFIX_FILE=${GLB_FLASH_PREP_DIR}/$(basename "$IMAGE_PREFIX_FILE")
IMAGE_SUFFIX_FILE=${GLB_FLASH_PREP_DIR}/$(basename "$IMAGE_SUFFIX_FILE")
UBOOT_FILE=${GLB_FLASH_PREP_DIR}/$(basename "$UBOOT_FILE")
NOR_BOOT_FILE=${GLB_FLASH_PREP_DIR}/$(basename "$NOR_BOOT_FILE")
bootloader_sector=${bootloader_sector}
bootloader_after_sector=${bootloader_after_sector}
gpt_action=${gpt_action}
EOF
    echo "Prepared flashing assets in ${GLB_FLASH_PREP_DIR}"
    exit 0
fi

if [[ $ARG_DRY_RUN == true ]]; then
    echo "Dry run enabled; generated UUU script:"
    sed 's/^/  /' "$UUU_FILE"
    echo
    echo "Run on hardware with:"
    echo "  $UUU $UUU_FILE"
    exit 0
fi

echo "The board must be connected through USB OTG and already running 'fastboot 0'."
if ! sudo "$UUU" -lsusb 2>/dev/null | grep -q 'FB:'; then
    error 1 "No UUU Fastboot device detected. Start U-Boot fastboot with: fastboot 0"
fi

if [[ $ARG_ASSUME_YES == false ]]; then
    echo "This will overwrite:"
    if [[ $ARG_FLASH_BOOTLOADER == true ]]; then
        echo "  - eMMC bootloader at sector ${bootloader_sector}"
        echo "  - SPI NOR first-stage bootloader"
    fi
    if [[ $ARG_SKIP_EMMC == false ]]; then
        echo "  - eMMC user area covered by the generated image, excluding bootloader reserved sectors ${bootloader_sector}..$((bootloader_after_sector - 1))"
        if [[ "$gpt_action" == rewrite ]]; then
            echo "  - eMMC GPT rewritten so the backup header lands at the physical device end"
        elif [[ "$gpt_action" == repair ]]; then
            echo "  - eMMC backup GPT header repaired to the physical device end"
        fi
    fi
    read -r -p "Continue? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) error 130 "Aborted" ;;
    esac
fi

echo "Flashing with UUU..."
sudo "$UUU" "$UUU_FILE"

echo "Done"
