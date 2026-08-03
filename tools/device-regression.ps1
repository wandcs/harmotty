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
    & $Hdc -t $Target shell uitest dumpLayout -p $remotePath -a -b com.leantty.app | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS UI layout capture failed' }
    & $Hdc -t $Target file recv $remotePath $LocalPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS UI layout transfer failed' }
    & $Hdc -t $Target shell rm -f $remotePath | Out-Null
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
        [Parameter(Mandatory = $true)][string]$Target
    )

    Invoke-LeanTTYDeviceCtrlC -Hdc $Hdc -Target $Target
    & $Hdc -t $Target shell `
        'i=0; while [ $i -lt 160 ]; do uitest uiInput keyEvent 2055 >/dev/null; i=$((i+1)); done' |
        Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS terminal-line cleanup failed' }
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
        [Parameter(Mandatory = $true)][string]$Pid
    )

    return ((& $Hdc -t $Target shell "hilog -x -t app -z 500 -P $Pid -T SessionViewModel,KeyCommandService" 2>&1) -join "`n")
}

function Wait-LeanTTYAppLog {
    param(
        [Parameter(Mandatory = $true)][string]$Hdc,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Pid,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 10
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $logs = Get-LeanTTYAppLogs -Hdc $Hdc -Target $Target -Pid $Pid
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
    & $Hdc -t $Target shell uitest screenCap -p $remotePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS screenshot capture failed' }
    & $Hdc -t $Target file recv $remotePath $LocalPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS screenshot transfer failed' }
    & $Hdc -t $Target shell rm -f $remotePath | Out-Null
}

function New-LeanTTYRegressionSecret {
    return 'T' + [Guid]::NewGuid().ToString('N').Substring(0, 23)
}
