<#
.SYNOPSIS
  Start the controlled SSH authentication fixture with temporary credentials.
.DESCRIPTION
  Creates random credentials under the current user's temporary directory,
  starts the repository-only russh server in WSL, and removes the credentials
  when the server exits. The fixture is not part of the native library or HAP.
#>
[CmdletBinding()]
param(
    [string]$ListenAddress = '0.0.0.0:22222',
    [ValidateRange(1, 3600)]
    [int]$RunSeconds = 900,
    [string]$Distribution = $env:LEANTTY_WSL_DISTRO
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'rust-wsl.ps1')

function New-FixtureSecret {
    $bytes = [byte[]]::new(16)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToHexString($bytes).ToLowerInvariant()
}

$fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('leantty-ssh-auth-' + [guid]::NewGuid().ToString('N'))
$credentialsPath = Join-Path $fixtureDirectory 'server-credentials'
New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null

try {
    $lines = @(
        'password=' + (New-FixtureSecret)
        'account=' + (New-FixtureSecret)
        'token=' + (New-FixtureSecret)
        'second_token=' + (New-FixtureSecret)
    )
    [IO.File]::WriteAllLines($credentialsPath, $lines, [Text.UTF8Encoding]::new($false))
    $lines = $null

    $wslCredentialsPath = ConvertTo-LeanTTYWslPath -WindowsPath $credentialsPath -Distribution $Distribution
    Write-Host "Temporary fixture directory: $fixtureDirectory" -ForegroundColor Yellow
    Write-Host 'Credentials are available only in server-credentials while this process is running.'
    Write-Host 'Users: password, publickey, password-kbdint, publickey-password, publickey-kbdint, kbdint-multiround'
    Write-Host 'Stop with Ctrl+C; temporary credentials will be removed.'

    Invoke-LeanTTYRustWsl -RepoRoot $repoRoot -Distribution $Distribution -CargoArguments @(
        'run', '--locked', '--offline', '--manifest-path', './leantty_ssh/Cargo.toml',
        '-p', 'leantty-ssh-auth-fixture', '--', $ListenAddress, $wslCredentialsPath,
        $RunSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
    )
} finally {
    if (Test-Path -LiteralPath $fixtureDirectory) {
        Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force
    }
}
