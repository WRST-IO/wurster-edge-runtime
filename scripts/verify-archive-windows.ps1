param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [switch]$BlockNetwork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$ExtractRoot = Join-Path ([IO.Path]::GetTempPath()) "wurster-edge-archive-$([Guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Path $ExtractRoot | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $ExtractRoot
    $Entries = @(Get-ChildItem -LiteralPath $ExtractRoot)
    if ($Entries.Count -ne 1 -or
        $Entries[0].Name -ne "wurster-edge-runtime-windows-amd64" -or
        -not $Entries[0].PSIsContainer) {
        throw "archive must contain exactly the windows-amd64 top-level directory"
    }
    if ($BlockNetwork) {
        $Edge = Join-Path $Entries[0].FullName "bin/edge.exe"
        $Wasmer = Join-Path $Entries[0].FullName "bin/wasmer.exe"
        $EdgeRule = "WursterEdge-$([Guid]::NewGuid())"
        $WasmerRule = "WursterWasmer-$([Guid]::NewGuid())"
        New-NetFirewallRule -DisplayName $EdgeRule -Direction Outbound -Action Block `
            -Program $Edge -Profile Any | Out-Null
        New-NetFirewallRule -DisplayName $WasmerRule -Direction Outbound -Action Block `
            -Program $Wasmer -Profile Any | Out-Null
        try {
            & "$ScriptDir/verify-bundle-windows.ps1" -Bundle $Entries[0].FullName
        } finally {
            Remove-NetFirewallRule -DisplayName $EdgeRule -ErrorAction SilentlyContinue
            Remove-NetFirewallRule -DisplayName $WasmerRule -ErrorAction SilentlyContinue
        }
    } else {
        & "$ScriptDir/verify-bundle-windows.ps1" -Bundle $Entries[0].FullName
    }
} finally {
    Remove-Item -LiteralPath $ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
}
