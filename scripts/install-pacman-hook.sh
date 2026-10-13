#!/usr/bin/env bash
# install-pacman-hook.sh: Install pre-transaction ALPM snapshot hook
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Elevating privileges to install Pacman ALPM hook..."
  exec sudo "$0" "$@"
fi

mkdir -p /etc/pacman.d/hooks /usr/share/libalpm/scripts

echo "Installing Pacman pre-transaction snapshot hook..."
install -Dm644 "$SCRIPT_DIR/packaging/00-omarchy-snapshots-pre.hook" "/etc/pacman.d/hooks/00-omarchy-snapshots-pre.hook"
install -Dm755 "$SCRIPT_DIR/scripts/omarchy-snapshots-pre-hook" "/usr/share/libalpm/scripts/omarchy-snapshots-pre-hook"

echo "✓ Pacman pre-transaction snapshot hook successfully installed."
echo "  Hook:   /etc/pacman.d/hooks/00-omarchy-snapshots-pre.hook"
echo "  Script: /usr/share/libalpm/scripts/omarchy-snapshots-pre-hook"
