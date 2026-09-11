<#
.SYNOPSIS
  Create or refresh an isolated Dog Paw WSL2 + WSLg developer environment.

.DESCRIPTION
  Default path (safe for machines that already have WSL):
    1. Create a dedicated distro named DogPaw (Ubuntu 24.04 rootfs import).
    2. Configure only that distro's /etc/wsl.conf (systemd, interop, automount)
       and /etc/fstab tmpfs for /mnt/shared_memory (WSLg invisible-window fix).
    3. Clone dog-paw-sdk into the distro.
    4. Install apt packages, a pinned Flutter SDK, and JACK→pacat audio units.
    5. Print Cursor Remote-WSL next steps.

  Does not modify other WSL distros unless you pass the dangerous escape hatch:
    -UseExistingDistro -ConfirmExistingDistro I_UNDERSTAND

  Fresh-machine one-liner (after the script is published to the public SDK repo):
    irm https://raw.githubusercontent.com/Dog-Paw-Music/dog-paw-sdk/development/scripts/windows/Setup-DogPawWsl.ps1 | iex

  Re-runs against an existing DogPaw distro skip rootfs download/import, repair
  user/home/sudoers/wsl.conf, terminate so systemd and default user apply, then
  continue with clone / apt / Flutter.

.PARAMETER DistroName
  Name of the dedicated Dog Paw distro. Default: DogPaw.

.PARAMETER InstallRoot
  Windows directory that stores the imported distro filesystem.
  Default: %LOCALAPPDATA%\DogPaw\wsl

.PARAMETER SdkRepo
  Git URL cloned into the distro. Default: https://github.com/Dog-Paw-Music/dog-paw-sdk.git

.PARAMETER SdkRef
  Git ref to checkout after clone. Default: development (until this lands on main).

.PARAMETER SdkLinuxPath
  Absolute Linux path for the SDK clone inside the distro. Default: ~/dog-paw-sdk
  (expanded for the default Linux user).

.PARAMETER FlutterVersion
  Pinned Flutter stable version installed into ~/flutter. Default: 3.44.6

.PARAMETER LinuxUsername
  Default Linux username created inside a new DogPaw distro. Default: sanitized
  Windows username, or "dogpaw" if sanitization yields nothing usable.

.PARAMETER UbuntuRootfsUrl
  Ubuntu 24.04 WSL rootfs tarball used by wsl --import.

.PARAMETER UseExistingDistro
  Dangerous escape hatch: configure an already-existing distro in place instead
  of creating DogPaw. Requires -ConfirmExistingDistro I_UNDERSTAND.

.PARAMETER ConfirmExistingDistro
  Must be exactly I_UNDERSTAND when -UseExistingDistro is set.

.PARAMETER ExistingDistroName
  Distro name used with -UseExistingDistro. Default: the current default WSL distro.

.PARAMETER DryRun
  Print actions without changing the system where practical.

.PARAMETER SkipClone
  Skip git clone/fetch (SDK must already exist at SdkLinuxPath).

.PARAMETER SkipApt
  Skip apt package installation.

.PARAMETER SkipFlutter
  Skip Flutter download/install.

.PARAMETER SkipAudio
  Skip JACK→pacat user unit installation.

.PARAMETER SkipSmoke
  Skip paplay / metronome smoke tests.
#>

[CmdletBinding()]
param(
    [string] $DistroName = "DogPaw",
    [string] $InstallRoot = "",
    [string] $SdkRepo = "https://github.com/Dog-Paw-Music/dog-paw-sdk.git",
    [string] $SdkRef = "development",
    [string] $SdkLinuxPath = "~/dog-paw-sdk",
    [string] $FlutterVersion = "3.44.6",
    [string] $LinuxUsername = "",
    [string] $UbuntuRootfsUrl = "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz",
    [switch] $UseExistingDistro,
    [string] $ConfirmExistingDistro = "",
    [string] $ExistingDistroName = "",
    [switch] $DryRun,
    [switch] $SkipClone,
    [switch] $SkipApt,
    [switch] $SkipFlutter,
    [switch] $SkipAudio,
    [switch] $SkipSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SanitizedLinuxUsername {
    <#
    .SYNOPSIS
      Turn a Windows username into a safe Linux login name.

    .PARAMETER Candidate
      Raw username string (typically $env:USERNAME). May contain spaces or symbols.

    .OUTPUTS
      [string] Lowercase [A-Za-z0-9_-] name, max 32 chars. Falls back to "dogpaw".
      Digits-only names get a leading "u".

    .NOTES
      Architecture: shared by dedicated-distro bootstrap and refresh paths.
    #>
    param([string] $Candidate)
    $clean = ($Candidate -replace '[^A-Za-z0-9_-]', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return "dogpaw"
    }
    if ($clean -match '^[0-9]') {
        $clean = "u$clean"
    }
    if ($clean.Length -gt 32) {
        $clean = $clean.Substring(0, 32)
    }
    return $clean
}

function Get-WslDistroNames {
    <#
    .SYNOPSIS
      List installed WSL distro names (UTF-16 nulls stripped).

    .OUTPUTS
      [string[]] Distro names, or empty array if wsl.exe fails.
    #>
    $raw = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    $names = @()
    foreach ($line in $raw) {
        $name = ($line -replace '\u0000', '').Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $names += $name
        }
    }
    return $names
}

function Test-WslDistroExists {
    <#
    .SYNOPSIS
      Return whether a named WSL distro is installed.

    .PARAMETER Name
      Exact distro name (e.g. DogPaw).

    .OUTPUTS
      [bool] True if Name appears in Get-WslDistroNames.
    #>
    param([string] $Name)
    return (Get-WslDistroNames) -contains $Name
}

function ConvertTo-WslMountPath {
    <#
    .SYNOPSIS
      Map a Windows absolute path to the WSL /mnt/<drive>/... form.

    .PARAMETER WindowsPath
      Absolute Windows path (e.g. C:\Users\...\Temp\script.sh).

    .OUTPUTS
      [string] Linux path such as /mnt/c/Users/.../script.sh

    .NOTES
      Used so Invoke-Wsl can hand bash a real file instead of a fragile -c string.
      Requires the drive to be mounted in the target distro (normal for WSL2).
    #>
    param([Parameter(Mandatory = $true)][string] $WindowsPath)
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($full -notmatch '^[A-Za-z]:') {
        throw "ConvertTo-WslMountPath expects a drive-letter path, got: $WindowsPath"
    }
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    $rest = $full.Substring(2) -replace '\\', '/'
    if (-not $rest.StartsWith('/')) {
        $rest = '/' + $rest
    }
    return "/mnt/$drive$rest"
}

function Stop-WslDistro {
    <#
    .SYNOPSIS
      Terminate a WSL distro and wait briefly so the next start picks up wsl.conf.

    .PARAMETER Distro
      Distro name to terminate.

    .NOTES
      Needed after writing systemd=true / default user so the next Invoke-Wsl
      session is not a stale boot. No-op when -DryRun is set.
    #>
    param([Parameter(Mandatory = $true)][string] $Distro)
    Write-Host "Terminating '$Distro' so wsl.conf / default user apply..."
    if ($DryRun) {
        Write-Host "dry-run: skipped wsl --terminate" -ForegroundColor DarkYellow
        return
    }
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep -Seconds 2
}

function Invoke-Wsl {
    <#
    .SYNOPSIS
      Run a bash script inside a WSL distro without PowerShell mangling quotes.

    .PARAMETER Distro
      Target distro name (e.g. DogPaw).

    .PARAMETER User
      Linux user for -u. Empty string omits -u (distro default user).

    .PARAMETER BashCommand
      Full bash script body (may contain newlines, quotes, heredocs).

    .PARAMETER PassThru
      If set, return stdout as a single trimmed string (NUL bytes stripped).

    .OUTPUTS
      None by default. With -PassThru: [string] captured stdout.
      Throws if wsl.exe exits non-zero.

    .NOTES
      Architecture: central host→guest execution helper for this setup script.
      Writes BashCommand to a UTF-8 (no BOM) temp .sh with Unix newlines, runs
      `bash <wsl-mount-path>`, then deletes the temp file. Avoids `bash -lc`
      string passing, which breaks on embedded double quotes under PowerShell.
      Honors script-level -DryRun (prints and returns without executing).
      Without -PassThru, guest stdout streams to the console so apt/debconf
      output and any unexpected prompt are visible instead of a silent hang.
    #>
    param(
        [string] $Distro,
        [string] $User = "",
        [Parameter(Mandatory = $true)][string] $BashCommand,
        [switch] $PassThru
    )
    $argList = @("-d", $Distro)
    if (-not [string]::IsNullOrWhiteSpace($User)) {
        $argList += @("-u", $User)
    }

    $preview = ($BashCommand -split "`r?`n")[0]
    if ($preview.Length -gt 80) {
        $preview = $preview.Substring(0, 77) + "..."
    }
    Write-Host (">> wsl -d $Distro" + $(if ($User) { " -u $User" } else { "" }) + " -- bash <temp.sh>  ($preview)") -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host "dry-run: skipped wsl execution" -ForegroundColor DarkYellow
        if ($PassThru) {
            return ""
        }
        return
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("dogpaw-wsl-" + [guid]::NewGuid().ToString("N") + ".sh")
    $unixBody = $BashCommand -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $unixBody.EndsWith("`n")) {
        $unixBody += "`n"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    # Guest output is UTF-8, but PowerShell decodes piped/captured native output
    # with [Console]::OutputEncoding (OEM code page by default on 5.1). Switch for
    # the duration of the call and restore afterwards. Best effort: hosts without
    # a real console (e.g. ISE) throw on the setter.
    $savedOutputEncoding = $null
    try {
        $savedOutputEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = $utf8NoBom
    }
    catch {
        $savedOutputEncoding = $null
    }
    try {
        [System.IO.File]::WriteAllText($tempFile, $unixBody, $utf8NoBom)
        $linuxTemp = ConvertTo-WslMountPath -WindowsPath $tempFile
        $argList += @("--", "bash", $linuxTemp)
        if ($PassThru) {
            $output = & wsl.exe @argList
        }
        else {
            # Stream guest stdout live. Capturing it for every call hid all
            # apt/debconf output, so an interactive prompt looked like a hang.
            & wsl.exe @argList | Out-Host
        }
        if ($LASTEXITCODE -ne 0) {
            throw "WSL command failed with exit code $LASTEXITCODE"
        }
        if ($PassThru) {
            return ((($output | Out-String) -replace '\u0000', '').Trim())
        }
    }
    finally {
        if ($null -ne $savedOutputEncoding) {
            try { [Console]::OutputEncoding = $savedOutputEncoding } catch { }
        }
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ExpandedLinuxPath {
    <#
    .SYNOPSIS
      Expand a Linux path spec (e.g. ~/dog-paw-sdk) inside a distro as a given user.

    .PARAMETER Distro
      Target distro name.

    .PARAMETER User
      Linux user whose home is used for ~ expansion.

    .PARAMETER PathSpec
      Path string; typically starts with ~/.

    .OUTPUTS
      [string] Absolute Linux path with NUL bytes stripped.

    .NOTES
      Under -DryRun with a ~/ path, expands locally as /home/<User>/... without WSL.
    #>
    param(
        [string] $Distro,
        [string] $User,
        [string] $PathSpec
    )
    if ($DryRun -and $PathSpec.StartsWith("~/")) {
        return "/home/$User/" + $PathSpec.Substring(2)
    }
    $expanded = & wsl.exe -d $Distro -u $User -- bash -lc "printf '%s\n' $PathSpec"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($expanded)) {
        throw "Could not expand Linux path '$PathSpec' in distro '$Distro'"
    }
    return (($expanded -replace '\u0000', '').Trim())
}

function Resolve-DedicatedLinuxUsername {
    <#
    .SYNOPSIS
      Pick the Linux username for an existing dedicated DogPaw distro.

    .PARAMETER Distro
      Dedicated distro name.

    .PARAMETER PreferredUsername
      Sanitized Windows-derived name we want to keep using when it already exists.

    .OUTPUTS
      [string] Username to use for later steps.

    .NOTES
      Prefer PreferredUsername when that account exists. Otherwise use the distro
      default login (`wsl -d Distro` without -u) only if it is non-root.
      Otherwise keep PreferredUsername so the ensure step can create it.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Distro,
        [Parameter(Mandatory = $true)][string] $PreferredUsername
    )
    if ($DryRun) {
        return $PreferredUsername
    }

    $probeScript = @"
set -euo pipefail
if id -u '$PreferredUsername' >/dev/null 2>&1; then
  printf 'FOUND\n'
else
  printf 'MISSING\n'
fi
"@
    $text = Invoke-Wsl -Distro $Distro -User "root" -BashCommand $probeScript -PassThru
    if ($text -match '(?m)^FOUND$') {
        Write-Host "Using preferred Linux user (exists): $PreferredUsername"
        return $PreferredUsername
    }

    # Distro default user (honors /etc/wsl.conf [user] default=...), not root -u.
    $defaultUser = (((& wsl.exe -d $Distro -- bash -lc "id -un") -replace '\u0000', '').Trim())
    if (-not [string]::IsNullOrWhiteSpace($defaultUser) -and $defaultUser -ne "root") {
        Write-Host "Preferred user missing; using distro default user: $defaultUser"
        return $defaultUser
    }
    Write-Host "Preferred user missing and default is root/empty; will create: $PreferredUsername"
    return $PreferredUsername
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. On Windows 11 run: wsl --install --no-distribution   then reboot if prompted and re-run this script."
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "DogPaw\wsl"
}
if ([string]::IsNullOrWhiteSpace($LinuxUsername)) {
    $LinuxUsername = Get-SanitizedLinuxUsername -Candidate $env:USERNAME
}

$targetDistro = $DistroName
$creatingDedicated = -not $UseExistingDistro

if ($UseExistingDistro) {
    if ($ConfirmExistingDistro -ne "I_UNDERSTAND") {
        throw @"
-UseExistingDistro will mutate an existing WSL distro (wsl.conf, apt packages,
PipeWire/JACK user units). Re-run with:

  -UseExistingDistro -ConfirmExistingDistro I_UNDERSTAND [-ExistingDistroName <name>]

Prefer the default path, which creates an isolated '$DistroName' distro instead.
"@
    }
    if ([string]::IsNullOrWhiteSpace($ExistingDistroName)) {
        $defaultName = (& wsl.exe -l -q 2>$null | Select-Object -First 1)
        $ExistingDistroName = (($defaultName -replace '\u0000', '').Trim())
    }
    if ([string]::IsNullOrWhiteSpace($ExistingDistroName)) {
        throw "No WSL distro available for -UseExistingDistro. Install WSL first or omit the escape hatch."
    }
    $targetDistro = $ExistingDistroName
    $creatingDedicated = $false
    Write-Host "WARNING: configuring existing distro '$targetDistro' in place." -ForegroundColor Yellow
}

Write-Host "== Dog Paw Windows → WSL setup ==" -ForegroundColor Cyan
Write-Host "Target distro: $targetDistro"
Write-Host "Install root: $InstallRoot"
Write-Host "SDK repo: $SdkRepo @ $SdkRef"
Write-Host "Flutter: $FlutterVersion"
Write-Host "Linux user: $LinuxUsername"
Write-Host ""
Write-Host "Installed WSL distros:" -ForegroundColor Cyan
& wsl.exe -l -v

& wsl.exe --status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "WSL does not look fully installed. Attempting: wsl --install --no-distribution" -ForegroundColor Yellow
    if (-not $DryRun) {
        & wsl.exe --install --no-distribution
        throw "WSL install was started. Reboot if Windows asks, then re-run this script."
    }
}

# WSLg shared-memory workaround for invisible windows ([WARN:COPY MODE]).
# See microsoft/wslg#1456 — missing /mnt/shared_memory breaks VAIL/gfxredir.
$wslgSharedMemoryBash = @'
mkdir -p /mnt/shared_memory
touch /etc/fstab
if ! grep -qE '^[^#]*[[:space:]]+/mnt/shared_memory[[:space:]]' /etc/fstab; then
  printf '\n# Dog Paw WSLg shared memory (microsoft/wslg#1456)\ntmpfs /mnt/shared_memory tmpfs defaults 0 0\n' >>/etc/fstab
fi
'@

if ($creatingDedicated -and -not (Test-WslDistroExists -Name $targetDistro)) {
    Write-Host ""
    Write-Host "== Creating dedicated distro '$targetDistro' ==" -ForegroundColor Cyan
    $distroDir = Join-Path $InstallRoot $targetDistro
    $tarPath = Join-Path $InstallRoot "ubuntu-24.04-wsl.rootfs.tar.gz"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
        New-Item -ItemType Directory -Force -Path $distroDir | Out-Null
        if (-not (Test-Path $tarPath)) {
            Write-Host "Downloading Ubuntu 24.04 WSL rootfs..."
            Write-Host $UbuntuRootfsUrl -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $UbuntuRootfsUrl -OutFile $tarPath
        } else {
            Write-Host "Using cached rootfs: $tarPath"
        }
        & wsl.exe --import $targetDistro $distroDir $tarPath --version 2
        if ($LASTEXITCODE -ne 0) {
            throw "wsl --import failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "dry-run: would download rootfs and wsl --import $targetDistro $distroDir"
    }

    $bootstrapUser = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y sudo passwd adduser ca-certificates curl git
if ! id -u '$LinuxUsername' >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' '$LinuxUsername'
fi
usermod -aG sudo '$LinuxUsername'
echo '$LinuxUsername ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-dogpaw-$LinuxUsername
chmod 440 /etc/sudoers.d/90-dogpaw-$LinuxUsername
mkdir -p /home/$LinuxUsername
chown -R '$LinuxUsername':'$LinuxUsername' /home/$LinuxUsername
cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=$LinuxUsername

[interop]
appendWindowsPath=false

[automount]
mountFsTab=true
EOF
$wslgSharedMemoryBash
"@
    Invoke-Wsl -Distro $targetDistro -User "root" -BashCommand $bootstrapUser
    Stop-WslDistro -Distro $targetDistro
} elseif ($creatingDedicated) {
    Write-Host "Dedicated distro '$targetDistro' already exists; refreshing configuration only."
    $LinuxUsername = Resolve-DedicatedLinuxUsername -Distro $targetDistro -PreferredUsername $LinuxUsername
}

if (-not $UseExistingDistro) {
    Write-Host ""
    Write-Host "== Ensure user, home ownership, sudoers, wsl.conf ==" -ForegroundColor Cyan
    # Idempotent repair for fresh import and partial prior runs (e.g. root-owned home).
    $ensureUserAndConf = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! id -u '$LinuxUsername' >/dev/null 2>&1; then
  echo 'error: creating missing Linux user $LinuxUsername in distro $targetDistro' >&2
  apt-get update -y
  apt-get install -y sudo passwd adduser ca-certificates curl git
  adduser --disabled-password --gecos '' '$LinuxUsername'
fi
usermod -aG sudo '$LinuxUsername' || true
echo '$LinuxUsername ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-dogpaw-$LinuxUsername
chmod 440 /etc/sudoers.d/90-dogpaw-$LinuxUsername
mkdir -p /home/$LinuxUsername
chown -R '$LinuxUsername':'$LinuxUsername' /home/$LinuxUsername
cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=$LinuxUsername

[interop]
appendWindowsPath=false

[automount]
mountFsTab=true
EOF
$wslgSharedMemoryBash
"@
    Invoke-Wsl -Distro $targetDistro -User "root" -BashCommand $ensureUserAndConf
    Stop-WslDistro -Distro $targetDistro
} else {
    $applyConf = @"
set -euo pipefail
UPDATED=0
if [ ! -f /etc/wsl.conf ] || ! grep -qE "^systemd=true" /etc/wsl.conf || ! grep -qE "^appendWindowsPath=false" /etc/wsl.conf || ! grep -qE "^mountFsTab=true" /etc/wsl.conf; then
  cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[interop]
appendWindowsPath=false

[automount]
mountFsTab=true
EOF
  UPDATED=1
fi
$wslgSharedMemoryBash
echo UPDATED=`$UPDATED
cat /etc/wsl.conf
"@
    Invoke-Wsl -Distro $targetDistro -User "root" -BashCommand $applyConf
    Stop-WslDistro -Distro $targetDistro
}

if ($UseExistingDistro) {
    $LinuxUsername = (((& wsl.exe -d $targetDistro -- bash -lc "id -un") -replace '\u0000', '').Trim())
}

$sdkRoot = Resolve-ExpandedLinuxPath -Distro $targetDistro -User $LinuxUsername -PathSpec $SdkLinuxPath
Write-Host ""
Write-Host "SDK Linux path: $sdkRoot"

if (-not $SkipClone) {
    Write-Host ""
    Write-Host "== Clone / update SDK ==" -ForegroundColor Cyan
    # Escape $ for bash so PowerShell does not expand dirname.
    $cloneCmd = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v git >/dev/null 2>&1; then
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
fi
if [ ! -d '$sdkRoot/.git' ]; then
  parent=`$(dirname '$sdkRoot')
  mkdir -p "`$parent"
  git clone --branch '$SdkRef' --single-branch '$SdkRepo' '$sdkRoot'
else
  git -C '$sdkRoot' fetch --tags origin
  git -C '$sdkRoot' checkout '$SdkRef'
  git -C '$sdkRoot' pull --ff-only origin '$SdkRef' || true
fi
test -f '$sdkRoot/scripts/windows/setup_dogpaw_wsl_inside.sh'
"@
    Invoke-Wsl -Distro $targetDistro -User $LinuxUsername -BashCommand $cloneCmd
} else {
    Write-Host "== clone skipped ==" -ForegroundColor DarkYellow
    Invoke-Wsl -Distro $targetDistro -User $LinuxUsername -BashCommand "test -f '$sdkRoot/scripts/windows/setup_dogpaw_wsl_inside.sh'"
}

$inside = "$sdkRoot/scripts/windows/setup_dogpaw_wsl_inside.sh"
$insideArgs = "--sdk-root '$sdkRoot' --flutter-version '$FlutterVersion'"
if ($DryRun) { $insideArgs += " --dry-run" }
if ($SkipApt) { $insideArgs += " --skip-apt" }
if ($SkipFlutter) { $insideArgs += " --skip-flutter" }
if ($SkipAudio) { $insideArgs += " --skip-audio" }
if ($SkipSmoke) { $insideArgs += " --skip-smoke" }

Write-Host ""
Write-Host "== apt (as root) ==" -ForegroundColor Cyan
if ($SkipApt) {
    Write-Host "apt skipped"
} else {
    $aptOnly = "$insideArgs --skip-flutter --skip-audio --skip-smoke"
    Invoke-Wsl -Distro $targetDistro -User "root" -BashCommand "bash '$inside' $aptOnly"
}

Write-Host ""
Write-Host "== Flutter / audio / smoke (as $LinuxUsername) ==" -ForegroundColor Cyan
$userArgs = "$insideArgs --skip-apt"
Invoke-Wsl -Distro $targetDistro -User $LinuxUsername -BashCommand "bash '$inside' $userArgs"

Write-Host ""
Write-Host "Setup finished." -ForegroundColor Green
Write-Host "Open Cursor → Remote-WSL → distro '$targetDistro' → folder $sdkRoot"
Write-Host "Then (new shell so PATH / DOGPAW_EMULATOR_WLR_BACKENDS apply):"
Write-Host "  dogpaw emulator doctor"
Write-Host "  dogpaw emulator create --name default"
Write-Host "  dogpaw emulator run --name default"
