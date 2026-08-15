param(
    [string]$Bundle = "out/wurster-edge-runtime-windows-amd64"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Bundle = (Resolve-Path -LiteralPath $Bundle).Path
$Edge = Join-Path $Bundle "bin/edge.exe"
$Wasmer = Join-Path $Bundle "bin/wasmer.exe"
$Package = Join-Path $Bundle "share/edge-wasix"

foreach ($Artifact in @(
    $Edge,
    $Wasmer,
    (Join-Path $Package "edgejs.wasm"),
    (Join-Path $Package "wasmer.toml")
)) {
    if (-not (Test-Path -LiteralPath $Artifact -PathType Leaf)) {
        throw "bundle artifact missing: $Artifact"
    }
}

function Assert-PeAmd64([string]$Path) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -lt 64 -or $Bytes[0] -ne 0x4d -or $Bytes[1] -ne 0x5a) {
        throw "not a PE executable: $Path"
    }
    $PeOffset = [BitConverter]::ToInt32($Bytes, 0x3c)
    if ($PeOffset -lt 0 -or $PeOffset + 6 -gt $Bytes.Length) {
        throw "invalid PE header: $Path"
    }
    if ($Bytes[$PeOffset] -ne 0x50 -or $Bytes[$PeOffset + 1] -ne 0x45) {
        throw "missing PE signature: $Path"
    }
    $Machine = [BitConverter]::ToUInt16($Bytes, $PeOffset + 4)
    if ($Machine -ne 0x8664) {
        throw "expected PE32+ amd64 executable, machine=0x$($Machine.ToString('x4')): $Path"
    }
}

Assert-PeAmd64 $Edge
Assert-PeAmd64 $Wasmer

$VersionDetail = (& $Wasmer --version -v 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "bundled Wasmer --version failed" }
if ($VersionDetail -notmatch 'napi_v10' -or
    $VersionDetail -notmatch 'napi_extension_wasmer_v0') {
    throw "bundled Wasmer has no matching NAPI feature markers"
}

$WasmerToml = Get-Content (Join-Path $Package "wasmer.toml") -Raw
if ($WasmerToml -match 'quickjs-wasm/(etc|pnpm)|wasmer/edgejs@|registry|cdn') {
    throw "WASIX manifest contains a forbidden remote or missing-path reference"
}
if ($WasmerToml -match '(?m)^\[fs\]') {
    throw "WASIX manifest must not add ambient filesystem mounts"
}

& python "$ScriptDir/verify-manifest.py" $Bundle
if ($LASTEXITCODE -ne 0) { throw "bundle manifest verification failed" }
$Manifest = Get-Content (Join-Path $Bundle "manifest.json") -Raw | ConvertFrom-Json
if ($Manifest.target -ne "windows-amd64") {
    throw "bundle target mismatch: $($Manifest.target)"
}

$RunRoot = Join-Path ([IO.Path]::GetTempPath()) "wurster-edge-verify-$([Guid]::NewGuid())"
$Sandbox = Join-Path $RunRoot "sandbox"
$FakeBin = Join-Path $RunRoot "fake-bin"
$Outside = Join-Path $RunRoot "outside"
New-Item -ItemType Directory -Force -Path $Sandbox, $FakeBin, $Outside | Out-Null
Set-Content -LiteralPath (Join-Path $RunRoot "host-secret") `
    -Value "host-secret-must-not-be-visible" -Encoding utf8NoBOM
Set-Content -LiteralPath (Join-Path $Outside "host-secret") `
    -Value "junction-secret-must-not-be-visible" -Encoding utf8NoBOM
New-Item -ItemType Junction -Path (Join-Path $Sandbox "escape-dir") -Target $Outside | Out-Null

$SavedEnvironment = @{
    HOME = $env:HOME
    PATH = $env:PATH
    PATHEXT = $env:PATHEXT
    WURSTER_EDGE_BIN = $env:WURSTER_EDGE_BIN
    WASMER_BIN = $env:WASMER_BIN
    EDGE_WASMER_PACKAGE = $env:EDGE_WASMER_PACKAGE
    FAKE_WASMER_LOG = $env:FAKE_WASMER_LOG
    FAKE_WASMER_MODE = $env:FAKE_WASMER_MODE
}

try {
    $env:HOME = Join-Path $RunRoot "host-home-must-not-leak"
    $env:WURSTER_EDGE_BIN = $Edge
    $env:WASMER_BIN = $Wasmer
    $env:EDGE_WASMER_PACKAGE = $Package

    Push-Location $Sandbox
    try {
        $VersionOutput = (& $Edge --safe -e 'console.log(process.version)' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $VersionOutput -notmatch '(?m)^v[0-9]+') {
            throw "edge --safe process.version failed: $VersionOutput"
        }

        $FsScript = @'
const fs = require("node:fs");
fs.mkdirSync("dist", { recursive: true });
fs.writeFileSync("dist/out.txt", "pigsty-ok");
console.log(fs.readFileSync("dist/out.txt", "utf8"));
console.log("HOME=" + process.env.HOME);
'@
        $FsOutput = (& $Edge --safe -e $FsScript 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $FsOutput -notmatch '(?m)^pigsty-ok$' -or
            $FsOutput -notmatch '(?m)^HOME=/tmp$') {
            throw "node:fs or guest HOME test failed: $FsOutput"
        }
        if ((Get-Content (Join-Path $Sandbox "dist/out.txt") -Raw) -ne "pigsty-ok") {
            throw "workspace write did not persist"
        }

        $IsolationScript = @'
const fs = require("node:fs");
for (const candidate of ["../host-secret", "escape-dir/host-secret"]) {
  let blocked = false;
  try { fs.readFileSync(candidate, "utf8"); }
  catch (error) { blocked = true; }
  if (!blocked) throw new Error(`filesystem escape: ${candidate} was readable`);
}
console.log("outside-blocked");
'@
        $IsolationOutput = (& $Edge --safe -e $IsolationScript 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $IsolationOutput -notmatch '(?m)^outside-blocked$') {
            throw "filesystem isolation failed: $IsolationOutput"
        }
    } finally {
        Pop-Location
    }

    $FakeWasmer = Join-Path $RunRoot "fake-wasmer.exe"
    & rustc (Join-Path $Root "tests/fake-wasmer.rs") -o $FakeWasmer
    if ($LASTEXITCODE -ne 0) { throw "failed to build fake Wasmer probe" }

    foreach ($Fallback in @("node.exe", "nodejs.exe", "cmd.exe", "powershell.exe", "pwsh.exe")) {
        Copy-Item $FakeWasmer (Join-Path $FakeBin $Fallback)
    }
    $FallbackMarker = Join-Path $RunRoot "host-fallback-marker"
    $env:PATH = "$FakeBin;$env:SystemRoot\System32"
    $env:PATHEXT = ".EXE"
    $env:FAKE_WASMER_LOG = $FallbackMarker
    $env:FAKE_WASMER_MODE = "fallback"
    $env:WASMER_BIN = $Wasmer
    Push-Location $Sandbox
    try {
        $NoFallbackOutput = (& $Edge --safe -e 'console.log("no-host-node")' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $NoFallbackOutput -notmatch '(?m)^no-host-node$') {
            throw "PATH-poison runtime test failed: $NoFallbackOutput"
        }
    } finally {
        Pop-Location
    }
    if (Test-Path -LiteralPath $FallbackMarker) {
        throw "safe mode executed a host Node or shell fallback"
    }

    $ArgvLog = Join-Path $RunRoot "wasmer-argv"
    $env:FAKE_WASMER_LOG = $ArgvLog
    $env:FAKE_WASMER_MODE = "capture"
    $env:WASMER_BIN = $FakeWasmer
    & $Edge --safe -e 'console.log("captured")'
    if ($LASTEXITCODE -ne 0) { throw "safe command interception failed" }
    $Argv = Get-Content -LiteralPath $ArgvLog
    foreach ($Expected in @($Package, "--v8", "--experimental-napi", "--volume=.", "HOME=/tmp")) {
        if ($Argv -notcontains $Expected) { throw "safe command is missing: $Expected" }
    }
    if ($Argv -contains "--net" -or $Argv -contains "--llvm") {
        throw "Windows safe command granted networking or selected unavailable LLVM"
    }

    Write-Host "[ok] process.version: $VersionOutput"
    Write-Host "[ok] node:fs read/write: pigsty-ok"
    Write-Host "[ok] guest HOME: /tmp"
    Write-Host "[ok] parent and junction filesystem escapes blocked"
    Write-Host "[ok] no host Node, cmd, or PowerShell fallback"
    Write-Host "[ok] local package and network-disabled --v8 safe command"
    Write-Host "All Windows amd64 Wurster Edge Runtime smoke tests passed."
} finally {
    foreach ($Name in $SavedEnvironment.Keys) {
        $Value = $SavedEnvironment[$Name]
        if ($null -eq $Value) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$Name" $Value
        }
    }
    Remove-Item -LiteralPath $RunRoot -Recurse -Force -ErrorAction SilentlyContinue
}
