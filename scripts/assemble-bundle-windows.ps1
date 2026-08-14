param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$EdgeWasm
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$LockPath = Join-Path $Root "runtime.lock.json"
$Lock = Get-Content $LockPath -Raw | ConvertFrom-Json
$BundleName = "wurster-edge-runtime-windows-amd64"
$OutputRoot = Join-Path $Root "out"
$Bundle = Join-Path $OutputRoot $BundleName
$Archive = Join-Path $OutputRoot "$BundleName.zip"
$EdgeBin = Join-Path $SourceRoot "edgejs/build-edge/edge.exe"
$WasmerBin = Join-Path $SourceRoot "wasmer/target/release/wasmer.exe"

foreach ($Artifact in @($EdgeBin, $WasmerBin, $EdgeWasm)) {
    if (-not (Test-Path -LiteralPath $Artifact -PathType Leaf)) {
        throw "missing build artifact: $Artifact"
    }
}
if ((Test-Path -LiteralPath $Bundle) -or (Test-Path -LiteralPath $Archive)) {
    throw "refusing to overwrite existing bundle output: $Bundle"
}

$Package = Join-Path $Bundle "share/edge-wasix"
foreach ($Directory in @(
    (Join-Path $Bundle "bin"),
    $Package,
    (Join-Path $Bundle "LICENSES/edgejs"),
    (Join-Path $Bundle "LICENSES/wasmer"),
    (Join-Path $Bundle "LICENSES/wurster")
)) {
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
}

Copy-Item $EdgeBin (Join-Path $Bundle "bin/edge.exe")
Copy-Item $WasmerBin (Join-Path $Bundle "bin/wasmer.exe")
Copy-Item $EdgeWasm (Join-Path $Package "edgejs.wasm")
Copy-Item (Join-Path $Root "packaging/edge-wasix/wasmer.toml") $Package
Copy-Item (Join-Path $Root "packaging/BUNDLE_README.md") (Join-Path $Bundle "README.md")
Copy-Item $LockPath (Join-Path $Bundle "runtime.lock.json")
Copy-Item (Join-Path $Root "packaging/NOTICE.md") (Join-Path $Bundle "LICENSES/NOTICE.md")
Copy-Item (Join-Path $Root "LICENSE") (Join-Path $Bundle "LICENSES/wurster/LICENSE")

Push-Location $Package
try {
    & (Join-Path $Bundle "bin/wasmer.exe") package build --check .
} finally {
    Pop-Location
}

& python "$ScriptDir/generate-rust-notices.py" `
    --manifest-path (Join-Path $SourceRoot "wasmer/lib/cli/Cargo.toml") `
    --output (Join-Path $Bundle "LICENSES/wasmer-rust-dependencies.md")

function Copy-LicenseTree([string]$Source, [string]$Destination, [string]$ExcludedPart) {
    Get-ChildItem -LiteralPath $Source -Recurse -File | Where-Object {
        $_.Name -match '^(LICENSE|COPYING)(\..*)?$' -and
        $_.FullName -notlike "*$ExcludedPart*"
    } | ForEach-Object {
        $Relative = [IO.Path]::GetRelativePath($Source, $_.FullName)
        $Target = Join-Path $Destination $Relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
        Copy-Item $_.FullName $Target
    }
}

Copy-LicenseTree (Join-Path $SourceRoot "edgejs") (Join-Path $Bundle "LICENSES/edgejs") "build-"
Copy-LicenseTree (Join-Path $SourceRoot "wasmer") (Join-Path $Bundle "LICENSES/wasmer") "target"

& python "$ScriptDir/generate-manifest.py" `
    --bundle $Bundle `
    --lock $LockPath `
    --patch-root (Join-Path $Root "patches") `
    --target windows-amd64

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
& python "$ScriptDir/create-deterministic-zip.py" `
    --directory $Bundle `
    --output $Archive `
    --epoch $Lock.toolchain.source_date_epoch

$Digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
"$Digest  $BundleName.zip" | Set-Content -Encoding utf8NoBOM "$Archive.sha256"
Write-Host "Bundle: $Bundle"
Write-Host "Archive: $Archive"
Write-Host "Checksum: $Archive.sha256"
