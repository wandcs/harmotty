param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LeanTTY-build-workflow-test-' + [Guid]::NewGuid().ToString('N')
)

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    try {
        & $Action
    } catch {
        return
    }
    throw $Message
}

function Wait-ForPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 5
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $Path)) {
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            throw "Timed out waiting for test signal: $Path"
        }
        Start-Sleep -Milliseconds 50
    }
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $candidateScript = Join-Path $PSScriptRoot 'candidate-store.ps1'
    Assert-True (Test-Path -LiteralPath $candidateScript -PathType Leaf) (
        "Candidate store helper is missing: $candidateScript"
    )
    . $candidateScript
    $candidateScriptText = Get-Content -LiteralPath $candidateScript -Raw
    Assert-True (
        $candidateScriptText.Contains('diff --name-only $candidateCommit HEAD') -and
        -not $candidateScriptText.Contains('diff --name-only --diff-filter=')
    ) 'Candidate reuse comparison could omit deleted or otherwise changed product paths'

    $packagePolicyScript = Join-Path $PSScriptRoot 'package-policy.ps1'
    Assert-True (Test-Path -LiteralPath $packagePolicyScript -PathType Leaf) (
        "Package policy helper is missing: $packagePolicyScript"
    )
    . $packagePolicyScript

    $acceptanceSourceScript = Join-Path $PSScriptRoot 'acceptance-source.ps1'
    Assert-True (Test-Path -LiteralPath $acceptanceSourceScript -PathType Leaf) (
        "Acceptance source helper is missing: $acceptanceSourceScript"
    )
    . $acceptanceSourceScript
    $acceptanceArkTsPaths = @(
        Join-Path $repoRoot 'entry\src\main\ets\pages\Index.ets'
        Join-Path $repoRoot 'entry\src\main\ets\model\bridge\TerminalBridge.ets'
        Join-Path $repoRoot 'entry\src\main\ets\model\terminal\TerminalSurfaceController.ets'
        Join-Path $repoRoot 'entry\src\main\ets\viewmodel\SessionViewModel.ets'
    )
    $acceptanceSourceHashes = @{}
    foreach ($path in $acceptanceArkTsPaths) {
        $acceptanceSourceHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    Invoke-WithLeanTTYAcceptanceSource -RepoRoot $repoRoot -Enabled $true -Action {
        $injectedText = $acceptanceArkTsPaths | ForEach-Object {
            Get-Content -LiteralPath $_ -Raw
        }
        Assert-True (($injectedText -join "`n").Contains('ACCEPTANCE_INPUT_SUBMIT')) (
            'Debug acceptance source injection omitted input telemetry'
        )
        Assert-True (($injectedText -join "`n").Contains('Acceptance: Rebuild Renderer')) (
            'Debug acceptance source injection omitted renderer trigger'
        )
    }
    foreach ($path in $acceptanceArkTsPaths) {
        Assert-True (
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $acceptanceSourceHashes[$path]
        ) "Acceptance source injection did not restore $path byte-for-byte"
    }

    Assert-LeanTTYHarnessOnlyPaths `
        -ChangedPaths @('tools/verify-ssh-auth-pc.ps1', 'docs/quality-strategy.md') `
        -AllowedPaths @('tools/verify-ssh-auth-pc.ps1', 'docs/*.md')
    Assert-Throws -Action {
        Assert-LeanTTYHarnessOnlyPaths `
            -ChangedPaths @('entry/src/main/ets/pages/Index.ets') `
            -AllowedPaths @('tools/verify-ssh-auth-pc.ps1', 'docs/*.md')
    } -Message 'Candidate reuse accepted a product-source change'

    $safeHap = Join-Path $testRoot 'safe-release.hap'
    $unsafeHap = Join-Path $testRoot 'unsafe-release.hap'
    foreach ($archiveCase in @(
        @{ path = $safeHap; content = 'ordinary release bytecode' },
        @{ path = $unsafeHap; content = 'ACCEPTANCE_INPUT_SUBMIT must not ship' }
    )) {
        $archiveStream = [IO.File]::Open($archiveCase.path, [IO.FileMode]::Create)
        try {
            $zip = [IO.Compression.ZipArchive]::new(
                $archiveStream,
                [IO.Compression.ZipArchiveMode]::Create,
                $false
            )
            try {
                $entry = $zip.CreateEntry('modules.abc')
                $entryStream = $entry.Open()
                try {
                    $bytes = [Text.Encoding]::UTF8.GetBytes($archiveCase.content)
                    $entryStream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $entryStream.Dispose()
                }
            } finally {
                $zip.Dispose()
            }
        } finally {
            $archiveStream.Dispose()
        }
    }
    Assert-LeanTTYReleasePackageExcludesAcceptanceMarkers -PackagePath $safeHap
    Assert-Throws -Action {
        Assert-LeanTTYReleasePackageExcludesAcceptanceMarkers -PackagePath $unsafeHap
    } -Message 'Release package policy accepted an acceptance-only marker'

    $candidateBase = Join-Path $testRoot 'candidates'
    $latestSource = $null
    for ($index = 1; $index -le 7; $index++) {
        $source = Join-Path $testRoot "candidate-$index.hap"
        [IO.File]::WriteAllText(
            $source,
            "candidate-$index",
            [Text.UTF8Encoding]::new($false)
        )
        Save-LeanTTYVerifiedCandidate `
            -RepoRoot $repoRoot `
            -HapPath $source `
            -VerificationMode 'software' `
            -CandidateBasePath $candidateBase | Out-Null
        $latestSource = $source
        Start-Sleep -Milliseconds 10
    }

    $candidateRoot = Get-LeanTTYCandidateRoot `
        -RepoRoot $repoRoot `
        -CandidateBasePath $candidateBase
    $candidateDirectories = @(
        Get-ChildItem -LiteralPath $candidateRoot -Directory |
            Where-Object { $_.Name -match '^[0-9a-f]{64}$' }
    )
    Assert-True ($candidateDirectories.Count -eq 5) (
        "Expected exactly 5 retained candidates, found $($candidateDirectories.Count)"
    )

    $latestCandidate = Get-LeanTTYLatestVerifiedCandidate `
        -RepoRoot $repoRoot `
        -CandidateBasePath $candidateBase
    Assert-True ($null -ne $latestCandidate) 'Latest candidate was not returned'
    Assert-True (
        (Get-FileHash -LiteralPath $latestCandidate.hapPath -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $latestSource -Algorithm SHA256).Hash
    ) 'Latest candidate does not match the newest verified package'

    $behaviorEvidence = Join-Path $testRoot 'device-key-passphrase.json'
    [IO.File]::WriteAllText(
        $behaviorEvidence,
        '{"schemaVersion":1,"scenario":"ssh-keygen-passphrase","result":"passed"}',
        [Text.UTF8Encoding]::new($false)
    )
    Save-LeanTTYVerifiedCandidate `
        -RepoRoot $repoRoot `
        -HapPath $latestCandidate.hapPath `
        -VerificationMode 'device-behavior' `
        -EvidencePaths @($behaviorEvidence) `
        -CandidateBasePath $candidateBase | Out-Null
    $behaviorCandidate = Get-LeanTTYLatestVerifiedCandidate `
        -RepoRoot $repoRoot `
        -CandidateBasePath $candidateBase
    Assert-True ($behaviorCandidate.verificationMode -eq 'device-behavior') (
        'Device behavior evidence did not promote the retained candidate'
    )
    Assert-True ($behaviorCandidate.evidenceFiles.Count -eq 1) (
        'Device behavior evidence was not retained with the candidate'
    )
    Save-LeanTTYVerifiedCandidate `
        -RepoRoot $repoRoot `
        -HapPath $latestCandidate.hapPath `
        -VerificationMode 'software' `
        -CandidateBasePath $candidateBase | Out-Null
    $nonDowngradedCandidate = Get-LeanTTYLatestVerifiedCandidate `
        -RepoRoot $repoRoot `
        -CandidateBasePath $candidateBase
    Assert-True ($nonDowngradedCandidate.verificationMode -eq 'device-behavior') (
        'A later software-only save downgraded device behavior evidence'
    )

    $legacyManifestPath = Join-Path $candidateDirectories[0].FullName 'manifest.json'
    $legacyManifest = Get-Content -LiteralPath $legacyManifestPath -Raw | ConvertFrom-Json
    $legacyManifest.schemaVersion = 1
    $legacyManifest.verificationMode = 'device'
    $legacyManifest.PSObject.Properties.Remove('evidenceFiles')
    [IO.File]::WriteAllText(
        $legacyManifestPath,
        (ConvertTo-Json -InputObject $legacyManifest -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
    $legacyRecord = @(Get-LeanTTYCandidateRecords -CandidateRoot $candidateRoot |
        Where-Object { $_.manifestPath -eq $legacyManifestPath })
    Assert-True ($legacyRecord.Count -eq 1 -and
        $legacyRecord[0].verificationMode -eq 'device-deployed') (
        'Legacy device candidate mode was not normalized to device-deployed'
    )

    $wslScript = Join-Path $PSScriptRoot 'rust-wsl.ps1'
    . $wslScript
    Assert-True (
        (ConvertTo-LeanTTYWslPath -WindowsPath 'C:\src\project') -eq '/mnt/c/src/project'
    ) 'WSL repository path conversion is incorrect'
    Assert-True (
        (ConvertTo-LeanTTYWslPath -WindowsPath 'D:\SDK\native sysroot') -eq
        '/mnt/d/SDK/native sysroot'
    ) 'WSL path conversion did not preserve spaces'

    $devBuildText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'dev-build.ps1'
    ) -Raw
    Assert-True (
        $devBuildText.Contains('Invoke-WithLeanTTYBuildLock')
    ) 'dev-build.ps1 is not protected by the repository build lock'

    $verifyPcText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'verify-pc.ps1'
    ) -Raw
    Assert-True (
        $verifyPcText.Contains('[IO.Path]::GetTempPath()') -and
        -not $verifyPcText.Contains("Join-Path `$repoRoot 'build\verification'")
    ) 'verify-pc evidence would be deleted by its own clean build'

    $buildAllText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'build-all.ps1'
    ) -Raw
    Assert-True (
        $buildAllText.Contains('Assert-LeanTTYReleasePackageExcludesAcceptanceMarkers') -and
        $buildAllText.Contains("if (`$BuildMode -eq 'release')") -and
        $buildAllText.Contains('Invoke-WithLeanTTYAcceptanceSource')
    ) 'Formal release build does not reject acceptance-only package markers'
    Assert-True (
        Test-Path -LiteralPath (Join-Path $PSScriptRoot 'test-acceptance-harness.ps1') -PathType Leaf
    ) 'Focused acceptance-harness regression command is missing'

    $workerPath = Join-Path $testRoot 'lock-worker.ps1'
    $workerSource = @'
param(
    [Parameter(Mandatory = $true)][string]$BuildLockScript,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$AcquiredPath,
    [string]$ReleasePath
)
$ErrorActionPreference = 'Stop'
. $BuildLockScript
Invoke-WithLeanTTYBuildLock -RepoRoot $RepoRoot -Operation 'workflow-test' -Action {
    [IO.File]::WriteAllText($AcquiredPath, (Get-Date).ToString('o'))
    if ($ReleasePath) {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $ReleasePath)) {
            if ($stopwatch.Elapsed.TotalSeconds -ge 5) {
                throw "Timed out waiting for release signal: $ReleasePath"
            }
            Start-Sleep -Milliseconds 50
        }
    }
}
'@
    [IO.File]::WriteAllText(
        $workerPath,
        $workerSource,
        [Text.UTF8Encoding]::new($false)
    )

    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $firstAcquired = Join-Path $testRoot 'first-acquired'
    $secondAcquired = Join-Path $testRoot 'second-acquired'
    $releaseFirst = Join-Path $testRoot 'release-first'
    $firstProcess = Start-Process -FilePath $pwsh -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile',
        '-File', $workerPath,
        '-BuildLockScript', (Join-Path $PSScriptRoot 'build-lock.ps1'),
        '-RepoRoot', $repoRoot,
        '-AcquiredPath', $firstAcquired,
        '-ReleasePath', $releaseFirst
    )
    Wait-ForPath -Path $firstAcquired

    $secondProcess = Start-Process -FilePath $pwsh -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile',
        '-File', $workerPath,
        '-BuildLockScript', (Join-Path $PSScriptRoot 'build-lock.ps1'),
        '-RepoRoot', $repoRoot,
        '-AcquiredPath', $secondAcquired
    )
    Start-Sleep -Milliseconds 500
    Assert-True (-not (Test-Path -LiteralPath $secondAcquired)) (
        'Second build writer acquired the lock while the first still held it'
    )

    [IO.File]::WriteAllText($releaseFirst, 'release')
    Wait-ForPath -Path $secondAcquired
    [void]$firstProcess.WaitForExit(5000)
    [void]$secondProcess.WaitForExit(5000)
    Assert-True ($firstProcess.ExitCode -eq 0) 'First build-lock worker failed'
    Assert-True ($secondProcess.ExitCode -eq 0) 'Second build-lock worker failed'

    Write-Host 'Build workflow regression tests passed.' -ForegroundColor Green
} finally {
    $testRootFull = [IO.Path]::GetFullPath($testRoot)
    if ($testRootFull.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $testRootFull)) {
        Remove-Item -LiteralPath $testRootFull -Recurse -Force
    }
}
