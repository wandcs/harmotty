$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$rustPath = Join-Path $repoRoot 'leantty_ssh\src\lib.rs'
$typingPath = Join-Path $repoRoot 'entry\src\main\cpp\types\libleantty_ssh\index.d.ts'
$clientPath = Join-Path $repoRoot 'entry\src\main\ets\model\ssh\SshClient.ets'

$rust = Get-Content -Raw -LiteralPath $rustPath
$typing = Get-Content -Raw -LiteralPath $typingPath
$client = Get-Content -Raw -LiteralPath $clientPath

$finalData = 'try_send_transport_data(&transport_callback, final_output.clone())'
$close = 'send_transport_close(&transport_callback, close_result)'
$finalDataIndex = $rust.IndexOf($finalData, [StringComparison]::Ordinal)
$closeIndex = $rust.IndexOf($close, [StringComparison]::Ordinal)

if ($finalDataIndex -lt 0 -or $closeIndex -lt 0 -or $finalDataIndex -ge $closeIndex) {
    throw 'Final SSH data and close must be delivered in order through one transport callback'
}
if (-not $rust.Contains('type JsTransportCallback =') -or
    $rust.Contains('type JsDataCallback =') -or
    $rust.Contains('close_callback: JsCallback')) {
    throw 'Rust SSH data and close still use separate N-API callback types'
}
if (-not $typing.Contains('export interface TransportEvent') -or
    -not $typing.Contains('onTransport: (event: TransportEvent) => void') -or
    $typing.Contains('onData: (data: Uint8Array) => void') -or
    $typing.Contains('onClose: (exitCode: string) => void')) {
    throw 'N-API typing does not expose one structured SSH transport callback'
}
if (-not $client.Contains('handleNativeTransportEvent(event)') -or
    -not $client.Contains("event.kind === 'data'") -or
    -not $client.Contains("event.kind === 'close'")) {
    throw 'ArkTS SSH client does not route the structured transport event'
}

Write-Host 'SSH transport flow check passed.' -ForegroundColor Green
