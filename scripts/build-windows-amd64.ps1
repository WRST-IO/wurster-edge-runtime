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

$SystemNinja = (Get-Command ninja.exe -ErrorAction Stop).Source
if ($SystemNinja -match '[\\/]depot_tools[\\/]') {
    throw "Refusing to use depot_tools Ninja for Edge.js: $SystemNinja"
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

    $V8Root = if ($env:WURSTER_V8_ROOT) {
        $env:WURSTER_V8_ROOT
    } else {
        Join-Path $Root "build/v8-$($Lock.toolchain.v8.version)-windows-amd64"
    }
    $PathBeforeV8 = $env:Path
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $V8Root "include/v8.h")) -or
            -not (Test-Path -LiteralPath (Join-Path $V8Root "lib/v8.lib"))) {
            & "$ScriptDir/build-v8-windows-amd64.ps1" -Output $V8Root
        }
    } finally {
        # depot_tools prepends itself to PATH while building V8. Never let that
        # leak into the following CMake configure, where its POSIX `ninja`
        # wrapper can shadow the runner's native ninja.exe.
        $env:Path = $PathBeforeV8
    }
    $env:NAPI_V8_INCLUDE_DIR = Join-Path $V8Root "include"
    $env:NAPI_V8_LIBRARY = Join-Path $V8Root "lib/v8.lib"
    $env:NAPI_V8_BUILD_METHOD = "local"

    $EdgeBuild = Join-Path $SourceRoot "edgejs/build-edge"
    if (Test-Path -LiteralPath $EdgeBuild) {
        Remove-Item -LiteralPath $EdgeBuild -Recurse -Force
    }
    & $SystemNinja --version
    & cmake -S (Join-Path $SourceRoot "edgejs") -B $EdgeBuild -G Ninja `
        "-DCMAKE_MAKE_PROGRAM:FILEPATH=$SystemNinja" `
        -DCMAKE_BUILD_TYPE=Release `
        -DCMAKE_C_FLAGS=/utf-8 `
        "-DCMAKE_CXX_FLAGS=/utf-8 /Zc:__cplusplus /EHsc" `
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
