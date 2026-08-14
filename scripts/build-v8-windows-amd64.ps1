param(
    [string]$Output
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Lock = Get-Content (Join-Path $Root "runtime.lock.json") -Raw | ConvertFrom-Json
$Version = $Lock.toolchain.v8.version
$ExpectedCommit = $Lock.sources.v8.commit
$Jobs = if ($env:JOBS) { $env:JOBS } else { "4" }

if (-not $Output) {
    $Output = Join-Path $Root "build/v8-$Version-windows-amd64"
}
$WorkRoot = if ($env:WURSTER_V8_SOURCE_ROOT) {
    $env:WURSTER_V8_SOURCE_ROOT
} elseif ($env:RUNNER_TEMP) {
    Join-Path $env:RUNNER_TEMP "wurster-v8-$Version-windows-amd64"
} else {
    Join-Path $Root "build/v8-source-windows-amd64"
}
$BuilderRoot = Join-Path $WorkRoot "builder"
$DepotRoot = Join-Path $WorkRoot "depot_tools"
$CheckoutRoot = Join-Path $WorkRoot "checkout"
$V8Root = Join-Path $CheckoutRoot "v8"

if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    throw "V8 Windows build requires an AMD64 Windows host"
}

function Checkout-PinnedRepository {
    param([string]$Repository, [string]$Commit, [string]$Destination)

    if (Test-Path -LiteralPath (Join-Path $Destination ".git")) {
        if ((& git -C $Destination rev-parse HEAD) -ne $Commit) {
            throw "$Destination is not at pinned commit $Commit"
        }
        return
    }
    if (Test-Path -LiteralPath $Destination) {
        throw "refusing to overwrite non-repository path: $Destination"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    & git init -q $Destination
    & git -C $Destination remote add origin $Repository
    & git -C $Destination fetch --depth 1 origin $Commit
    & git -C $Destination checkout -q --detach FETCH_HEAD
    if ((& git -C $Destination rev-parse HEAD) -ne $Commit) {
        throw "failed to check out pinned commit $Commit"
    }
}

function Assert-V8Version {
    param([string]$IncludeRoot)

    $Header = Get-Content (Join-Path $IncludeRoot "v8-version.h") -Raw
    $Expected = $Version.Split('.')
    $Patterns = @(
        "#define V8_MAJOR_VERSION $($Expected[0])",
        "#define V8_MINOR_VERSION $($Expected[1])",
        "#define V8_BUILD_NUMBER $($Expected[2])",
        "#define V8_PATCH_LEVEL $($Expected[3])"
    )
    foreach ($Pattern in $Patterns) {
        if (-not $Header.Contains($Pattern)) {
            throw "V8 header version does not match pinned ${Version}: missing $Pattern"
        }
    }
}

if ((Test-Path -LiteralPath (Join-Path $Output "include/v8.h")) -and
    (Test-Path -LiteralPath (Join-Path $Output "lib/v8.lib"))) {
    Assert-V8Version (Join-Path $Output "include")
    exit 0
}
if (Test-Path -LiteralPath $Output) {
    throw "incomplete V8 output exists: $Output"
}

Checkout-PinnedRepository $Lock.sources.v8_custom_builds.repository `
    $Lock.sources.v8_custom_builds.commit $BuilderRoot
Checkout-PinnedRepository $Lock.sources.depot_tools.repository `
    $Lock.sources.depot_tools.commit $DepotRoot

$env:Path = "$DepotRoot;$env:Path"
$env:DEPOT_TOOLS_UPDATE = "0"
$env:DEPOT_TOOLS_METRICS = "0"
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
& git config --global core.autocrlf false
& git config --global core.longpaths true

# A pinned depot_tools checkout intentionally has no generated git.bat. The
# normal auto-update path creates it as a side effect, but auto-update must stay
# disabled for a reproducible build. Run only the pinned Windows bootstrap,
# which installs the manifest-locked CIPD tools and renders the Git wrapper.
& (Join-Path $DepotRoot "bootstrap/win_tools.bat")
$DepotGit = Join-Path $DepotRoot "git.bat"
if (-not (Test-Path -LiteralPath $DepotGit)) {
    throw "pinned depot_tools bootstrap did not generate git.bat"
}
& $DepotGit --version

$Synced = $false
for ($Attempt = 1; $Attempt -le 3 -and -not $Synced; $Attempt++) {
    if (Test-Path -LiteralPath $CheckoutRoot) {
        Remove-Item -LiteralPath $CheckoutRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $CheckoutRoot | Out-Null
    try {
        Push-Location $CheckoutRoot
        try {
            & fetch v8
        } finally {
            Pop-Location
        }
        & git -C $V8Root fetch --depth 1 origin $ExpectedCommit
        & git -C $V8Root checkout --detach $ExpectedCommit
        Push-Location $CheckoutRoot
        try {
            & gclient sync --with_branch_heads --with_tags --nohooks --revision "v8@$ExpectedCommit"
        } finally {
            Pop-Location
        }
        $Synced = $true
    } catch {
        if ($Attempt -eq 3) { throw }
        Write-Warning "V8 dependency sync attempt $Attempt failed; retrying from a clean checkout"
    }
}

if ((& git -C $V8Root rev-parse HEAD) -ne $ExpectedCommit) {
    throw "V8 source lock mismatch"
}
& python3 (Join-Path $V8Root "build/util/lastchange.py") `
    -o (Join-Path $V8Root "build/util/LASTCHANGE")

Get-ChildItem (Join-Path $BuilderRoot "patches") -Filter "*.patch" | Sort-Object Name | ForEach-Object {
    & git -C $V8Root apply --check $_.FullName
    & git -C $V8Root apply $_.FullName
}

$BuildRoot = Join-Path $V8Root "out/wurster-release"
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
@'
is_debug = false
v8_symbol_level = 0
symbol_level = 0
is_component_build = false
is_official_build = false
use_custom_libcxx = false
use_custom_libcxx_for_host = true
use_glib = false
v8_expose_symbols = true
v8_optimized_debug = false
v8_enable_sandbox = false
v8_enable_i18n_support = true
icu_use_data_file = false
v8_enable_gdbjit = false
v8_use_external_startup_data = false
treat_warnings_as_errors = false
v8_enable_pointer_compression = true
v8_enable_short_builtin_calls = true
target_cpu = "x64"
v8_target_cpu = "x64"
'@ | Set-Content -LiteralPath (Join-Path $BuildRoot "args.gn") -Encoding utf8

Push-Location $V8Root
try {
    & gn gen out/wurster-release
    & ninja -C out/wurster-release -j $Jobs wee8
} finally {
    Pop-Location
}

$Stage = Join-Path $WorkRoot "dist"
if (Test-Path -LiteralPath $Stage) {
    throw "refusing to overwrite V8 staging directory: $Stage"
}
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "include/wasm-c-api") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "lib") | Out-Null
Copy-Item (Join-Path $V8Root "include/*") (Join-Path $Stage "include") -Recurse
Get-ChildItem (Join-Path $Stage "include") -Recurse -File |
    Where-Object Extension -ne ".h" | Remove-Item -Force
Copy-Item (Join-Path $V8Root "third_party/wasm-api/wasm.h") `
    (Join-Path $Stage "include/wasm-c-api/wasm.h")
Copy-Item (Join-Path $BuildRoot "obj/wee8.lib") (Join-Path $Stage "lib/v8.lib")
Assert-V8Version (Join-Path $Stage "include")
Move-Item -LiteralPath $Stage -Destination $Output

if (-not (Test-Path -LiteralPath (Join-Path $Output "include/v8.h")) -or
    -not (Test-Path -LiteralPath (Join-Path $Output "lib/v8.lib"))) {
    throw "V8 source build did not produce the expected Windows SDK"
}
