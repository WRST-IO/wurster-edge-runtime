param(
    [string]$EdgeWasm = "build/guest/edgejs.wasm"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$SourceRoot = if ($env:WURSTER_BUILD_SOURCE_ROOT) {
    $env:WURSTER_BUILD_SOURCE_ROOT
} else {
    Join-Path $Root "build/src"
}
$Jobs = if ($env:JOBS) { $env:JOBS } else { "4" }

if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    throw "Windows amd64 build requires an AMD64 Windows host"
}

Push-Location $Root
try {
    & bash ./scripts/fetch-sources.sh build/src
    & bash ./scripts/apply-patches.sh build/src

    $Lock = Get-Content (Join-Path $Root "runtime.lock.json") -Raw | ConvertFrom-Json
    if ((& git -C $SourceRoot/edgejs rev-parse HEAD) -ne $Lock.sources.edgejs.commit) {
        throw "Edge.js source lock mismatch"
    }
    if ((& git -C $SourceRoot/wasmer rev-parse HEAD) -ne $Lock.sources.wasmer.commit) {
        throw "Wasmer source lock mismatch"
    }
    if ((& git -C $SourceRoot/edgejs rev-parse HEAD:napi) -ne $Lock.sources.napi.commit) {
        throw "Edge.js NAPI source lock mismatch"
    }
    if ((& git -C $SourceRoot/wasmer rev-parse HEAD:lib/napi) -ne $Lock.sources.napi.commit) {
        throw "Wasmer NAPI source lock mismatch"
    }

    $V8Target = $Lock.toolchain.v8.targets.'windows-amd64'
    $V8Root = if ($env:WURSTER_V8_ROOT) {
        $env:WURSTER_V8_ROOT
    } else {
        Join-Path $Root "build/v8-$($Lock.toolchain.v8.version)-windows-amd64"
    }
    $V8Archive = Join-Path $Root "build/downloads/v8-windows-amd64.tar.xz"
    if (-not (Test-Path -LiteralPath (Join-Path $V8Root "include/v8.h")) -or
        -not (Test-Path -LiteralPath (Join-Path $V8Root "lib/v8.lib"))) {
        if (Test-Path -LiteralPath $V8Root) {
            throw "incomplete V8 directory exists: $V8Root"
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $V8Archive) | Out-Null
        if (-not (Test-Path -LiteralPath $V8Archive)) {
            $Partial = "$V8Archive.partial"
            Invoke-WebRequest -Uri $V8Target.url -OutFile $Partial
            $PartialHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Partial).Hash.ToLowerInvariant()
            if ($PartialHash -ne $V8Target.sha256) { throw "downloaded V8 checksum mismatch" }
            Move-Item $Partial $V8Archive
        }
        $ArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $V8Archive).Hash.ToLowerInvariant()
        if ($ArchiveHash -ne $V8Target.sha256) { throw "cached V8 checksum mismatch" }
        $ExtractRoot = Join-Path $Root "build/v8-extract-$([Guid]::NewGuid())"
        New-Item -ItemType Directory -Path $ExtractRoot | Out-Null
        try {
            & tar -xJf $V8Archive -C $ExtractRoot
            if (-not (Test-Path -LiteralPath (Join-Path $ExtractRoot "include/v8.h")) -or
                -not (Test-Path -LiteralPath (Join-Path $ExtractRoot "lib/v8.lib"))) {
                throw "pinned Windows V8 archive has no expected headers/import library"
            }
            Move-Item $ExtractRoot $V8Root
        } finally {
            Remove-Item -LiteralPath $ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $env:NAPI_V8_INCLUDE_DIR = Join-Path $V8Root "include"
    $env:NAPI_V8_LIBRARY = Join-Path $V8Root "lib/v8.lib"

    # Wasmer's Windows WASM backend consumes the same signed V8 11.9.7 bytes
    # through its wee8 cache. Seed that cache from our verified download so the
    # Cargo build cannot silently fetch an unverified second copy.
    $Wee8Cache = Join-Path $SourceRoot "wasmer/target/wee8-artifacts/$($Lock.toolchain.v8.version)/windows-amd64"
    New-Item -ItemType Directory -Force -Path $Wee8Cache | Out-Null
    Copy-Item $V8Archive (Join-Path $Wee8Cache "v8-windows-amd64.tar.xz")
    Copy-Item (Join-Path $V8Root "lib") $Wee8Cache -Recurse -Force

    $EdgeBuild = Join-Path $SourceRoot "edgejs/build-edge"
    & cmake -S (Join-Path $SourceRoot "edgejs") -B $EdgeBuild -G Ninja `
        -DCMAKE_BUILD_TYPE=Release `
        -DCMAKE_C_FLAGS=/utf-8 `
        -DCMAKE_CXX_FLAGS=/utf-8 `
        -DEDGE_BUILD_NAPI_TESTS=OFF
    & cmake --build $EdgeBuild --parallel $Jobs

    Push-Location (Join-Path $SourceRoot "wasmer")
    try {
        & cargo build --release `
            --manifest-path lib/cli/Cargo.toml `
            --no-default-features `
            --features v8,wasm-c-api,napi-v8 `
            --bin wasmer `
            --locked
    } finally {
        Pop-Location
    }

    & "$ScriptDir/assemble-bundle-windows.ps1" -SourceRoot $SourceRoot -EdgeWasm $EdgeWasm
    & "$ScriptDir/verify-bundle-windows.ps1" `
        -Bundle (Join-Path $Root "out/wurster-edge-runtime-windows-amd64")
} finally {
    Pop-Location
}
