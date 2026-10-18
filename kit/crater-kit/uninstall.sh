#!/bin/bash
# Crater kit: remove the PS2 (ARMSX2) integration. Keeps PS2 games, BIOS, saves and memory cards.
DEST=/userdata/system/armsx2
ESCFG=/userdata/system/configs/emulationstation
echo "removing Crater PS2 kit..."
# stop the boot-time self-repair first, or it would reinstall at the next boot
if [ -f /boot/preshare.sh ] && grep -q crater-kit /boot/preshare.sh && mount -o remount,rw /boot 2>/dev/null; then
    mv -f /boot/preshare.sh /boot/preshare.sh.disabled
    sync; mount -o remount,ro /boot
fi
rm -rf "$DEST"
rm -f "$ESCFG/es_systems_ps2.cfg" "$ESCFG/es_features_armsx2.cfg"
rm -f "/userdata/roms/ports/Crater - PS2 and Arcade check.sh"
echo "done (games, BIOS and saves were left alone). Restarting the menu..."
curl -s -m 5 http://127.0.0.1:1234/restart >/dev/null 2>&1
