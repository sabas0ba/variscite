# Render reference schematics with the Windows PDF API; no package installation.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Output,
    [int]$Page = 1,
    [uint32]$Width = 2400
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Wait-Operation($Operation, [Type]$ResultType) {
    $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.GetAwaiter().GetResult()
}
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$file = Wait-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($sourcePath)) ([Windows.Storage.StorageFile])
$document = Wait-Operation ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
if ($Page -lt 1 -or $Page -gt $document.PageCount) { throw 'Page is outside document' }
$pdfPage = $document.GetPage([uint32]($Page - 1))
$stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
try {
    $options = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    $options.DestinationWidth = $Width
    $action = $pdfPage.RenderToStreamAsync($stream, $options)
    $asActionTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    $null = $asActionTask.Invoke($null, @($action)).GetAwaiter().GetResult()
    $stream.Seek(0)
    $inputStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
    $outputStream = [System.IO.File]::Create($outputPath)
    try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    Write-Output "Rendered page $Page to $outputPath"
} finally {
    $stream.Dispose()
    $pdfPage.Dispose()
}
