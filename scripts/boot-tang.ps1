# SRAM-load the Linux platform, upload a packaged Image/DTB and capture UART.
# Hardware transport only: build the ROM, bitstream and package in the container.
#Requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Suite,
    [Parameter(Mandatory=$true)][string]$Port,
    [Parameter(Mandatory=$true)][string]$Package,
    [ValidateRange(1,3600)][int]$CaptureSeconds=120,
    [string]$ExpectedText='',
    [string]$ConsoleCommand='',
    [string]$CommandExpectedText='',
    [ValidateSet('Uart','Lcd','Standalone')][string]$Platform='Uart',
    [switch]$KeepRunning
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($ConsoleCommand -and (-not $ExpectedText -or -not $CommandExpectedText)) {
    throw 'ConsoleCommand requires ExpectedText (ready marker) and CommandExpectedText'
}
if ($CommandExpectedText -and -not $ConsoleCommand) { throw 'CommandExpectedText requires ConsoleCommand' }
if ($ConsoleCommand -match '[\r\n\x00-\x1f\x7f-\uffff]') { throw 'ConsoleCommand must be one printable ASCII line' }
$root=Split-Path -Parent $PSScriptRoot
$bitstream=Join-Path $root 'sim/fpga/linux_boot/impl/pnr/linux_boot.fs'
if ($Platform -eq 'Lcd') { $bitstream=Join-Path $root 'sim/fpga/linux_lcd/impl/pnr/linux_lcd.fs' }
if ($Platform -eq 'Standalone') { $bitstream=Join-Path $root 'sim/fpga/linux_standalone/impl/pnr/linux_standalone.fs' }
$lcd=Join-Path $root 'sim/fpga/lcd_soc/soc.fs'
$knownLcd='40bac365ce8f971d240ac5aa6a2e4c69c1fff5579c6dbbb2afe4f97662b9eb0a'
if (-not $KeepRunning -and (Get-FileHash $lcd -Algorithm SHA256).Hash.ToLowerInvariant() -ne $knownLcd) {
    throw 'LCD restore image does not match the validated image'
}
$wire=[System.IO.File]::ReadAllBytes((Resolve-Path $Package))
# Validate the complete container before touching the board.
$offset=0
while ($offset -lt $wire.Length) {
    if ($wire.Length-$offset -lt 20 -or [BitConverter]::ToUInt32($wire,$offset) -ne 0x314c4256) {
        throw 'Invalid boot package header'
    }
    $length=[BitConverter]::ToUInt32($wire,$offset+12)
    $command=[BitConverter]::ToUInt32($wire,$offset+4)
    if ($length -lt 1 -or $length -gt 256 -or $wire.Length-$offset -lt 20+$length -or $command -notin @(87,66)) {
        throw 'Invalid boot package record'
    }
    if (($command -eq 66) -ne ($offset+20+$length -eq $wire.Length)) { throw 'Boot manifest must be last' }
    $offset+=20+$length
}
if ($offset -eq 0) { throw 'Empty boot package' }
$logDir=Join-Path $root 'logs/board'
New-Item -ItemType Directory -Force $logDir | Out-Null
$prefix=Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-LinuxBoot')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,'None',8,'One'
$serial.ReadTimeout=1000
$serial.WriteTimeout=10000
$capture=[System.IO.File]::Open("$prefix-uart.bin",[System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
$failure=$null
$uploaded=$false
$matched=$false
$commandMatched=$false
$previousPath=$env:PATH
$timer=[System.Diagnostics.Stopwatch]::StartNew()
function Read-ByteUntil([double]$Deadline) {
    while ($timer.Elapsed.TotalSeconds -lt $Deadline) {
        try {
            $value=$serial.ReadByte()
            $capture.WriteByte([byte]$value)
            return $value
        } catch [System.TimeoutException] { }
    }
    throw 'UART response timeout'
}
try {
    $loader=Join-Path $Suite 'bin/openFPGALoader.exe'
    $env:PATH=(Join-Path $Suite 'bin')+';'+(Join-Path $Suite 'lib')+';'+$env:PATH
    & $loader --detect -b tangprimer20k 2>&1 | Tee-Object -FilePath "$prefix-jtag.log"
    if ($LASTEXITCODE -ne 0) { throw 'JTAG detection failed' }
    $detection=Get-Content -Raw "$prefix-jtag.log"
    if ($detection -notmatch 'idcode 0x81b' -or ([regex]::Matches($detection,'idcode')).Count -ne 1) {
        throw 'Expected exactly one GW2A-18C target'
    }
    $serial.Open()
    $serial.DiscardInBuffer()
    & (Join-Path $PSScriptRoot 'flash.ps1') -Suite $Suite -Bitstream $bitstream
    $banner=''
    $deadline=$timer.Elapsed.TotalSeconds+30
    while (-not $banner.EndsWith("VBL1`n")) {
        $banner += [char](Read-ByteUntil $deadline)
        if ($banner.Length -gt 64) { $banner=$banner.Substring($banner.Length-64) }
    }
    Write-Host 'Boot ROM ready'
    $offset=0
    $nextReport=65536
    while ($offset -lt $wire.Length) {
        $length=[BitConverter]::ToUInt32($wire,$offset+12)
        $serial.Write($wire,$offset,20+$length)
        $waitSeconds=if ([BitConverter]::ToUInt32($wire,$offset+4) -eq 66) { 600 } else { 10 }
        $replyDeadline=$timer.Elapsed.TotalSeconds+$waitSeconds
        $reply=Read-ByteUntil $replyDeadline
        if ($Platform -eq 'Standalone' -and $offset -eq 0 -and $reply -eq 83) {
            # Flash completion can outlast the ROM's UART selection window.
            # The queued first packet remains valid after the SD fallback banner.
            $notice='S'
            while (-not $notice.EndsWith("`n") -and $notice.Length -lt 64) {
                $notice += [char](Read-ByteUntil $replyDeadline)
            }
            if ($notice -ne "SD unavailable`n" -and $notice -ne "SD failed`n") {
                throw "Boot ROM selected another boot source: $($notice.Trim())"
            }
            $fallback=''
            for ($n=0; $n -lt 5; $n++) { $fallback += [char](Read-ByteUntil $replyDeadline) }
            if ($fallback -ne "VBL1`n") { throw 'Invalid SD fallback banner' }
            $reply=Read-ByteUntil $replyDeadline
        }
        if ($reply -ne 75) { throw "Boot ROM rejected packet at package offset $offset (reply $reply)" }
        $offset+=20+$length
        if ($offset -ge $nextReport) {
            Write-Host "Uploaded $offset / $($wire.Length) bytes"
            $nextReport+=65536
        }
    }
    $uploaded=$true
    Write-Host 'Image/DTB verified; entry acknowledged'
    $deadline=$timer.Elapsed.TotalSeconds+$CaptureSeconds
    $output=''
    $line=''
    while ($timer.Elapsed.TotalSeconds -lt $deadline) {
        try { $value=$serial.ReadByte() } catch [System.TimeoutException] { continue }
        $capture.WriteByte([byte]$value)
        $output += [char]$value
        $line += [char]$value
        if ($value -eq 10) {
            Write-Host $line -NoNewline
            $line=''
            $capture.Flush()
        }
        if (-not $matched -and $ExpectedText -and $output.Contains($ExpectedText)) {
            $matched=$true
            if (-not $ConsoleCommand) { break }
            $serial.Write($ConsoleCommand+"`n")
            Write-Host "Console command sent: $ConsoleCommand"
            $output=''
            $deadline=$timer.Elapsed.TotalSeconds+$CaptureSeconds
        } elseif ($matched -and $ConsoleCommand -and $output.Contains($CommandExpectedText)) {
            $commandMatched=$true
            break
        }
    }
    if ($line) { Write-Host $line }
    if ($ExpectedText -and -not $matched) { throw "Expected UART text not seen: $ExpectedText" }
    if ($ConsoleCommand -and -not $commandMatched) { throw "Expected command response not seen: $CommandExpectedText" }
} catch {
    $failure=$_.Exception.Message
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $capture.Dispose()
    $env:PATH=$previousPath
    $result=[ordered]@{
        uploaded=$uploaded; expected=$ExpectedText; matched=$matched; error=$failure
        console_command=$ConsoleCommand; command_expected=$CommandExpectedText; command_matched=$commandMatched
        elapsed_seconds=[Math]::Round($timer.Elapsed.TotalSeconds,3)
        bitstream_sha256=(Get-FileHash $bitstream -Algorithm SHA256).Hash
        package_sha256=(Get-FileHash $Package -Algorithm SHA256).Hash
    }
    $result | ConvertTo-Json | Tee-Object -FilePath "$prefix-result.json"
    if (-not $KeepRunning) {
        & (Join-Path $PSScriptRoot 'test-board.ps1') -Suite $Suite -Port $Port -Mode LcdSoc -Seconds 5
    }
}
if ($failure) { throw $failure }
