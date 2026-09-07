# Install the Windows OSS CAD Suite under tools\, for programming the board.
#
# Synthesis, place and route and every check run in the container
# (container/Containerfile). The only step that cannot is programming, because
# the container has no path to the USB device - so this installs the same
# pinned release of the suite for the host and nothing else uses it.
#
#   .\scripts\setup-toolchain.ps1
#
# The version and hash must stay in step with OSSCAD_VER in
# scripts/setup_toolchain.sh, which pins the Linux build of the same release.
# The SHA-256 below is the asset digest reported by the GitHub Releases API;
# the Linux archive's digest from the same response matches the one that script
# already carries, which is what makes this source trustworthy for both.
# Upstream publishes no signature, and the digest comes from the same origin as
# the download, so this pin detects tampering in transit and any change made
# after pinning - no more.
#
# After installing, Windows needs the WinUSB driver bound to the board's JTAG
# interface (FTDI interface 0) before openFPGALoader can reach it. Zadig
# (https://zadig.akeo.ie/) does that.
#Requires -Version 5.1
param(
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '2026-08-10'
$File    = 'oss-cad-suite-windows-x64-20260810.tgz'
$Sha256  = '818a5bc96c0e0719e2e21da0d2cf6fbbeed959689657202b5b942cf26af4e502'
$Url     = "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$Version/$File"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Tools    = Join-Path $RepoRoot 'tools'
$Suite    = Join-Path $Tools 'oss-cad-suite'
$Dl       = Join-Path $Tools 'dl'

if ((Test-Path (Join-Path $Suite 'bin\openFPGALoader.exe')) -and -not $Force) {
    Write-Host "already installed: $Suite"
    exit 0
}

New-Item -ItemType Directory -Force $Dl | Out-Null
$archive = Join-Path $Dl $File

# A previous download is reused only if it still hashes correctly.
$have = $false
if (Test-Path $archive) {
    $have = (Get-FileHash -Algorithm SHA256 $archive).Hash -eq $Sha256.ToUpper()
    if (-not $have) { Remove-Item $archive }
}
if (-not $have) {
    Write-Host "fetching $File (about 590 MB)"
    # Invoke-WebRequest's progress bar makes large downloads several times
    # slower in PowerShell 5.1.
    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing
    } finally {
        $ProgressPreference = $prev
    }
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash
    if ($actual -ne $Sha256.ToUpper()) {
        Remove-Item $archive
        throw "SHA-256 mismatch: expected $Sha256, got $actual"
    }
}

Write-Host "extracting to $Tools"
if (Test-Path $Suite) { Remove-Item -Recurse -Force $Suite }
# bsdtar ships with Windows 10 1803 and later and reads .tgz directly.
tar -xzf $archive -C $Tools
if ($LASTEXITCODE -ne 0) { throw "tar failed" }

$loader = Join-Path $Suite 'bin\openFPGALoader.exe'
if (-not (Test-Path $loader)) { throw "openFPGALoader.exe missing after extraction" }
Write-Host "installed: $loader"
