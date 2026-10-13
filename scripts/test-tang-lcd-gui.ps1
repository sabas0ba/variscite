# Exercise an already booted Tang LCD Linux image over UART. No reprogramming.
# Leaves the GUI displayed after verifying color/movement, exit and status.
#Requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Port,
    [ValidateRange(1,600)][int]$TimeoutSeconds=180
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$logDir=Join-Path $root 'logs/board'
New-Item -ItemType Directory -Force $logDir | Out-Null
$prefix=Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-LinuxLcdGui')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,'None',8,'One'
$serial.WriteTimeout=10000
$file=[IO.File]::Open("$prefix-uart.txt",[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)
$writer=[IO.StreamWriter]::new($file,[Text.UTF8Encoding]::new($false))
$writer.AutoFlush=$true
$steps=[Collections.Generic.List[object]]::new()
$failure=$null
function Invoke-ConsoleStep([string]$Command,[string]$Expected) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $output=''
    $serial.Write($Command+"`n")
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $text=$serial.ReadExisting()
        if ($text) {
            $writer.Write($text)
            $output+=$text
            if ($output.Contains($Expected)) {
                $steps.Add([ordered]@{command=$Command; expected=$Expected; seconds=[Math]::Round($timer.Elapsed.TotalSeconds,3)})
                Write-Host "$Command : $Expected"
                return
            }
            if ($output.Length -gt 8192) { $output=$output.Substring($output.Length-8192) }
        } else { Start-Sleep -Milliseconds 20 }
    }
    throw "UART timeout after command '$Command': expected '$Expected'"
}
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    Invoke-ConsoleStep 'lcdstat' 'LCD scanout status: OK'
    Invoke-ConsoleStep 'gui' 'fbui: ready'
    Invoke-ConsoleStep 'g' 'fbui: updated'
    Invoke-ConsoleStep 'd' 'fbui: updated'
    Invoke-ConsoleStep 'q' 'veryl$ '
    Invoke-ConsoleStep 'lcdstat' 'LCD scanout status: OK'
    Invoke-ConsoleStep 'gui' 'fbui: ready'
} catch {
    $failure=$_.Exception.Message
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $writer.Dispose()
    [ordered]@{passed=($null -eq $failure); steps=$steps.ToArray(); error=$failure} |
        ConvertTo-Json -Depth 4 | Tee-Object -FilePath "$prefix-result.json"
}
if ($failure) { throw $failure }
