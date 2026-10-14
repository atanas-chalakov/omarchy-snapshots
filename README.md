# Snapshots & Recovery (`ac.snapshots`)

[![Omarchy Plugin](https://img.shields.io/badge/omarchy-plugin-blue?style=flat-square)](https://plugins.omarchy.org/)
[![Quickshell](https://img.shields.io/badge/quickshell-QML-violet?style=flat-square)](https://quickshell.outfoxxed.me/)
[![Category: System](https://img.shields.io/badge/category-System-emerald?style=flat-square)](https://plugins.omarchy.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

A native **Btrfs & Snapper snapshot manager and system recovery HUD** for [Omarchy](https://omarchy.org/) Linux. 

Inspect system recovery points, verify Limine bootloader synchronization, inspect package and config file diffs, browse snapshot directories, and trigger safe rollbacks directly from your desktop.

![Snapshots & Recovery Preview](preview.png)

---

## The Problem It Solves

Omarchy configures Btrfs and Snapper out-of-the-box, taking automatic snapshots right before running `omarchy update`. However, users have **zero desktop visibility** into their recovery points:

1. **The Silent Boot Failure Risk**: If `limine-snapper-sync` quietly stalls or fails in the background, you won't know your snapshots aren't bootable until your system breaks and you reboot into an empty menu.
2. **Hidden Disk Bloat**: Without visual storage telemetry, outdated snapshots can lock tens of gigabytes of disk space on your NVMe.
3. **No Granular File Recovery**: If you break a single config file in `~/.config/hypr/` or `/etc/fstab`, you shouldn't have to roll back the entire OS. You just want to grab that one file from two hours ago.
4. **Terminal Friction Before Risky Tests**: Testing an AUR kernel or new GPU driver requires remembering cryptic CLI flags instead of hitting a single hotkey to create a named checkpoint.

`ac.snapshots` bridges this gap with a sleek, keyboard-friendly Quickshell interface.

---

## Visual Showcase

| Recovery Timeline & Health | Change Diff Inspector |
| :---: | :---: |
| ![Timeline Overview](assets/screenshots/overview.png) | ![Diff Inspector](assets/screenshots/diff-inspector.png) |
| *Live health indicator, storage telemetry, boot sync status, and recovery points* | *Filterable list of added, modified, and deleted packages and configs* |

| New Checkpoint Dialog | Safe Rollback Confirmation |
| :---: | :---: |
| ![Create Checkpoint](assets/screenshots/create-modal.png) | ![Restore Confirmation](assets/screenshots/restore-modal.png) |
| *One-click named checkpoints with quick preset chips & auto-prune pinning* | *Guided safety confirmation before executing Limine bootloader rollback* |

| Smart Btrfs Disk Optimizer | Limine Boot Verification & Sync |
| :---: | :---: |
| ![Disk Optimizer](assets/screenshots/optimizer-modal.png) | ![Boot Verification](assets/screenshots/boot-sync-modal.png) |
| *Intelligent space reclaim with safety retention lock on critical milestones* | *Kernel verification and ESP partition monitoring for instant boot recovery* |

---

## Key Features

- **Recovery Readiness Health Check**:
  - Live indicator dot: **Protected** (sync active & recent snapshots) vs. **Warning** (stale snapshots or permissions required) vs. **Error** (Snapper offline).
  - Automatically verifies whether `limine-snapper-sync.service` is actively tracking `/.snapshots` and keeping your boot menu up-to-date.
- **Visual Recovery Timeline**:
  - Grouped cards showing Snapshot ID (`#19`), relative age (`2h ago`), exact timestamp, trigger reason (`Pre-Update`, `Manual Checkpoint`), and auto-prune algorithm.
  - Search and filter pills: `[All]`, `[Pre-Update]`, `[Manual]`, `[Pinned 📌]`.
- **Change Diff Inspector**:
  - Compares any snapshot against your running system.
  - Instant counts of `+X added`, `~Y modified`, `-Z deleted` files with instant search/filter.
- **Snapshot Pinning (`📌`)**:
  - Protect critical milestones from Snapper's automatic `NUMBER_LIMIT` retention cleanup with one click.
- **Time Machine File Recovery**:
  - Click **[Browse]** to open `/.snapshots/<id>/snapshot/` in your file manager to restore individual files without rebooting.
- **One-Click Authorization**:
  - Built-in `[Authorize Access]` banner allows wheel users to configure passwordless desktop access via `pkexec` in seconds (securing `/.snapshots` with mode `0750` restricted to `root:wheel`).
- **Full Keyboard Navigation & Shortcuts**:
  - Complete keyboard control: browse snapshots, create checkpoints, inspect diffs, and restore with Vim-style and standard desktop hotkeys (`J/K`, `C`, `D`, `B`, `P`, `R`, `X`, `F`, `G`, `Esc`).

---

### Keyboard Shortcuts

| Key | Action | Context |
| :---: | :--- | :--- |
| <kbd>J</kbd> / <kbd>↓</kbd> | Select next snapshot card | Timeline view |
| <kbd>K</kbd> / <kbd>↑</kbd> | Select previous snapshot card | Timeline view |
| <kbd>Home</kbd> / <kbd>End</kbd> | Jump to first / last snapshot | Timeline view |
| <kbd>C</kbd> / <kbd>N</kbd> | Create new recovery checkpoint | Main HUD |
| <kbd>D</kbd> / <kbd>Enter</kbd> | Inspect diff changes for selected snapshot | Main HUD |
| <kbd>B</kbd> | Browse snapshot directory in file manager | Main HUD |
| <kbd>P</kbd> | Toggle pin (retention protection `📌`) | Main HUD |
| <kbd>R</kbd> | Stage rollback / restore to selected snapshot | Main HUD |
| <kbd>X</kbd> / <kbd>Del</kbd> | Delete selected snapshot | Main HUD |
| <kbd>F</kbd> / <kbd>/</kbd> | Focus search filter input | Main HUD |
| <kbd>H</kbd> / <kbd>L</kbd> or <kbd>1</kbd>-<kbd>4</kbd> | Cycle filter pills (`All`, `Pre-Update`, `Manual`, `Pinned`) | Main HUD |
| <kbd>G</kbd> | Refresh snapshot status | Main HUD |
| <kbd>Esc</kbd> / <kbd>Q</kbd> | Dismiss active modal or close HUD | Any view |

---

## Installation

### Method 1: Automated Installer (Recommended)
Clone the repository and run the setup script:
```bash
git clone https://github.com/atanas-chalakov/omarchy-snapshots.git
cd omarchy-snapshots
./install.sh
```
This automatically:
- Symlinks the plugin into `~/.config/omarchy/plugins/ac.snapshots`
- Links CLI launchers into `~/.local/bin`
- Integrates Snapshots & Recovery into the native **Omarchy Command Palette** (`Super+Space`) via `~/.config/omarchy/extensions/omarchy-menu.jsonc`
- Installs application menu entries and vector/PNG icons
- Enables the companion widget in your Omarchy status bar

#### Automatic Pre-Upgrade Snapshots (Pacman ALPM Hook)
To ensure every `pacman -Syu`, install, or package removal automatically captures a safety snapshot before modifying system files, enable the pre-transaction ALPM hook:
```bash
sudo ./scripts/install-pacman-hook.sh
```
To verify hook status:
```bash
omarchy-snapshots hook
```

To uninstall at any time:
```bash
./uninstall.sh
# To also remove the pacman hook:
sudo ./scripts/uninstall-pacman-hook.sh
```

### Method 2: Arch Linux (AUR / PKGBUILD)
```bash
cd packaging
makepkg -si
```
*(The PKGBUILD automatically installs `/usr/share/libalpm/hooks/00-omarchy-snapshots-pre.hook` and the menu extension template).*

### Method 3: Using the Omarchy CLI
```bash
omarchy plugin add https://github.com/atanas-chalakov/omarchy-snapshots --enable
```

---

## Omarchy Command Palette Integration (`Super+Space`)

`omarchy-snapshots` includes first-class integration with the native Quickshell Omarchy command palette (`Super+Space`). You can summon it anytime:
- Press <kbd>Super</kbd> + <kbd>Space</kbd> and type `snapshots`, `snapper`, `backup`, or `restore`
- Or navigate hierarchically: **System** → **Snapshots & Recovery** (or **Setup** → **Snapshots & Recovery**)

Check or refresh your menu extension configuration anytime:
```bash
omarchy-snapshots menu
```

---

## Recommended Hyprland Keybinding

Add a convenient hotkey to summon the Snapshots HUD anywhere in your desktop. Add this to `~/.config/hypr/bindings.lua`:

```lua
-- Summon Snapshots & Recovery HUD
o.bind("SUPER ALT", "S", "omarchy-shell shell toggle ac.snapshots")
```

---

## CLI Reference (`omarchy-snapshots`)

A standalone CLI tool is included in `bin/omarchy-snapshots`:

```bash
# List all snapshots with health summary and storage telemetry
omarchy-snapshots list

# Create a manual checkpoint with a custom description
omarchy-snapshots create --desc "Before testing experimental kernel"

# Create a pinned snapshot (protected from auto-cleanup)
omarchy-snapshots create --desc "Stable Baseline" --important

# Inspect file changes in a snapshot
omarchy-snapshots diff --id 19

# Pin or unpin a snapshot
omarchy-snapshots pin --id 18
omarchy-snapshots unpin --id 18

# Delete a snapshot
omarchy-snapshots delete --id 17

# Restore / rollback system to a snapshot
omarchy-snapshots restore --id 19

# Verify Limine bootloader health & registered snapshot entries
omarchy-snapshots boot-health

# Synchronize Limine bootloader with Snapper snapshots
omarchy-snapshots boot-sync

# Check status of automatic pacman pre-transaction hook
omarchy-snapshots hook

# Check Omarchy command palette menu extension status
omarchy-snapshots menu

# One-time authorization for passwordless desktop access
omarchy-snapshots authorize

# Output structured JSON for automation or scripting
omarchy-snapshots json

# Summon desktop HUD
omarchy-snapshots gui
omarchy-snapshots gui --action create   # Open directly to New Checkpoint dialog
omarchy-snapshots gui --action diff     # Open directly to Diff inspector
omarchy-snapshots gui --mock            # Open demo preview mode
```

---

## Running the Automated Test Suite

```bash
# Run the entire unified test suite (Validator, Unit Engine, CLI, QML, and IPC)
./tests/run_all_tests.sh

# Or run individual test modules
python3 -m unittest tests/test_unit_engine.py
python3 -m unittest tests/test_cli_commands.py
python3 -m unittest tests/test_qml_and_manifest.py
python3 -m unittest tests/test_ipc_integration.py
```

---

## License

MIT License. Designed with care for the Omarchy Linux community.
