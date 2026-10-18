#!/bin/bash
# Build the release zip (what users copy to roms/ports) from this repo + the ARMSX2 nightly files.
#
#   tools/build-release.sh <dir-with-armsx2-files>
#
# <dir> must contain the two upstream files named in kit/crater-kit/payload/manifest.sh:
#   ARMSX2-nightly-<date>-<commit>-Linux-arm64-4K-pages.AppImage
#   ARMSX2-nightly-<date>-<commit>-Linux-arm64-libretro-core.tar.zst
# (from https://github.com/ARMSX2/ARMSX2/releases). Both are checked against the SHA-256 in the manifest.
# Output: dist/Crater-PS2-Kit-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=${1:?usage: tools/build-release.sh <dir-with-armsx2-files>}
. kit/crater-kit/payload/manifest.sh
VER=$(tr -d '\n' < kit/crater-kit/VERSION)

for f in "$APPIMAGE_NAME" "$LIBRETRO_NAME"; do [ -f "$SRC/$f" ] || { echo "missing $SRC/$f"; exit 1; }; done
echo "$APPIMAGE_SHA256  $SRC/$APPIMAGE_NAME" | sha256sum -c -
echo "$LIBRETRO_SHA256  $SRC/$LIBRETRO_NAME" | sha256sum -c -

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -a kit/crater-kit "$STAGE/crater-kit"; cp kit/preshare.sh "$STAGE/"
rm -rf "$STAGE/crater-kit/reports"
# FAT32 + GitHub web limits: ship the AppImage in 25 MiB parts; install.sh reassembles + re-verifies
split -b 25M -d -a 2 "$SRC/$APPIMAGE_NAME" "$STAGE/crater-kit/payload/appimage.part"
cp "$SRC/$LIBRETRO_NAME" "$STAGE/crater-kit/payload/"
( cd "$STAGE/crater-kit/payload" && sha256sum appimage.part* "$LIBRETRO_NAME" > SHA256SUMS.txt )
sed "s/@VERSION@/$VER/g" "installer/Crater - Install or Repair PS2.sh.in" > "$STAGE/Crater - Install or Repair PS2.sh"
sed "s/@VERSION@/$VER/g" "installer/HOW TO INSTALL.txt.in" > "$STAGE/HOW TO INSTALL.txt"
chmod 755 "$STAGE"/*.sh "$STAGE"/crater-kit/*.sh "$STAGE/crater-kit/files/emulatorlauncher-armsx2"

mkdir -p dist
OUT="dist/Crater-PS2-Kit-$VER.zip"; rm -f "$OUT"
python3 - "$STAGE" "$OUT" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w") as z:
    for root, _, files in os.walk(stage):
        for fn in sorted(files):
            p = os.path.join(root, fn); arc = os.path.relpath(p, stage)
            zi = zipfile.ZipInfo.from_file(p, arc)
            zi.external_attr = (0o755 if os.access(p, os.X_OK) else 0o644) << 16
            zi.compress_type = zipfile.ZIP_STORED if "/payload/" in "/" + arc else zipfile.ZIP_DEFLATED
            with open(p, "rb") as f: z.writestr(zi, f.read())
PY
sha256sum "$OUT"
echo "built $OUT"
