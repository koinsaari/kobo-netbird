# kobo-netbird

Run [netbird](https://netbird.io) on a rooted Kobo e-reader, so it can join your mesh network and reach a self-hosted server directly (e.g. OPDS/Calibre book-sync via KOReader), without exposing SSH to the internet.

Tested on a Mediatek `mt8113t-ntx` Kobo, firmware `4.9.77.4.45.23646`. Other models should work since the installer detects CPU arch and tmpfs layout rather than assuming this one's, but they're untested. PRs and issue reports for other device/firmware combos are welcome.

## Prerequisites

Stock Kobo firmware has a native, undocumented SSH toggle: rename `.kobo/ssh-disabled` to `.kobo/ssh-enabled` on the FAT32 partition (mount via USB), reboot, then `ssh root@<device-ip>`. First login prompts you to set a root password. No jailbreak or NickelMenu/KFMon/KOReader needed; if you have KOReader and want to keep it, it doesn't interfere.

## Usage

SSH into the device as root, then:

```sh
wget -qO- https://raw.githubusercontent.com/koinsaari/kobo-netbird/main/install.sh | sh
```

or clone the repo onto the device and run `./install.sh` directly.

Enroll:

```sh
netbird up --setup-key <YOUR_SETUP_KEY>
# or, for interactive SSO:
netbird up
```

Check it's alive: `netbird status`. Reboot once to confirm it comes back on its own.

Pin a version instead of fetching latest: `NETBIRD_VERSION=0.78.2 ./install.sh`.

Uninstall: `./uninstall.sh` (stops the daemon, removes binary/config/autostart hook; peer stays enrolled on your mesh dashboard until removed there too).

## What it does

1. Detects CPU arch, picks the matching netbird release.
2. Installs a CA bundle (`/etc/ssl/certs/ca-certificates.crt`) if missing. Stock firmware ships none, which breaks all outbound TLS for statically-linked Go binaries like netbird.
3. Downloads and checksum-verifies the latest netbird release to `/opt/netbird/netbird`.
4. Points netbird's config/log/state at a persistent directory (`/etc/netbird` by default), not wherever it'd otherwise land. `/var/lib` is a small tmpfs on stock firmware, wiped every boot, which silently loses your mesh enrollment if unhandled.
5. Symlinks `netbird` onto `/usr/local/bin`.
6. Hooks a small init script into Kobo's boot sequence so the daemon survives reboot.

Doesn't enroll the device on any mesh, doesn't touch SSH config. You do enrollment yourself, however you prefer.

## Kobo firmware internals

- Onboard FAT32 (`/mnt/onboard`, the USB mass-storage view) is not the rootfs. Nickel/rcS read specific paths from it (`.kobo/`, `KoboRoot.tgz`) but it's a separate filesystem from where daemons and configs live.
- Real rootfs is ext4, reachable only via SSH. No systemd/upstart, no `rcN.d` scheme: boot runs one monolithic `/etc/init.d/rcS` script.
- `/var/lib`, `/var/log`, `/var/run` are mounted tmpfs by `rcS` on every boot. `/etc`, `/opt`, `/usr/local` are real ext4, persistent.
- No dm-verity, no A/B slot switching, no process that reverts manual `rcS` edits. Something that looked exactly like that was actually an unsynced write lost on an unclean shutdown, see Troubleshooting.
- `mmcblk0p10` is the active rootfs; `mmcblk0p11` is a same-size second rootfs partition (`UBOOT_RECOVERY` in `rcS`), confirmed to hold an older unrelated firmware snapshot, not a live mirror, only reachable via the factory-reset path.
- Real OpenSSH, not dropbear. `Match User root` sets `ForceCommand /etc/ssh/initial_ssh_setup.sh`, which overrides every session type (shell, exec, SFTP): any command passed as an ssh argument is ignored, and scp/sftp never negotiate. Pipe commands through stdin (`echo "cmd" | ssh host`) and transfer files by base64-encoding through an ssh-piped heredoc.
- `/etc/passwd`'s root homedir is `/`, not `/root`. Combined with `sshd_config`'s relative `AuthorizedKeysFile .ssh/authorized_keys`, sshd looks for `//.ssh/authorized_keys` and silently ignores a key placed at `/root/.ssh/authorized_keys`. Mirror the key at `/.ssh/authorized_keys` instead of editing `/etc/passwd`.
- netbird is a statically-linked Go binary needing only `/dev/net/tun` (present on stock kernel), no in-kernel WireGuard module. `netbird service install` targets systemd/upstart/launchd, none of which exist here, so the daemon is started manually (`netbird service run` via `nohup setsid`) and hooked into `rcS` by hand.

## Troubleshooting

**`x509: certificate signed by unknown authority`** — no CA bundle at `/etc/ssl/certs/ca-certificates.crt`. `install.sh` fixes this automatically; check `[ -s /etc/ssl/certs/ca-certificates.crt ]` if debugging manually.

**`failed to connect to daemon ... context deadline exceeded` on `netbird up`** — no daemon running. `netbird up`/`status` just talk to a background `netbird service run` process over `/var/run/netbird.sock`; start the daemon first.

**Peer shows `NeedsLogin` after every reboot** — state dir landed on tmpfs (`/var/lib/netbird` by default). Point `--config` at a persistent path (`/etc/netbird/default.json`), which `install.sh` does automatically.

**`ssh host "cmd"` / `scp` does nothing or hangs** — `ForceCommand` breaks both. Pipe commands through stdin instead of passing them as arguments. If it's the very first login ever, the forced script is waiting on an interactive password prompt; log in with a real terminal once first.

**Pubkey auth fails despite correct `authorized_keys`** — the `/etc/passwd` homedir bug above. Confirm with `sshd -d -p 2222` run in the foreground and check the exact path it tries. Fix by mirroring the key at `/.ssh/authorized_keys`.

**"rcS gets wiped every reboot, my autostart hook disappears"** — not a real wipe. No active restore mechanism exists (checked `/etc`, `/usr/local`, `strings` on `hindenburg`/`pickel`, the `mmcblk0p11` recovery partition, the `fs.md5sum` manifest — nothing). The edit just wasn't `fsync`'d before a power cycle. Always `sync` after editing `rcS` and reboot cleanly (`install.sh` does this).

**`ssh-copy-id` fails with `ssh-ed25519: not found`** — BusyBox `/bin/sh` chokes on it. Append the pubkey manually: `echo "ssh-ed25519 AAAA... you" >> ~/.ssh/authorized_keys`.

## Related projects

[IKA3RUS/kobo-netbird](https://github.com/IKA3RUS/kobo-netbird) does the same thing for the Kobo Libra Colour.

## License

MIT.
