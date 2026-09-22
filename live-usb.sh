#!/usr/bin/env bash
# Live-USB install driver for these dotfiles.
#
# Boot the NixOS minimal ISO, mount the USB stick holding this folder,
# then run this script from inside the transferred copy:
#
#   sudo -i  # optional; script uses sudo where needed
#   bash /path/to/dotfiles/live-usb.sh [HOST]
#
# HOST defaults to nixos-host and must match hosts/<HOST>.nix
# (configuration-id). The live tooling profile is always nixos@live.
set -euo pipefail

HOST="${1:-nixos-host}"
LIVE_REF="nixos@live"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# This script lives at the repo/flake root. Copy the whole repo to RAM so
# nix never builds straight off the (possibly vfat) USB stick.
WORK="$HOME/dotfiles"                     # ram copy; matches $DOTFILES_DIR default
FLAKE_DIR="$WORK"

step() { echo; echo "=== $* ==="; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$SCRIPT_DIR/flake.nix" ] || die "no flake.nix next to $0"
[ -d "$SCRIPT_DIR/dotfiles" ] || die "no dotfiles/ module tree next to $0"

# 0. Copy repo into RAM (skip if already running from there).
step "0/5 repo copy"
if [ "$SCRIPT_DIR" = "$WORK" ]; then
  echo "already in $WORK, skipping copy"
else
  rm -rf "$WORK"
  cp -r "$SCRIPT_DIR" "$WORK"
  echo "copied $SCRIPT_DIR -> $WORK"
fi
[ -f "$FLAKE_DIR/hosts/$HOST.nix" ] || die "no hosts/$HOST.nix (edit one, see hosts/nixos-host.nix)"

# 1. Flakes on (per-user config files; /etc is read-only on the live ISO,
# so enable flakes via $HOME and /root instead of /etc/nix/nix.conf).
step "1/5 nix flakes + network"
mkdir -p "$HOME/.config/nix"
grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null || \
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
sudo mkdir -p /root/.config/nix
sudo sh -c 'grep -q "experimental-features" /root/.config/nix/nix.conf 2>/dev/null || echo "experimental-features = nix-command flakes" >> /root/.config/nix/nix.conf'
ping -c1 -W3 nixos.org >/dev/null 2>&1 || die "no network (check cable/wifi via nmtui, then re-run)"
mem_gb=$(free -g | awk '/^Mem:/{print $2}')
if [ "${mem_gb:-0}" -lt 4 ]; then
  echo "WARNING: only ${mem_gb:-?}GB RAM — nix eval + install wants 8GB. Bump the VM RAM if you can."
  echo "Stopgap: enabling 4G zram swap for this session..."
  sudo modprobe zram num_devices=1 2>/dev/null || true
  if [ -e /sys/block/zram0/disksize ]; then
    echo lz4 | sudo tee /sys/block/zram0/comp_algorithm >/dev/null 2>&1 || true
    echo 4G | sudo tee /sys/block/zram0/disksize >/dev/null 2>&1 || true
    sudo mkswap /dev/zram0 >/dev/null 2>&1 && sudo swapon -p 100 /dev/zram0 || true
  fi
  free -h | head -n 3 || true
fi

# 2. Live tooling profile: nushell + fnox + pass-cli + git + vpn (RAM only).
step "2/5 live tooling (home-manager $LIVE_REF, takes a while)"
nix run github:nix-community/home-manager -- switch --flake "$FLAKE_DIR#$LIVE_REF"
export PATH="$HOME/.nix-profile/bin:$PATH"

# 3. Interactive logins (pass/fnox/ssh/VPN) inside nushell.
step "3/5 logins"
cat <<EOF
Opening nushell. Run these, then 'exit' to continue the install:
  setup-pass-cli
  ,pc pat-login
  init-pass-secret-service
  systemctl --user restart pass-secret-service  # was expected to fail before init
  ,pc ssh-keys-load
  (optional) ,vpn on            # only if you need masked traffic first
  (optional) setup-proton-drive # only if you need drive restores now
Manifest to install: hosts/$HOST.nix
  edit passwords/hostname/git BEFORE continuing (nano $FLAKE_DIR/hosts/$HOST.nix)
  new-hostname / new-machine-id generate IDs; backup-manifest pushes to Proton Pass
EOF
read -rp "Press Enter to open nushell..."
nu
read -rp "Hosts/$HOST.nix edited with passwords + hostname + git identity? [y/N] " ans
[ "$ans" = "y" ] || die "edit $FLAKE_DIR/hosts/$HOST.nix, then re-run with $HOST"

# 4. Wipe + partition (disko). Device comes from manifest.params.disko.device.
step "4/5 disko (WIPES the target disk)"
lsblk -d -o NAME,SIZE,MODEL
read -rp "Type YES to wipe and partition: " confirm
[ "$confirm" = "YES" ] || die "aborted"
sudo nix run github:nix-community/disko -- --mode disko --flake "$FLAKE_DIR#$HOST"

# 5. Install.
step "5/5 nixos-install $HOST"
sudo nixos-install --flake "$FLAKE_DIR#$HOST" --no-root-passwd

echo
echo "Done. Remove USB + ISO, then reboot. First login: changeme unless manifest sets hashes."
echo "Then in nushell: setup-pass-cli, setup-all (restores), init-all."
