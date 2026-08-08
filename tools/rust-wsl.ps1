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

function ConvertFrom-LeanTTYWslPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$WslRoot,
        [Parameter(Mandatory = $true)][string]$WindowsRoot,
        [Parameter(Mandatory = $true)][string]$WslPath
    )

    $normalizedRoot = $WslRoot.Replace('\', '/').TrimEnd('/')
    $normalizedPath = $WslPath.Replace('\', '/')
    $rootPrefix = $normalizedRoot + '/'
    if (-not $normalizedPath.StartsWith($rootPrefix, [StringComparison]::Ordinal)) {
        throw "WSL path is outside the approved root: $WslPath"
    }

    $relativePath = $normalizedPath.Substring($rootPrefix.Length).Replace('/', '\')
    return Join-Path ([IO.Path]::GetFullPath($WindowsRoot)) $relativePath
}

function Get-LeanTTYWslCargoHome {
    param([string]$Distribution = $env:LEANTTY_WSL_DISTRO)

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe not found; LeanTTY Rust commands require WSL'
    }

    $wslPrefix = Get-LeanTTYWslPrefix -Distribution $Distribution
    $cargoHomeOutput = @(& wsl.exe @wslPrefix -- env RUSTUP_TOOLCHAIN=stable `
        sh -c 'printf %s "${CARGO_HOME:-$HOME/.cargo}"')
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to resolve the WSL Cargo home'
    }
    $wslCargoHome = ($cargoHomeOutput -join "`n").Trim()
    if (-not $wslCargoHome.StartsWith('/', [StringComparison]::Ordinal)) {
        throw "WSL Cargo home is not an absolute Linux path: $wslCargoHome"
    }

    $windowsHomeOutput = @(& wsl.exe @wslPrefix -- wslpath -w -- $wslCargoHome)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to map the WSL Cargo home to Windows'
    }
    $windowsCargoHome = ($windowsHomeOutput -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($windowsCargoHome)) {
        throw 'Mapped WSL Cargo home is empty'
    }

    return [pscustomobject]@{
        WslPath = $wslCargoHome
        WindowsPath = [IO.Path]::GetFullPath($windowsCargoHome)
    }
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
