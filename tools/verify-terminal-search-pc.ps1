<#
.SYNOPSIS
  Verify named terminal-search behavior on a physical HarmonyOS PC.
.DESCRIPTION
  Installs one explicit signed diagnostic HAP, drives the production
  Ctrl+Alt+F search route, and records candidate, harness, device, layout,
  screenshot, timing, failure-domain, and cleanup evidence.
#>
[CmdletBinding()]
param(
    [string]$Target = '',
    [Parameter(Mandatory = $true)][string]$HapPath,
    [string]$EvidenceDirectory = '',
    [string]$UnlockPasswordPath = '',
    [ValidateSet('open-close-focus', 'ascii-query-navigation')]
    [string[]]$Only = @('open-close-focus')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'hdc-common.ps1')
. (Join-Path $PSScriptRoot 'device-regression.ps1')

$harnessStatus = @(git -C $repoRoot status --porcelain --untracked-files=all 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect terminal-search harness source state' }
if ($harnessStatus.Count -gt 0) {
    throw 'Terminal-search device harness requires a clean committed tree'
}
$harnessCommit = (& git -C $repoRoot rev-parse HEAD 2>&1).Trim()
$harnessTree = (& git -C $repoRoot rev-parse 'HEAD^{tree}' 2>&1).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve terminal-search harness identity' }

$HapPath = [IO.Path]::GetFullPath($HapPath)
if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) {
    throw "Diagnostic HAP is missing: $HapPath"
}
if ((Split-Path $HapPath -Leaf) -match 'unsigned') {
    throw 'Terminal-search device verification requires a signed HAP'
}
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path ([IO.Path]::GetTempPath()) (
        'LeanTTY-terminal-search-' + [Guid]::NewGuid().ToString('N')
    )
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$hdc = Resolve-Hdc
$Target = Resolve-LeanTTYRegressionTarget -Hdc $hdc -Target $Target
if ([string]::IsNullOrWhiteSpace($UnlockPasswordPath)) {
    $UnlockPasswordPath = Get-LeanTTYDeviceUnlockPasswordPath
}
Assert-LeanTTYCredentialPathOutsideRepository `
    -CredentialPath $UnlockPasswordPath `
    -RepositoryRoot $repoRoot

$startedAt = [DateTimeOffset]::UtcNow
$attemptId = [Guid]::NewGuid().ToString('N')
$checks = [Collections.Generic.List[object]]::new()
$failure = ''
$failureDomain = 'none'
$cleanupFailure = ''
$awakeLeaseAcquired = $false
$searchClosed = $false
$appPid = ''
$deviceUnlockResult = ''
$deviceModel = ''
$deviceAbi = ''
$deviceTransport = ''
$hapHash = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hapLength = (Get-Item -LiteralPath $HapPath).Length

function Get-TerminalSearchInputNodes {
    param([Parameter(Mandatory = $true)]$Layout)
    return @(Get-LeanTTYLayoutNodes -Node $Layout | Where-Object {
        [string]$_.attributes.type -eq 'textField' -and
        [string]$_.attributes.hint -match '^Search text' -and
        [string]$_.attributes.visible -eq 'true'
    })
}

function Get-TerminalSearchResultNodes {
    param([Parameter(Mandatory = $true)]$Layout)
    return @(Get-LeanTTYLayoutNodes -Node $Layout | Where-Object {
        [string]$_.attributes.visible -eq 'true' -and
        ([string]$_.attributes.text -match '^(?:No results|[1-9][0-9]*/[1-9][0-9]*)$' -or
            [string]$_.attributes.originalText -match '^(?:No results|[1-9][0-9]*/[1-9][0-9]*)$')
    })
}

function Get-TerminalSearchResultLabel {
    param([Parameter(Mandatory = $true)]$Layout)
    $nodes = @(Get-TerminalSearchResultNodes -Layout $Layout)
    if ($nodes.Count -ne 1) { return '' }
    $text = [string]$nodes[0].attributes.text
    if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    return [string]$nodes[0].attributes.originalText
}

function Wait-TerminalSearchQueryState {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExpectedQuery,
        [Parameter(Mandatory = $true)][string]$LayoutName,
        [string]$ExpectedResultPattern = '',
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 15
    )
    $path = Join-Path $EvidenceDirectory $LayoutName
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        $layout = Get-LeanTTYDeviceLayout -Hdc $hdc -Target $Target -LocalPath $path
        $searchInputs = @(Get-TerminalSearchInputNodes -Layout $layout)
        if ($searchInputs.Count -eq 1 -and
            [string]$searchInputs[0].attributes.focused -eq 'true') {
            $query = [string]$searchInputs[0].attributes.text
            if ([string]::IsNullOrEmpty($query)) {
                $query = [string]$searchInputs[0].attributes.originalText
            }
            $label = Get-TerminalSearchResultLabel -Layout $layout
            if ($query -ceq $ExpectedQuery -and
                ([string]::IsNullOrEmpty($ExpectedResultPattern) -or
                    $label -match $ExpectedResultPattern)) {
                return [pscustomobject]@{
                    layout = $layout
                    query = $query
                    resultLabel = $label
                }
            }
        }
        Start-Sleep -Milliseconds 200
    } while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw (
        "Timed out waiting for terminal search query '$ExpectedQuery'" +
        $(if ($ExpectedResultPattern) { " and result '$ExpectedResultPattern'" } else { '' })
    )
}

function ConvertFrom-TerminalSearchResultLabel {
    param([Parameter(Mandatory = $true)][string]$Label)
    if ($Label -notmatch '^(?<index>[1-9][0-9]*)/(?<count>[1-9][0-9]*)$') {
        throw "Terminal search result label is not a selected match: $Label"
    }
    $index = [int]$Matches.index
    $count = [int]$Matches.count
    if ($index -gt $count) { throw "Terminal search result index exceeds its count: $Label" }
    return [pscustomobject]@{ index = $index; count = $count }
}

function Wait-TerminalSearchState {
    param(
        [Parameter(Mandatory = $true)][bool]$Open,
        [Parameter(Mandatory = $true)][string]$LayoutName,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 15
    )
    $path = Join-Path $EvidenceDirectory $LayoutName
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        $layout = Get-LeanTTYDeviceLayout -Hdc $hdc -Target $Target -LocalPath $path
        $searchInputs = @(Get-TerminalSearchInputNodes -Layout $layout)
        if ($Open -and $searchInputs.Count -eq 1 -and
            [string]$searchInputs[0].attributes.focused -eq 'true') {
            return $layout
        }
        if (-not $Open -and $searchInputs.Count -eq 0) {
            $terminalInputs = @(Get-LeanTTYTerminalInputNodes -Layout $layout | Where-Object {
                [string]$_.attributes.focused -eq 'true'
            })
            if ($terminalInputs.Count -eq 1) { return $layout }
        }
        Start-Sleep -Milliseconds 200
    } while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    $state = if ($Open) { 'open and focused' } else { 'closed with terminal focus restored' }
    throw "Timed out waiting for terminal search to be $state"
}

function Invoke-TerminalSearchShortcut {
    & $hdc -t $Target shell 'uitest uiInput keyEvent 2072 2045 2022' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to invoke product Ctrl+Alt+F search shortcut' }
}

function Clear-TerminalSearchQuery {
    & $hdc -t $Target shell 'uitest uiInput keyEvent 2072 2017' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to select the complete terminal search query' }
    Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2055
}

function Invoke-TerminalSearchPrevious {
    & $hdc -t $Target shell 'uitest uiInput keyEvent 2047 2054' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to invoke Shift+Enter in terminal search' }
}

function Save-SearchAppLogs {
    param([Parameter(Mandatory = $true)][string]$FileName)
    if ($appPid -notmatch '^\d+$') { return }
    $logs = Get-LeanTTYAppLogs -Hdc $hdc -Target $Target -ProcessId $appPid
    [IO.File]::WriteAllText(
        (Join-Path $EvidenceDirectory $FileName),
        $logs,
        [Text.UTF8Encoding]::new($false)
    )
}

try {
    $deviceModel = (Invoke-HdcShell $hdc $Target 'param get const.product.model').Trim()
    $deviceAbi = (Invoke-HdcShell $hdc $Target 'param get const.product.cpu.abilist').Trim()
    $deviceTransport = Get-HdcTargetTransport -Hdc $hdc -Target $Target
    if ($deviceTransport -ne 'usb') { throw '[environment] Terminal-search scenario requires USB' }
    if ($deviceAbi -notmatch 'arm64-v8a') {
        throw '[environment] Terminal-search scenario requires an ARM64 HarmonyOS PC'
    }

    Start-LeanTTYDeviceAwakeLease -Hdc $hdc -Target $Target
    $awakeLeaseAcquired = $true
    $installOutput = @(& $hdc -t $Target install -r $HapPath 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $installOutput -match '(?i)\[Fail\]|error') {
        throw "[environment] Diagnostic HAP install failed: $installOutput"
    }
    $start = Start-LeanTTYRegressionApp `
        -Hdc $hdc `
        -Target $Target `
        -CredentialPath $UnlockPasswordPath `
        -RepositoryRoot $repoRoot
    $appPid = [string]$start.processId
    $deviceUnlockResult = [string]$start.unlock

    $layout = Wait-LeanTTYTerminalInputLayout `
        -Hdc $hdc `
        -Target $Target `
        -LocalPath (Join-Path $EvidenceDirectory 'layout-ready.json')
    $terminalInputs = @(Get-LeanTTYTerminalInputNodes -Layout $layout)
    $focused = @($terminalInputs | Where-Object { [string]$_.attributes.focused -eq 'true' })
    $terminalInput = if ($focused.Count -eq 1) { $focused[0] } else { $terminalInputs[0] }
    Set-LeanTTYTerminalInputFocus `
        -Hdc $hdc `
        -Target $Target `
        -InputNode $terminalInput `
        -LocalPath (Join-Path $EvidenceDirectory 'layout-terminal-focused.json') | Out-Null

    if ($Only -contains 'open-close-focus') {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
        Invoke-TerminalSearchShortcut
        Wait-TerminalSearchState `
            -Open $true `
            -LayoutName 'layout-search-open.json' | Out-Null
        Save-LeanTTYDeviceScreenshot `
            -Hdc $hdc `
            -Target $Target `
            -LocalPath (Join-Path $EvidenceDirectory 'search-open.png')
        Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2070
        Wait-TerminalSearchState `
            -Open $false `
            -LayoutName 'layout-search-closed.json' | Out-Null
        $searchClosed = $true
        Save-LeanTTYDeviceScreenshot `
            -Hdc $hdc `
            -Target $Target `
            -LocalPath (Join-Path $EvidenceDirectory 'search-closed.png')
        Save-SearchAppLogs -FileName 'app-logs.txt'
        $checks.Add([pscustomobject]@{
            name = 'open-close-focus'
            result = 'passed'
            durationMs = $timer.ElapsedMilliseconds
        })
    }

    if ($Only -contains 'ascii-query-navigation') {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $typedQueries = [Collections.Generic.List[string]]::new()
        $forwardLabels = [Collections.Generic.List[string]]::new()
        $backwardLabels = [Collections.Generic.List[string]]::new()
        Clear-LeanTTYAppLogs -Hdc $hdc -Target $Target
        Invoke-TerminalSearchShortcut
        $searchClosed = $false
        Wait-TerminalSearchState `
            -Open $true `
            -LayoutName 'layout-ascii-search-open.json' | Out-Null

        $query = ''
        foreach ($character in 'ltty'.ToCharArray()) {
            Invoke-LeanTTYDeviceText -Hdc $hdc -Target $Target -Text ([string]$character)
            $query += $character
            $typed = Wait-TerminalSearchQueryState `
                -ExpectedQuery $query `
                -LayoutName ("layout-ascii-query-$($query.Length).json")
            $typedQueries.Add($typed.query)
        }
        $matching = Wait-TerminalSearchQueryState `
            -ExpectedQuery 'ltty' `
            -ExpectedResultPattern '^[1-9][0-9]*/[1-9][0-9]*$' `
            -LayoutName 'layout-ascii-query-match.json'

        Clear-TerminalSearchQuery
        Wait-TerminalSearchQueryState `
            -ExpectedQuery '' `
            -LayoutName 'layout-ascii-query-cleared.json' | Out-Null
        $missingQuery = 'LEANTTY_NO_RESULT_8A6D'
        Invoke-LeanTTYDeviceText -Hdc $hdc -Target $Target -Text $missingQuery
        $missing = Wait-TerminalSearchQueryState `
            -ExpectedQuery $missingQuery `
            -ExpectedResultPattern '^No results$' `
            -LayoutName 'layout-ascii-query-no-results.json'

        Clear-TerminalSearchQuery
        Wait-TerminalSearchQueryState `
            -ExpectedQuery '' `
            -LayoutName 'layout-ascii-navigation-cleared.json' | Out-Null
        Invoke-LeanTTYDeviceText -Hdc $hdc -Target $Target -Text 't'
        $initial = Wait-TerminalSearchQueryState `
            -ExpectedQuery 't' `
            -ExpectedResultPattern '^[1-9][0-9]*/[1-9][0-9]*$' `
            -LayoutName 'layout-ascii-navigation-initial.json'
        $position = ConvertFrom-TerminalSearchResultLabel -Label $initial.resultLabel
        if ($position.count -lt 2) {
            throw '[harness] The fresh terminal did not provide two ASCII navigation matches'
        }

        $expectedIndex = $position.index
        for ($step = 1; $step -le $position.count; $step++) {
            Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2054
            $expectedIndex = ($expectedIndex % $position.count) + 1
            $next = Wait-TerminalSearchQueryState `
                -ExpectedQuery 't' `
                -ExpectedResultPattern "^$expectedIndex/$($position.count)$" `
                -LayoutName ("layout-ascii-next-$step.json")
            $forwardLabels.Add($next.resultLabel)
        }
        if ($expectedIndex -ne $position.index) {
            throw '[harness] Forward terminal search did not wrap to its starting match'
        }

        for ($step = 1; $step -le $position.count; $step++) {
            Invoke-TerminalSearchPrevious
            $expectedIndex = (($expectedIndex - 2 + $position.count) % $position.count) + 1
            $previous = Wait-TerminalSearchQueryState `
                -ExpectedQuery 't' `
                -ExpectedResultPattern "^$expectedIndex/$($position.count)$" `
                -LayoutName ("layout-ascii-previous-$step.json")
            $backwardLabels.Add($previous.resultLabel)
        }
        if ($expectedIndex -ne $position.index) {
            throw '[harness] Backward terminal search did not wrap to its starting match'
        }

        Save-LeanTTYDeviceScreenshot `
            -Hdc $hdc `
            -Target $Target `
            -LocalPath (Join-Path $EvidenceDirectory 'ascii-query-navigation.png')
        Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2070
        Wait-TerminalSearchState `
            -Open $false `
            -LayoutName 'layout-ascii-query-closed.json' | Out-Null
        $searchClosed = $true
        Save-SearchAppLogs -FileName 'ascii-query-navigation-app-logs.txt'
        $checks.Add([pscustomobject]@{
            name = 'ascii-query-navigation'
            result = 'passed'
            durationMs = $timer.ElapsedMilliseconds
            typedQueries = @($typedQueries)
            firstQueryResult = $matching.resultLabel
            noResultLabel = $missing.resultLabel
            navigationQuery = 't'
            navigationMatchCount = $position.count
            forwardLabels = @($forwardLabels)
            backwardLabels = @($backwardLabels)
            wrappedForward = $true
            wrappedBackward = $true
            terminalFocusRestored = $true
        })
    }
} catch {
    $failure = $_.Exception.Message
    $failureDomain = if ($failure -match '^\[environment\]') {
        'environment'
    } elseif ($failure -match '^\[harness\]') {
        'harness'
    } else {
        'product'
    }
    try {
        Save-LeanTTYDeviceScreenshot `
            -Hdc $hdc `
            -Target $Target `
            -LocalPath (Join-Path $EvidenceDirectory 'failure.png')
    } catch {}
    try { Save-SearchAppLogs -FileName 'failure-app-logs.txt' } catch {}
} finally {
    if ($appPid -match '^\d+$' -and -not $searchClosed) {
        try {
            Invoke-LeanTTYDeviceKey -Hdc $hdc -Target $Target -KeyCode 2070
            Wait-TerminalSearchState `
                -Open $false `
                -LayoutName 'layout-cleanup-search-closed.json' `
                -TimeoutSeconds 10 | Out-Null
            $searchClosed = $true
        } catch {
            $cleanupFailure = $_.Exception.Message
        }
    }
    if ($awakeLeaseAcquired) {
        try {
            Stop-LeanTTYDeviceAwakeLease -Hdc $hdc -Target $Target
        } catch {
            if ([string]::IsNullOrWhiteSpace($cleanupFailure)) {
                $cleanupFailure = $_.Exception.Message
            }
        }
    }

    $evidence = [ordered]@{
        schemaVersion = 1
        gate = 'diagnostic'
        scenario = 'terminal-search'
        attemptId = $attemptId
        result = $(if (-not $failure -and -not $cleanupFailure) { 'passed' } else { 'failed' })
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        durationMs = [int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
        candidate = [ordered]@{
            sha256 = $hapHash
            bytes = $hapLength
            provenance = 'explicit-unretained-diagnostic-hap'
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
            unlock = $deviceUnlockResult
        }
        trigger = 'HarmonyOS-uitest-Ctrl-Alt-F-product-route'
        automationBoundary = (
            'HDC system-key injection validates the production event chain but does not ' +
            'satisfy physical-keyboard or Chinese/English IME acceptance.'
        )
        selectedScenarios = @($Only)
        checks = @($checks)
        failureDomain = $failureDomain
        failure = $failure
        cleanup = [ordered]@{
            result = $(if ($cleanupFailure) { 'failed' } else { 'passed' })
            transientSearchClosed = $searchClosed
            awakeLeaseRestored = $awakeLeaseAcquired -and -not $cleanupFailure
            failure = $cleanupFailure
        }
    }
    [IO.File]::WriteAllText(
        (Join-Path $EvidenceDirectory 'device-terminal-search.json'),
        (ConvertTo-Json -InputObject $evidence -Depth 7),
        [Text.UTF8Encoding]::new($false)
    )
}

if ($failure) { throw $failure }
if ($cleanupFailure) { throw "Terminal-search cleanup failed: $cleanupFailure" }
Write-Host (
    'DIAGNOSTIC SUCCESS: terminal-search ' +
    "(scenarios=$($Only -join ','), evidence=$EvidenceDirectory\device-terminal-search.json)"
) -ForegroundColor Green
