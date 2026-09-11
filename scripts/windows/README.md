# Windows host setup (WSL)

Creates an **isolated** `DogPaw` WSL2 + WSLg distro, clones the public SDK into
it, installs a pinned Flutter SDK, and enables JACK→WSLg audio.

This is the supported Windows path. It does **not** modify your existing Ubuntu
(or other) distro unless you intentionally pass the dangerous escape hatch.

## Fresh machine (recommended)

From **Windows PowerShell**:

```powershell
irm https://raw.githubusercontent.com/Dog-Paw-Music/dog-paw-sdk/development/scripts/windows/Setup-DogPawWsl.ps1 | iex
```

Or download/run the script from a checkout:

```powershell
.\scripts\windows\Setup-DogPawWsl.ps1
```

Then in Cursor: **Remote - WSL** → distro `DogPaw` → open `~/dog-paw-sdk`.

## What the default path does

1. Imports Ubuntu 24.04 as a dedicated distro named `DogPaw` under
   `%LOCALAPPDATA%\DogPaw\wsl` (skipped if that distro already exists).
2. Writes `/etc/wsl.conf` **only in DogPaw** (`systemd=true`,
   `appendWindowsPath=false`, `mountFsTab=true`) and ensures a tmpfs
   `/mnt/shared_memory` fstab entry so WSLg can paint GUI windows (avoids
   invisible windows titled `[WARN:COPY MODE]`; see microsoft/wslg#1456).
3. Clones `https://github.com/Dog-Paw-Music/dog-paw-sdk` at `development` into
   `~/dog-paw-sdk`.
4. Installs apt packages, Flutter **3.44.6**, and `scripts/wsl-audio` user units.
5. Optional audio smoke (`paplay` + metronome).
6. Inside-script safety net: remounts `/mnt/shared_memory` if needed and warns when
   Weston is still stuck in COPY MODE (then run `wsl --shutdown` from PowerShell).

## Useful parameters

```powershell
.\Setup-DogPawWsl.ps1 -SdkRef development -FlutterVersion 3.44.6
.\Setup-DogPawWsl.ps1 -DryRun -SkipSmoke
.\Setup-DogPawWsl.ps1 -SkipClone   # SDK already present at ~/dog-paw-sdk
```

## Escape hatch (existing distro)

Only if you knowingly want to mutate a distro you already use:

```powershell
.\Setup-DogPawWsl.ps1 -UseExistingDistro -ConfirmExistingDistro I_UNDERSTAND -ExistingDistroName Ubuntu-24.04
```

Prefer the default `DogPaw` distro instead.

## After setup

Setup links `dogpaw` into `/usr/local/bin` and sets
`DOGPAW_EMULATOR_WLR_BACKENDS=x11` in your shell profile (WSLg-friendly default).
Open a new shell, then:

```bash
dogpaw emulator doctor
dogpaw emulator create --name default
dogpaw emulator run --name default
```

## Re-runs

Re-running the script against an existing `DogPaw` distro is supported. It skips
rootfs download/import, repairs user/home/sudoers/`wsl.conf`, then continues with
clone / apt / Flutter / audio. Bash steps are executed via a temporary `.sh` on
`/mnt/<drive>/...` so multi-line scripts are not mangled by PowerShell quoting.

