#!/usr/bin/env bash
set -euo pipefail

host_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            printf 'x86_64\n'
            ;;
        aarch64|arm64)
            printf 'aarch64\n'
            ;;
        *)
            printf 'unsupported host architecture for platform_smoke: %s\n' "$(uname -m)" >&2
            exit 1
            ;;
    esac
}

case "${1:-}" in
    target_arch)
        host_arch
        ;;
    target_arch_triplet)
        printf '%s-buildroot-linux-gnu\n' "$(host_arch)"
        ;;
    buildroot_arch_symbol)
        host_arch
        ;;
    buildroot_cpu_fragment)
        case "$(host_arch)" in
            x86_64)
                printf 'BR2_x86_core2=y\n'
                ;;
            aarch64)
                printf 'BR2_cortex_a53=y\n'
                ;;
        esac
        ;;
    *)
        printf 'unsupported platform_smoke export key: %s\n' "${1:-}" >&2
        exit 1
        ;;
esac
