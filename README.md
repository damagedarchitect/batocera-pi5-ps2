# batocera-pi5-ps2

PlayStation 2 emulation on **Batocera 43 for Raspberry Pi 5**, installed with one script from the Ports menu.

Stock Batocera 43 builds PCSX2 for x86_64 only, disables Play! on the Pi 5, and its new ARMSX2 package (Sept 2026) is limited to Qualcomm boards on the v44 launcher. This kit backports that integration to 43.x on the Pi 5. It installs everything under `/userdata`, so the read-only system image is never modified.

- **Emulator:** [ARMSX2](https://github.com/ARMSX2/ARMSX2) (ARM64 fork of PCSX2 with native ARM64 JIT), nightly `20261011` / commit `0076b5c389`, 4K-page Linux build.
- **Two ways to run it**, selectable per game in EmulationStation:
  - `armsx2` standalone (default), with full Batocera integration: controllers, hotkeys (exit, save/load state, menu) and per-game options.
  - `libretro/armsx2`, the same core inside RetroArch.
- **Renderer:** Vulkan on the Pi 5's V3D GPU. OpenGL can't be used because the GPU only supports GL 3.1. Software rendering is available as a fallback.

## Install / repair

1. Download `Crater-PS2-Kit-<version>.zip` from [Releases](../../releases).
2. Copy **both** of these into `\\BATOCERA\share\roms\ports\`:
   - `Crater - Install or Repair PS2.sh` (take it out of the zip)
   - the zip itself (leave it zipped)
3. On the Pi, open **Ports → Crater - Install or Repair PS2**. It takes about 1–2 minutes, and the menu restarts by itself.

You can run it again any time. Every run is a clean reinstall. It never touches PS2 games, BIOS, saves or per-game settings.

What the installer checks and does:

- Refuses to run when SHARE isn't mounted (Batocera's 256 MB RAM fallback) or the card is nearly full.
- Verifies the zip by checking each file's CRC, then the payload's SHA-256, before installing anything.
- Shows progress in a full-screen terminal on the TV when one is available. Either way it logs to `/userdata/system/logs/crater-kit.log`.
- Puts a copy of the kit on the boot partition. At each boot, a hook (`/boot/preshare.sh`) reinstalls the kit if the emulator is missing or the version changed.

**Remove:** run `bash /userdata/system/armsx2/uninstall.sh`. It keeps games, BIOS and saves, and disables the boot hook.

## You provide

- **PS2 BIOS** in `/userdata/bios/ps2/` (e.g. `SCPH-70012.bin`). Use your own dump.
- **PS2 games** in `/userdata/roms/ps2/`, as `.iso` or `.chd` (CHD recommended; `chdman createdvd -hs 2048`). Don't zip them.

## What to expect on a Pi 5

The Pi 5's CPU is the bottleneck, mostly for the main PS2 processor (the EE) and the VU1 vector unit. Overclocking doesn't close the gap, and higher voltage risks the hardware.

| Works well | Playable with drops | Too heavy |
|---|---|---|
| Light 2D titles and low-geometry 3D (e.g. Rez, Godzilla: Save the Earth) | THPS4, Burnout Revenge, Midnight Club 3 (worse in large areas), Katamari (choppy in levels) | GT4, open-world GTA, Jak, Ratchet, God of War, Shadow of the Colossus |

Tuning order: native resolution, Blending Accuracy Minimum, EE Cycle Rate 60–75%, MTVU on (default). For the heavy franchises, the PSP versions (GTA LCS/VCS, Midnight Club 3, Burnout Legends) run far better on this hardware.

## Performance toolkit

To find it, select a game, then go to **Advanced options → Performance toolkit**. Every option applies to that game only.

| Option | What it does |
|---|---|
| **Performance profile** (Off / Light / Medium / Max) | A one-click preset. It only fills in options you haven't set yourself. |
| **Effect removal patches** | Turns off motion blur, bloom, depth of field, fog and noise using the patches that ship with ARMSX2 (41 patch names, about 150 game versions). The game list is in [`kit/crater-kit/files/effect-patch-games.txt`](kit/crater-kit/files/effect-patch-games.txt). |
| **EE cycle skip** (0–3) | The strongest CPU saver. It can cause stutter or the wrong game speed. |
| **Hardware readbacks** | Accurate, Asynchronous, None or Disabled. GPU→CPU copies are expensive on the V3D GPU. |
| **Skipdraw** | Drops the first draw calls of effect passes, for games without a patch. Raise it step by step. |
| **Thread pinning** | Pins the emulator's threads to fixed cores, a small free gain on the Pi 5's 4 identical cores. |
| **Audio reverb / Audio sync** | Skips the PS2 reverb effect (ARMSX2's lightweight audio mode), and turns off time-stretching. Faster, but audio may crackle when the game slows down. |

| Profile | EE cycle rate | EE cycle skip | Readbacks | Audio reverb | Audio sync |
|---|---|---|---|---|---|
| Light | 75% | 0 | Asynchronous | on | TimeStretch |
| Medium | 60% | 1 | Asynchronous | off | TimeStretch |
| Max | 50% | 2 | None | off | Disabled |

Every profile also turns on effect patches and thread pinning, sets blending to Minimum, and switches the CPU governor to `performance` while the game runs. The governor change only happens when no power mode is set for the game or system, and it's restored when the game exits.

Notes:

- **PAL (50 Hz) versions** need about 17% less work than NTSC versions. Use them for borderline games.
- **There are no "lower LOD / draw distance" patches** in the PCSX2/ARMSX2 patch database, so these toolkit options are the closest substitute.
- **Patches match exact versions.** Each patch only applies to the exact version of a game (serial + CRC) it was written for.

## Arcade helper

The kit also includes `diag.sh`, which appears in Ports as *Crater - PS2 and Arcade check*. It writes a report on the PS2, MAME, Naomi, Naomi 2 and Atomiswave setup. If most sampled MAME sets verify against MAME 0.285, it switches MAME's default core to the current MAME. It never overrides an explicit user choice, and it filters secrets out of the report.

## Repo layout

```
kit/crater-kit/            installer, boot hook, diag, uninstall
  files/configgen/armsx2/  Batocera configgen generator (port of v43.1 pcsx2Generator)
  files/emulatorlauncher-armsx2   launcher wrapper (registers the generator, PS2 defaults)
  files/es/                es_systems_ps2.cfg, es_features_armsx2.cfg (33 per-game options)
  payload/manifest.sh      ARMSX2 file names + SHA-256 (binaries are in the release zip)
kit/preshare.sh            boot hook entry (Batocera calls /boot/preshare.sh)
installer/                 Ports installer + how-to templates
tools/build-release.sh     builds dist/Crater-PS2-Kit-<version>.zip from the ARMSX2 nightly files
```

To build a release: `tools/build-release.sh <dir containing the two ARMSX2 nightly files>`.

## Compatibility

- Tested target: Batocera 43.1, Raspberry Pi 5 (bcm2712), kernel 6.12, 4K pages, Mesa 25.3 V3DV.
- Batocera 44 changed the launcher code. The installer validates the configgen integration and refuses to install instead of half-working.

## Credits and licenses

- **ARMSX2:** © the ARMSX2 and PCSX2 teams, GPL-3.0. The release zip redistributes the unmodified nightly build. Source: https://github.com/ARMSX2/ARMSX2 (commit `0076b5c389`).
- **`armsx2Generator.py`:** adapted from Batocera's `pcsx2Generator.py` (configgen). It remains under Batocera's license (see the `COPYING` file in [batocera.linux](https://github.com/batocera-linux/batocera.linux)).
- **Everything else in this repo:** GPL-3.0 (see `LICENSE`).
- No BIOS files, games or other copyrighted content are included or linked.
