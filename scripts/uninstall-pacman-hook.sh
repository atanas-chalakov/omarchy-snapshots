#!/usr/bin/env bash
# uninstall-pacman-hook.sh: Remove pre-transaction ALPM snapshot hook
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Elevating privileges to remove Pacman ALPM hook..."
  exec sudo "$0" "$@"
fi

echo "Removing Pacman pre-transaction snapshot hook..."
rm -f /etc/pacman.d/hooks/00-omarchy-snapshots-pre.hook
rm -f /usr/share/libalpm/scripts/omarchy-snapshots-pre-hook

echo "✓ Pacman pre-transaction snapshot hook removed."
