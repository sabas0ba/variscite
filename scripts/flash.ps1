# Load the Tang Primer 20K bitstream over JTAG.
#
# Everything up to sim/fpga/tang/soc.fs is built in the container
# (.\scripts\dev.ps1 make fpga-tang). Programming is the one step that has to
# run on the host, because the container cannot reach the USB device.
#
#   .\scripts\flash.ps1              # load into SRAM, gone at power off
#   .\scripts\flash.ps1 -Flash       # write the board's flash instead
#   .\scripts\flash.ps1 -Detect      # JTAG IDCODE scan only, writes nothing
#
# openFPGALoader comes from a Windows OSS CAD Suite. Point -Suite (or
# $env:OSS_CAD_SUITE_WIN) at one; the default is tools\oss-cad-suite under this
# repository. The board needs the WinUSB driver on its FTDI interface 0, which
# Zadig assigns.
#Requires -Version 5.1
param(
    [switch]$Flash,
    [switch]$Detect,
    [string]$Suite,
    [string]$Bitstream
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Suite) {
    if ($env:OSS_CAD_SUITE_WIN) { $Suite = $env:OSS_CAD_SUITE_WIN }
    else { $Suite = Join-Path $RepoRoot 'tools\oss-cad-suite' }
}
$loader = Join-Path $Suite 'bin\openFPGALoader.exe'
if (-not (Test-Path $loader)) {
    throw @"
openFPGALoader not found at $loader

Install a Windows OSS CAD Suite and point at it, either with -Suite <path> or
by setting OSS_CAD_SUITE_WIN.
"@
}
$env:PATH = (Join-Path $Suite 'bin') + ';' + (Join-Path $Suite 'lib') + ';' + $env:PATH

if ($Detect) {
    openFPGALoader --detect -b tangprimer20k
    if ($LASTEXITCODE -ne 0) { throw "openFPGALoader failed" }
    exit 0
}

if (-not $Bitstream) { $Bitstream = Join-Path $RepoRoot 'sim\fpga\tang\soc.fs' }
if (-not (Test-Path $Bitstream)) {
    throw "$Bitstream not found. Run: .\scripts\dev.ps1 make fpga-tang"
}

if ($Flash) {
    openFPGALoader -b tangprimer20k -f $Bitstream
} else {
    openFPGALoader -b tangprimer20k $Bitstream
}
if ($LASTEXITCODE -ne 0) { throw "openFPGALoader failed" }
