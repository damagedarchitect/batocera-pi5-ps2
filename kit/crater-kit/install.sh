#!/bin/bash
# Crater kit installer - PS2 (ARMSX2) for Batocera 43 on Raspberry Pi 5, plus arcade checks.
# Runs automatically at boot (via /boot/preshare.sh -> boot-hook.sh) or manually over SSH:
#     bash /boot/crater-kit/install.sh
# Everything it installs lives in /userdata; nothing in the read-only system image is touched.
# Uninstall: bash /boot/crater-kit/install.sh --uninstall
set -u
KIT=${CRATER_KIT:-/boot/crater-kit}   # the Ports installer runs it from an unpacked copy
BOOTKIT=/boot/crater-kit
DEST=/userdata/system/armsx2
ESCFG=/userdata/system/configs/emulationstation
VER=$(cat "$KIT/VERSION" 2>/dev/null || echo unknown)
TS() { date '+%F %T'; }
log() { echo "[$(TS)] $*"; }
die() {
    log "ERROR: $*"
    rm -rf "${WORK:-/nonexistent}" "$DEST/app.new"   # never leave half-extracted files filling /userdata
    echo "$VER" > /userdata/system/logs/crater-kit.failed 2>/dev/null  # boot hook won't retry this version
    report_to_boot; exit 1
}

boot_rw() { mount -o remount,rw /boot 2>/dev/null; }
boot_ro() { sync; mount -o remount,ro /boot 2>/dev/null; }

report_to_boot() {
    # copy the install log + diagnostics report next to the boot copy of the kit (readable from Windows)
    [ -d "$BOOTKIT" ] || return 0
    boot_rw || return 0
    mkdir -p "$BOOTKIT/reports"
    cp -f /userdata/system/logs/crater-kit.log "$BOOTKIT/reports/install-log.txt" 2>/dev/null
    cp -f /userdata/system/logs/crater-report.txt "$BOOTKIT/reports/report.txt" 2>/dev/null
    rm -f "$BOOTKIT/FORCE_REINSTALL"
    boot_ro
}

if [ "${1:-}" = "--uninstall" ]; then
    exec bash "$KIT/uninstall.sh"
fi

if [ "${1:-}" != "--from-boot" ]; then
    mkdir -p /userdata/system/logs
    exec > >(tee -a /userdata/system/logs/crater-kit.log) 2>&1
fi
log "===== crater kit $VER install start ($*) ====="
grep -q '^43' /usr/share/batocera/batocera.version 2>/dev/null || log "WARNING: built for Batocera 43.x, this is $(cat /usr/share/batocera/batocera.version 2>/dev/null)"
[ "$(cat /boot/boot/batocera.board 2>/dev/null)" = "bcm2712" ] || log "WARNING: built for Raspberry Pi 5 (bcm2712)"
[ "$(getconf PAGESIZE)" = "4096" ] || die "kernel page size is $(getconf PAGESIZE); this kit ships the 4K-page ARMSX2 build"

PY=${CRATER_PY:-"python3 -I"}
LDSO=${CRATER_LDSO:-/lib/ld-linux-aarch64.so.1}
grep -qsE "^[^ ]+ /userdata tmpfs " /proc/mounts && die "/userdata is a RAM fallback (tmpfs): the SHARE partition did not mount - fix that first (e2fsck)"
# scratch in RAM (/tmp), not on /userdata: only the final ~230 MB lands on the card
WORK=$(mktemp -d /tmp/crater-kit.XXXXXX) || die "cannot create work dir"
rm -rf "$DEST/.work"
mkdir -p "$DEST" || die "cannot create $DEST"
need_mb=600   # 230 MB install + old copy during swap + headroom so EmulationStation can still write
free_mb=$(df -Pm /userdata | awk 'NR==2{print $4}')
log "/userdata free: ${free_mb} MB (need ${need_mb} MB)"
[ "${free_mb:-0}" -ge "$need_mb" ] || die "not enough space on /userdata (${free_mb} MB free, need ${need_mb} MB) - nothing was installed"
tmp_mb=$(df -Pm /tmp | awk 'NR==2{print $4}')
[ "${tmp_mb:-0}" -ge 450 ] || die "not enough RAM in /tmp for unpacking (${tmp_mb} MB)"

# ---- 1. reassemble + verify payload -------------------------------------------------------
. "$KIT/payload/manifest.sh" || die "payload manifest missing"
cat "$KIT"/payload/appimage.part* > "$WORK/$APPIMAGE_NAME" || die "appimage parts missing"
( cd "$WORK" && echo "$APPIMAGE_SHA256  $APPIMAGE_NAME" | sha256sum -c - ) || die "AppImage checksum mismatch (card copy corrupted?)"
cp -f "$KIT/payload/$LIBRETRO_NAME" "$WORK/" || die "libretro payload missing"
( cd "$WORK" && echo "$LIBRETRO_SHA256  $LIBRETRO_NAME" | sha256sum -c - ) || die "libretro checksum mismatch"
log "payload verified: $APPIMAGE_NAME / $LIBRETRO_NAME"

# ---- 2. extract the AppImage (no FUSE needed) ---------------------------------------------
magic=$(dd if="$WORK/$APPIMAGE_NAME" bs=1 skip="$APPIMAGE_OFFSET" count=4 2>/dev/null)
[ "$magic" = "hsqs" ] || die "squashfs not found at offset $APPIMAGE_OFFSET"
rm -rf "$DEST/app.new"
unsquashfs -no-progress -f -o "$APPIMAGE_OFFSET" -d "$DEST/app.new" "$WORK/$APPIMAGE_NAME" >/dev/null || die "unsquashfs failed"
rm -f "$WORK/$APPIMAGE_NAME"
[ -x "$DEST/app.new/usr/bin/armsx2-qt" ] || die "armsx2-qt missing after extract"

missing=$($LDSO --list "$DEST/app.new/usr/bin/armsx2-qt" 2>&1 | grep "not found")
[ -z "$missing" ] || die "missing libraries for armsx2-qt: $missing"

mkdir -p "$WORK/libretro"
zstd -dc "$WORK/$LIBRETRO_NAME" | tar -x -C "$WORK" || die "libretro extract failed"
find "$WORK" -name armsx2_libretro.so -path '*libretro-sha*' -exec mv -f {} "$WORK/libretro/armsx2_libretro.so" \;
[ -f "$WORK/libretro/armsx2_libretro.so" ] || die "armsx2_libretro.so missing after extract"

# ---- 3. swap in atomically ----------------------------------------------------------------
rm -rf "$DEST/app.old" "$DEST/libretro.old"
[ -d "$DEST/app" ] && mv "$DEST/app" "$DEST/app.old"
[ -d "$DEST/libretro" ] && mv "$DEST/libretro" "$DEST/libretro.old"
mv "$DEST/app.new" "$DEST/app" && cp -r "$WORK/libretro" "$DEST/libretro" || die "install move failed"
rm -rf "$DEST/app.old" "$DEST/libretro.old"

rm -rf "$DEST/configgen" "$DEST/libretro-share"
cp -r "$KIT/files/configgen" "$DEST/configgen"
cp -r "$KIT/files/libretro-share" "$DEST/libretro-share"
cp -f "$KIT/files/emulatorlauncher-armsx2" "$DEST/emulatorlauncher-armsx2"
cp -f "$KIT/diag.sh" "$DEST/diag.sh"
cp -f "$KIT/files/effect-patch-games.txt" "$DEST/effect-patch-games.txt" 2>/dev/null
chmod 755 "$DEST/emulatorlauncher-armsx2" "$DEST/diag.sh"
# the wrapper is a python script: sanity check that configgen accepts our generator
$PY -c "
import sys; sys.argv=['x']
src=open('$DEST/emulatorlauncher-armsx2').read().replace('if __name__ == \"__main__\":','if False:')
exec(compile(src,'w','exec'),{'__name__':'w'})
from configgen.generators import get_generator
g=get_generator('armsx2','armsx2'); print('generator ok:', type(g).__name__)
" || die "configgen refused the armsx2 generator (Batocera configgen changed?)"

# ---- 4. EmulationStation system + options -------------------------------------------------
mkdir -p "$ESCFG"
for f in es_systems_ps2.cfg es_features_armsx2.cfg; do
    if [ -f "$ESCFG/$f" ] && ! cmp -s "$ESCFG/$f" "$KIT/files/es/$f"; then
        cp -f "$ESCFG/$f" "$ESCFG/$f.bak-$(date +%Y%m%d%H%M%S)"
    fi
    cp -f "$KIT/files/es/$f" "$ESCFG/$f"
done

# ---- 5. folders ---------------------------------------------------------------------------
mkdir -p /userdata/roms/ps2 /userdata/bios/ps2 /userdata/saves/ps2/armsx2 /userdata/cheats/ps2 /userdata/bios/pcsx2
[ -e /userdata/bios/pcsx2/bios ] || ln -s ../ps2 /userdata/bios/pcsx2/bios   # libretro core looks in <system>/pcsx2/bios
[ -f /userdata/roms/ps2/_info.txt ] || cat > /userdata/roms/ps2/_info.txt <<'EOF'
PlayStation 2 (ARMSX2, Crater kit)
ROMs:  .iso .chd .cso .zso .bin/.cue .mdf .nrg .gz .elf   (CHD recommended - smaller, same speed)
BIOS:  put your own PS2 BIOS dump(s) in /userdata/bios/ps2  (e.g. SCPH-70012 / SCPH-39001 .bin)
Pick the emulator per game in EmulationStation: ARMSX2 (default) or LIBRETRO/ARMSX2.
EOF
cp -f "$KIT/files/effect-patch-games.txt" /userdata/roms/ps2/_effect-patch-games.txt 2>/dev/null
mkdir -p /userdata/roms/ports
cp -f "$KIT/diag.sh" "/userdata/roms/ports/Crater - PS2 and Arcade check.sh"
chmod 755 "/userdata/roms/ports/Crater - PS2 and Arcade check.sh"

echo "$VER" > "$DEST/.installed"
rm -f /userdata/system/logs/crater-kit.failed
rm -rf "$WORK"
log "ARMSX2 installed to $DEST ($(du -sh "$DEST" | cut -f1))"

# ---- 6. arcade (MAME / Naomi / Atomiswave) evidence-based defaults + report ---------------
CRATER_KIT="$KIT" bash "$KIT/diag.sh" --apply-arcade-fixes --quiet || log "diag returned non-zero"

report_to_boot

# ---- 7. reload EmulationStation so PS2 appears ---------------------------------------------
if [ "${1:-}" = "--from-boot" ]; then
    for _ in $(seq 1 90); do
        [ "$(batocera-es-swissknife --espid 2>/dev/null)" != "0" ] && break
        sleep 2
    done
fi
if [ -z "${CRATER_NO_ES_RESTART:-}" ] && [ "$(batocera-es-swissknife --emupid 2>/dev/null | head -1)" = "0" ]; then
    # ask ES to restart itself through its own API (clean exit -> emulationstation-standalone relaunches).
    # NOT "batocera-es-swissknife --restart": that is a kill -9, which on the Pi 5 labwc session
    # can leave a bare desktop (Terminal / Reconfigure / Exit menu) instead of ES.
    curl -s -m 3 http://127.0.0.1:1234/notify -d "Crater kit $VER installed - PS2 is ready (restarting menu)" >/dev/null 2>&1
    sleep 4
    curl -s -m 5 http://127.0.0.1:1234/restart >/dev/null 2>&1
fi
log "===== crater kit install done ====="
exit 0
