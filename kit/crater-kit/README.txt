CRATER KIT 1.0.4 - PS2 + arcade for Batocera 43.1 on Raspberry Pi 5
=====================================================================

WHAT IT DOES
  * Adds a working "PlayStation 2" system using ARMSX2 (ARM64 fork of PCSX2,
    native ARM64 JIT), nightly-20261011, 4K-page Linux build.
      - Emulator "armsx2" (standalone, default) - full Batocera integration:
        controllers, Batocera hotkeys (exit, save/load state, menu), per-game options in ES.
      - Emulator "libretro / armsx2" - same core inside RetroArch (alternative).
  * Checks MAME / Naomi / Naomi 2 / Atomiswave setups against the real MAME 0.285
    on the card and, if your MAME sets are 0.285 sets, switches the MAME default from
    MAME 2003-Plus (0.78 sets) to MAME 0.285. Your own explicit choices are never changed.

WHY STOCK BATOCERA FAILS HERE
  Batocera 43 only builds PCSX2 for x86_64 and disabled Play! on Pi 5. Upstream added
  ARMSX2 in Sept 2026 but only for Qualcomm boards and only on the newer v44 launcher
  code. This kit backports that integration to 43.1 without touching the system image.

HOW IT INSTALLS
  /boot/preshare.sh (run by Batocera at every boot) starts crater-kit/boot-hook.sh,
  which waits for /userdata and runs install.sh once per kit version (~30-60 s on the
  first boot; ES restarts by itself when done). Everything goes to:
      /userdata/system/armsx2/                       emulator + launcher
      /userdata/system/configs/emulationstation/     es_systems_ps2.cfg, es_features_armsx2.cfg
      /userdata/roms/ports/Crater - PS2 and Arcade check.sh   (re-run the checks from ES)

YOU STILL NEED TO ADD (legally your own dumps)
  * PS2 BIOS  -> /userdata/bios/ps2/      (e.g. SCPH-70012.bin, 4 MB)
  * PS2 games -> /userdata/roms/ps2/      (.chd recommended; .iso .cso .zso also fine)
  * Naomi BIOS -> /userdata/bios/dc/naomi.zip, naomi2.zip, awbios.zip (MAME 0.285 sets)
  * Naomi GD-ROM games: ikaruga.zip + ikaruga/ikaruga.chd  (CHD in a sub-folder!)

REPORTS
  After first boot, look in this folder on Windows:  crater-kit\reports\report.txt
  (and install-log.txt). Bring the card back to the PC to share them.

PI 5 REALITY CHECK
  ARMSX2 on a Pi 5 runs lighter PS2 games well at native res; heavy games
  (MGS2/3, GoW, Jak) will be below full speed. Keep it at 1x resolution, Vulkan,
  MTVU on (kit defaults). OpenGL is NOT usable (Pi 5 GPU = GL 3.1).
  Active cooling + no throttling matters more than any setting.

REPAIR / REINSTALL FROM THE MENU (no SSH needed)
  Copy "Crater - Install or Repair PS2.sh" into \\BATOCERA\share\roms\ports and run it from
  Ports. It contains the whole kit, checks itself, reinstalls cleanly and restarts the menu.

PERFORMANCE TOOLKIT (per game: select game -> Advanced options -> PERFORMANCE TOOLKIT)
  PERFORMANCE PROFILE     Off / Light / Medium / Max - fills every option below you have not set
  EFFECT REMOVAL PATCHES  motion blur / bloom / DoF / fog / noise off, about 150 game versions
                          (list: \\BATOCERA\share\roms\ps2\_effect-patch-games.txt)
  EE CYCLE SKIP           0-3, strongest CPU saver (may cause stutter / wrong game speed)
  HARDWARE READBACKS      Accurate / Asynchronous / None / Disabled
  SKIPDRAW                drop effect draw calls in games without a patch (raise step by step)
  THREAD PINNING          pin emulator threads to fixed cores (small free gain)
  AUDIO REVERB / SYNC     skip PS2 reverb; disable time-stretching (faster, may crackle)
  Profiles also switch the CPU governor to performance while the game runs
  (only when no power mode is set for the game/system; restored when the game exits).
  PAL versions run at 50 Hz = ~17% less work than NTSC: prefer them for borderline games.
  There are no "lower LOD / draw distance" patches in the database; this is the closest you get.

COMMANDS (SSH, root / linux)
  bash /boot/crater-kit/install.sh               re-install / repair
  bash /boot/crater-kit/install.sh --uninstall   remove (keeps saves/BIOS/ROMs, disables boot hook)
  bash /boot/crater-kit/diag.sh --apply-arcade-fixes   re-run checks
  Disable the boot hook: delete /boot/preshare.sh (from Windows: H:\preshare.sh).

CHANGES 1.0.1
  * Refuses to install when /userdata is Batocera's 256 MB RAM fallback (SHARE not mounted).
  * Checks for 600 MB free on /userdata first; unpacks in RAM (/tmp), cleans up on any failure.
  * A failed version is not retried every boot (logs/crater-kit.failed); run install.sh by hand.
  * Restarts EmulationStation through its own API instead of kill -9.

CHANGES 1.0.2
  * Single-file Ports installer/repair ("Crater - Install or Repair PS2.sh"), self-verifying (SHA-256).
  * install.sh can run from any unpacked copy (CRATER_KIT); reports still go to /boot/crater-kit/reports.
  * Uninstall also disables the boot hook so it does not reinstall itself at the next boot.

CHANGES 1.0.3
  * Performance toolkit: profiles, effect-removal patches (41 patch names / about 150 game versions),
    EE cycle skip, hardware readback mode, skipdraw - all per game from the EmulationStation menu.

CHANGES 1.0.4
  * Toolkit: thread pinning, audio reverb off (ARMSX2 lightweight mode), audio sync mode,
    and CPU governor 'performance' during play for every profile (unless a power mode is set).
