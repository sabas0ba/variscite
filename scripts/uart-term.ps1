# Serial console for the board port: prints what the SoC sends, forwards what
# you type. Exit with Esc.
#
#   .\scripts\uart-term.ps1                  # auto-detect the FTDI COM port
#   .\scripts\uart-term.ps1 -Port COM7
#   .\scripts\uart-term.ps1 -MaxBytes 200    # exit after N bytes (for capture)
#
# 115200 8N1 is what the host uses. The Tang port transmits at 112500 (27 MHz
# divided by 16 * 15), 2.3% low; by the stop bit the sample point has drifted
# 22% of a bit, which 8N1 absorbs. Uses .NET's SerialPort, so there is nothing
# to install.
#Requires -Version 5.1
param(
    [string]$Port,
    [int]$BaudRate = 115200,
    [switch]$Hex,
    [int]$MaxBytes = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Port) {
    $names = Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'FTDIBUS%'" |
        Select-Object -ExpandProperty Name
    foreach ($n in $names) {
        if ($n -match '\((COM\d+)\)') { $Port = $Matches[1]; break }
    }
    if (-not $Port) { throw "FTDI COM port not found. Specify -Port explicitly" }
}

$serial = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, 'None', 8, 'One'
$serial.Open()
$serial.DiscardInBuffer()
Write-Host "Connected: $Port @ $BaudRate baud (8N1). Press Esc to exit."

# Keyboard polling fails when no interactive console is attached (a capture run
# with redirected stdin, for instance); disable it on the first failure.
$keyboardOk = $true
$rxCount    = 0
$done       = $false

try {
    while (-not $done) {
        while ($serial.BytesToRead -gt 0 -and -not $done) {
            if ($Hex) {
                $b = $serial.ReadByte()
                Write-Host -NoNewline ('{0:x2} ' -f $b)
                $rxCount++
                if ($rxCount % 16 -eq 0) { Write-Host '' }
            } else {
                $s = $serial.ReadExisting()
                Write-Host -NoNewline $s
                $rxCount += $s.Length
            }
            if ($MaxBytes -gt 0 -and $rxCount -ge $MaxBytes) { $done = $true }
        }
        if (-not $done -and $keyboardOk) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq 'Escape') { $done = $true }
                    else { $serial.Write($key.KeyChar) }
                }
            } catch {
                $keyboardOk = $false
            }
        }
        Start-Sleep -Milliseconds 10
    }
} finally {
    $serial.Close()
    Write-Host "`nDisconnected: $Port ($rxCount bytes received)"
}
