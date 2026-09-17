#!/bin/sh
# Installs netbird on a rooted Kobo. Run as root, on-device, over SSH.
# See README "Prerequisites" if SSH isn't enabled yet.
#
#   wget -qO- https://raw.githubusercontent.com/koinsaari/kobo-netbird/main/install.sh | sh
#
# or clone the repo onto the device and run ./install.sh directly.
#
# Set NETBIRD_VERSION=x.y.z to pin a version instead of fetching latest if you want.
set -eu

log()  { printf '[kobo-netbird] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

NB_INSTALL_DIR=/opt/netbird
NB_BIN_LINK=/usr/local/bin/netbird
NB_STATE_DIR=/etc/netbird
NB_CONFIG=$NB_STATE_DIR/default.json
NB_LOG_DIR=$NB_STATE_DIR/log
NB_TMP=/tmp/kobo-netbird-fetch
NB_API_LATEST=https://api.github.com/repos/netbirdio/netbird/releases/latest
CACERT_URL=https://curl.se/ca/cacert.pem
CACERT_SHA256_URL=https://curl.se/ca/cacert.pem.sha256
CACERT_PATH=/etc/ssl/certs/ca-certificates.crt
RCS=/etc/init.d/rcS
INITD_SCRIPT=/etc/init.d/netbird
NETBIRD_VERSION=${NETBIRD_VERSION:-}

[ "$(id -u)" = "0" ] || die "must run as root (you're on the Kobo, right?)"
[ -c /dev/net/tun ] || die "/dev/net/tun missing, this firmware build lacks TUN support, netbird (userspace WireGuard) can't work here"

uname_m=$(uname -m)
case "$uname_m" in
	armv6l)
		NB_ARCH=armv6 ;;
	armv7l)
		# no armv7 asset upstream but armv6 build runs fine on armv7 hardfp
		NB_ARCH=armv6 ;;
	aarch64)
		NB_ARCH=arm64 ;;
	x86_64)
		NB_ARCH=amd64 ;;
	*)
		die "unrecognized CPU arch '$uname_m', check https://github.com/netbirdio/netbird/releases for a matching asset" ;;
esac
log "arch: $uname_m -> netbird asset: $NB_ARCH"

if [ ! -s "$CACERT_PATH" ]; then
	log "no CA bundle found, fetching Mozilla's (via curl.se)..."
	mkdir -p /etc/ssl/certs
	tmp=/tmp/cacert.pem

	# wget doesn't verify TLS chains, netbird's Go stack does, so installing it first
	wget -qO "$tmp" "$CACERT_URL" || die "failed to download CA bundle"
	wget -qO "$tmp.sha256" "$CACERT_SHA256_URL" || die "failed to download CA bundle checksum"
	expected=$(awk '{print $1}' "$tmp.sha256")
	actual=$(sha256sum "$tmp" | awk '{print $1}')
	[ "$expected" = "$actual" ] || die "CA bundle checksum mismatch: expected $expected, got $actual"
	mv "$tmp" "$CACERT_PATH"
	rm -f "$tmp.sha256"
	log "CA bundle installed at $CACERT_PATH"
else
	log "CA bundle already present, skipping"
fi

mkdir -p "$NB_TMP" "$NB_INSTALL_DIR"
if [ -n "$NETBIRD_VERSION" ]; then
	version=$NETBIRD_VERSION
	log "using pinned version: $version"
else
	log "looking up latest netbird release..."
	version=$(wget -qO- "$NB_API_LATEST" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)
	[ -n "$version" ] || die "couldn't determine latest netbird version from GitHub API (rate limited? offline?), set NETBIRD_VERSION=x.y.z to skip lookup"
	log "latest netbird version: $version"
fi

already_installed=0
if [ -x "$NB_INSTALL_DIR/netbird" ]; then
	current=$("$NB_INSTALL_DIR/netbird" version 2>/dev/null | head -n1)
	case "$current" in
		*"$version"*) already_installed=1 ;;
	esac
fi

if [ "$already_installed" = "1" ]; then
	log "netbird $version already installed, skipping download"
else
	asset="netbird_${version}_linux_${NB_ARCH}.tar.gz"
	checksums="netbird_${version}_checksums.txt"
	base_url="https://github.com/netbirdio/netbird/releases/download/v${version}"

	log "downloading $asset ..."
	wget -qO "$NB_TMP/$asset" "$base_url/$asset" || die "download failed: $base_url/$asset"
	wget -qO "$NB_TMP/$checksums" "$base_url/$checksums" || die "checksum file download failed"

	expected=$(grep " $asset\$" "$NB_TMP/$checksums" | awk '{print $1}')
	[ -n "$expected" ] || die "no checksum entry for $asset in $checksums"
	actual=$(sha256sum "$NB_TMP/$asset" | awk '{print $1}')
	[ "$expected" = "$actual" ] || die "checksum mismatch for $asset: expected $expected, got $actual"
	log "checksum verified"

	tar -xzf "$NB_TMP/$asset" -C "$NB_TMP" netbird || die "extraction failed"
	mv "$NB_TMP/netbird" "$NB_INSTALL_DIR/netbird"
	chmod 755 "$NB_INSTALL_DIR/netbird"
	rm -rf "$NB_TMP"
	log "netbird $version installed to $NB_INSTALL_DIR/netbird"
fi

# Stock rcS mounts /var/lib as tmpfs, wiped every boot, which would lose
# netbird's enrollment on reboot
fstype=$(awk -v d="/var/lib" '$2 == d {print $3}' /proc/mounts)
if [ "$fstype" = "tmpfs" ]; then
	log "/var/lib is tmpfs on this device, using persistent state dir: $NB_STATE_DIR"
else
	log "/var/lib is on persistent storage ($fstype), using it as-is"
	NB_STATE_DIR=/var/lib/netbird
	NB_CONFIG=$NB_STATE_DIR/default.json
	NB_LOG_DIR=/var/log/netbird
fi
mkdir -p "$NB_STATE_DIR" "$NB_LOG_DIR"

cat > "$INITD_SCRIPT" <<EOF
#!/bin/sh
mkdir -p $NB_STATE_DIR $NB_LOG_DIR
nohup setsid $NB_INSTALL_DIR/netbird service run \\
	--config $NB_CONFIG \\
	--log-file $NB_LOG_DIR/client.log \\
	> $NB_LOG_DIR/daemon.log 2>&1 < /dev/null &
EOF
chmod 755 "$INITD_SCRIPT"
log "wrote $INITD_SCRIPT"

# no systemd/rcN.d on Kobo, so autostart = appending a guarded line to rcS
if grep -q "init.d/netbird" "$RCS" 2>/dev/null; then
	log "rcS already hooks netbird, skipping"
else
	[ -f "$RCS.bak.kobo-netbird" ] || cp "$RCS" "$RCS.bak.kobo-netbird"
	echo "$INITD_SCRIPT &" >> "$RCS"
	sync
	log "hooked $INITD_SCRIPT into $RCS (backup: $RCS.bak.kobo-netbird)"
fi

mkdir -p /usr/local/bin
ln -sf "$NB_INSTALL_DIR/netbird" "$NB_BIN_LINK"
log "linked $NB_BIN_LINK -> $NB_INSTALL_DIR/netbird"
case ":$PATH:" in
	*:/usr/local/bin:*) : ;;
	*) log "WARNING: /usr/local/bin not on \$PATH in this shell, use $NB_BIN_LINK directly, or add it to PATH" ;;
esac

"$NB_INSTALL_DIR/netbird" service run --config "$NB_CONFIG" --log-file "$NB_LOG_DIR/client.log" > "$NB_LOG_DIR/daemon.log" 2>&1 < /dev/null &
sleep 1

log ""
log "netbird installed and running. Enroll it with your preferred method, e.g.:"
log "  netbird up --setup-key <YOUR_SETUP_KEY>"
log "  netbird up                              # interactive SSO login"
log ""
log "It will auto-start on every reboot from here on."
