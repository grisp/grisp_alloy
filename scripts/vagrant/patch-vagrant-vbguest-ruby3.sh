#!/usr/bin/env bash
# Patch the installed vagrant-vbguest gem for Ruby 3.2+: File.exists? was removed;
# File.exist? is the correct API.
#
# Usage (host): ./scripts/vagrant/patch-vagrant-vbguest-ruby3.sh
# In the VM (repo at /vagrant): /vagrant/scripts/vagrant/patch-vagrant-vbguest-ruby3.sh
# Run on the host after installing the plugin. After patching, optionally:
# VAGRANT_VBGUEST_AUTO_UPDATE=1 vagrant up

set -euo pipefail

VAGRANT_HOME="${VAGRANT_HOME:-$HOME/.vagrant.d}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ ! -d "${VAGRANT_HOME}/gems" ]]; then
    die "Vagrant gems tree missing: ${VAGRANT_HOME}/gems"
fi

# Vagrant 2.4+: ~/.vagrant.d/gems/<ruby>/gems/vagrant-vbguest-* (older: .../gems/gems/...)
GEM_DIR="$(find "${VAGRANT_HOME}/gems" -type d -name 'vagrant-vbguest-*' 2>/dev/null \
    | sort -V | tail -n 1)"
if [[ -z "${GEM_DIR:-}" ]]; then
    die "vagrant-vbguest not found; run: vagrant plugin install vagrant-vbguest"
fi

echo "Gem directory: $GEM_DIR"

patched=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    perl -pi -e 's/File\.exists\?/File.exist?/g' "$f"
    echo "  patched: $f"
    patched=$((patched + 1))
done < <(grep -rl 'File\.exists?' "$GEM_DIR" --include='*.rb' 2>/dev/null || true)

if [[ "$patched" -eq 0 ]]; then
    echo "Nothing to patch (already compatible or gem layout changed)."
else
    echo "Patched $patched file(s)."
    echo "Optional: VAGRANT_VBGUEST_AUTO_UPDATE=1 vagrant up"
fi
