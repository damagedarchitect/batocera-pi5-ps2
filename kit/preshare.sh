#!/bin/bash
# Batocera calls "/boot/preshare.sh start" from /etc/init.d/S11share, before /userdata is mounted.
# Crater kit: hand off to a detached job that waits for /userdata, then installs/updates the
# PS2 (ARMSX2) + arcade kit from /boot/crater-kit. Safe to delete this file to disable the kit hook.
[ "$1" = "start" ] || exit 0
[ -f /boot/crater-kit/boot-hook.sh ] || exit 0
setsid bash /boot/crater-kit/boot-hook.sh </dev/null >/dev/null 2>&1 &
exit 0
