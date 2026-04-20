#!/usr/bin/env bash
# Quick dump of host/Vagrant/VirtualBox state useful for GRISP Alloy VM issues.
#
# Usage (host): ./scripts/vagrant/vagrant-diagnose.sh
# Compact (short) output: ./scripts/vagrant/vagrant-diagnose.sh --compact
# In the VM (repo at /vagrant): /vagrant/scripts/vagrant/vagrant-diagnose.sh

if [[ "${1:-}" == "--compact" ]]; then
    echo "=== GRISP Alloy — host snapshot (compact) ==="
    if command -v vagrant >/dev/null 2>&1; then
        vagrant --version
    else
        echo "vagrant: not in PATH"
    fi
    if command -v VBoxManage >/dev/null 2>&1; then
        echo "VirtualBox: $(VBoxManage --version)"
    else
        echo "VirtualBox: VBoxManage not in PATH"
    fi
    echo "ruby in PATH ($(command -v ruby 2>/dev/null || echo none)): $(ruby -v 2>/dev/null || echo n/a)"
    echo "(Vagrant plugins run under its embedded Ruby; see gem path below.)"
    VAGRANT_HOME="${VAGRANT_HOME:-$HOME/.vagrant.d}"
    if [[ -d "${VAGRANT_HOME}/gems" ]]; then
        GEM_DIR="$(find "${VAGRANT_HOME}/gems" -type d -name 'vagrant-vbguest-*' 2>/dev/null \
            | sort -V | tail -n 1)"
        if [[ -n "${GEM_DIR:-}" ]]; then
            echo "vagrant-vbguest gem: $GEM_DIR"
            if grep -rq 'File\.exists?' "$GEM_DIR" --include='*.rb' 2>/dev/null; then
                echo "File.exists? in gem .rb: YES (hook should patch before up)"
            else
                echo "File.exists? in gem .rb: no"
            fi
        else
            echo "vagrant-vbguest gem: not installed"
        fi
    else
        echo "Vagrant gems: ${VAGRANT_HOME}/gems missing"
    fi
    exit 0
fi

set -euo pipefail

section() {
    echo ""
    echo "=== $1 ==="
}

section "Host"
uname -a 2>/dev/null || true
if [[ "$(uname -s)" == "Darwin" ]]; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null || true
fi

section "Ruby"
if command -v ruby >/dev/null 2>&1; then
    ruby -v
    command -v ruby
else
    echo "ruby not in PATH"
fi

section "Vagrant"
if command -v vagrant >/dev/null 2>&1; then
    vagrant --version
    command -v vagrant
else
    echo "vagrant not in PATH"
fi

section "Vagrant plugins"
if command -v vagrant >/dev/null 2>&1; then
    vagrant plugin list
else
    echo "(skipped: no vagrant)"
fi

section "vagrant-vbguest gem"
VAGRANT_HOME="${VAGRANT_HOME:-$HOME/.vagrant.d}"
if [[ ! -d "${VAGRANT_HOME}/gems" ]]; then
    echo "No gems tree: ${VAGRANT_HOME}/gems"
else
    GEM_DIR="$(find "${VAGRANT_HOME}/gems" -type d -name 'vagrant-vbguest-*' 2>/dev/null \
        | sort -V | tail -n 1)"
    if [[ -z "${GEM_DIR:-}" ]]; then
        echo "(vagrant-vbguest gem directory not found)"
    else
        echo "Path: $GEM_DIR"
        if grep -rq 'File\.exists?' "$GEM_DIR" --include='*.rb' 2>/dev/null; then
            echo "File.exists? in .rb: YES (run: scripts/vagrant/patch-vagrant-vbguest-ruby3.sh)"
        else
            echo "File.exists? in .rb: no (OK for Ruby 3.2+)"
        fi
    fi
fi

section "VirtualBox"
if command -v VBoxManage >/dev/null 2>&1; then
    VBoxManage --version
else
    echo "VBoxManage not in PATH"
fi

section "Environment (VAGRANT_*, GLB_VAGRANT_*, VM_*)"
env | grep -E '^(VAGRANT_|GLB_VAGRANT|VM_)' | sort || true
if ! env | grep -qE '^(VAGRANT_|GLB_VAGRANT|VM_)'; then
    echo "(none set)"
fi
