# Load the standalone platform and observe SD boot without UART writes.
# The card must already contain TANGBOOT.VBL. Leaves the platform running.
#Requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Suite,
    [Parameter(Mandatory=$true)][string]$Port,
    [ValidateRange(1,3600)][int]$CaptureSeconds=600,
    [ValidateRange(100000,6000000)][int]$Frequency=6000000,
    [ValidateRange(10,3600)][int]$ProgramSeconds=300,
    [switch]$Flash
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$bitstream=Join-Path $root 'sim/fpga/linux_standalone/impl/pnr/linux_standalone.fs'
$hash=(Get-FileHash $bitstream -Algorithm SHA256).Hash
$loader=Join-Path $Suite 'bin/openFPGALoader.exe'
$loaderHash=(Get-FileHash $loader -Algorithm SHA256).Hash
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

function Invoke-Loader {
    param([string[]]$LoaderArguments, [string]$LogPath, [int]$TimeoutSeconds)
    # Redirect to files to avoid a full stdout/stderr pipe blocking the programmer.
    $process=$null
    try {
        $process=Start-Process -FilePath $loader -ArgumentList $LoaderArguments -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.stderr"
        $null=$process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "openFPGALoader timed out after $TimeoutSeconds seconds; flash may be partially written"
        }
        # Refresh the process handle before reading the exit code on Windows PowerShell.
        $process.Refresh()
        if ($process.ExitCode -ne 0) { throw "openFPGALoader failed: exit $($process.ExitCode)" }
    } finally {
        if ($null -ne $process) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
        }
        if (Test-Path $LogPath) { Get-Content $LogPath | Write-Host }
        if (Test-Path "$LogPath.stderr") { Get-Content "$LogPath.stderr" | Write-Host }
    }
}

try {
    $env:PATH=(Join-Path $Suite 'bin')+';'+(Join-Path $Suite 'lib')+';'+$env:PATH
    Invoke-Loader -LoaderArguments @('--detect','-b','tangprimer20k','--freq',"$Frequency") `
        -LogPath "$prefix-jtag.log" -TimeoutSeconds 30
    $detection=(Get-Content -Raw "$prefix-jtag.log")+(Get-Content -Raw "$prefix-jtag.log.stderr")
    if ($detection -notmatch 'idcode 0x81b' -or ([regex]::Matches($detection,'idcode')).Count -ne 1) {
        throw 'Expected exactly one GW2A-18C target'
    }
    $serial.Open()
    $serial.DiscardInBuffer()
    $programArguments=@('-b','tangprimer20k','--freq',"$Frequency")
    if ($Flash) { $programArguments+=@('-f','--verify') }
    $programArguments+='"'+$bitstream+'"'
    Invoke-Loader -LoaderArguments $programArguments -LogPath "$prefix-program.log" -TimeoutSeconds $ProgramSeconds
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
        program_timeout_seconds=$ProgramSeconds
        loader_sha256=$loaderHash
        error=$failure
        elapsed_seconds=[Math]::Round($timer.Elapsed.TotalSeconds,3)
        bitstream_sha256=$hash
    } | ConvertTo-Json | Tee-Object -FilePath "$prefix-result.json"
}
if ($failure) { throw $failure }
