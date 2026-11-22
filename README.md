# Kobo Netbird

Run [netbird](https://netbird.io) on a Kobo e-reader, so it joins your mesh and reaches self-hosted services directly (e.g. an OPDS catalog in KOReader). Kobo firmware installs `.kobo/KoboRoot.tgz` from its USB drive at boot.

Tested on a Kobo Libra Colour, firmware `4.45.23655`. Other 4.x models should work too.

## Install

1. Download `kobo-netbird.zip` from the [latest release](https://github.com/koinsaari/kobo-netbird/releases/latest).
2. Plug the Kobo in, tap **Connect**, and unzip onto the root of the `KOBOeReader` drive. It adds `.kobo/KoboRoot.tgz` and `.adds/netbird/env`.
3. Edit `.adds/netbird/env`: paste a setup key in `NB_SETUP_KEY=`, and set `NB_MANAGEMENT_URL` if you self-host. A one-off key with a short expiry is best.
4. Eject, restart the Kobo, and turn Wi-Fi on.

The Kobo moves the key off the USB drive, enrols, and deletes it. The peer appears in your dashboard once Wi-Fi is up.

To update, drop a newer `KoboRoot.tgz` into `.kobo/` and restart. Enrolment lives in `/etc/netbird` and survives updates.

## Verify or build it yourself

```sh
gh attestation verify KoboRoot.tgz -R koinsaari/kobo-netbird
```

`SHA256SUMS` lists the upstream netbird asset (compare with netbird's own `checksums.txt`) and every file in the bundle. Or build it yourself with `make` (GNU tar; on macOS `make TAR=gtar`) and use `build/`.

## What it installs

| path | what |
|---|---|
| `/opt/netbird/netbird` | upstream armv6 binary |
| `/etc/ssl/certs/ca-certificates.crt` | Mozilla CA bundle via curl.se; stock firmware has none |
| `/etc/udev/rules.d/97-netbird.rules` | runs the hook once per boot |
| `/usr/local/netbird/boot.sh` | starts the daemon with state in `/etc/netbird`, enrols once |

## Notes

- The peer goes offline while the Kobo sleeps (Wi-Fi off) and reconnects on wake.
- Netbird rewrites `/etc/resolv.conf` for mesh DNS, but the firmware's glibc 2.19 reads it once per process. An app started before netbird keeps the old resolver until restarted; for KOReader, a user patch calling `__res_init()` before each HTTP request fixes it.
- A firmware update may replace system files; drop `KoboRoot.tgz` in again.

## Uninstall

Enable SSH by renaming `.kobo/ssh-disabled` to `.kobo/ssh-enabled` and rebooting. Commands must go through stdin, because root's forced login script ignores ssh arguments:

```sh
echo 'pkill netbird; rm -rf /opt/netbird /usr/local/netbird /etc/netbird /etc/udev/rules.d/97-netbird.rules; sync' | ssh root@<device-ip>
```

Then remove the peer in the dashboard.

## Related

[IKA3RUS/kobo-netbird](https://github.com/IKA3RUS/kobo-netbird) installs netbird over SSH with an on-device script, and ships a `tun.ko` for models without `/dev/net/tun`.

## License

[MIT](LICENSE)
