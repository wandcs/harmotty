[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$rustPath = Join-Path $repoRoot 'leantty_ssh\src\lib.rs'
$arkTsPath = Join-Path $repoRoot 'entry\src\main\ets\model\ssh\SshKeyManager.ets'
$declarationPath = Join-Path $repoRoot 'entry\src\main\cpp\types\libleantty_ssh\index.d.ts'

$rust = Get-Content -LiteralPath $rustPath -Raw
$arkTs = Get-Content -LiteralPath $arkTsPath -Raw
$declaration = Get-Content -LiteralPath $declarationPath -Raw

if ($rust -notmatch 'pub\s+async\s+fn\s+ssh_generate_key_pair\s*\(') {
    throw 'Rust key generation is not exported as an asynchronous N-API function'
}
if ($rust -notmatch 'tokio::task::spawn_blocking\s*\(') {
    throw 'CPU-bound key generation is not isolated from the async runtime workers'
}
if ($declaration -notmatch 'sshGenerateKeyPair\([^;]+\):\s*Promise<string>') {
    throw 'ArkTS native declaration does not expose key generation as a Promise'
}
if ($arkTs -notmatch 'await\s+sshNative\.sshGenerateKeyPair\s*\(') {
    throw 'SshKeyManager does not await native key generation'
}
if ($arkTs -match 'let\s+json:\s*string\s*=\s*sshNative\.sshGenerateKeyPair\s*\(') {
    throw 'SshKeyManager still invokes key generation synchronously'
}

Write-Host 'SSH key-generation async flow check passed.' -ForegroundColor Green
