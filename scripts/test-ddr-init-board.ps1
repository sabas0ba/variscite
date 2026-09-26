# Run the initialization-only DDR probe and restore the validated LCD sample.
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$Suite,
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [ValidateSet('DdrInit', 'DdrRead', 'DdrMpr', 'DdrMprDelay', 'DdrMprAlign', 'DdrArray', 'DdrArrayScan', 'DdrArraySame', 'DdrArrayTrace', 'DdrArrayMatch', 'DdrArrayFlags', 'DdrArrayTimeline', 'DdrArraySimpleTimeline', 'DdrArrayEarlyTimeline', 'DdrArrayFullTimeline', 'DdrArrayExpectedTimeline')]
    [string]$Mode = 'DdrInit'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lcd = Join-Path $root 'sim/fpga/lcd_soc/soc.fs'
$knownLcdSha256 = '40bac365ce8f971d240ac5aa6a2e4c69c1fff5579c6dbbb2afe4f97662b9eb0a'
if (-not (Test-Path $lcd)) { throw "Missing LCD restore image: $lcd" }
if ((Get-FileHash -Algorithm SHA256 $lcd).Hash.ToLowerInvariant() -ne $knownLcdSha256) {
    throw 'The LCD restore image differs from the validated hardware image.'
}
try {
    $probeSeconds = if ($Mode -in @('DdrMprDelay', 'DdrMprAlign', 'DdrArray', 'DdrArrayScan', 'DdrArraySame', 'DdrArrayTrace', 'DdrArrayMatch', 'DdrArrayFlags', 'DdrArrayTimeline', 'DdrArraySimpleTimeline', 'DdrArrayEarlyTimeline', 'DdrArrayFullTimeline', 'DdrArrayExpectedTimeline')) { 6 } else { 4 }
    & (Join-Path $PSScriptRoot 'test-board.ps1') -Suite $Suite -Port $Port -Mode $Mode -Seconds $probeSeconds
} finally {
    & (Join-Path $PSScriptRoot 'test-board.ps1') -Suite $Suite -Port $Port -Mode LcdSoc -Seconds 5
}
