<#
.SYNOPSIS
  Build and optionally deploy one clean LeanTTY verification candidate.
.DESCRIPTION
  Requires a clean committed tree, runs the mandatory software regression gate
  and performs one clean ARM64 debug HAP build. By default the resulting signed
  HAP is installed and launched on a physical HarmonyOS PC and retained as
  device-deployed evidence. Feature behavior needs a separate named scenario.
#>
param(
    [string]$Target = '',
    [switch]$SkipDevice,
    [switch]$FollowLogs,
    [string]$EvidenceDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

$candidateSourceStatus = @(git -C $repoRoot status --porcelain --untracked-files=all 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect candidate source state' }
if ($candidateSourceStatus.Count -gt 0) {
    throw 'verify-pc requires a clean committed candidate; run tools/test-regression.ps1 before committing'
}

foreach ($scriptName in @(
        'build-native.ps1',
        'build-lock.ps1',
        'candidate-store.ps1',
        'rust-wsl.ps1',
        'device-regression.ps1',
        'test-device-regression.ps1',
        'test-regression.ps1',
        'verify-key-passphrase-pc.ps1',
        'test-build-workflows.ps1',
        'build-all.ps1',
        'dev-build.ps1',
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

$temporaryEvidenceDirectory = $false
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path (
        [IO.Path]::GetTempPath()
    ) ('LeanTTY-verification-' + [Guid]::NewGuid().ToString('N'))
    $temporaryEvidenceDirectory = $true
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$softwareEvidencePath = Join-Path $EvidenceDirectory 'software.json'
& (Join-Path $PSScriptRoot 'test-regression.ps1') -EvidencePath $softwareEvidencePath
if ($LASTEXITCODE -ne 0) { throw 'Mandatory software regression gate failed' }

. (Join-Path $PSScriptRoot 'build-lock.ps1')
. (Join-Path $PSScriptRoot 'candidate-store.ps1')
. (Join-Path $PSScriptRoot 'rust-wsl.ps1')
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

if ($SkipDevice) {
    & (Join-Path $PSScriptRoot 'build-all.ps1') -Clean -BuildMode debug
} else {
    $deviceArgs = @{ Clean = $true; Target = $Target }
    if ($FollowLogs) { $deviceArgs['FollowLogs'] = $true }
    & (Join-Path $PSScriptRoot 'dev-pc.ps1') @deviceArgs
}
if ($LASTEXITCODE -ne 0) { throw 'PC verification build or deployment failed' }

$verifiedHap = Join-Path $repoRoot (
    'entry\build\default\outputs\default\entry-default-signed.hap'
)
$verificationMode = if ($SkipDevice) { 'software' } else { 'device-deployed' }
$retainedCandidate = Save-LeanTTYVerifiedCandidate `
    -RepoRoot $repoRoot `
    -HapPath $verifiedHap `
    -VerificationMode $verificationMode `
    -EvidencePaths @($softwareEvidencePath)
if ($temporaryEvidenceDirectory -and
    (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) {
    Remove-Item -LiteralPath $EvidenceDirectory -Recurse -Force
}
Write-Host (
    "Retained $verificationMode-verified candidate: " +
    "$($retainedCandidate.hapPath) (SHA256=$($retainedCandidate.sha256))"
) -ForegroundColor Cyan

Write-Host 'VERIFY PC SUCCESS' -ForegroundColor Green
}
