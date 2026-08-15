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
if ($env:VisualStudioVersion -notmatch '^17\.') {
    throw "V8 13.6 requires Visual Studio 2022 (17.x), got $env:VisualStudioVersion"
}
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw "Visual Studio 2022 x64 cl.exe is not available"
}
if ($env:VSCMD_ARG_TGT_ARCH -ne "x64" -or
    -not $env:VSINSTALLDIR -or -not $env:VCToolsInstallDir -or
    -not $env:WindowsSdkDir) {
    throw "Incomplete Visual Studio 2022 x64 build environment"
}
foreach ($Tool in @("link.exe", "lib.exe")) {
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "Visual Studio 2022 x64 tool is unavailable: $Tool"
    }
}
$env:GYP_MSVS_VERSION = "2022"

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

function Assert-CompleteV8Sdk {
    param([string]$SdkRoot)

    foreach ($RelativePath in @(
        "include/v8.h",
        "include/v8-version.h",
        "include/cppgc/allocation.h",
        "include/cppgc/internal/api-constants.h",
        "include/wasm-c-api/wasm.h",
        "lib/v8.lib"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $SdkRoot $RelativePath))) {
            throw "Windows V8 SDK is incomplete: missing $RelativePath"
        }
    }
    Assert-V8Version (Join-Path $SdkRoot "include")
}

function Invoke-BoundedNative {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds,
        [string]$Description
    )

    Write-Host ">>> $Description (timeout ${TimeoutSeconds}s)"
    $StartedAt = [DateTime]::UtcNow
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $FilePath
    $StartInfo.UseShellExecute = $false
    foreach ($Argument in $Arguments) {
        [void]$StartInfo.ArgumentList.Add([string]$Argument)
    }

    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) {
            throw "failed to start $Description"
        }
        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $Process.Kill($true) } catch { }
            $Process.WaitForExit()
            throw "$Description exceeded hard timeout of ${TimeoutSeconds}s"
        }
        if ($Process.ExitCode -ne 0) {
            throw "$Description failed with exit code $($Process.ExitCode)"
        }
    } finally {
        $Process.Dispose()
    }
    $Elapsed = [Math]::Round(([DateTime]::UtcNow - $StartedAt).TotalSeconds, 1)
    Write-Host "<<< $Description complete in ${Elapsed}s"
}

function Hydrate-PinnedCppgcHeaders {
    param([string]$DestinationInclude)

    # The audited 11.9.7 Windows archive contains the built V8 library and the
    # patched wasm C API header, but its packaging omits the public cppgc tree.
    # Do not sparse-fetch the enormous V8 Git repository here. Enumerate only
    # include/cppgc from GitHub's V8 mirror at the exact pinned commit, download
    # those tiny headers, and verify every file against its Git blob SHA.
    $ApiHeaders = @{
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "wurster-edge-runtime-ci"
    }
    $Deadline = [DateTime]::UtcNow.AddMinutes(5)
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    $Queue.Enqueue("include/cppgc")
    $Downloaded = 0

    Write-Host ">>> Hydrating pinned cppgc headers from V8 $ExpectedCommit (hard total budget 300s)"
    while ($Queue.Count -gt 0) {
        $Remaining = [int][Math]::Floor(($Deadline - [DateTime]::UtcNow).TotalSeconds)
        if ($Remaining -le 0) {
            throw "cppgc header hydration exceeded hard total timeout of 300s"
        }

        $RemoteDirectory = $Queue.Dequeue()
        Write-Host "Listing $RemoteDirectory"
        $ApiUrl = "https://api.github.com/repos/v8/v8/contents/$RemoteDirectory`?ref=$ExpectedCommit"
        $RequestTimeout = [Math]::Max(5, [Math]::Min(60, $Remaining))
        # Invoke-RestMethod already exposes a JSON array as an Object[] value.
        # Wrapping it in @() nests that array, so property enumeration below
        # collapses all returned paths into one invalid space-separated string.
        $Items = Invoke-RestMethod -Uri $ApiUrl -Headers $ApiHeaders -TimeoutSec $RequestTimeout

        foreach ($Item in $Items) {
            if ($Item.type -eq "dir") {
                $Queue.Enqueue([string]$Item.path)
                continue
            }
            if ($Item.type -ne "file" -or -not ([string]$Item.name).EndsWith(".h", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not $Item.download_url -or -not ([string]$Item.path).StartsWith("include/", [StringComparison]::Ordinal)) {
                throw "invalid pinned V8 header metadata for $($Item.path)"
            }

            $Remaining = [int][Math]::Floor(($Deadline - [DateTime]::UtcNow).TotalSeconds)
            if ($Remaining -le 0) {
                throw "cppgc header hydration exceeded hard total timeout of 300s"
            }
            $RequestTimeout = [Math]::Max(5, [Math]::Min(45, $Remaining))

            $Destination = $DestinationInclude
            foreach ($Part in ([string]$Item.path).Substring("include/".Length).Split('/')) {
                $Destination = Join-Path $Destination $Part
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
            Invoke-WebRequest -Uri ([string]$Item.download_url) -Headers @{ "User-Agent" = "wurster-edge-runtime-ci" } `
                -OutFile $Destination -TimeoutSec $RequestTimeout

            $ActualBlobSha = (& git hash-object -- $Destination).Trim()
            if ($ActualBlobSha -ne [string]$Item.sha) {
                throw "V8 header blob mismatch for $($Item.path): expected $($Item.sha), got $ActualBlobSha"
            }
            $Downloaded++
        }
    }

    if ($Downloaded -eq 0) {
        throw "cppgc header hydration downloaded no headers"
    }
    Write-Host "<<< Hydrated and blob-verified $Downloaded cppgc headers"
}

function Provision-PinnedReleaseSdk {
    # Release 11.9.7 was produced from exactly the builder and V8 revisions
    # pinned by runtime.lock.json. Its Windows archive contains the built
    # wee8/v8 library and patched wasm C API header, but its upstream packaging
    # omitted public cppgc headers. Hydrate only that missing public header tree
    # from the exact V8 commit instead of recompiling V8 for several hours.
    $AssetRelease = "11.9.7"
    $AssetSha256 = "2aee8b6c3e8cecae2ce0325ac01b9bcaea4bef49e8f2aac599e1729d60c17285"
    $AssetBuilderCommit = "844d01dc10edaa0461715f484e06b004f1fd023e"
    $AssetV8Commit = "b0a55a7dad7f536cce1f9aaddba89894c8533946"

    if ($Version -ne "13.6.233.17" -or
        $Lock.toolchain.v8.upstream_asset_release -ne $AssetRelease -or
        $Lock.sources.v8_custom_builds.commit -ne $AssetBuilderCommit -or
        $ExpectedCommit -ne $AssetV8Commit) {
        throw "Pinned Windows V8 release provisioner no longer matches runtime.lock.json; update its audited asset pins before continuing"
    }

    foreach ($Tool in @("curl.exe", "git.exe")) {
        if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
            throw "Windows V8 release provisioner requires $Tool"
        }
    }
    $GitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
    if (-not (Test-Path -LiteralPath $GitBash)) {
        throw "Windows V8 release provisioner requires Git for Windows Bash at $GitBash"
    }

    $OutputParent = Split-Path -Parent $Output
    New-Item -ItemType Directory -Force -Path $OutputParent | Out-Null
    $DownloadRoot = Join-Path $Root "build/downloads"
    New-Item -ItemType Directory -Force -Path $DownloadRoot | Out-Null
    $Archive = Join-Path $DownloadRoot "v8-$AssetRelease-windows-amd64.tar.xz"
    $AssetUrl = "https://github.com/wasmerio/v8-custom-builds/releases/download/$AssetRelease/v8-windows-amd64.tar.xz"

    if (Test-Path -LiteralPath $Archive) {
        Write-Host ">>> Verifying existing pinned Windows V8 release archive"
        $ExistingSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
        if ($ExistingSha -ne $AssetSha256) {
            Remove-Item -LiteralPath $Archive -Force
        }
    }
    if (-not (Test-Path -LiteralPath $Archive)) {
        $Partial = "$Archive.partial"
        Remove-Item -LiteralPath $Partial -Force -ErrorAction SilentlyContinue
        try {
            Invoke-BoundedNative -FilePath (Get-Command curl.exe -ErrorAction Stop).Source `
                -Arguments @(
                    "--fail", "--location", "--proto", "=https", "--tlsv1.2",
                    "--retry", "3", "--retry-delay", "2", "--connect-timeout", "30",
                    "--max-time", "600", "--output", $Partial, $AssetUrl
                ) -TimeoutSeconds 620 -Description "Download pinned Windows V8 release archive"
            Write-Host ">>> Verifying downloaded Windows V8 SHA-256"
            $DownloadedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Partial).Hash.ToLowerInvariant()
            if ($DownloadedSha -ne $AssetSha256) {
                throw "Windows V8 release asset checksum mismatch: expected $AssetSha256, got $DownloadedSha"
            }
            Move-Item -LiteralPath $Partial -Destination $Archive
        } finally {
            Remove-Item -LiteralPath $Partial -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host ">>> Verifying pinned Windows V8 archive before extraction"
    $ActualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant()
    if ($ActualSha -ne $AssetSha256) {
        throw "Windows V8 release asset checksum mismatch: expected $AssetSha256, got $ActualSha"
    }

    $Stage = "$Output.staging"
    if (Test-Path -LiteralPath $Stage) {
        Remove-Item -LiteralPath $Stage -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null

    try {
        # The pinned upstream Windows archive is created on windows-2022 from a
        # Git Bash step using GNU tar + xz. Extract it with the same tool family
        # rather than Windows' System32 tar/libarchive, which hangs on this
        # exact archive on GitHub's windows-2022 runner.
        $BashExtract = @'
set -euo pipefail
printf 'bash: %s\n' "$BASH_VERSION"
printf 'tar: '
command -v tar
tar --version | head -n 1
printf 'xz: '
command -v xz
xz --version | head -n 1
archive="$(cygpath -u "$WURSTER_V8_ARCHIVE")"
stage="$(cygpath -u "$WURSTER_V8_STAGE")"
tar -xJf "$archive" -C "$stage"
'@
        $env:WURSTER_V8_ARCHIVE = $Archive
        $env:WURSTER_V8_STAGE = $Stage
        try {
            Invoke-BoundedNative -FilePath $GitBash `
                -Arguments @("--noprofile", "--norc", "-c", $BashExtract) `
                -TimeoutSeconds 300 -Description "Extract pinned Windows V8 release archive with Git Bash GNU tar"
        } finally {
            Remove-Item Env:WURSTER_V8_ARCHIVE -ErrorAction SilentlyContinue
            Remove-Item Env:WURSTER_V8_STAGE -ErrorAction SilentlyContinue
        }

        foreach ($RelativePath in @("include/v8.h", "include/wasm-c-api/wasm.h", "lib/v8.lib")) {
            if (-not (Test-Path -LiteralPath (Join-Path $Stage $RelativePath))) {
                throw "Pinned upstream Windows V8 archive is missing expected payload: $RelativePath"
            }
        }
        Assert-V8Version (Join-Path $Stage "include")

        Hydrate-PinnedCppgcHeaders (Join-Path $Stage "include")
        Assert-CompleteV8Sdk $Stage

        if (Test-Path -LiteralPath $Output) {
            throw "refusing to overwrite existing V8 output: $Output"
        }
        Write-Host ">>> Publishing completed Windows V8 SDK to $Output"
        Move-Item -LiteralPath $Stage -Destination $Output
        Assert-CompleteV8Sdk $Output
        Write-Host "<<< Windows V8 SDK ready: $Output"
    } finally {
        if (Test-Path -LiteralPath $Stage) {
            Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ((Test-Path -LiteralPath (Join-Path $Output "include/v8.h")) -and
    (Test-Path -LiteralPath (Join-Path $Output "include/cppgc/allocation.h")) -and
    (Test-Path -LiteralPath (Join-Path $Output "lib/v8.lib"))) {
    Assert-CompleteV8Sdk $Output
    exit 0
}
if (Test-Path -LiteralPath $Output) {
    throw "incomplete V8 output exists: $Output"
}

$ForceSourceBuild = [Environment]::GetEnvironmentVariable("WURSTER_FORCE_V8_SOURCE_BUILD") -eq "1"
if (-not $ForceSourceBuild) {
    Provision-PinnedReleaseSdk
    exit 0
}
Write-Warning "WURSTER_FORCE_V8_SOURCE_BUILD=1: bypassing pinned release SDK and compiling V8 from source"

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
    # Match the pinned upstream Windows builder: Git for Windows may expose
    # CRLF in this checkout even with autocrlf disabled, so ignore whitespace
    # differences while retaining the exact patch content and target lines.
    & git -C $V8Root apply --ignore-whitespace --check $_.FullName
    & git -C $V8Root apply --ignore-whitespace $_.FullName
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
Assert-CompleteV8Sdk $Stage
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
Move-Item -LiteralPath $Stage -Destination $Output
Assert-CompleteV8Sdk $Output