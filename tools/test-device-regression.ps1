param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'device-regression.ps1')

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$layout = @'
{
  "attributes": {"bounds":"[0,0][3120,2080]","text":"","originalText":"","hint":""},
  "children": [
    {
      "attributes": {
        "bounds":"[120,130][3000,1980]",
        "text":"ssh-keygen -p -f regression_key",
        "originalText":"ssh-keygen -p -f regression_key",
        "hint":"Terminal input"
      },
      "children": []
    },
    {
      "attributes": {
        "bounds":"[1900,1200][2200,1300]",
        "text":"Delete key",
        "originalText":"Delete key",
        "hint":""
      },
      "children": []
    }
  ]
}
'@ | ConvertFrom-Json -Depth 20

Assert-True (
    (Get-LeanTTYTerminalInputText -Layout $layout) -eq 'ssh-keygen -p -f regression_key'
) 'Terminal input text was not read from the accessibility layout'

$center = Get-LeanTTYBoundsCenter -Bounds '[1900,1200][2200,1300]'
Assert-True ($center.x -eq 2050 -and $center.y -eq 1250) (
    'Native-layout button coordinates were not calculated correctly'
)

Assert-LeanTTYLayoutExcludesValues -Layout $layout -Values @('runtime-only-secret')
Assert-Throws -Action {
    Assert-LeanTTYLayoutExcludesValues -Layout $layout -Values @('regression_key')
} -Message 'Layout secret detection did not reject an exposed value'

Assert-Throws -Action {
    Get-LeanTTYBoundsCenter -Bounds '[0,0][bad,20]'
} -Message 'Malformed device bounds were accepted'

$appLogParameters = (Get-Command Get-LeanTTYAppLogs).Parameters.Keys
$waitLogParameters = (Get-Command Wait-LeanTTYAppLog).Parameters.Keys
Assert-True (
    $appLogParameters -notcontains 'Pid' -and
    $waitLogParameters -notcontains 'Pid'
) 'Device log helpers conflict with the read-only PowerShell PID automatic variable'

$deviceRegressionText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'device-regression.ps1'
) -Raw
Assert-True (
    $deviceRegressionText -notmatch 'hilog\s+-x[^\r\n]*\s-z\s'
) 'Device log query combines mutually exclusive hilog exit and tail modes'

foreach ($scriptName in @('device-regression.ps1', 'verify-key-passphrase-pc.ps1')) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Device regression script is missing: $scriptName"
    }
    $content = Get-Content -LiteralPath $scriptPath -Raw
    Assert-True ($content -notmatch '3QC[0-9A-Z]{8,}') (
        "$scriptName contains a fixed physical device identifier"
    )
    if ($scriptName -eq 'verify-key-passphrase-pc.ps1') {
        Assert-True (
            $content.Contains('Device behavior harness requires a clean committed tree') -and
            $content.Contains('harness = [ordered]@{')
        ) 'Device behavior evidence is not bound to a clean committed harness'
    }
}

Write-Host 'Device regression helper tests passed.' -ForegroundColor Green
