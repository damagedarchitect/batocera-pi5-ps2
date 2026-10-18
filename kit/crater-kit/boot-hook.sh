#!/bin/bash
# Crater kit boot hook - runs detached from /boot/preshare.sh on every boot.
# Waits for /userdata, then runs install.sh only when the kit version changed
# (or the install is missing). Normal boots cost one version-file comparison.
KIT=/boot/crater-kit
DEST=/userdata/system/armsx2

for _ in $(seq 1 240); do
    grep -qs " /userdata " /proc/mounts && [ -d /userdata/system ] && break
    sleep 1
done
grep -qs " /userdata " /proc/mounts || exit 0
# Batocera falls back to a 256 MB tmpfs when the SHARE partition fails to mount - never install into that
grep -qsE "^[^ ]+ /userdata tmpfs " /proc/mounts && exit 0

want=$(cat "$KIT/VERSION" 2>/dev/null)
have=$(cat "$DEST/.installed" 2>/dev/null)
if [ -n "$want" ] && [ "$want" = "$have" ] && [ -x "$DEST/app/usr/bin/armsx2-qt" ] && [ ! -e "$KIT/FORCE_REINSTALL" ]; then
    exit 0
fi

# a version that already failed (e.g. disk full) is not retried on every boot; run install.sh by hand
[ "$(cat /userdata/system/logs/crater-kit.failed 2>/dev/null)" = "$want" ] && [ ! -e "$KIT/FORCE_REINSTALL" ] && exit 0
mkdir -p /userdata/system/logs
exec flock -n /var/run/crater-kit.lock bash "$KIT/install.sh" --from-boot >>/userdata/system/logs/crater-kit.log 2>&1
