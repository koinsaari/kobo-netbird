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

env="$onboard/env"
cr=$(printf '\r')
if [ -f "$env" ]; then
	while IFS="=" read -r k v || [ -n "$k" ]; do
		v=${v%"$cr"}
		[ -n "$v" ] || continue
		# Not exported: netbird would take it as --setup-key and reject --setup-key-file.
		case "$k" in
			NB_SETUP_KEY) (umask 077 && printf '%s\n' "$v" >"$state/setup-key") ;;
			NB_MANAGEMENT_URL | NB_HOSTNAME) export "$k=$v" ;;
		esac
	done <"$env"
	# Anyone with a USB cable can read the FAT partition.
	sed -i 's/^NB_SETUP_KEY=.*/NB_SETUP_KEY=/' "$env"
	sync
fi
[ -f "$state/setup-key" ] || exit 0

until "$nb" up --setup-key-file "$state/setup-key" >>"$state/log/enrol.log" 2>&1; do
	sleep 30
done
rm -f "$state/setup-key"
sync
