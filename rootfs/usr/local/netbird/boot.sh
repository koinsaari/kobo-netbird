#!/bin/sh
# Started by udev at boot. udev kills long-running RUN children, so detach first.
[ "$1" = detached ] || { setsid "$0" detached </dev/null >/dev/null 2>&1 & exit 0; }

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
# /var/lib is a 16k tmpfs on stock firmware, wiped every boot.
export NB_STATE_DIR=/etc/netbird
nb=/opt/netbird/netbird
state=/etc/netbird
onboard=/mnt/onboard/.adds/netbird
mkdir -p "$state/log"

if [ ! -c /dev/net/tun ]; then
	mkdir -p /dev/net
	mknod /dev/net/tun c 10 200
fi

# Not pidof: `netbird up` below has the same process name.
if [ ! -S /var/run/netbird.sock ]; then
	"$nb" service run \
		--config "$state/default.json" \
		--log-file "$state/log/client.log" \
		>"$state/log/daemon.log" 2>&1 </dev/null &
fi

# The onboard FAT partition mounts after loop0 appears.
i=0
until grep -q " /mnt/onboard " /proc/mounts || [ $i -ge 60 ]; do
	sleep 1
	i=$((i + 1))
done

# Move the key off the FAT partition, which anyone with a USB cable can read.
if [ -f "$onboard/setup-key" ]; then
	mv "$onboard/setup-key" "$state/setup-key"
	chmod 600 "$state/setup-key"
	sync
fi
[ -f "$state/setup-key" ] || exit 0

if [ -f "$onboard/env" ]; then
	while IFS='=' read -r k v; do
		case "$k" in
			NB_MANAGEMENT_URL | NB_HOSTNAME) export "$k=$v" ;;
		esac
	done <"$onboard/env"
fi

until "$nb" up --setup-key-file "$state/setup-key" >>"$state/log/enrol.log" 2>&1; do
	sleep 30
done
rm -f "$state/setup-key"
sync
