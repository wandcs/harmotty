function Get-LeanTTYWslPrefix {
    param([string]$Distribution = $env:LEANTTY_WSL_DISTRO)

    $prefix = @()
    if ($Distribution) {
        $prefix += @('--distribution', $Distribution)
    }
    return $prefix
}

function ConvertTo-LeanTTYWslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath,
        [string]$Distribution = $env:LEANTTY_WSL_DISTRO
    )

    $resolvedPath = [IO.Path]::GetFullPath($WindowsPath)
    $match = [regex]::Match($resolvedPath, '^(?<drive>[A-Za-z]):(?<rest>\\.*)$')
    if (-not $match.Success) {
        throw "LeanTTY WSL commands require a drive-rooted Windows path: $resolvedPath"
    }
    $drive = $match.Groups['drive'].Value.ToLowerInvariant()
    $rest = $match.Groups['rest'].Value.Replace('\', '/')
    return "/mnt/$drive$rest"
}

function Invoke-LeanTTYRustWsl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string[]]$CargoArguments,
        [hashtable]$Environment = @{},
        [string]$Distribution = $env:LEANTTY_WSL_DISTRO
    )

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe not found; LeanTTY Rust commands require WSL'
    }

    $wslRepoRoot = ConvertTo-LeanTTYWslPath -WindowsPath $RepoRoot -Distribution $Distribution
    $wslPrefix = Get-LeanTTYWslPrefix -Distribution $Distribution
    $environmentArguments = @('env', 'RUSTUP_TOOLCHAIN=stable')
    foreach ($name in @($Environment.Keys | Sort-Object)) {
        $environmentArguments += "$name=$($Environment[$name])"
    }

    & wsl.exe @wslPrefix --cd $wslRepoRoot -- @environmentArguments cargo @CargoArguments
    if ($LASTEXITCODE -ne 0) {
        throw "WSL cargo command failed with exit code $LASTEXITCODE"
    }
}
