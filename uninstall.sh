#!/bin/sh
set -eu

RCS=/etc/init.d/rcS
INITD_SCRIPT=/etc/init.d/netbird

echo "[kobo-netbird] stopping daemon..." >&2
pkill -f "netbird service run" 2>/dev/null || true

rm -f "$INITD_SCRIPT"
rm -f /usr/local/bin/netbird
rm -rf /opt/netbird
rm -rf /etc/netbird /var/lib/netbird

if grep -q "init.d/netbird" "$RCS" 2>/dev/null; then
	grep -v "init.d/netbird" "$RCS" > "$RCS.tmp"
	mv "$RCS.tmp" "$RCS"
	chmod 755 "$RCS"
	sync
	echo "[kobo-netbird] removed autostart hook from $RCS" >&2
fi

echo "[kobo-netbird] uninstalled. Peer enrollment on your netbird mesh still exists remotely, remove it from the dashboard if you don't want it there anymore." >&2
