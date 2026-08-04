<#
.SYNOPSIS
  Verify interactive SSH authentication on the retained HarmonyOS PC candidate.
.DESCRIPTION
  Starts the repository-only SSH fixture with temporary credentials, maps one
  device loopback port to it, drives LeanTTY through raw keyboard events, and
  records non-secret behavior evidence. The retained HAP is installed without
  rebuilding, and all temporary credentials and port mappings are removed.
#>
[CmdletBinding()]
param(
    [string]$Target = '',
    [string]$HapPath = '',
    [string]$EvidenceDirectory = '',
    [string]$CandidateBasePath = '',
    [string]$UnlockPasswordPath = '',
    [ValidateRange(1024, 65535)]
    [int]$FixturePort = 22222,
    [string]$Distribution = $env:LEANTTY_WSL_DISTRO
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'candidate-store.ps1')
. (Join-Path $PSScriptRoot 'hdc-common.ps1')
. (Join-Path $PSScriptRoot 'device-regression.ps1')
. (Join-Path $PSScriptRoot 'rust-wsl.ps1')

$harnessStatus = @(git -C $repoRoot status --porcelain --untracked-files=all 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect SSH authentication harness source state' }
if ($harnessStatus.Count -gt 0) { throw 'SSH authentication harness requires a clean committed tree' }
$harnessCommit = (& git -C $repoRoot rev-parse HEAD 2>&1).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve SSH authentication harness commit' }
$harnessTree = (& git -C $repoRoot rev-parse 'HEAD^{tree}' 2>&1).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve SSH authentication harness tree' }

$hdc = Resolve-Hdc
$Target = Resolve-LeanTTYRegressionTarget -Hdc $hdc -Target $Target
if ([string]::IsNullOrWhiteSpace($UnlockPasswordPath)) {
    $UnlockPasswordPath = Get-LeanTTYDeviceUnlockPasswordPath
}
Assert-LeanTTYCredentialPathOutsideRepository `
    -CredentialPath $UnlockPasswordPath `
    -RepositoryRoot $repoRoot

$candidateRoot = Get-LeanTTYCandidateRoot `
    -RepoRoot $repoRoot `
    -CandidateBasePath $CandidateBasePath
$candidateRecords = @(Get-LeanTTYCandidateRecords -CandidateRoot $candidateRoot)
if ([string]::IsNullOrWhiteSpace($HapPath)) {
    $candidate = $candidateRecords | Select-Object -First 1
    if ($null -eq $candidate) { throw 'No retained candidate exists; run tools/verify-pc.ps1 first' }
} else {
    $resolvedHap = [IO.Path]::GetFullPath($HapPath)
    if (-not (Test-Path -LiteralPath $resolvedHap -PathType Leaf)) {
        throw "Candidate HAP is missing: $resolvedHap"
    }
    $requestedHash = (Get-FileHash -LiteralPath $resolvedHap -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidate = $candidateRecords | Where-Object { $_.sha256 -eq $requestedHash } | Select-Object -First 1
    if ($null -eq $candidate) { throw 'The selected HAP is not a retained verified candidate' }
}
if ($candidate.gitDirty) {
    throw 'SSH authentication evidence requires a clean committed candidate'
}
if ($candidate.gitTree -ne $harnessTree) {
    throw 'Retained candidate and SSH authentication harness must use the same committed tree'
}

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $repoRoot (
        'build\verification\device-ssh-auth-' +
        [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    )
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$evidencePath = Join-Path $EvidenceDirectory 'device-ssh-auth.json'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'leantty-ssh-auth-device-' + [Guid]::NewGuid().ToString('N')
)
$fixtureControl = Join-Path $fixtureRoot 'control'
$fixtureStdout = Join-Path $fixtureRoot 'stdout.log'
$fixtureStderr = Join-Path $fixtureRoot 'stderr.log'
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

$checks = [Collections.Generic.List[object]]::new()
$startedAt = [DateTimeOffset]::UtcNow
$fixtureProcess = $null
$fixtureLinuxPid = 0
$mappingActive = $false
$awakeLeaseActive = $false
$awakeLeaseResult = 'not-acquired'
$awakeLeaseFailure = ''
$cleanupResult = 'not-started'
$cleanupFailure = ''
$deviceModel = ''
$deviceAbi = ''
$deviceTransport = ''
$deviceUnlockResult = 'not-attempted'
$appPid = ''
$credentials = @{}
$secrets = @()
$keyName = 'ltty_reg_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$keyPassphrase = New-LeanTTYRegressionSecret
$keyCleanupRequired = $false
$failure = ''
$scenarioResult = 'failed'
$caughtError = $null
$stageStartedAt = $null

function Add-AuthCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$DurationMs
    )
    $checks.Add([pscustomobject]@{ name = $Name; result = 'passed'; durationMs = $DurationMs })
    Write-Host "[device-auth] PASS $Name ($DurationMs ms)" -ForegroundColor Green
}

function Start-AuthStage {
    param([Parameter(Mandatory = $true)][string]$Name)
    Write-Host "[device-auth] START $Name"
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    $script:stageStartedAt = [Diagnostics.Stopwatch]::StartNew()
}

function Assert-NoSecretExposure {
    param([Parameter(Mandatory = $true)][string]$LayoutName)
    $logs = Get-LeanTTYAppLogs -Hdc $hdc -Target $Target -ProcessId $appPid
    foreach ($secret in $secrets) {
        if (-not [string]::IsNullOrEmpty($secret) -and $logs.Contains($secret)) {
            throw 'HarmonyOS application logs exposed a temporary SSH fixture secret'
        }
    }
    $layout = Get-LeanTTYDeviceLayout `
        -Hdc $hdc `
        -Target $Target `
        -LocalPath (Join-Path $EvidenceDirectory $LayoutName)
    Assert-LeanTTYLayoutExcludesValues -Layout $layout -Values $secrets
}

function Complete-AuthStage {
    param([Parameter(Mandatory = $true)][string]$Name)
    Assert-NoSecretExposure -LayoutName ("layout-$Name.json")
    if ($null -eq $stageStartedAt) { throw 'SSH authentication stage timing was not started' }
    Add-AuthCheck -Name $Name -DurationMs $stageStartedAt.ElapsedMilliseconds
    $script:stageStartedAt = $null
}

function Wait-AuthLog {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 20
    )
    Wait-LeanTTYAppLog `
        -Hdc $hdc `
        -Target $Target `
        -ProcessId $appPid `
        -Pattern $Pattern `
        -TimeoutSeconds $TimeoutSeconds | Out-Null
}

function Submit-AuthValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$LayoutName
    )
    Invoke-LeanTTYDeviceText -Hdc $hdc -Target $Target -Text $Value
    Assert-NoSecretExposure -LayoutName $LayoutName
    Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2054
    Start-Sleep -Milliseconds 150
}

function Start-AuthCommand {
    param(
        [Parameter(Mandatory = $true)][string]$User,
        [string]$Identity = ''
    )
    $identityOption = if ([string]::IsNullOrWhiteSpace($Identity)) { '' } else { " -i $Identity" }
    Submit-LeanTTYDeviceCommand `
        -Hdc $hdc `
        -Target $Target `
        -Command "ssh -p $FixturePort$identityOption $User@127.0.0.1"
}

function Close-FixtureShell {
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Invoke-LeanTTYDeviceCtrlD -Hdc $hdc -Target $Target
    Wait-AuthLog -Pattern 'SSH closed, exitCode=0'
}

function Restart-RegressionApp {
    & $hdc -t $Target shell 'aa force-stop com.leantty.app' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stop LeanTTY between SSH authentication scenarios' }
    $start = Start-LeanTTYRegressionApp `
        -Hdc $hdc `
        -Target $Target `
        -CredentialPath $UnlockPasswordPath `
        -RepositoryRoot $repoRoot
    $script:appPid = $start.processId
    $script:deviceUnlockResult = $start.unlock
    Wait-LeanTTYTerminalInputLayout `
        -Hdc $hdc `
        -Target $Target `
        -LocalPath (Join-Path $EvidenceDirectory ('layout-restart-' + $appPid + '.json')) `
        -TimeoutSeconds 20 | Out-Null
}

function Invoke-DeleteKeyDialog {
    param([Parameter(Mandatory = $true)][string]$LayoutName)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt 10) {
        try {
            Invoke-LeanTTYDialogButton `
                -Hdc $hdc `
                -Target $Target `
                -ButtonText 'Delete key' `
                -LayoutPath (Join-Path $EvidenceDirectory $LayoutName)
            return
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw 'Delete-key confirmation did not appear'
}

function Remove-DisposableAuthKey {
    param([Parameter(Mandatory = $true)][string]$LayoutPrefix)
    if (-not (Test-LeanTTYDeviceKeyFilesPresent `
        -Hdc $hdc `
        -Target $Target `
        -KeyName $keyName)) {
        return 'already-absent'
    }
    Clear-LeanTTYDeviceInput -Hdc $hdc -Target $Target
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-LeanTTYDeviceCommand -Hdc $hdc -Target $Target -Command "key rm $keyName"
    Invoke-DeleteKeyDialog -LayoutName "$LayoutPrefix-dialog.json"
    Wait-AuthLog -Pattern 'KEY_DELETE result=success'
    if (Test-LeanTTYDeviceKeyFilesPresent `
        -Hdc $hdc `
        -Target $Target `
        -KeyName $keyName) {
        throw 'Disposable SSH authentication key remains after deletion'
    }
    return 'verified-absent'
}

function Read-FixtureCredentials {
    $path = Join-Path $fixtureControl 'server-credentials'
    $readyPath = Join-Path $fixtureControl 'fixture-ready'
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt 90) {
        if ($null -ne $fixtureProcess -and $fixtureProcess.HasExited) {
            throw "SSH fixture exited before readiness (exit=$($fixtureProcess.ExitCode))"
        }
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and
            (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
            $readyText = [IO.File]::ReadAllText($readyPath)
            $readyMatch = [regex]::Match(
                $readyText,
                "(?m)^address=(?:0\.0\.0\.0|127\.0\.0\.1):$FixturePort`$[\r\n]+^pid=(?<pid>\d+)`$"
            )
            if ($readyMatch.Success) {
                $script:fixtureLinuxPid = [int]$readyMatch.Groups['pid'].Value
                $result = @{}
                foreach ($line in [IO.File]::ReadAllLines($path)) {
                    $parts = $line.Split('=', 2)
                    if ($parts.Count -ne 2) { throw 'SSH fixture credential file is malformed' }
                    $result[$parts[0]] = $parts[1]
                }
                foreach ($name in @('password', 'account', 'token', 'second_token')) {
                    if (-not $result.ContainsKey($name) -or [string]::IsNullOrEmpty($result[$name])) {
                        throw "SSH fixture credential is missing: $name"
                    }
                }
                return $result
            }
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'Timed out waiting for the SSH authentication fixture'
}

function Write-AuthEvidence {
    $evidence = [ordered]@{
        schemaVersion = 1
        gate = 'device-behavior'
        scenario = 'ssh-interactive-authentication'
        result = $scenarioResult
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        durationMs = [long]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
        candidate = [ordered]@{
            sha256 = $candidate.sha256
            gitCommit = $candidate.gitCommit
            gitTree = $candidate.gitTree
            gitDirty = $candidate.gitDirty
        }
        harness = [ordered]@{
            gitCommit = $harnessCommit
            gitTree = $harnessTree
            gitDirty = $false
        }
        device = [ordered]@{
            model = $deviceModel
            abi = $deviceAbi
            transport = $deviceTransport
        }
        fixture = [ordered]@{
            endpoint = "127.0.0.1:$FixturePort"
            transport = 'hdc-reverse-to-repository-only-russh-server'
            credentials = 'runtime-generated-temporary-values'
        }
        environment = [ordered]@{
            awakeLease = $awakeLeaseResult
            deviceUnlock = $deviceUnlockResult
            failure = $awakeLeaseFailure
        }
        input = [ordered]@{
            method = 'raw-physical-key-events'
            secretInjection = 'runtime-generated-printable-ascii'
            textChunkCharacters = 12
            interChunkPacingMilliseconds = 25
            interPromptSettleMilliseconds = 150
            fixedDelayUsedAsVerdict = $false
        }
        coverage = @(
            'password-success',
            'password-then-keyboard-interactive-mixed-echo',
            'keyboard-interactive-multi-round-wrong-answer-recovery',
            'publickey-unencrypted',
            'publickey-then-password',
            'publickey-then-keyboard-interactive',
            'publickey-encrypted-passphrase',
            'process-stop-during-hidden-prompt-cleanup'
        )
        checks = @($checks)
        cleanup = [ordered]@{ result = $cleanupResult; failure = $cleanupFailure }
        failure = $failure
    }
    [IO.File]::WriteAllText(
        $evidencePath,
        (ConvertTo-Json -InputObject $evidence -Depth 7),
        [Text.UTF8Encoding]::new($false)
    )
}

try {
    Write-Host '[device-auth] START fixture-and-device-preflight'
    $preflight = [Diagnostics.Stopwatch]::StartNew()
    $pwshPath = (Get-Process -Id $PID).Path
    $fixtureArguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $PSScriptRoot 'start-ssh-auth-fixture.ps1'),
        '-ListenAddress', "0.0.0.0:$FixturePort",
        '-RunSeconds', '600',
        '-ControlDirectory', $fixtureControl
    )
    if (-not [string]::IsNullOrWhiteSpace($Distribution)) {
        $fixtureArguments += @('-Distribution', $Distribution)
    }
    $fixtureProcess = Start-Process `
        -FilePath $pwshPath `
        -ArgumentList $fixtureArguments `
        -RedirectStandardOutput $fixtureStdout `
        -RedirectStandardError $fixtureStderr `
        -WindowStyle Hidden `
        -PassThru
    $credentials = Read-FixtureCredentials
    $secrets = @(
        $credentials.password,
        $credentials.account,
        $credentials.token,
        $credentials.second_token,
        $keyPassphrase
    )

    $existingMappings = @(& $hdc -t $Target fport ls 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect existing HDC port mappings' }
    if ($existingMappings -match "(?m)tcp:$FixturePort\s+tcp:$FixturePort\s+\[Reverse\]") {
        throw "HDC reverse mapping already exists for fixture port $FixturePort"
    }
    $mappingOutput = @(
        & $hdc -t $Target rport "tcp:$FixturePort" "tcp:$FixturePort" 2>&1
    ) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $mappingOutput -notmatch 'Forwardport result:OK') {
        throw "Unable to create HDC reverse mapping: $mappingOutput"
    }
    $mappingActive = $true
    Start-LeanTTYDeviceAwakeLease -Hdc $hdc -Target $Target
    $awakeLeaseActive = $true
    $awakeLeaseResult = 'acquired'
    & (Join-Path $PSScriptRoot 'dev-pc.ps1') `
        -Target $Target `
        -HapPath $candidate.hapPath `
        -SkipBuild `
        -NoLaunch
    if ($LASTEXITCODE -ne 0) { throw 'Exact candidate deployment failed' }
    Restart-RegressionApp
    $deviceModel = (Invoke-HdcShell $hdc $Target 'param get const.product.model').Trim()
    $deviceAbi = (Invoke-HdcShell $hdc $Target 'param get const.product.cpu.abilist').Trim()
    $deviceTransport = Get-HdcTargetTransport -Hdc $hdc -Target $Target
    if ($deviceAbi -notmatch 'arm64-v8a') { throw "Device is not ARM64: $deviceAbi" }
    Clear-LeanTTYDeviceInput -Hdc $hdc -Target $Target
    Submit-LeanTTYDeviceCommand `
        -Hdc $hdc `
        -Target $Target `
        -Command "ssh-keygen -R [127.0.0.1]:$FixturePort"
    Start-Sleep -Milliseconds 500
    Add-AuthCheck -Name 'fixture-and-device-preflight' -DurationMs $preflight.ElapsedMilliseconds

    Start-AuthStage -Name 'password-success'
    Start-AuthCommand -User 'password'
    Wait-AuthLog -Pattern 'rust event: HOST_KEY_PROMPT:'
    Submit-LeanTTYDeviceCommand -Hdc $hdc -Target $Target -Command 'yes'
    Wait-AuthLog -Pattern 'native auth event kind=password'
    Submit-AuthValue -Value $credentials.password -LayoutName 'layout-password-value.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'password-success'

    Start-AuthStage -Name 'password-kbdint-mixed-echo'
    Start-AuthCommand -User 'password-kbdint'
    Wait-AuthLog -Pattern 'native auth event kind=password'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.password -LayoutName 'layout-password-kbdint-password.json'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.account -LayoutName 'layout-password-kbdint-account.json'
    Submit-AuthValue -Value $credentials.token -LayoutName 'layout-password-kbdint-token.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'password-kbdint-mixed-echo'

    Start-AuthStage -Name 'multiround-wrong-answer-recovery'
    Start-AuthCommand -User 'kbdint-multiround'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.account -LayoutName 'layout-multiround-account-first.json'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    $wrongAnswer = New-LeanTTYRegressionSecret
    $secrets += $wrongAnswer
    Submit-AuthValue -Value $wrongAnswer -LayoutName 'layout-multiround-wrong.json'
    Wait-AuthLog -Pattern 'rust event: AUTH:authentication was rejected'
    Assert-NoSecretExposure -LayoutName 'layout-multiround-rejected.json'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Start-AuthCommand -User 'kbdint-multiround'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.account -LayoutName 'layout-multiround-account-retry.json'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.second_token -LayoutName 'layout-multiround-token.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'multiround-wrong-answer-recovery'

    Start-AuthStage -Name 'generated-disposable-auth-key'
    $keyCleanupRequired = $true
    Submit-LeanTTYDeviceCommand `
        -Hdc $hdc `
        -Target $Target `
        -Command "ssh-keygen -t ed25519 -f $keyName -C regression"
    Wait-AuthLog -Pattern 'Key generated:'
    Complete-AuthStage -Name 'generated-disposable-auth-key'

    Start-AuthStage -Name 'publickey-unencrypted'
    Start-AuthCommand -User 'publickey' -Identity $keyName
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'publickey-unencrypted'

    Start-AuthStage -Name 'publickey-then-password'
    Start-AuthCommand -User 'publickey-password' -Identity $keyName
    Wait-AuthLog -Pattern 'native auth event kind=password'
    Submit-AuthValue -Value $credentials.password -LayoutName 'layout-publickey-password.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'publickey-then-password'

    Start-AuthStage -Name 'publickey-then-keyboard-interactive'
    Start-AuthCommand -User 'publickey-kbdint' -Identity $keyName
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.account -LayoutName 'layout-publickey-kbdint-account.json'
    Submit-AuthValue -Value $credentials.token -LayoutName 'layout-publickey-kbdint-token.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'publickey-then-keyboard-interactive'

    Start-AuthStage -Name 'encrypted-disposable-auth-key'
    Submit-LeanTTYDeviceCommand -Hdc $hdc -Target $Target -Command "ssh-keygen -p -f $keyName"
    Wait-AuthLog -Pattern 'KEY_PASSPHRASE_CHANGE stage=old'
    Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2054
    Wait-AuthLog -Pattern 'KEY_PASSPHRASE_CHANGE stage=new'
    Submit-AuthValue -Value $keyPassphrase -LayoutName 'layout-key-passphrase-new.json'
    Wait-AuthLog -Pattern 'KEY_PASSPHRASE_CHANGE stage=confirm'
    Submit-AuthValue -Value $keyPassphrase -LayoutName 'layout-key-passphrase-confirm.json'
    Wait-AuthLog -Pattern 'KEY_PASSPHRASE_CHANGE result=success'
    Complete-AuthStage -Name 'encrypted-disposable-auth-key'

    Start-AuthStage -Name 'publickey-encrypted-passphrase'
    Start-AuthCommand -User 'publickey' -Identity $keyName
    Wait-AuthLog -Pattern 'native auth event kind=private_key_passphrase'
    Submit-AuthValue -Value $keyPassphrase -LayoutName 'layout-key-passphrase-auth.json'
    Wait-AuthLog -Pattern 'SSH session connected'
    Close-FixtureShell
    Complete-AuthStage -Name 'publickey-encrypted-passphrase'

    Start-AuthStage -Name 'process-stop-during-hidden-prompt-cleanup'
    Start-AuthCommand -User 'kbdint-multiround'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
    Submit-AuthValue -Value $credentials.account -LayoutName 'layout-cancel-account.json'
    Wait-AuthLog -Pattern 'native auth event kind=challenge'
    Invoke-LeanTTYDeviceText -Hdc $hdc -Target $Target -Text $credentials.second_token
    Assert-NoSecretExposure -LayoutName 'layout-cancel-hidden-token.json'
    Restart-RegressionApp
    Assert-NoSecretExposure -LayoutName 'layout-cancel-restarted.json'
    Complete-AuthStage -Name 'process-stop-during-hidden-prompt-cleanup'

    Start-AuthStage -Name 'deleted-disposable-auth-key'
    Remove-DisposableAuthKey -LayoutPrefix 'layout-key-cleanup' | Out-Null
    $keyCleanupRequired = $false
    Complete-AuthStage -Name 'deleted-disposable-auth-key'

    Submit-LeanTTYDeviceCommand `
        -Hdc $hdc `
        -Target $Target `
        -Command "ssh-keygen -R [127.0.0.1]:$FixturePort"
    Start-Sleep -Milliseconds 500
    $scenarioResult = 'passed'
} catch {
    $caughtError = $_
    $failure = $_.Exception.Message
    try {
        Save-LeanTTYDeviceScreenshot `
            -Hdc $hdc `
            -Target $Target `
            -LocalPath (Join-Path $EvidenceDirectory 'failure.png')
    } catch {}
} finally {
    $cleanupFailures = [Collections.Generic.List[string]]::new()
    if ($keyCleanupRequired -and -not [string]::IsNullOrWhiteSpace($appPid)) {
        try {
            Restart-RegressionApp
            Remove-DisposableAuthKey -LayoutPrefix 'layout-key-finally-cleanup' | Out-Null
            $keyCleanupRequired = $false
        } catch {
            $cleanupFailures.Add('Disposable SSH authentication key cleanup failed')
        }
    }
    if ($mappingActive) {
        $removeOutput = @(
            & $hdc -t $Target fport rm "tcp:$FixturePort" "tcp:$FixturePort" 2>&1
        ) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $removeOutput -notmatch 'Remove forward ruler success') {
            $cleanupFailures.Add('HDC reverse mapping cleanup failed')
        } else {
            $remainingMappings = @(& $hdc -t $Target fport ls 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or
                $remainingMappings -match "(?m)tcp:$FixturePort\s+tcp:$FixturePort\s+\[Reverse\]") {
                $cleanupFailures.Add('HDC reverse mapping remained after cleanup')
            } else {
                $mappingActive = $false
            }
        }
    }
    if ($fixtureLinuxPid -gt 0) {
        try {
            $wslPrefix = Get-LeanTTYWslPrefix -Distribution $Distribution
            & wsl.exe @wslPrefix --exec kill -TERM $fixtureLinuxPid 2>$null
        } catch {}
    }
    if ($null -ne $fixtureProcess -and -not $fixtureProcess.HasExited) {
        Wait-Process -Id $fixtureProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
        $fixtureProcess.Refresh()
        if (-not $fixtureProcess.HasExited) {
            Stop-Process -Id $fixtureProcess.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $fixtureProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
            $fixtureProcess.Refresh()
        }
        if (-not $fixtureProcess.HasExited) {
            $cleanupFailures.Add('SSH fixture launcher process remained after cleanup')
        }
    }
    if ($awakeLeaseActive) {
        try {
            Stop-LeanTTYDeviceAwakeLease -Hdc $hdc -Target $Target
            $awakeLeaseActive = $false
            $awakeLeaseResult = 'restored'
        } catch {
            $awakeLeaseResult = 'restore-failed'
            $awakeLeaseFailure = $_.Exception.Message
            $cleanupFailures.Add('HarmonyOS awake lease cleanup failed')
        }
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $fixtureRoot) {
            $cleanupFailures.Add('SSH fixture temporary directory remained after cleanup')
        }
    }
    $credentials = @{}
    $secrets = @()
    $keyPassphrase = ''
    if ($cleanupFailures.Count -eq 0) {
        $cleanupResult = 'passed'
    } else {
        $cleanupResult = 'failed'
        $cleanupFailure = $cleanupFailures -join '; '
        if ([string]::IsNullOrWhiteSpace($failure)) { $failure = $cleanupFailure }
        $scenarioResult = 'failed'
    }
}

Write-AuthEvidence
if ($scenarioResult -ne 'passed') {
    if ($null -ne $caughtError) { throw $caughtError }
    throw $failure
}

Save-LeanTTYVerifiedCandidate `
    -RepoRoot $repoRoot `
    -HapPath $candidate.hapPath `
    -VerificationMode 'device-behavior' `
    -EvidencePaths @($evidencePath) `
    -CandidateBasePath $CandidateBasePath | Out-Null
Write-Host (
    'DEVICE BEHAVIOR SUCCESS: ssh-interactive-authentication ' +
    "(SHA256=$($candidate.sha256), evidence=$evidencePath)"
) -ForegroundColor Green
