<#
.SYNOPSIS
  Run the complete LeanTTY formal-release software regression gate.
.DESCRIPTION
  Runs source policy, script workflow, Web terminal, trusted ArkTS and WSL Rust
  checks, then writes a machine-readable local evidence record. This gate does
  not build, sign, install or claim physical-device behavior. Routine feature
  iterations and bug fixes use only their mapped focused checks and quick main
  path instead of this complete suite.
#>
[CmdletBinding()]
param(
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'rust-wsl.ps1')

$startedAt = [DateTimeOffset]::UtcNow
$script:regressionResults = [Collections.Generic.List[object]]::new()
$script:regressionDetail = ''

if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $evidenceDirectory = Join-Path $repoRoot 'build\verification'
    $evidenceName = 'software-' + $startedAt.ToString('yyyyMMddTHHmmssfffZ') + '.json'
    $EvidencePath = Join-Path $evidenceDirectory $evidenceName
} else {
    $EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
    $evidenceDirectory = Split-Path $EvidencePath -Parent
}
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

function Get-GitValue {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& git -C $repoRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
        throw "Git identity query failed: git $($Arguments -join ' ')"
    }
    return [string]$output[0]
}

function Write-RegressionEvidence {
    param([string]$Failure = '')

    $status = @(git -C $repoRoot status --porcelain --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to record regression Git status' }
    $evidence = [ordered]@{
        schemaVersion = 1
        gate = 'software'
        result = $(if ([string]::IsNullOrWhiteSpace($Failure)) { 'passed' } else { 'failed' })
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        git = [ordered]@{
            commit = Get-GitValue -Arguments @('rev-parse', 'HEAD')
            tree = Get-GitValue -Arguments @('rev-parse', 'HEAD^{tree}')
            dirty = ($status.Count -gt 0)
        }
        checks = @($script:regressionResults)
        failure = $Failure
    }
    [IO.File]::WriteAllText(
        $EvidencePath,
        (ConvertTo-Json -InputObject $evidence -Depth 6),
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-RegressionCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $checkStartedAt = [DateTimeOffset]::UtcNow
    $script:regressionDetail = ''
    Write-Host "[regression] $Name" -ForegroundColor Cyan
    try {
        & $Action
        $script:regressionResults.Add([pscustomobject]@{
            name = $Name
            result = 'passed'
            durationMs = [int]([DateTimeOffset]::UtcNow - $checkStartedAt).TotalMilliseconds
            detail = $script:regressionDetail
        })
    } catch {
        $message = $_.Exception.Message
        $script:regressionResults.Add([pscustomobject]@{
            name = $Name
            result = 'failed'
            durationMs = [int]([DateTimeOffset]::UtcNow - $checkStartedAt).TotalMilliseconds
            detail = $message
        })
        Write-RegressionEvidence -Failure "$Name`: $message"
        throw
    }
}

Invoke-RegressionCheck -Name 'public-source-policy' -Action {
    & (Join-Path $PSScriptRoot 'check-public-source.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Public-source policy check failed' }
}

Invoke-RegressionCheck -Name 'build-workflow-regressions' -Action {
    & (Join-Path $PSScriptRoot 'test-build-workflows.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build workflow regression tests failed' }
}

Invoke-RegressionCheck -Name 'device-regression-helpers' -Action {
    & (Join-Path $PSScriptRoot 'test-device-regression.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Device regression helper tests failed' }
}

Invoke-RegressionCheck -Name 'ssh-transport-order' -Action {
    & (Join-Path $PSScriptRoot 'check-ssh-transport-flow.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'SSH transport ordering check failed' }
}

Invoke-RegressionCheck -Name 'ssh-keygen-async-flow' -Action {
    & (Join-Path $PSScriptRoot 'check-keygen-async-flow.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'SSH key-generation async flow check failed' }
}

$script:devecoPath = ''
$script:nodePath = ''
$script:hvigorPath = ''
$script:ohpmPath = ''
Invoke-RegressionCheck -Name 'deveco-environment' -Action {
    $resolvedDeveco = $env:DEVECO_HOME
    if (-not $resolvedDeveco) {
        foreach ($candidate in @(
                'C:\Program Files\Huawei\DevEco Studio',
                'D:\Program Files\Huawei\DevEco Studio'
            )) {
            if (Test-Path -LiteralPath $candidate) { $resolvedDeveco = $candidate; break }
        }
    }
    if (-not $resolvedDeveco) { throw 'DevEco Studio not found. Set DEVECO_HOME.' }
    $resolvedNode = Join-Path $resolvedDeveco 'tools\node\node.exe'
    $resolvedHvigor = Join-Path $resolvedDeveco 'tools\hvigor\bin\hvigorw.js'
    $resolvedOhpm = Join-Path $resolvedDeveco 'tools\ohpm\bin\ohpm.bat'
    foreach ($requiredTool in @($resolvedNode, $resolvedHvigor, $resolvedOhpm)) {
        if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
            throw "DevEco tool is missing: $requiredTool"
        }
    }
    $script:devecoPath = $resolvedDeveco
    $script:nodePath = $resolvedNode
    $script:hvigorPath = $resolvedHvigor
    $script:ohpmPath = $resolvedOhpm
}
$deveco = $script:devecoPath
$nodeExe = $script:nodePath
$hvigorJs = $script:hvigorPath
$ohpm = $script:ohpmPath
$env:NODE_OPTIONS = ''
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:JAVA_HOME = Join-Path $deveco 'jbr'
$env:PATH = (Join-Path $deveco 'jbr\bin') + ';' + $env:PATH

$hypiumPath = Join-Path $repoRoot 'oh_modules\@ohos\hypium'
if (-not (Test-Path -LiteralPath $hypiumPath)) {
    Invoke-RegressionCheck -Name 'ohpm-lockfile-restore' -Action {
        Push-Location $repoRoot
        try {
            & $ohpm install --all --lockfile_stable_order
            if ($LASTEXITCODE -ne 0) { throw 'OHPM dependency restore failed' }
        } finally {
            Pop-Location
        }
        if (-not (Test-Path -LiteralPath $hypiumPath)) {
            throw 'Hypium dependency is still missing after OHPM restore'
        }
    }
}

Invoke-RegressionCheck -Name 'web-terminal-policy' -Action {
    & $nodeExe (Join-Path $repoRoot 'tools\web-terminal\test-terminal-policy.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Web terminal policy tests failed' }
}

Invoke-RegressionCheck -Name 'trusted-arkts-tests' -Action {
    Push-Location $repoRoot
    try {
        $arkTsTestStartedAt = Get-Date
        & $nodeExe $hvigorJs --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) { throw 'Trusted ArkTS unit tests failed' }
    } finally {
        Pop-Location
    }
    $resultPath = Join-Path $repoRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "Trusted ArkTS unit test result not found: $resultPath"
    }
    if ((Get-Item -LiteralPath $resultPath).LastWriteTime -lt $arkTsTestStartedAt.AddSeconds(-1)) {
        throw 'Trusted ArkTS unit test result was not refreshed by the current run'
    }
    $summary = Get-Content -LiteralPath $resultPath -Raw
    $summaryMatch = [regex]::Match(
        $summary,
        '(?m)^Tests run: (?<run>\d+), Failure: (?<failure>\d+), Error: (?<error>\d+), Pass: (?<pass>\d+), Ignore: (?<ignore>\d+)\s*$'
    )
    if (-not $summaryMatch.Success) { throw 'Trusted ArkTS unit test summary is missing or malformed' }
    if ([int]$summaryMatch.Groups['failure'].Value -ne 0 -or
        [int]$summaryMatch.Groups['error'].Value -ne 0) {
        throw ('Trusted ArkTS unit tests failed: ' + $summaryMatch.Value.Trim())
    }
    $script:regressionDetail = $summaryMatch.Value.Trim()
}

Invoke-RegressionCheck -Name 'rust-format-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'fmt', '--manifest-path', './leantty_ssh/Cargo.toml', '--all', '--', '--check'
    )
}

Invoke-RegressionCheck -Name 'rust-clippy-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'clippy', '--locked', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty-ssh-core', '--all-targets', '--', '-D', 'warnings'
    )
}

Invoke-RegressionCheck -Name 'rust-native-clippy-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'clippy', '--locked', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty_ssh', '--all-targets', '--', '-D', 'warnings'
    )
}

Invoke-RegressionCheck -Name 'rust-native-test-isolation-wsl' -Action {
    $wslRepoRoot = ConvertTo-LeanTTYWslPath -WindowsPath $repoRoot
    $wslPrefix = Get-LeanTTYWslPrefix
    $treeOutput = @(
        & wsl.exe @wslPrefix --cd $wslRepoRoot -- env RUSTUP_TOOLCHAIN=stable cargo tree `
            --locked --offline --manifest-path ./leantty_ssh/Cargo.toml -p leantty_ssh `
            -e normal,build -f '{p} {f}' 2>&1
    )
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the production Rust feature tree' }
    $productionNapiLines = @($treeOutput | Where-Object { $_ -match 'napi-(ohos|sys-ohos)' })
    if ($productionNapiLines.Count -eq 0) { throw 'Production N-API feature tree is missing' }
    if (($productionNapiLines -join "`n") -match '(dyn-symbols|noop)') {
        throw 'Test-only N-API symbol features leaked into the production dependency tree'
    }
    $script:regressionDetail = 'production N-API tree excludes dyn-symbols and noop'
}

Invoke-RegressionCheck -Name 'rust-native-tests-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'test', '--locked', '--offline', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty_ssh'
    )
}

Invoke-RegressionCheck -Name 'rust-core-tests-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'test', '--locked', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty-ssh-core'
    )
}

Invoke-RegressionCheck -Name 'ssh-auth-fixture-tests-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'test', '--locked', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty-ssh-auth-fixture'
    )
}

Invoke-RegressionCheck -Name 'ssh-auth-fixture-clippy-wsl' -Action {
    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -CargoArguments @(
        'clippy', '--locked', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty-ssh-auth-fixture', '--all-targets', '--', '-D', 'warnings'
    )
}

Invoke-RegressionCheck -Name 'ssh-auth-fixture-e2e-wsl' -Action {
    $wslRepoRoot = ConvertTo-LeanTTYWslPath -WindowsPath $repoRoot
    $wslPrefix = Get-LeanTTYWslPrefix
    & wsl.exe @wslPrefix --cd $wslRepoRoot -- env RUSTUP_TOOLCHAIN=stable bash ./leantty_ssh/ssh-auth-fixture/test-e2e.sh
    if ($LASTEXITCODE -ne 0) { throw 'SSH authentication fixture end-to-end tests failed' }
}

Invoke-RegressionCheck -Name 'git-diff-check' -Action {
    & git -C $repoRoot diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Unstaged diff check failed' }
    & git -C $repoRoot diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'Staged diff check failed' }
}

Write-RegressionEvidence
Write-Host "SOFTWARE REGRESSION SUCCESS: $EvidencePath" -ForegroundColor Green
