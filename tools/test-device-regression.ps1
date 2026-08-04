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

$printableAscii = -join (32..126 | ForEach-Object { [char]$_ })
$printableKeyCommand = ConvertTo-LeanTTYDeviceTextKeyCommand -Text $printableAscii
$unexpectedKeyTokens = @($printableKeyCommand -split ' ' | Where-Object {
    $_ -notmatch '^(?:uinput|-K|-d|-u|\d+)$'
})
Assert-True (
    $printableKeyCommand.StartsWith('uinput -K ') -and
    $unexpectedKeyTokens.Count -eq 0 -and
    $printableKeyCommand -notmatch 'uitest|uiInput'
) 'Device text key conversion did not cover the complete printable ASCII range'
Assert-Throws -Action {
    ConvertTo-LeanTTYDeviceTextKeyCommand -Text "line`nbreak"
} -Message 'Device text key conversion accepted non-printable input'

& {
    $script:capturedHdcArgs = @()
    function Invoke-FakeHdc {
        $script:capturedHdcArgs = @($args)
        $global:LASTEXITCODE = 0
    }

    Invoke-LeanTTYDeviceText `
        -Hdc 'Invoke-FakeHdc' `
        -Target 'regression-device' `
        -Text 'echo LEANTTY_SMOKE'
    Assert-True (
        $script:capturedHdcArgs.Count -eq 4 -and
        $script:capturedHdcArgs[0] -eq '-t' -and
        $script:capturedHdcArgs[1] -eq 'regression-device' -and
        $script:capturedHdcArgs[2] -eq 'shell' -and
        $script:capturedHdcArgs[3] -eq (
            ConvertTo-LeanTTYDeviceTextKeyCommand -Text 'echo LEANTTY_SMOKE'
        )
    ) 'Device text injection did not preserve the requested echo command'
}

& {
    $script:injectedText = ''
    $script:submittedKeyCodes = [Collections.Generic.List[int]]::new()
    function Invoke-LeanTTYDeviceText {
        param($Hdc, $Target, $Text)
        $script:injectedText = $Text
    }
    function Invoke-LeanTTYDeviceKey {
        param($Hdc, $Target, $KeyCode)
        $script:submittedKeyCodes.Add($KeyCode)
    }

    Submit-LeanTTYDeviceCommand `
        -Hdc 'unused' `
        -Target 'unused' `
        -Command 'echo LEANTTY_SMOKE'
    Assert-True (
        $script:injectedText -eq 'echo LEANTTY_SMOKE' -and
        $script:submittedKeyCodes.Count -eq 1 -and
        $script:submittedKeyCodes[0] -eq 2054
    ) 'Device command submission did not inject raw text before pressing Enter'
}

$submitCommandParameters = (Get-Command Submit-LeanTTYDeviceCommand).Parameters.Keys
$submitCommandSource = (Get-Command Submit-LeanTTYDeviceCommand).Definition
Assert-True (
    $submitCommandParameters -notcontains 'LayoutPath' -and
    -not $submitCommandSource.Contains('Get-LeanTTYTerminalInputText')
) 'Device command submission still treats ArkWeb accessibility text as the native command buffer'

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
Assert-True (
    $deviceRegressionText -notmatch 'terminal-line cleanup|backspaceCount'
) 'Device input cleanup still uses inferred backspaces'
Assert-True (
    $deviceRegressionText -notmatch 'shell\s+run-as\s+com\.leantty\.app' -and
    $deviceRegressionText -match 'shell\s+-b\s+com\.leantty\.app'
) 'Device key-state inspection does not use the HarmonyOS bundle shell'

$clearInputParameters = (Get-Command Clear-LeanTTYDeviceInput).Parameters.Keys
$clearInputSource = (Get-Command Clear-LeanTTYDeviceInput).Definition
Assert-True (
    $clearInputParameters -notcontains 'LayoutPath' -and
    $clearInputSource.Contains('Invoke-LeanTTYDeviceCtrlC') -and
    -not $clearInputSource.Contains('Get-LeanTTYTerminalInputText')
) 'Device input cleanup still accepts the non-authoritative ArkWeb layout readback'

& {
    $script:ctrlCCount = 0
    function Invoke-LeanTTYDeviceCtrlC {
        param($Hdc, $Target)
        $script:ctrlCCount++
    }
    Clear-LeanTTYDeviceInput -Hdc 'unused' -Target 'unused'
    Assert-True ($script:ctrlCCount -eq 1) (
        'Device input cleanup did not use the single application interrupt path'
    )
}

Assert-True (
    $null -ne (Get-Command Start-LeanTTYDeviceAwakeLease -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Stop-LeanTTYDeviceAwakeLease -ErrorAction SilentlyContinue)
) 'Device regression has no reversible screen-timeout lease'

Assert-True (
    $null -ne (Get-Command ConvertTo-LeanTTYDevicePasswordKeyCommand -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Assert-LeanTTYCredentialPathOutsideRepository -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Start-LeanTTYRegressionApp -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Wait-LeanTTYTerminalInputLayout -ErrorAction SilentlyContinue)
) 'Device regression has no conditional local-credential unlock helpers'
$passwordKeyCommand = ConvertTo-LeanTTYDevicePasswordKeyCommand -Password 'abc'
Assert-True (
    $passwordKeyCommand -eq (
        'uinput -K -d 2017 -u 2017 -d 2018 -u 2018 -d 2019 -u 2019 ' +
        '-d 2054 -u 2054'
    ) -and
    -not $passwordKeyCommand.Contains('abc')
) 'Device unlock command does not convert plaintext to the expected non-secret key events'
Assert-Throws -Action {
    ConvertTo-LeanTTYDevicePasswordKeyCommand -Password 'unsafe value'
} -Message 'Device unlock accepted an unsupported password alphabet'
Assert-Throws -Action {
    Assert-LeanTTYCredentialPathOutsideRepository `
        -CredentialPath (Join-Path $PSScriptRoot 'device-password.txt') `
        -RepositoryRoot (Split-Path $PSScriptRoot -Parent)
} -Message 'Device unlock accepted a credential file inside the repository'

$keyPresenceCommand = Get-Command Test-LeanTTYDeviceKeyFilesPresent -ErrorAction SilentlyContinue
Assert-True ($null -ne $keyPresenceCommand) (
    'Device cleanup has no independent app-sandbox key-file verification helper'
)
Assert-Throws -Action {
    Test-LeanTTYDeviceKeyFilesPresent `
        -Hdc 'unused' `
        -Target 'unused' `
        -KeyName '../unsafe'
} -Message 'Device key-file verification accepted an unsafe generated-key name'

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
        Assert-True (
            $content.Contains('schemaVersion = 2') -and
            $content.Contains('cleanup = [ordered]@{') -and
            $content.Contains('durationMs =')
        ) 'Device behavior evidence does not record stage timing and cleanup outcome'
        Assert-True (
            $content.Contains("'device-harness-preflight'") -and
            $content.Contains('Test-LeanTTYDeviceKeyFilesPresent')
        ) 'Device scenario does not preflight telemetry and independently verify cleanup'
        Assert-True (
            $content.Contains('Start-LeanTTYDeviceAwakeLease') -and
            $content.Contains('Stop-LeanTTYDeviceAwakeLease')
        ) 'Device scenario does not acquire and restore a screen-timeout lease'
        Assert-True (
            $content.Contains('UnlockPasswordPath') -and
            $content.Contains('Start-LeanTTYRegressionApp') -and
            $content.Contains('Wait-LeanTTYTerminalInputLayout') -and
            $content.Contains('deviceUnlock = $deviceUnlockResult')
        ) 'Device scenario does not record conditional local-credential unlock behavior'
    }
}

Write-Host 'Device regression helper tests passed.' -ForegroundColor Green
