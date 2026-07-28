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

    $devBuildText = Get-Content -LiteralPath (
        Join-Path $PSScriptRoot 'dev-build.ps1'
    ) -Raw
    Assert-True (
        $devBuildText.Contains('Invoke-WithLeanTTYBuildLock')
    ) 'dev-build.ps1 is not protected by the repository build lock'

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
