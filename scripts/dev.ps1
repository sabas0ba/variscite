# Run a command inside the podman container defined by container/Containerfile.
#
# Everything in this repository is built and verified in that container: the
# Windows-native binaries (veryl.exe, nextpnr, verilator) are blocked by Smart
# App Control, and the toolchain versions the README pins are Linux builds.
#
#   .\scripts\dev.ps1                       # interactive shell
#   .\scripts\dev.ps1 make all              # the full verification suite
#   .\scripts\dev.ps1 veryl fmt --check
#   .\scripts\dev.ps1 -Setup                # clone riscv-tests into third_party/
#
# The image carries the toolchain and the Linux source tree, so runs are
# offline by default. -Network lifts that for the steps that fetch (only
# -Setup needs it).
#Requires -Version 5.1
param(
    [switch]$Setup,
    [switch]$Network,
    [switch]$Rebuild,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Image    = 'variscite-dev'

if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
    throw "podman not found in PATH"
}

podman image exists $Image
$exists = ($LASTEXITCODE -eq 0)
if ($Rebuild -or (-not $exists)) {
    podman build -t $Image -f (Join-Path $RepoRoot 'container\Containerfile') $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "podman build failed" }
}

$runArgs = @('run', '--rm', '-v', "${RepoRoot}:/work")
if ($Setup -or $Network) {
    # setup_toolchain.sh clones riscv-tests from github
} else {
    $runArgs += @('--network', 'none')
}

if ($Setup) {
    $inner = @('env', 'WITH_TESTS=1', 'scripts/setup_toolchain.sh')
} elseif ($Command) {
    $inner = $Command
} else {
    $runArgs += '-it'
    $inner = @('bash')
}

podman @runArgs $Image @inner
exit $LASTEXITCODE
