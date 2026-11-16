# nixos-bootstrap

Makes a freshly installed NixOS machine reachable for remote management from the
(private) `nixos-config` repo. After that, all configuration of the machine is done there.

## Use

1. Install NixOS as usual (the minimal ISO is enough) and make sure the machine has network.
2. On the new machine:
   ```sh
   nix-shell -p git --run 'git clone https://github.com/deoreal/nixos-bootstrap'
   cd nixos-bootstrap
   git log -1 --format=%H      # compare with the commit the controller shows (git log -1 there)
   sudo ./bootstrap.sh <hostname>
   ```
   `<hostname>` is optional; it's the name the machine will have in `nixos-config`.
3. The script prints the fingerprints of the keys it installed and of the machine's own host key,
   and an `add-host.sh` command. Compare the key fingerprints with the controller's trusted list
   (`scripts/trusted-keys.sh` there), then run the command in `nixos-config` on the controller,
   or give the printed address to Claude.

## What it changes

- Writes `/etc/nixos/bootstrap.nix` and adds it to the imports of `/etc/nixos/configuration.nix`
  (backup: `configuration.nix.pre-bootstrap`).
- Enables flakes and the SSH server.
- Creates user `builder` (SSH key login only, keys in `keys/builder/`, no sudo): the controller
  syncs the configuration to its home and builds it there.
- Creates user `deploy` (keys in `keys/deploy/`, passwordless sudo): activates the configuration.
  Hardware-token keys (`sk-*`) are only accepted after the token's PIN check.
- Installs `git` and `rsync`.
- Runs `nixos-rebuild switch`.

Existing users, passwords and settings stay as they are.

## Keys

`keys/builder/*.pub` are the controller Macs' software keys; `keys/deploy/*.pub` are the user's
hardware tokens (one file per YubiKey). Same files as `nixos-config/keys/`. Every key must also
be in each controller's trusted key list (see the nixos-config README): the controller's
`add-host.sh` refuses a machine on which this script installed a key that isn't on that list, so
a tampered copy of this repo can't slip in another key. Only public keys belong here; this repo
is public.
