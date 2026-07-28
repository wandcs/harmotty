function Get-LeanTTYHashIdentity {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
    } finally {
        $sha256.Dispose()
    }
    return ([BitConverter]::ToString($digest).Replace('-', '')).ToLowerInvariant()
}

function Get-LeanTTYCandidateRoot {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$CandidateBasePath = ''
    )

    $commonDirectoryOutput = @(
        & git -C $RepoRoot rev-parse --git-common-dir 2>&1
    )
    if ($LASTEXITCODE -ne 0 -or $commonDirectoryOutput.Count -ne 1) {
        throw 'Unable to resolve the Git common directory for candidate storage'
    }
    $commonDirectory = [string]$commonDirectoryOutput[0]
    if (-not [IO.Path]::IsPathRooted($commonDirectory)) {
        $commonDirectory = Join-Path $RepoRoot $commonDirectory
    }
    $repositoryIdentity = Get-LeanTTYHashIdentity -Value (
        [IO.Path]::GetFullPath($commonDirectory).TrimEnd('\').ToUpperInvariant()
    )

    if ([string]::IsNullOrWhiteSpace($CandidateBasePath)) {
        $localAppData = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::LocalApplicationData
        )
        if ([string]::IsNullOrWhiteSpace($localAppData)) {
            throw 'Local application data directory is unavailable'
        }
        $CandidateBasePath = Join-Path $localAppData 'LeanTTY\verified-candidates'
    }

    return Join-Path ([IO.Path]::GetFullPath($CandidateBasePath)) $repositoryIdentity
}

function Get-LeanTTYCandidateRecords {
    param([Parameter(Mandatory = $true)][string]$CandidateRoot)

    if (-not (Test-Path -LiteralPath $CandidateRoot -PathType Container)) {
        return @()
    }

    $records = @()
    foreach ($directory in @(
        Get-ChildItem -LiteralPath $CandidateRoot -Directory |
            Where-Object { $_.Name -match '^[0-9a-f]{64}$' }
    )) {
        $manifestPath = Join-Path $directory.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Candidate manifest is missing: $manifestPath"
        }
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json
            if ([int]$manifest.schemaVersion -ne 1) {
                throw 'Unsupported schema version'
            }
            $manifestHash = [string]$manifest.sha256
            if ($manifestHash -notmatch '^[0-9a-f]{64}$' -or
                $manifestHash -ne $directory.Name) {
                throw 'Candidate hash identity mismatch'
            }
            $hapFile = [string]$manifest.hapFile
            if ($hapFile -ne 'LeanTTY-test-signed.hap') {
                throw 'Unexpected candidate HAP name'
            }
            $verificationMode = [string]$manifest.verificationMode
            if ($verificationMode -notin @('software', 'device')) {
                throw 'Unexpected candidate verification mode'
            }
            $verifiedAtValue = $manifest.verifiedAt
            if ($verifiedAtValue -is [DateTimeOffset]) {
                $verifiedAt = $verifiedAtValue
            } elseif ($verifiedAtValue -is [DateTime]) {
                $verifiedAt = [DateTimeOffset]::new($verifiedAtValue)
            } else {
                $verifiedAt = [DateTimeOffset]::Parse(
                    [string]$verifiedAtValue,
                    [Globalization.CultureInfo]::InvariantCulture
                )
            }
        } catch {
            throw "Candidate manifest is invalid: $manifestPath"
        }
        $records += [pscustomobject]@{
            directory = $directory.FullName
            manifestPath = $manifestPath
            hapPath = Assert-LeanTTYCandidatePath `
                -CandidateRoot $CandidateRoot `
                -Path (Join-Path $directory.FullName $hapFile)
            sha256 = $manifestHash
            verifiedAt = $verifiedAt
            verificationMode = $verificationMode
            gitCommit = [string]$manifest.git.commit
            gitTree = [string]$manifest.git.tree
            gitDirty = [bool]$manifest.git.dirty
        }
    }

    return @(
        $records | Sort-Object `
            @{ Expression = 'verifiedAt'; Descending = $true },
            @{ Expression = 'sha256'; Descending = $true }
    )
}

function Assert-LeanTTYCandidatePath {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootPrefix = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Candidate path is outside the managed root: $fullPath"
    }
    return $fullPath
}

function Save-LeanTTYVerifiedCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$HapPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('software', 'device')]
        [string]$VerificationMode,
        [string]$CandidateBasePath = ''
    )

    $sourceHap = [IO.Path]::GetFullPath($HapPath)
    if (-not (Test-Path -LiteralPath $sourceHap -PathType Leaf)) {
        throw "Verified candidate HAP is missing: $sourceHap"
    }
    if ([IO.Path]::GetExtension($sourceHap) -ne '.hap' -or
        (Split-Path $sourceHap -Leaf) -match '(?i)unsigned') {
        throw "Verified candidate must be a signed HAP: $sourceHap"
    }

    $candidateRoot = Get-LeanTTYCandidateRoot `
        -RepoRoot $RepoRoot `
        -CandidateBasePath $CandidateBasePath
    New-Item -ItemType Directory -Path $candidateRoot -Force | Out-Null

    $hapHash = (
        Get-FileHash -LiteralPath $sourceHap -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $candidateDirectory = Assert-LeanTTYCandidatePath `
        -CandidateRoot $candidateRoot `
        -Path (Join-Path $candidateRoot $hapHash)
    $candidateHapName = 'LeanTTY-test-signed.hap'
    $candidateHap = Join-Path $candidateDirectory $candidateHapName
    $manifestPath = Join-Path $candidateDirectory 'manifest.json'

    $gitCommit = (& git -C $RepoRoot rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve candidate Git commit' }
    $gitTree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}' 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve candidate Git tree' }
    $gitStatus = @(git -C $RepoRoot status --porcelain --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve candidate Git dirty state' }

    $manifest = [ordered]@{
        schemaVersion = 1
        verifiedAt = [DateTimeOffset]::UtcNow.ToString('o')
        verificationMode = $VerificationMode
        hapFile = $candidateHapName
        sha256 = $hapHash
        size = (Get-Item -LiteralPath $sourceHap).Length
        git = [ordered]@{
            commit = $gitCommit
            tree = $gitTree
            dirty = ($gitStatus.Count -gt 0)
        }
    }

    $temporaryDirectory = Assert-LeanTTYCandidatePath `
        -CandidateRoot $candidateRoot `
        -Path (Join-Path $candidateRoot ('.tmp-' + [Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    try {
        $temporaryHap = Join-Path $temporaryDirectory $candidateHapName
        $temporaryManifest = Join-Path $temporaryDirectory 'manifest.json'
        Copy-Item -LiteralPath $sourceHap -Destination $temporaryHap
        [IO.File]::WriteAllText(
            $temporaryManifest,
            (ConvertTo-Json -InputObject $manifest -Depth 4),
            [Text.UTF8Encoding]::new($false)
        )

        if (Test-Path -LiteralPath $candidateDirectory -PathType Container) {
            Copy-Item -LiteralPath $temporaryHap -Destination $candidateHap -Force
            Copy-Item -LiteralPath $temporaryManifest -Destination $manifestPath -Force
        } else {
            Move-Item -LiteralPath $temporaryDirectory -Destination $candidateDirectory
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        }
    }
    [IO.Directory]::SetLastWriteTimeUtc($candidateDirectory, [DateTime]::UtcNow)

    $records = @(Get-LeanTTYCandidateRecords -CandidateRoot $candidateRoot)
    foreach ($expiredCandidate in @($records | Select-Object -Skip 5)) {
        $expiredPath = Assert-LeanTTYCandidatePath `
            -CandidateRoot $candidateRoot `
            -Path $expiredCandidate.directory
        Remove-Item -LiteralPath $expiredPath -Recurse -Force
    }

    return Get-LeanTTYLatestVerifiedCandidate `
        -RepoRoot $RepoRoot `
        -CandidateBasePath $CandidateBasePath
}

function Get-LeanTTYLatestVerifiedCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$CandidateBasePath = ''
    )

    $candidateRoot = Get-LeanTTYCandidateRoot `
        -RepoRoot $RepoRoot `
        -CandidateBasePath $CandidateBasePath
    $latest = @(
        Get-LeanTTYCandidateRecords -CandidateRoot $candidateRoot
    ) | Select-Object -First 1
    if ($null -eq $latest) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $latest.hapPath -PathType Leaf)) {
        throw "Candidate HAP is missing: $($latest.hapPath)"
    }
    $actualHash = (
        Get-FileHash -LiteralPath $latest.hapPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($actualHash -ne $latest.sha256) {
        throw "Candidate HAP hash mismatch: $($latest.hapPath)"
    }
    return $latest
}
