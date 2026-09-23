# Load a Tang Primer 20K SRAM image and verify its serial output.
# Build the corresponding image in the development container first.
# Results and the raw serial capture are saved under logs/board/.
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$Suite,
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [ValidateSet('UartProbe', 'Loopback', 'Soc', 'LcdSoc', 'DdrInit', 'DdrRead', 'DdrMpr', 'DdrMprDelay', 'DdrMprAlign', 'DdrArray', 'DdrArrayScan', 'DdrArraySame', 'DdrArrayTrace', 'DdrArrayMatch')]
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
    DdrRead = 'sim/fpga/ddr_read/impl/pnr/ddr_read.fs'
    DdrMpr = 'sim/fpga/ddr_mpr/impl/pnr/ddr_mpr.fs'
    DdrMprDelay = 'sim/fpga/ddr_mpr_delay/impl/pnr/ddr_mpr_delay.fs'
    DdrMprAlign = 'sim/fpga/ddr_mpr_align/impl/pnr/ddr_mpr_align.fs'
    DdrArray = 'sim/fpga/ddr_array/impl/pnr/ddr_array.fs'
    DdrArrayScan = 'sim/fpga/ddr_array_scan/impl/pnr/ddr_array_scan.fs'
    DdrArraySame = 'sim/fpga/ddr_array_same/impl/pnr/ddr_array_same.fs'
    DdrArrayTrace = 'sim/fpga/ddr_array_trace/impl/pnr/ddr_array_trace.fs'
    DdrArrayMatch = 'sim/fpga/ddr_array_match/impl/pnr/ddr_array_match.fs'
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
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        # PowerShell 5 treats a native process's stderr as a terminating error
        # under Stop, even when the process exit code can be retried.
        $ErrorActionPreference = 'Continue'
        try {
            & $loader -b tangprimer20k $bitstream 2>&1 |
                Tee-Object -FilePath "$prefix-load.log" -Append
        } finally {
            $ErrorActionPreference = 'Stop'
        }
        if ($LASTEXITCODE -eq 0) { break }
        $loadLog = Get-Content -Raw "$prefix-load.log"
        if ($attempt -ne 1 -or $loadLog -notmatch 'FTDI reset error') {
            throw 'SRAM loading failed'
        }
        Start-Sleep -Milliseconds 500
    }
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
            # The old SRAM image can transmit while the new image is loading.
            $probe = [regex]::Match($received, '[PLIR]+$').Value
            $passed = ([regex]::Matches($probe, 'R')).Count -ge 5
        }
        DdrRead {
            # Each report is a status and the two selected gate phases.
            $frames = @([regex]::Matches($received, '[PLIRGE][0-3][0-9A-F][0-3][0-9A-F]') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'G' }).Count -eq 0
        }
        DdrMpr {
            # Each report is a status and four hexadecimal MPR data digits.
            $frames = @([regex]::Matches($received, '[PLIRMEVB][0-9A-F]{4}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'M' }).Count -eq 0
        }
        DdrMprDelay {
            # Status, two lane pass masks, then two raw lane patterns.
            $frames = @([regex]::Matches($received, '[PLIRMEVB][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'M' }).Count -eq 0
        }
        DdrMprAlign {
            # Status, two lane alignment masks, then two raw lane patterns.
            $frames = @([regex]::Matches($received, '[PLIRMEVB][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'M' }).Count -eq 0
        }
        DdrArray {
            # A proves both columns matched in the same cycle position per lane.
            # Four bytes report DQ0/DQ8 at RVALID for columns 0 and 8.
            $frames = @([regex]::Matches($received, '[PLIRABVE][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'A' }).Count -eq 0
        }
        DdrArrayScan {
            # T means both byte lanes passed at some gate candidate. The
            # first two bytes are DQ0/DQ8 pass masks; the last two are masks
            # where the two columns differ at the same RVALID cycle.
            $frames = @([regex]::Matches($received, '[PLIRTBVE][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'T' }).Count -eq 0
        }
        DdrArraySame {
            # Both columns have the same write data. Their observed patterns
            # should not differ at the same read-gate candidate and cycle.
            $frames = @([regex]::Matches($received, '[PLIRTBVE][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object {
                    $_.Value[0] -notin @('V', 'T') -or $_.Value.Substring(5, 4) -ne '0000'
                }).Count -eq 0
        }
        DdrArrayTrace {
            # This is an observation mode; T still requires the expected
            # pattern on both byte lanes at some gate candidate.
            $frames = @([regex]::Matches($received, '[PLIRTBVE][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'T' }).Count -eq 0
        }
        DdrArrayMatch {
            # Four masks report column 0 DQ0/DQ8 and column 8 DQ0/DQ8.
            $frames = @([regex]::Matches($received, '[PLIRTBVE][0-9A-F]{8}') |
                Select-Object -Last 3)
            $passed = $frames.Count -eq 3 -and
                @($frames | Where-Object { $_.Value[0] -ne 'T' }).Count -eq 0
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
