function Get-LeanTTYBuildLockIdentity {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $normalizedRoot = [IO.Path]::GetFullPath($RepoRoot).
        TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).
        ToUpperInvariant()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalizedRoot))
    } finally {
        $sha256.Dispose()
    }
    return ([BitConverter]::ToString($digest).Replace('-', '').Substring(0, 16)).ToLowerInvariant()
}

function Invoke-WithLeanTTYBuildLock {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 1800
    )

    $lockIdentity = Get-LeanTTYBuildLockIdentity -RepoRoot $RepoRoot
    if ($env:LEANTTY_BUILD_LOCK_TOKEN -eq $lockIdentity) {
        & $Action
        return
    }

    $lockDirectory = Join-Path ([IO.Path]::GetTempPath()) 'LeanTTY'
    New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
    $lockPath = Join-Path $lockDirectory "build-$lockIdentity.lock"
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $lockStream = $null
    $lastStatusAt = [TimeSpan]::MinValue

    while ($null -eq $lockStream) {
        try {
            $lockStream = [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::Read
            )
        } catch [IO.IOException] {
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw "Timed out after $TimeoutSeconds seconds waiting for another LeanTTY build or verification task: $lockPath"
            }

            if ($lastStatusAt -eq [TimeSpan]::MinValue -or
                ($stopwatch.Elapsed - $lastStatusAt).TotalSeconds -ge 30) {
                $owner = $null
                try {
                    $reader = [IO.File]::Open(
                        $lockPath,
                        [IO.FileMode]::Open,
                        [IO.FileAccess]::Read,
                        [IO.FileShare]::ReadWrite
                    )
                    try {
                        $textReader = [IO.StreamReader]::new($reader, [Text.UTF8Encoding]::new($false))
                        try {
                            $owner = $textReader.ReadToEnd() | ConvertFrom-Json
                        } finally {
                            $textReader.Dispose()
                        }
                    } finally {
                        $reader.Dispose()
                    }
                } catch {
                    $owner = $null
                }

                if ($null -ne $owner) {
                    Write-Host (
                        "Waiting for LeanTTY task PID $($owner.processId): " +
                        "$($owner.operation) (started $($owner.startedAt))"
                    ) -ForegroundColor Yellow
                } else {
                    Write-Host 'Waiting for another LeanTTY build or verification task...' -ForegroundColor Yellow
                }
                $lastStatusAt = $stopwatch.Elapsed
            }
            Start-Sleep -Milliseconds 250
        }
    }

    $previousToken = $env:LEANTTY_BUILD_LOCK_TOKEN
    try {
        $lockMetadata = [ordered]@{
            processId = $PID
            operation = $Operation
            startedAt = (Get-Date).ToString('o')
            repoRoot = [IO.Path]::GetFullPath($RepoRoot)
        } | ConvertTo-Json -Compress
        $metadataBytes = [Text.UTF8Encoding]::new($false).GetBytes($lockMetadata)
        $lockStream.SetLength(0)
        $lockStream.Write($metadataBytes, 0, $metadataBytes.Length)
        $lockStream.Flush($true)

        $env:LEANTTY_BUILD_LOCK_TOKEN = $lockIdentity
        & $Action
    } finally {
        if ($null -eq $previousToken) {
            Remove-Item Env:LEANTTY_BUILD_LOCK_TOKEN -ErrorAction SilentlyContinue
        } else {
            $env:LEANTTY_BUILD_LOCK_TOKEN = $previousToken
        }
        $lockStream.Dispose()
    }
}
