#!/usr/bin/env bash
# Prepare a freshly installed NixOS system for remote management from the nixos-config repo.
#
# Adds /etc/nixos/bootstrap.nix (imported from configuration.nix) which:
#   - enables flakes and SSH,
#   - creates the `builder` user (keys in ./keys/builder, no sudo): the controller syncs and
#     builds the configuration as this user,
#   - creates the `deploy` user (keys in ./keys/deploy, passwordless sudo): activates it. Hardware
#     token keys (sk-*) are only accepted with the token's PIN check (verify-required),
#   - installs git and rsync.
# Then runs `nixos-rebuild switch` and prints what the controller needs to onboard this machine,
# including the fingerprints of the keys it installed, for the user to compare with the
# controller's trusted list.
#
# Usage: sudo ./bootstrap.sh [hostname]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
NIXOS_DIR=/etc/nixos
CONFIG="$NIXOS_DIR/configuration.nix"
MODULE="$NIXOS_DIR/bootstrap.nix"

die() {
  echo "error: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0 $*"
[ -e /etc/NIXOS ] || die "this is not a NixOS system"
[ -f "$CONFIG" ] || die "$CONFIG not found"

hostname_arg="${1:-}"
if [ -n "$hostname_arg" ] && ! [[ "$hostname_arg" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  die "invalid hostname '$hostname_arg' (use lowercase letters, digits and dashes)"
fi

# Collect the public keys of one keys/<role>/ folder as Nix list items. Token keys (sk-*) for
# deploy get the verify-required option, so the host insists on the token's PIN check.
shopt -s nullglob
collect_keys() {
  local role=$1 f line out=""
  for f in "$REPO_DIR"/keys/"$role"/*.pub; do
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      [[ "$line" =~ ^(ssh-|ecdsa-|sk-)[A-Za-z0-9@.-]+\ [A-Za-z0-9+/=]+(\ [^\"\$\\]*)?$ ]] \
        || die "unexpected line in $f: $line"
      if [ "$role" = deploy ] && [[ "$line" == sk-* ]]; then line="verify-required $line"; fi
      out+="        \"$line\""$'\n'
    done <"$f"
  done
  [ -n "$out" ] || die "no public keys found in $REPO_DIR/keys/$role"
  printf '%s' "$out"
}
builder_keys="$(collect_keys builder)"
deploy_keys="$(collect_keys deploy)"

hostname_line=""
if [ -n "$hostname_arg" ]; then
  hostname_line="  networking.hostName = lib.mkForce \"$hostname_arg\";"
fi

echo "==> Writing $MODULE"
cat >"$MODULE" <<EOF
# Written by nixos-bootstrap. Gives the nixos-config controller access to this machine.
# Superseded once the machine is deployed from nixos-config.
{ lib, pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh.enable = true;

  users.users.builder = {
    isNormalUser = true;
    description = "Builds nixos-config, reads state (no sudo)";
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = [
$builder_keys    ];
  };

  users.users.deploy = {
    isNormalUser = true;
    description = "Activates nixos-config (hardware tokens, sudo)";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
$deploy_keys    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "deploy" ];
      commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
    }
  ];

  environment.systemPackages = with pkgs; [ git rsync ];
$hostname_line
}
EOF

if ! grep -q '\./bootstrap\.nix' "$CONFIG"; then
  grep -q '\./hardware-configuration\.nix' "$CONFIG" \
    || die "can't find './hardware-configuration.nix' in $CONFIG; add './bootstrap.nix' to its imports by hand and re-run"
  cp "$CONFIG" "$CONFIG.pre-bootstrap"
  echo "==> Adding ./bootstrap.nix to imports in $CONFIG (backup: $CONFIG.pre-bootstrap)"
  sed -i '0,/\.\/hardware-configuration\.nix/s|\./hardware-configuration\.nix|./hardware-configuration.nix\n      ./bootstrap.nix|' "$CONFIG"
fi

echo "==> nixos-rebuild switch"
nixos-rebuild switch

system="$(uname -m)-linux"
state_version="$(sed -nE 's/^[[:space:]]*system\.stateVersion[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CONFIG" | head -n1)"
addresses="$(ip -4 -o addr show scope global | awk '{ split($4, a, "/"); print a[1] }')"
name="${hostname_arg:-$(hostname)}"

cat <<EOF

==> Done. This machine is ready to be managed.
    hostname:     $(hostname)
    system:       $system
    stateVersion: ${state_version:-unknown}
    addresses:    $(echo "$addresses" | paste -sd ' ' -)

    Keys installed (compare with the trusted list on the controller before onboarding):
EOF
for f in "$REPO_DIR"/keys/*/*.pub; do
  printf '      %-8s %s  %s\n' "$(basename "$(dirname "$f")")" "$(ssh-keygen -lf "$f" | awk '{print $2}')" "$(basename "$f")"
done
cat <<EOF
    This machine's host key (compare on the controller after the first connection):
      $(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')

On the controller, in the nixos-config repo, run (or ask Claude to):
    scripts/add-host.sh $name $(echo "$addresses" | head -n1)
EOF
