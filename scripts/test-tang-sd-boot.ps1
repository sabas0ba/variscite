# Load the standalone platform and observe SD boot without UART writes.
# The card must already contain TANGBOOT.VBL. Leaves the platform running.
#Requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Suite,
    [Parameter(Mandatory=$true)][string]$Port,
    [ValidateRange(1,3600)][int]$CaptureSeconds=600,
    [ValidateRange(100000,6000000)][int]$Frequency=6000000,
    [switch]$Flash
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$bitstream=Join-Path $root 'sim/fpga/linux_standalone/impl/pnr/linux_standalone.fs'
$hash=(Get-FileHash $bitstream -Algorithm SHA256).Hash
$logDir=Join-Path $root 'logs/board'
New-Item -ItemType Directory -Force $logDir | Out-Null
$prefix=Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-SdBoot')
$serial=New-Object System.IO.Ports.SerialPort $Port,115200,'None',8,'One'
$serial.ReadTimeout=1000
$serial.ReadBufferSize=65536
$capture=[System.IO.File]::Open("$prefix-uart.bin",[System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
$failure=$null
$flashVerified=$false
$output=''
$line=''
$timer=[System.Diagnostics.Stopwatch]::StartNew()
$previousPath=$env:PATH
try {
    $env:PATH=(Join-Path $Suite 'bin')+';'+(Join-Path $Suite 'lib')+';'+$env:PATH
    & (Join-Path $Suite 'bin/openFPGALoader.exe') --detect -b tangprimer20k --freq $Frequency 2>&1 |
        Tee-Object -FilePath "$prefix-jtag.log"
    if ($LASTEXITCODE -ne 0) { throw 'JTAG detection failed' }
    $detection=Get-Content -Raw "$prefix-jtag.log"
    if ($detection -notmatch 'idcode 0x81b' -or ([regex]::Matches($detection,'idcode')).Count -ne 1) {
        throw 'Expected exactly one GW2A-18C target'
    }
    $serial.Open()
    $serial.DiscardInBuffer()
    & (Join-Path $PSScriptRoot 'flash.ps1') -Suite $Suite -Bitstream $bitstream -Flash:$Flash -Frequency $Frequency 2>&1 |
        Tee-Object -FilePath "$prefix-program.log"
    $flashVerified=[bool]$Flash
    $deadline=$timer.Elapsed.TotalSeconds+$CaptureSeconds
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
        if ($output.Contains('SD failed') -or $output.Contains('SD unavailable')) {
            throw 'ROM could not boot from microSD'
        }
        if ($output.Contains('fbui: ready')) { break }
    }
    foreach ($marker in @('SD verified','Linux version','fbui: ready')) {
        if (-not $output.Contains($marker)) { throw "Expected UART text not seen: $marker" }
    }
} catch {
    $failure=$_.Exception.Message
} finally {
    if ($line) { Write-Host $line }
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $capture.Dispose()
    $env:PATH=$previousPath
    [ordered]@{
        sd_verified=$output.Contains('SD verified')
        linux_started=$output.Contains('Linux version')
        gui_ready=$output.Contains('fbui: ready')
        uart_bytes_written=0
        flash_requested=[bool]$Flash
        flash_verified=$flashVerified
        requested_jtag_hz=$Frequency
        error=$failure
        elapsed_seconds=[Math]::Round($timer.Elapsed.TotalSeconds,3)
        bitstream_sha256=$hash
    } | ConvertTo-Json | Tee-Object -FilePath "$prefix-result.json"
}
if ($failure) { throw $failure }
