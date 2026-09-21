# Load a Tang Primer 20K SRAM image and verify its serial output.
# Build the corresponding image in the development container first.
# Results and the raw serial capture are saved under logs/board/.
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$Suite,
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [ValidateSet('UartProbe', 'Loopback', 'Soc', 'LcdSoc', 'DdrInit')]
    [string]$Mode = 'UartProbe',
    [ValidateRange(2, 60)]
    [int]$Seconds = 5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$images = @{
    UartProbe = 'sim/fpga/probe/probe.fs'
    Loopback = 'sim/fpga/probe/loopback.fs'
    Soc = 'sim/fpga/tang/soc.fs'
    LcdSoc = 'sim/fpga/lcd_soc/soc.fs'
    DdrInit = 'sim/fpga/ddr_init/impl/pnr/ddr_init.fs'
}
$bitstream = Join-Path $root $images[$Mode]
$loader = Join-Path $Suite 'bin/openFPGALoader.exe'
if (-not (Test-Path $bitstream)) { throw "Missing bitstream: $bitstream" }
if (-not (Test-Path $loader)) { throw "Missing loader: $loader" }
$logDir = Join-Path $root 'logs/board'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$prefix = Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Mode)
$previousPath = $env:PATH
$serial = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$capture = New-Object System.IO.MemoryStream
$passed = $false
$failure = $null
try {
    $env:PATH = (Join-Path $Suite 'bin') + ';' + (Join-Path $Suite 'lib') + ';' + $env:PATH
    & $loader --detect -b tangprimer20k 2>&1 | Tee-Object -FilePath "$prefix-jtag.log"
    if ($LASTEXITCODE -ne 0) { throw 'JTAG detection failed' }
    $detection = Get-Content -Raw "$prefix-jtag.log"
    if ($detection -notmatch 'idcode 0x81b' -or ([regex]::Matches($detection, 'idcode')).Count -ne 1) {
        throw 'Expected exactly one GW2A-18C JTAG target'
    }
    $serial.Open()
    $serial.DiscardInBuffer()
    & $loader -b tangprimer20k $bitstream 2>&1 | Tee-Object -FilePath "$prefix-load.log"
    if ($LASTEXITCODE -ne 0) { throw 'SRAM loading failed' }
    # Keep startup bytes for the SoC banner; probes need no startup capture.
    if ($Mode -notin @('Soc', 'LcdSoc')) { $serial.DiscardInBuffer() }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $sent = $false
    $buffer = New-Object byte[] 4096
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        if (-not $sent -and $timer.Elapsed.TotalSeconds -ge 1) {
            if ($Mode -eq 'Loopback') { $serial.Write('Tang20K-loopback-55AA') }
            if ($Mode -in @('Soc', 'LcdSoc')) { $serial.Write('Z') }
            $sent = $true
        }
        if ($serial.BytesToRead -gt 0) {
            $count = $serial.Read($buffer, 0, [Math]::Min($buffer.Length, $serial.BytesToRead))
            $capture.Write($buffer, 0, $count)
        }
        Start-Sleep -Milliseconds 10
    }
    $bytes = $capture.ToArray()
    $received = [System.Text.Encoding]::ASCII.GetString($bytes)
    switch ($Mode) {
        UartProbe { $passed = $bytes.Length -ge 100 -and $received -cmatch '^U+$' }
        Loopback { $passed = $received -ceq 'Tang20K-loopback-55AA' }
        DdrInit {
            $passed = $received -cmatch '^[PLIR]+$' -and
                ([regex]::Matches($received, 'R')).Count -ge 5
        }
        { $_ -in @('Soc', 'LcdSoc') } {
            # Ignore output from the old SRAM image before the new boot banner.
            # Keep the unmodified bytes in the capture file for diagnosis.
            $banner = $received.LastIndexOf('rv32ima_veryl on FPGA', [StringComparison]::Ordinal)
            if ($banner -ge 0) { $received = $received.Substring($banner) }
            $passed = $received.Contains('rv32ima_veryl on FPGA') -and
                ([regex]::Matches($received, '\[tick\]')).Count -ge 2 -and
                $received.Contains('[rx] Z (0x0000005a)') -and
                -not $received.Contains('[trap]')
            if ($Mode -eq 'LcdSoc') {
                $passed = $passed -and $received.Contains('[lcd] ready:') -and
                    ([regex]::Matches($received, '\[lcd\] applied')).Count -ge 2 -and
                    -not $received.Contains('[lcd] timeout')
            }
        }
    }
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $env:PATH = $previousPath
    [System.IO.File]::WriteAllBytes("$prefix-uart.bin", $capture.ToArray())
    $report = [ordered]@{
        mode = $Mode
        port = $Port
        baud = 115200
        seconds = $Seconds
        bitstream = $bitstream
        sha256 = (Get-FileHash -Algorithm SHA256 $bitstream).Hash
        bytes = $capture.Length
        passed = $passed
        error = $failure
    }
    $report | ConvertTo-Json | Set-Content -Encoding UTF8 "$prefix-result.json"
    $capture.Dispose()
    $report | ConvertTo-Json | Write-Output
}
if ($failure) { throw $failure }
if (-not $passed) { throw "Board verification failed; see $prefix-result.json" }
