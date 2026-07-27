$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$rustPath = Join-Path $repoRoot 'leantty_ssh\src\lib.rs'
$viewModelPath = Join-Path $repoRoot 'entry\src\main\ets\viewmodel\SessionViewModel.ets'

$rust = Get-Content -Raw -LiteralPath $rustPath
$viewModel = Get-Content -Raw -LiteralPath $viewModelPath

$kexIndex = $rust.IndexOf('stage=kex_complete')
$promptIndex = $rust.IndexOf('send_control(&control_callback, "PASSWORD_PROMPT")')
$authWaitIndex = $rust.IndexOf('let auth_method = tokio::select!')

if ($kexIndex -lt 0 -or $promptIndex -lt 0 -or $authWaitIndex -lt 0) {
  throw 'Required SSH authentication flow markers were not found.'
}

if (-not ($kexIndex -lt $promptIndex -and $promptIndex -lt $authWaitIndex)) {
  throw 'PASSWORD_PROMPT must be sent after key exchange and before waiting for auth input.'
}

if ($viewModel.Contains("key.hasPassphrase ? '' : ''")) {
  throw 'Encrypted and unencrypted private keys still select the same empty-passphrase branch.'
}

if (-not $rust.Contains('pub fn ssh_auth_private_key(')) {
  throw 'Private-key N-API function name must map to sshAuthPrivateKey.'
}

if (-not $rust.Contains('stage=key_rejected fallback=password')) {
  throw 'Authentication must allow private-key rejection to fall back to password.'
}

if (-not $viewModel.Contains('private privateKeyAttempted: boolean = false')) {
  throw 'Session state must prevent retrying the same default private key forever.'
}

Write-Output 'SSH authentication flow regression checks passed.'
