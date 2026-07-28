<#
.SYNOPSIS
  Run the low-frequency LeanTTY verification gate and deploy to a real PC.
.DESCRIPTION
  Runs the trusted ArkTS suite, Rust formatting and script syntax checks, and a
  clean ARM64 debug build. The ARM64 build compiles both the pure Rust core and
  the HarmonyOS N-API layer. By default the resulting signed HAP is also
  installed and launched on the HarmonyOS PC.
#>
param(
    [string]$Target = '',
    [switch]$SkipDevice,
    [switch]$FollowLogs
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

foreach ($scriptName in @(
        'build-native.ps1',
        'build-lock.ps1',
        'build-all.ps1',
        'hdc-common.ps1',
        'dev-pc.ps1',
        'deploy-usb.ps1',
        'verify-pc.ps1'
    )) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error ("$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)") }
        throw "PowerShell syntax check failed: $scriptName"
    }
}
Write-Host 'PowerShell syntax checks passed.' -ForegroundColor Green

. (Join-Path $PSScriptRoot 'build-lock.ps1')
Invoke-WithLeanTTYBuildLock -RepoRoot $repoRoot -Operation 'verify-pc' -Action {
$generatedNativePath = 'entry/libs/arm64-v8a/libleantty_ssh.so'
$trackedNative = @(git -C $repoRoot ls-files -- $generatedNativePath)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect tracked native build outputs'
}
if ($trackedNative.Count -gt 0) {
    throw "Generated native library must not be tracked: $generatedNativePath"
}
git -C $repoRoot check-ignore --quiet -- $generatedNativePath
if ($LASTEXITCODE -ne 0) {
    throw "Generated native library must be ignored: $generatedNativePath"
}
Write-Host 'Generated native library source-control policy passed.' -ForegroundColor Green

$deveco = $env:DEVECO_HOME
if (-not $deveco) {
    foreach ($candidate in @('C:\Program Files\Huawei\DevEco Studio', 'D:\Program Files\Huawei\DevEco Studio')) {
        if (Test-Path -LiteralPath $candidate) { $deveco = $candidate; break }
    }
}
if (-not $deveco) { throw 'DevEco Studio not found. Set DEVECO_HOME.' }

$nodeExe = Join-Path $deveco 'tools\node\node.exe'
$hvigorJs = Join-Path $deveco 'tools\hvigor\bin\hvigorw.js'
$ohpm = Join-Path $deveco 'tools\ohpm\bin\ohpm.bat'
$env:NODE_OPTIONS = ''
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:JAVA_HOME = Join-Path $deveco 'jbr'
$env:PATH = (Join-Path $deveco 'jbr\bin') + ';' + $env:PATH

$hypiumPath = Join-Path $repoRoot 'oh_modules\@ohos\hypium'
if (-not (Test-Path -LiteralPath $hypiumPath)) {
    if (-not (Test-Path -LiteralPath $ohpm)) { throw "OHPM not found: $ohpm" }
    Push-Location $repoRoot
    try {
        & $ohpm install --all --lockfile_stable_order
        $ohpmExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($ohpmExitCode -ne 0 -or -not (Test-Path -LiteralPath $hypiumPath)) {
        throw 'OHPM dependency restore failed'
    }
    Write-Host 'OHPM dependencies restored from the lockfile.' -ForegroundColor Green
}

& $nodeExe (Join-Path $repoRoot 'tools\web-terminal\test-terminal-policy.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Web terminal policy tests failed' }
Write-Host 'Web terminal policy tests passed.' -ForegroundColor Green

Push-Location $repoRoot
try {
    $arkTsTestStartedAt = Get-Date
    & $nodeExe $hvigorJs --mode module -p module=entry@default test
    $arkTsTestExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($arkTsTestExitCode -ne 0) { throw 'Trusted ArkTS unit tests failed' }
$arkTsTestResult = Join-Path $repoRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
if (-not (Test-Path -LiteralPath $arkTsTestResult)) {
    throw "Trusted ArkTS unit test result not found: $arkTsTestResult"
}
$arkTsTestResultInfo = Get-Item -LiteralPath $arkTsTestResult
if ($arkTsTestResultInfo.LastWriteTime -lt $arkTsTestStartedAt.AddSeconds(-1)) {
    throw 'Trusted ArkTS unit test result was not refreshed by the current run'
}
$arkTsTestSummary = Get-Content -LiteralPath $arkTsTestResult -Raw
$arkTsTestSummaryMatch = [regex]::Match(
    $arkTsTestSummary,
    '(?m)^Tests run: (?<run>\d+), Failure: (?<failure>\d+), Error: (?<error>\d+), Pass: (?<pass>\d+), Ignore: (?<ignore>\d+)\s*$'
)
if (-not $arkTsTestSummaryMatch.Success) {
    throw 'Trusted ArkTS unit test summary is missing or malformed'
}
if ([int]$arkTsTestSummaryMatch.Groups['failure'].Value -ne 0 -or
    [int]$arkTsTestSummaryMatch.Groups['error'].Value -ne 0) {
    throw ('Trusted ArkTS unit tests failed: ' + $arkTsTestSummaryMatch.Value.Trim())
}
Write-Host 'Trusted ArkTS unit tests passed.' -ForegroundColor Green

$cargoManifest = Join-Path $repoRoot 'leantty_ssh\Cargo.toml'
& cargo fmt --manifest-path $cargoManifest -- --check
if ($LASTEXITCODE -ne 0) { throw 'Rust formatting check failed' }
Write-Host 'Rust formatting passed; ARM64 compilation is verified by the HAP build.' -ForegroundColor Green

if ($SkipDevice) {
    & (Join-Path $PSScriptRoot 'build-all.ps1') -Clean -BuildMode debug
} else {
    $deviceArgs = @{ Clean = $true; Target = $Target }
    if ($FollowLogs) { $deviceArgs['FollowLogs'] = $true }
    & (Join-Path $PSScriptRoot 'dev-pc.ps1') @deviceArgs
}
if ($LASTEXITCODE -ne 0) { throw 'PC verification build or deployment failed' }

Write-Host 'VERIFY PC SUCCESS' -ForegroundColor Green
}
