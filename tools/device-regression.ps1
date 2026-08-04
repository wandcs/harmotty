function Resolve-LeanTTYRegressionTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [string]$Target = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Target)) { return $Target }
    $readyTargets = @(Get-HdcTargets -Hdc $Hdc | Where-Object {
        $_.transport -match '^(USB|TCP)$' -and $_.status -match '^(Ready|Connected)$'
    })
    $usbTargets = @($readyTargets | Where-Object { $_.transport -eq 'USB' })
    $candidates = if ($usbTargets.Count -gt 0) { $usbTargets } else { $readyTargets }
    if ($candidates.Count -eq 1) { return $candidates[0].key }
    if ($candidates.Count -eq 0) {
        throw 'No ready physical HarmonyOS PC found for device regression'
    }
    throw 'Multiple HarmonyOS PCs are connected; pass -Target explicitly'
}

function Start-LeanTTYDeviceAwakeLease {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [ValidateRange(60000, 1800000)][int]$TimeoutMilliseconds = 900000
    )

    & $Hdc -t $Target shell 'power-shell wakeup' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to wake the HarmonyOS regression PC' }
    $output = @(
        & $Hdc -t $Target shell "power-shell timeout -o $TimeoutMilliseconds" 2>&1
    ) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Override screen off time') {
        throw 'Unable to acquire the HarmonyOS regression screen-timeout lease'
    }
}

function Stop-LeanTTYDeviceAwakeLease {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $output = @(& $Hdc -t $Target shell 'power-shell timeout -r 0' 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Restore screen off time') {
        throw 'Unable to restore the HarmonyOS regression screen timeout'
    }
}

function Get-LeanTTYDeviceUnlockPasswordPath {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw 'Unable to resolve the current Windows user LocalAppData directory'
    }
    return Join-Path $localAppData 'LeanTTY\regression\device-unlock-password.txt'
}

function Assert-LeanTTYCredentialPathOutsideRepository {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $credentialFullPath = [IO.Path]::GetFullPath($CredentialPath)
    $repositoryPrefix = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/') + `
        [IO.Path]::DirectorySeparatorChar
    if ($credentialFullPath.StartsWith(
        $repositoryPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Device unlock credential must be stored outside the repository'
    }
}

function ConvertTo-LeanTTYDevicePasswordKeyCommand {
    param([Parameter(Mandatory = $true)][string]$Password)

    if ($Password -notmatch '^[a-z]{1,64}$') {
        throw 'Device unlock password must contain only lowercase ASCII letters'
    }
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add('uinput -K')
    foreach ($character in $Password.ToCharArray()) {
        $keyCode = 2017 + ([int]$character - [int][char]'a')
        $parts.Add("-d $keyCode -u $keyCode")
    }
    $parts.Add('-d 2054 -u 2054')
    return $parts -join ' '
}

function Start-LeanTTYRegressionApp {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    Assert-LeanTTYCredentialPathOutsideRepository `
        -CredentialPath $CredentialPath `
        -RepositoryRoot $RepositoryRoot
    $launchCommand = 'aa start -a EntryAbility -b com.leantty.app'
    $launchOutput = @(& $Hdc -t $Target shell $launchCommand 2>&1) -join "`n"
    $launchExitCode = $LASTEXITCODE
    $deviceLocked = $launchOutput -match 'Error Code:10106102|device screen is locked'
    if ($launchExitCode -ne 0 -and -not $deviceLocked) {
        throw 'LeanTTY application launch command failed before device unlock detection'
    }
    if ($launchOutput -match '(?i)\[Fail\]|error' -and -not $deviceLocked) {
        throw "LeanTTY application launch failed: $launchOutput"
    }

    $unlockResult = 'not-required'
    if ($deviceLocked) {
        if (-not (Test-Path -LiteralPath $CredentialPath -PathType Leaf)) {
            throw "Locked regression PC requires local credential file: $CredentialPath"
        }
        $password = [IO.File]::ReadAllText($CredentialPath).TrimEnd("`r", "`n")
        try {
            $keyCommand = ConvertTo-LeanTTYDevicePasswordKeyCommand -Password $password
            & $Hdc -t $Target shell 'power-shell wakeup' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to wake the locked regression PC' }
            & $Hdc -t $Target shell 'uinput -K -d 2050 -u 2050' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to focus the regression PC unlock prompt' }
            Start-Sleep -Milliseconds 500
            & $Hdc -t $Target shell $keyCommand | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Unable to inject regression PC unlock key events' }
        } finally {
            $password = ''
            $keyCommand = ''
        }
        Start-Sleep -Milliseconds 800
        $launchOutput = @(& $Hdc -t $Target shell $launchCommand 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $launchOutput -match '(?i)\[Fail\]|error') {
            throw 'Regression PC remained locked after local credential injection'
        }
        $unlockResult = 'local-plaintext-credential'
    }

    Start-Sleep -Milliseconds 800
    $processId = (@(& $Hdc -t $Target shell 'pidof com.leantty.app' 2>&1) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or $processId -notmatch '^\d+$') {
        throw 'LeanTTY application PID is unavailable after launch'
    }
    return [pscustomobject]@{
        processId = $processId
        unlock = $unlockResult
    }
}

function Get-LeanTTYLayoutNodes {
    param([Parameter(Mandatory = $true)]$Node)

    $nodes = [Collections.Generic.List[object]]::new()
    $nodes.Add($Node)
    foreach ($child in @($Node.children)) {
        foreach ($descendant in @(Get-LeanTTYLayoutNodes -Node $child)) {
            $nodes.Add($descendant)
        }
    }
    return @($nodes)
}

function Get-LeanTTYBoundsCenter {
    param([Parameter(Mandatory = $true)][string]$Bounds)

    $match = [regex]::Match($Bounds, '^\[(?<x1>\d+),(?<y1>\d+)\]\[(?<x2>\d+),(?<y2>\d+)\]$')
    if (-not $match.Success) { throw "Invalid UI bounds: $Bounds" }
    return [pscustomobject]@{
        x = [int](([int]$match.Groups['x1'].Value + [int]$match.Groups['x2'].Value) / 2)
        y = [int](([int]$match.Groups['y1'].Value + [int]$match.Groups['y2'].Value) / 2)
    }
}

function Get-LeanTTYDeviceLayout {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $remotePath = '/data/local/tmp/leantty-layout-' + [Guid]::NewGuid().ToString('N') + '.json'
    try {
        & $Hdc -t $Target shell uitest dumpLayout -p $remotePath -a -b com.leantty.app | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS UI layout capture failed' }
        & $Hdc -t $Target file recv $remotePath $LocalPath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS UI layout transfer failed' }
        if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
            throw 'HarmonyOS UI layout transfer produced no local file'
        }
    } finally {
        & $Hdc -t $Target shell rm -f $remotePath 2>$null | Out-Null
    }
    return Get-Content -LiteralPath $LocalPath -Raw | ConvertFrom-Json -Depth 100
}

function Get-LeanTTYTerminalInputText {
    param([Parameter(Mandatory = $true)]$Layout)

    $inputNode = @(Get-LeanTTYLayoutNodes -Node $Layout | Where-Object {
        [string]$_.attributes.hint -eq 'Terminal input'
    } | Select-Object -First 1)
    if ($inputNode.Count -ne 1) {
        throw 'LeanTTY terminal input accessibility node was not found'
    }
    $originalText = [string]$inputNode[0].attributes.originalText
    if (-not [string]::IsNullOrEmpty($originalText)) { return $originalText }
    return [string]$inputNode[0].attributes.text
}

function Assert-LeanTTYLayoutExcludesValues {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [Parameter(Mandatory = $true)][string[]]$Values
    )

    $layoutText = ConvertTo-Json -InputObject $Layout -Depth 100 -Compress
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrEmpty($value) -and $layoutText.Contains($value)) {
            throw 'A device layout snapshot exposed secret input'
        }
    }
}

function Invoke-LeanTTYDeviceText {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Text
    )

    if ($Text -notmatch '^[\x20-\x7E]*$' -or $Text.Contains("'")) {
        throw 'Device regression text must be printable ASCII without a single quote'
    }
    $shellCommand = "uitest uiInput text '$Text'"
    & $Hdc -t $Target shell $shellCommand 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS UI text injection failed' }
}

function Invoke-LeanTTYDeviceKey {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$KeyCode
    )

    & $Hdc -t $Target shell "uitest uiInput keyEvent $KeyCode" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "HarmonyOS key injection failed: $KeyCode" }
}

function Invoke-LeanTTYDeviceCtrlC {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target
    )

    & $Hdc -t $Target shell 'uinput -K -d 2072 -d 2019 -u 2019 -u 2072' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS Ctrl+C injection failed' }
}

function Clear-LeanTTYDeviceInput {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$LayoutPath
    )

    Invoke-LeanTTYDeviceCtrlC -Hdc $Hdc -Target $Target
    $layout = Get-LeanTTYDeviceLayout -Hdc $Hdc -Target $Target -LocalPath $LayoutPath
    $currentText = Get-LeanTTYTerminalInputText -Layout $layout
    if ([string]::IsNullOrEmpty($currentText)) { return 0 }
    if ($currentText.Length -gt 256) {
        throw 'HarmonyOS terminal-line cleanup refused unexpectedly long input'
    }

    $backspaceCount = $currentText.Length + 2
    & $Hdc -t $Target shell (
        "i=0; while [ `$i -lt $backspaceCount ]; do " +
        'uitest uiInput keyEvent 2055 >/dev/null; i=$((i+1)); done'
    ) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS terminal-line cleanup failed' }

    $verifiedLayout = Get-LeanTTYDeviceLayout `
        -Hdc $Hdc `
        -Target $Target `
        -LocalPath $LayoutPath
    $remainingText = Get-LeanTTYTerminalInputText -Layout $verifiedLayout
    if (-not [string]::IsNullOrEmpty($remainingText)) {
        throw "HarmonyOS terminal-line cleanup left $($remainingText.Length) input characters"
    }
    return $backspaceCount
}

function Test-LeanTTYDeviceKeyFilesPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    if ($KeyName -notmatch '^ltty_reg_[0-9a-f]{10}$') {
        throw 'Device regression key name is outside the disposable-key namespace'
    }
    $sshDirectory = '/data/app/el2/100/base/com.leantty.app/haps/entry/files/.ssh'
    $privatePath = "$sshDirectory/$KeyName"
    $publicPath = "$privatePath.pub"
    $condition = (
        "if [ -e $privatePath ] || [ -e $publicPath ]; " +
        'then echo PRESENT; else echo ABSENT; fi'
    )
    $output = @(& $Hdc -t $Target shell -b com.leantty.app $condition 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect disposable key state in the LeanTTY application sandbox'
    }
    $result = ($output -join "`n").Trim()
    if ($result -eq 'PRESENT') { return $true }
    if ($result -eq 'ABSENT') { return $false }
    throw 'Unexpected disposable key-state response from the LeanTTY application sandbox'
}

function Submit-LeanTTYDeviceCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$LayoutPath
    )

    Invoke-LeanTTYDeviceText -Hdc $Hdc -Target $Target -Text $Command
    $layout = Get-LeanTTYDeviceLayout -Hdc $Hdc -Target $Target -LocalPath $LayoutPath
    $actual = Get-LeanTTYTerminalInputText -Layout $layout
    if ($actual -ne $Command) {
        throw "Injected terminal command differs from the requested command: $actual"
    }
    Invoke-LeanTTYDeviceKey -Hdc $Hdc -Target $Target -KeyCode 2054
}

function Clear-LeanTTYAppLogs {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target
    )

    & $Hdc -t $Target shell 'hilog -r -t app' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clear HarmonyOS application logs' }
}

function Get-LeanTTYAppLogs {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ProcessId
    )

    $output = @(
        & $Hdc -t $Target shell (
            "hilog -z 500 -t app -P $ProcessId " +
            '-T SessionViewModel,KeyCommandService'
        ) 2>&1
    )
    $exitCode = $LASTEXITCODE
    $logs = $output -join "`n"
    if ($exitCode -ne 0 -or $logs -match 'Mutlti commands can''t be used') {
        throw 'HarmonyOS application log query failed'
    }
    return $logs
}

function Wait-LeanTTYAppLog {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 10
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $logs = Get-LeanTTYAppLogs -Hdc $Hdc -Target $Target -ProcessId $ProcessId
        if ($logs -match $Pattern) { return $logs }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for LeanTTY device state: $Pattern"
}

function Invoke-LeanTTYDialogButton {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ButtonText,
        [Parameter(Mandatory = $true)][string]$LayoutPath
    )

    $layout = Get-LeanTTYDeviceLayout -Hdc $Hdc -Target $Target -LocalPath $LayoutPath
    $buttonNode = @(Get-LeanTTYLayoutNodes -Node $layout | Where-Object {
        [string]$_.attributes.text -eq $ButtonText -or
        [string]$_.attributes.originalText -eq $ButtonText
    } | Select-Object -First 1)
    if ($buttonNode.Count -ne 1) { throw "Dialog button was not found: $ButtonText" }
    $center = Get-LeanTTYBoundsCenter -Bounds ([string]$buttonNode[0].attributes.bounds)
    & $Hdc -t $Target shell "uitest uiInput click $($center.x) $($center.y)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Dialog button click failed: $ButtonText" }
}

function Save-LeanTTYDeviceScreenshot {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $remotePath = '/data/local/tmp/leantty-screen-' + [Guid]::NewGuid().ToString('N') + '.png'
    try {
        & $Hdc -t $Target shell uitest screenCap -p $remotePath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS screenshot capture failed' }
        & $Hdc -t $Target file recv $remotePath $LocalPath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS screenshot transfer failed' }
        if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
            throw 'HarmonyOS screenshot transfer produced no local file'
        }
    } finally {
        & $Hdc -t $Target shell rm -f $remotePath 2>$null | Out-Null
    }
}

function New-LeanTTYRegressionSecret {
    return 'T' + [Guid]::NewGuid().ToString('N').Substring(0, 23)
}
