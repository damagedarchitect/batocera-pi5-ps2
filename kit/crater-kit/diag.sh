#!/bin/bash
# Crater kit diagnostics - PS2 (ARMSX2) + MAME / Naomi / Naomi 2 / Atomiswave on Batocera 43 (Pi 5)
#   bash /boot/crater-kit/diag.sh                       report only
#   bash /boot/crater-kit/diag.sh --apply-arcade-fixes  also set evidence-based MAME defaults
# Also installed as a Ports entry ("Crater - PS2 and Arcade check") so it can run from a controller.
# Report: /userdata/system/logs/crater-report.txt  (+ copied to /boot/crater-kit/reports/report.txt)
# The report never includes batocera.conf secrets (wifi, passwords, tokens).
APPLY=0; QUIET=0
for a in "$@"; do
    case "$a" in --apply-arcade-fixes) APPLY=1 ;; --quiet) QUIET=1 ;; esac
done
OUT=/userdata/system/logs/crater-report.txt
DEST=/userdata/system/armsx2
MAMEBIN=${CRATER_MAMEBIN:-/usr/bin/mame/mame}
SAMPLE=${CRATER_SAMPLE:-25}
mkdir -p /userdata/system/logs
exec 3>"$OUT"
r() { echo "$*" >&3; }
hdr() { r ""; r "=== $* ==="; }
summary=()

get() { batocera-settings-get "$1" 2>/dev/null; }

r "Crater kit report - $(date '+%F %T')"
r "kit: $(cat ${CRATER_KIT:-/boot/crater-kit}/VERSION 2>/dev/null)  installed: $(cat $DEST/.installed 2>/dev/null || echo no)"
r "batocera: $(cat /usr/share/batocera/batocera.version 2>/dev/null)  board: $(cat /boot/boot/batocera.board 2>/dev/null)"
r "kernel: $(uname -r)  pagesize: $(getconf PAGESIZE)  model: $( { tr -d '\0' </proc/device-tree/model; } 2>/dev/null)"
r "ram: $(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo)  userdata free: $(df -h /userdata | awk 'NR==2{print $4}')"
command -v vcgencmd >/dev/null && r "throttled: $(vcgencmd get_throttled 2>/dev/null)  temp: $(vcgencmd measure_temp 2>/dev/null)  arm_freq: $(vcgencmd get_config arm_freq 2>/dev/null)"
r "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
r "vulkan: $(batocera-vulkan hasVulkan 2>/dev/null) / $(batocera-vulkan defaultName 2>/dev/null)"

# ------------------------------------------------------------------ PS2
hdr "PS2 / ARMSX2"
if [ -x "$DEST/app/usr/bin/armsx2-qt" ]; then
    miss=$(/lib/ld-linux-aarch64.so.1 --list "$DEST/app/usr/bin/armsx2-qt" 2>&1 | grep "not found")
    r "armsx2-qt: present, libs: ${miss:-all resolved}"
    r "libretro core: $(ls -la $DEST/libretro/armsx2_libretro.so 2>/dev/null | awk '{print $5" bytes"}')"
else
    r "armsx2-qt: NOT INSTALLED"; summary+=("PS2: ARMSX2 not installed")
fi
r "es_systems_ps2.cfg: $( [ -f /userdata/system/configs/emulationstation/es_systems_ps2.cfg ] && echo present || echo MISSING)"
r "ps2.emulator=$(get ps2.emulator) ps2.core=$(get ps2.core) (empty = kit default armsx2)"
bios=$(find /userdata/bios/ps2 -maxdepth 1 -type f \( -iname '*.bin' -o -iname '*.rom*' -o -iname '*.mec' -o -iname '*.nvm' \) 2>/dev/null)
nbios=$(find /userdata/bios/ps2 -maxdepth 1 -type f -size +3000k -size -5000k -iname '*.bin' 2>/dev/null | wc -l)
r "BIOS candidates (4 MB .bin): $nbios"
echo "$bios" | while read -r f; do [ -n "$f" ] && r "   $(basename "$f")  $(stat -c %s "$f") bytes  md5=$(md5sum "$f" | cut -c1-32)"; done
[ "$nbios" -gt 0 ] || summary+=("PS2: no BIOS in /userdata/bios/ps2 - games will not boot")
nps2=$(find /userdata/roms/ps2 -maxdepth 2 -type f \( -iname '*.iso' -o -iname '*.chd' -o -iname '*.cso' -o -iname '*.zso' -o -iname '*.bin' -o -iname '*.gz' -o -iname '*.mdf' -o -iname '*.nrg' -o -iname '*.elf' \) 2>/dev/null | wc -l)
r "PS2 games found: $nps2"
if [ -f /userdata/system/configs/ARMSX2/logs/emulog.txt ]; then
    r "--- last ARMSX2 emulog (errors/warnings) ---"
    grep -iE "error|fail|vulkan|renderer|bios|warning" /userdata/system/configs/ARMSX2/logs/emulog.txt 2>/dev/null | tail -40 | sed 's/^/   /' >&3
fi

# ------------------------------------------------------------------ arcade helpers
verify_sets() {   # $1 = rom dir, $2 = label ; prints "ok total" ; details to report
    local dir="$1" label="$2" n=0 ok=0 bad=0 nf=0 res
    [ -x "$MAMEBIN" ] || { echo "0 0"; return; }
    local rompath="$dir;/userdata/bios/mame;/userdata/bios/dc;/userdata/bios"
    while read -r z; do
        [ -n "$z" ] || continue
        local set; set=$(basename "$z"); set="${set%.*}"
        res=$(cd /tmp && timeout 25 "$MAMEBIN" -rompath "$rompath" -verifyroms "$set" 2>&1 | grep -iE "^romset|no matching systems" | head -1)
        n=$((n+1))
        case "$res" in
            *"is good"*|*"is best available"*) ok=$((ok+1)) ;;
            *"No matching systems"*) nf=$((nf+1)); r "   [$label] $set: not a MAME 0.285 machine name (device/bios zip, or renamed older set)" ;;
            *) bad=$((bad+1)); r "   [$label] $set: ${res:-no answer}  (files missing/wrong for 0.285)" ;;
        esac
    done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.7z' \) 2>/dev/null | shuf -n "$SAMPLE" 2>/dev/null)
    r "   [$label] sampled $n sets: $ok good/best-available, $bad bad/incomplete, $nf unknown names (MAME $( "$MAMEBIN" -version 2>/dev/null | cut -d' ' -f1 ))"
    # unknown names are ambiguous (device/bios zips), so judge on recognised machines only
    echo "$ok $((ok+bad))"
}

list_zip() { [ -f "$1" ] && r "   $1: $(unzip -Z1 "$1" 2>/dev/null | tr '\n' ' ' | cut -c1-400)" || r "   $1: MISSING"; }

# ------------------------------------------------------------------ MAME
hdr "MAME"
nm=$(find /userdata/roms/mame -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.7z' \) 2>/dev/null | wc -l)
mame_emu=$(get mame.emulator); mame_core=$(get mame.core)
r "sets in /userdata/roms/mame: $nm   mame.emulator=${mame_emu:-<default libretro>} mame.core=${mame_core:-<default mame078plus = MAME 2003-Plus, needs 0.78 sets>}"
r "available: libretro mame (0.285), libretro mame078plus (0.78), standalone mame (0.285)"
if [ "$nm" -gt 0 ]; then
    read -r ok tot < <(verify_sets /userdata/roms/mame mame | tail -1)
    r "   verdict input: $ok/$tot recognised sets are valid MAME 0.285"
    if [ "$tot" -ge 5 ] && [ $((ok*100/tot)) -ge 60 ]; then
        if [ -z "$mame_emu$mame_core" ]; then
            if [ "$APPLY" = 1 ]; then
                batocera-settings-set mame.emulator libretro mame.core mame
                r "   APPLIED: mame.emulator=libretro mame.core=mame (your sets match MAME 0.285, the stock default MAME 2003-Plus can't run them)"
                summary+=("MAME: switched default core to MAME 0.285 ($ok/$tot sampled sets valid)")
            else
                r "   RECOMMEND: set MAME core to 'mame' (0.285) - run with --apply-arcade-fixes"
                summary+=("MAME: sets are 0.285 - use core 'mame', not the default MAME 2003-Plus")
            fi
        else
            r "   left your explicit mame emulator/core choice alone"
        fi
    elif [ "$tot" -ge 5 ]; then
        r "   most sampled sets are NOT valid 0.285 sets: if they are a 0.78 set keep MAME 2003-Plus (default); otherwise rebuild the set for 0.285 with ClrMamePro/RomVault"
        summary+=("MAME: only $ok/$tot sampled sets match 0.285 - check romset version")
    fi
fi

# ------------------------------------------------------------------ Naomi / Naomi 2 / Atomiswave (Flycast)
hdr "NAOMI / NAOMI 2 / ATOMISWAVE (Flycast)"
r "BIOS folder /userdata/bios/dc:"
list_zip /userdata/bios/dc/naomi.zip
list_zip /userdata/bios/dc/naomi2.zip
list_zip /userdata/bios/dc/awbios.zip
for b in naomi naomi2 awbios; do [ -f "/userdata/bios/dc/$b.zip" ] || [ -f "/userdata/bios/$b.zip" ] || summary+=("Flycast: /userdata/bios/dc/$b.zip missing"); done
for sys in naomi naomi2 atomiswave; do
    d=/userdata/roms/$sys
    n=$(find "$d" -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.7z' \) 2>/dev/null | wc -l)
    chd=$(find "$d" -mindepth 2 -maxdepth 2 -iname '*.chd' 2>/dev/null | wc -l)
    loosechd=$(find "$d" -maxdepth 1 -iname '*.chd' 2>/dev/null | wc -l)
    r "$sys: $n zips, $chd CHDs in <set>/ subfolders, $loosechd loose CHDs   $sys.emulator=$(get $sys.emulator) $sys.core=$(get $sys.core)"
    [ "$loosechd" -gt 0 ] && summary+=("$sys: $loosechd CHD(s) loose in the folder - GD-ROM CHDs must sit in a sub-folder named after the zip (e.g. ikaruga/ikaruga.chd next to ikaruga.zip)")
    if [ "$n" -gt 0 ]; then
        read -r ok tot < <(verify_sets "$d" "$sys" | tail -1)
        [ "$tot" -ge 3 ] && [ $((ok*100/tot)) -lt 60 ] && summary+=("$sys: only $ok/$tot sampled sets match current MAME naming (Flycast expects modern MAME naomi/aw sets)")
    fi
done

# ------------------------------------------------------------------ last launch log (filtered)
hdr "LAST LAUNCH (es_launch_*.log, secrets filtered)"
for f in /userdata/system/logs/es_launch_stdout.log /userdata/system/logs/es_launch_stderr.log; do
    [ -f "$f" ] || continue
    r "--- $(basename "$f")"
    grep -viE "token|password|passwd|wifi|ssid|Settings:|key=" "$f" | tail -40 | sed 's/^/   /' >&3
done
[ -f /tmp/launch_error.log ] && r "launch_error: $(cat /tmp/launch_error.log)"

hdr "SUMMARY"
if [ ${#summary[@]} -eq 0 ]; then r "no problems detected"; else for s in "${summary[@]}"; do r " - $s"; done; fi
exec 3>&-

# copy to the boot partition when run by hand / from Ports (install.sh does its own copy)
if [ "$QUIET" = 0 ]; then
    if mount -o remount,rw /boot 2>/dev/null; then
        mkdir -p /boot/crater-kit/reports && cp -f "$OUT" /boot/crater-kit/reports/report.txt
        sync; mount -o remount,ro /boot
    fi
    msg="Crater check done. Report: /userdata/system/logs/crater-report.txt"
    [ ${#summary[@]} -gt 0 ] && msg="$msg\n$(printf ' - %s\n' "${summary[@]}" | head -8)"
    curl -s -m 3 http://127.0.0.1:1234/messagebox -d "$(echo -e "$msg")" >/dev/null 2>&1
    cat "$OUT"
fi
exit 0
