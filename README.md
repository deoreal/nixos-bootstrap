# nixos-bootstrap

Makes a freshly installed NixOS machine reachable for remote management from the
(private) `nixos-config` repo. After that, all configuration of the machine is done there.

## Use

1. Install NixOS as usual (the minimal ISO is enough) and make sure the machine has network.
2. On the new machine:
   ```sh
   nix-shell -p git --run 'git clone https://github.com/deoreal/nixos-bootstrap'
   cd nixos-bootstrap
   sudo ./bootstrap.sh <hostname>
   ```
   `<hostname>` is optional; it's the name the machine will have in `nixos-config`.
3. The script prints an `add-host.sh` command. Run it in `nixos-config` on the controller,
   or give the printed address to Claude.

## What it changes

- Writes `/etc/nixos/bootstrap.nix` and adds it to the imports of `/etc/nixos/configuration.nix`
  (backup: `configuration.nix.pre-bootstrap`).
- Enables flakes and the SSH server.
- Creates user `deploy` (SSH key login only, using the keys in `keys/`) with passwordless sudo.
- Installs `git` and `rsync`.
- Runs `nixos-rebuild switch`.

Existing users, passwords and settings stay as they are.

## Controller keys

`keys/*.pub` are the public keys of the machines allowed to manage the systems (one file per
controller). To manage from another machine, add its public key here **and** in `nixos-config/keys/`.
Only public keys belong in this repo; it is public.
