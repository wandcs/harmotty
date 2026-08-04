function Set-LeanTTYAcceptanceSourceText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Anchor,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    $targetNewLine = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalizedAnchor = $Anchor.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", $targetNewLine)
    $normalizedReplacement = $Replacement.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", $targetNewLine)

    $first = $Text.IndexOf($normalizedAnchor, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Acceptance source anchor is missing: $Anchor" }
    if ($Text.IndexOf(
            $normalizedAnchor,
            $first + $normalizedAnchor.Length,
            [StringComparison]::Ordinal
        ) -ge 0) {
        throw "Acceptance source anchor is ambiguous: $Anchor"
    }
    return $Text.Substring(0, $first) + $normalizedReplacement +
        $Text.Substring($first + $normalizedAnchor.Length)
}

function Add-LeanTTYAcceptanceSource {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $files = [ordered]@{
        index = Join-Path $RepoRoot 'entry\src\main\ets\pages\Index.ets'
        bridge = Join-Path $RepoRoot 'entry\src\main\ets\model\bridge\TerminalBridge.ets'
        surface = Join-Path $RepoRoot 'entry\src\main\ets\model\terminal\TerminalSurfaceController.ets'
        session = Join-Path $RepoRoot 'entry\src\main\ets\viewmodel\SessionViewModel.ets'
    }
    $text = @{}
    foreach ($name in $files.Keys) {
        $text[$name] = [IO.File]::ReadAllText($files[$name])
    }

    $text.index = Set-LeanTTYAcceptanceSourceText $text.index `
        "import { BrowserLauncher } from '../model/browser/BrowserLauncher'" `
        "import { BrowserLauncher } from '../model/browser/BrowserLauncher'`nimport { ACCEPTANCE_TESTS } from 'BuildProfile'"
    $text.index = Set-LeanTTYAcceptanceSourceText $text.index `
        'const MENU_ACTION_COUNT: number = 6' `
        'const MENU_ACTION_COUNT: number = ACCEPTANCE_TESTS ? 7 : 6'
    $selectionAnchor = "    if (selected === 5) { this.handleFontDecrease(); return }"
    $selectionReplacement = $selectionAnchor + "`n" +
        "    if (selected === 6 && ACCEPTANCE_TESTS) { this.rebuildRendererForAcceptance(); return }"
    $text.index = Set-LeanTTYAcceptanceSourceText `
        $text.index $selectionAnchor $selectionReplacement
    $rendererMethod = @'
  private rebuildRendererForAcceptance(): void {
    if (!ACCEPTANCE_TESTS) {
      return
    }
    let pane: PaneInfo | null = this.appVm.getActivePane()
    let runtime: PaneRuntime | null = pane === null ? null : this.findPaneRuntime(pane.id)
    if (runtime === null) {
      logger.error('Acceptance renderer rebuild has no active pane')
      return
    }
    let targetRuntime: PaneRuntime = runtime
    targetRuntime.surface.captureSnapshot((captured: boolean) => {
      if (!captured) {
        logger.error('Acceptance renderer rebuild cancelled because checkpoint failed')
        return
      }
      let terminated: boolean = targetRuntime.surface.terminateRendererForAcceptance()
      logger.info('Acceptance renderer rebuild requested=' + terminated.toString() + ',pane=' + targetRuntime.id)
    })
  }

'@
    $text.index = Set-LeanTTYAcceptanceSourceText $text.index `
        "  @Builder`n  menuPanel() {" `
        ($rendererMethod + "  @Builder`n  menuPanel() {")
    $menuAnchor = @'
      this.menuRow(5, 'A⁻', 'Font Size -', 'Ctrl+-', true, () => { this.handleFontDecrease() })
'@
    $menuAddition = @'
      this.menuRow(5, 'A⁻', 'Font Size -', 'Ctrl+-', true, () => { this.handleFontDecrease() })
      if (ACCEPTANCE_TESTS) {
        this.menuDivider()
        this.menuRow(6, '↻', 'Acceptance: Rebuild Renderer', '', true,
          () => { this.rebuildRendererForAcceptance() })
      }
'@
    $text.index = Set-LeanTTYAcceptanceSourceText $text.index $menuAnchor $menuAddition

    $text.bridge = Set-LeanTTYAcceptanceSourceText $text.bridge `
        "import { Logger } from '../../common/logger/Logger'" `
        "import { Logger } from '../../common/logger/Logger'`nimport { ACCEPTANCE_TESTS } from 'BuildProfile'"
    $bridgeMethod = @'
  terminateRendererForAcceptance(): boolean {
    if (!ACCEPTANCE_TESTS) {
      return false
    }
    try {
      return this.webCtrl.terminateRenderProcess()
    } catch (e) {
      this.logger.error('Acceptance renderer termination failed: ' + e)
      return false
    }
  }

'@
    $text.bridge = Set-LeanTTYAcceptanceSourceText $text.bridge `
        '  private postTerminalPacket(data: Uint8Array): number {' `
        ($bridgeMethod + '  private postTerminalPacket(data: Uint8Array): number {')

    $text.surface = Set-LeanTTYAcceptanceSourceText $text.surface `
        "import util from '@ohos.util'" `
        "import util from '@ohos.util'`nimport { ACCEPTANCE_TESTS } from 'BuildProfile'"
    $surfaceMethod = @'
  terminateRendererForAcceptance(): boolean {
    if (!ACCEPTANCE_TESTS || this.bridge === null) {
      return false
    }
    return this.bridge.terminateRendererForAcceptance()
  }

'@
    $text.surface = Set-LeanTTYAcceptanceSourceText $text.surface `
        '  private handleBridgeMessage(sourceBridge: TerminalBridge, msg: BridgeMessage): void {' `
        ($surfaceMethod + '  private handleBridgeMessage(sourceBridge: TerminalBridge, msg: BridgeMessage): void {')

    $text.session = Set-LeanTTYAcceptanceSourceText $text.session `
        "import { CommandParser, KeyCommandKind } from '../model/command/CommandParser'" `
        "import { CommandParser, KeyCommandKind } from '../model/command/CommandParser'`nimport { ACCEPTANCE_TESTS } from 'BuildProfile'"
    $text.session = Set-LeanTTYAcceptanceSourceText $text.session `
        '  private perfPingStartedMs: number = 0' `
        "  private perfPingStartedMs: number = 0`n  private acceptanceInputSequence: number = 0"
    foreach ($inputPoint in @(
        @{ anchor = "  private executeCommandBuffer(): void {"; kind = 'command' },
        @{ anchor = "    this.writeTerminal('\r\n')`n    let pw: string = this.passwordBuffer"; kind = 'password' },
        @{ anchor = '    this.authResponses.push(this.authResponseBuffer)'; kind = 'keyboard-interactive' },
        @{ anchor = "    this.writeTerminal('\r\n')`n    let pass: string = this.pendingKeyPassphrase"; kind = 'private-key-passphrase' }
    )) {
        if ($inputPoint.kind -eq 'command') {
            $replacement = $inputPoint.anchor + "`n    this.logAcceptanceInputSubmit('command')"
        } else {
            $replacement = $inputPoint.anchor.Replace(
                "`n    let ",
                "`n    this.logAcceptanceInputSubmit('$($inputPoint.kind)')`n    let "
            )
            if ($inputPoint.kind -eq 'keyboard-interactive') {
                $replacement = "    this.logAcceptanceInputSubmit('keyboard-interactive')`n" + $inputPoint.anchor
            }
        }
        $text.session = Set-LeanTTYAcceptanceSourceText $text.session $inputPoint.anchor $replacement
    }
    $keyChangeAnchor = @'
  private submitKeyPassphraseChangeStage(): void {
    if (this.mode !== TerminalMode.KEY_PASSPHRASE_CHANGE_INPUT) {
      return
    }
'@
    $text.session = Set-LeanTTYAcceptanceSourceText `
        $text.session `
        $keyChangeAnchor `
        ($keyChangeAnchor + "    this.logAcceptanceInputSubmit('key-passphrase-change')`n")
    $sessionMethod = @'
  private logAcceptanceInputSubmit(kind: string): void {
    if (ACCEPTANCE_TESTS) {
      this.acceptanceInputSequence++
      this.logger.info('ACCEPTANCE_INPUT_SUBMIT sequence=' + this.acceptanceInputSequence.toString() +
        ',kind=' + kind)
    }
  }

'@
    $text.session = Set-LeanTTYAcceptanceSourceText $text.session `
        '  private submitKeyPassphrase(): void {' `
        ($sessionMethod + '  private submitKeyPassphrase(): void {')

    foreach ($name in $files.Keys) {
        [IO.File]::WriteAllText($files[$name], $text[$name], [Text.UTF8Encoding]::new($false))
    }
    return @($files.Values)
}

function Invoke-WithLeanTTYAcceptanceSource {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    if (-not $Enabled) {
        & $Action
        return
    }
    $paths = @(
        Join-Path $RepoRoot 'entry\src\main\ets\pages\Index.ets'
        Join-Path $RepoRoot 'entry\src\main\ets\model\bridge\TerminalBridge.ets'
        Join-Path $RepoRoot 'entry\src\main\ets\model\terminal\TerminalSurfaceController.ets'
        Join-Path $RepoRoot 'entry\src\main\ets\viewmodel\SessionViewModel.ets'
    )
    $backups = @{}
    foreach ($path in $paths) { $backups[$path] = [IO.File]::ReadAllBytes($path) }
    try {
        Add-LeanTTYAcceptanceSource -RepoRoot $RepoRoot | Out-Null
        & $Action
    } finally {
        foreach ($path in $paths) { [IO.File]::WriteAllBytes($path, $backups[$path]) }
    }
}
