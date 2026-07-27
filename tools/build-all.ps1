<#
.SYNOPSIS
  Build the HarmonyOS PC ARM64 HAP.
.DESCRIPTION
  This is the single HAP build path for current LeanTTY development.
  Native Rust code is rebuilt only when its inputs change. The resulting HAP
  is checked to ensure that it contains only the arm64-v8a native library.
#>
param(
    [switch]$Clean,
    [switch]$ForceNative,
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'debug',
    [switch]$Metadata,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$ReleaseId = '1.0.1'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$productName = 'default'
$projectProfilePath = Join-Path $repoRoot 'build-profile.json5'
$localSigningConfigPath = Join-Path $repoRoot 'signing.local.json5'

function Get-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release artifact is outside the repository: $fullPath"
    }
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-AppOutput {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][ValidateSet('unsigned', 'signed')][string]$SignatureState
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        if ($SignatureState -eq 'signed') { return $null }
        throw "APP output directory missing: $OutputDirectory"
    }

    $suffix = "-$SignatureState.app"
    $candidates = @(Get-ChildItem -LiteralPath $OutputDirectory -File |
        Where-Object {
            $_.Name.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)
        })
    if ($candidates.Count -eq 0 -and $SignatureState -eq 'signed') {
        return $null
    }
    if ($candidates.Count -ne 1) {
        throw "Expected one $BuildMode $SignatureState APP, found $($candidates.Count) in $OutputDirectory"
    }
    return $candidates[0].FullName
}

function Test-AppNativeAbi {
    param([Parameter(Mandatory = $true)][string]$AppPath)

    $appArchive = [IO.Compression.ZipFile]::OpenRead($AppPath)
    try {
        $hapEntries = @($appArchive.Entries | Where-Object { $_.FullName -match '\.hap$' })
        if ($hapEntries.Count -ne 1) {
            throw "APP must contain exactly one HAP, found $($hapEntries.Count): $AppPath"
        }
        $hapStream = $hapEntries[0].Open()
        try {
            $hapArchive = [IO.Compression.ZipArchive]::new(
                $hapStream,
                [IO.Compression.ZipArchiveMode]::Read,
                $false
            )
            try {
                $nativeAbis = @($hapArchive.Entries |
                    Where-Object { $_.FullName -match '^libs/([^/]+)/[^/]+\.so$' } |
                    ForEach-Object { if ($_.FullName -match '^libs/([^/]+)/') { $Matches[1] } } |
                    Select-Object -Unique)
                if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -ne 'arm64-v8a') {
                    throw "APP ABI mismatch: expected arm64-v8a, found $($nativeAbis -join ', ')"
                }
            } finally {
                $hapArchive.Dispose()
            }
        } finally {
            $hapStream.Dispose()
        }
    } finally {
        $appArchive.Dispose()
    }
}

function Invoke-SignatureVerification {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$CertificateOutput,
        [Parameter(Mandatory = $true)][string]$ProfileOutput,
        [Parameter(Mandatory = $true)][string]$ExpectedProfile
    )

    $verificationOutput = @(& $javaExe -jar $signToolJar verify-app `
        -inFile $ArtifactPath `
        -outCertChain $CertificateOutput `
        -outProfile $ProfileOutput 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Signature verification failed: $ArtifactPath`n$($verificationOutput -join "`n")"
    }
    $verificationText = $verificationOutput -join "`n"
    if ($verificationText -notmatch 'Digest verify result:\s*true' -or
        $verificationText -notmatch 'verify-app success') {
        throw "Signature verification did not report success: $ArtifactPath"
    }
    if (-not (Test-Path -LiteralPath $CertificateOutput) -or
        -not (Test-Path -LiteralPath $ProfileOutput)) {
        throw "Signature verification outputs missing: $ArtifactPath"
    }
    if ((Get-FileHash -LiteralPath $ProfileOutput -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $ExpectedProfile -Algorithm SHA256).Hash) {
        throw "Signed artifact contains an unexpected Profile: $ArtifactPath"
    }

    return [ordered]@{
        digestVerified = $true
        verifyAppSuccess = $true
        certificateChain = Get-RepoRelativePath $CertificateOutput
        profile = Get-RepoRelativePath $ProfileOutput
    }
}

$deveco = $env:DEVECO_HOME
if (-not $deveco) {
    foreach ($candidate in @('C:\Program Files\Huawei\DevEco Studio', 'D:\Program Files\Huawei\DevEco Studio')) {
        if (Test-Path -LiteralPath $candidate) { $deveco = $candidate; break }
    }
}
if (-not $deveco) { throw 'DevEco Studio not found. Set DEVECO_HOME.' }

$nodeExe = Join-Path $deveco 'tools\node\node.exe'
$hvigorJs = Join-Path $deveco 'tools\hvigor\bin\hvigorw.js'
$jbrBin = Join-Path $deveco 'jbr\bin'
$javaExe = Join-Path $jbrBin 'java.exe'
$signToolJar = Join-Path $deveco 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'

$env:NODE_OPTIONS = ''
$env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
$env:JAVA_HOME = Join-Path $deveco 'jbr'
$env:PATH = "$jbrBin;$env:PATH"

if ($Clean) {
    foreach ($directory in @(
        (Join-Path $repoRoot 'entry\build'),
        (Join-Path $repoRoot 'build'),
        (Join-Path $repoRoot '.hvigor'),
        (Join-Path $repoRoot 'leantty_ssh\target')
    )) {
        if (Test-Path -LiteralPath $directory) {
            Remove-Item -LiteralPath $directory -Recurse -Force
        }
    }
}

$nativeArgs = @{}
if ($ForceNative -or $Clean) { $nativeArgs['Force'] = $true }
& (Join-Path $PSScriptRoot 'build-native.ps1') @nativeArgs
if ($LASTEXITCODE -ne 0) { throw 'ARM64 native build failed' }
$nativeSo = Join-Path $repoRoot 'entry\libs\arm64-v8a\libleantty_ssh.so'
if (-not (Test-Path -LiteralPath $nativeSo)) { throw "Native output missing: $nativeSo" }

$hapArgs = @(
    $hvigorJs,
    '--mode', 'project',
    '-p', ('product=' + $productName),
    'assembleApp',
    '-p', ('buildMode=' + $BuildMode)
)
$projectProfileBackup = $null
if (Test-Path -LiteralPath $localSigningConfigPath) {
    $projectProfileBackup = [IO.File]::ReadAllBytes($projectProfilePath)
    $projectProfile = Get-Content -LiteralPath $projectProfilePath -Raw | ConvertFrom-Json
    $localSigningConfig = Get-Content -LiteralPath $localSigningConfigPath -Raw | ConvertFrom-Json
    foreach ($requiredProperty in @('name', 'type', 'material')) {
        if ($null -eq $localSigningConfig.$requiredProperty) {
            throw "Local signing config is missing '$requiredProperty': $localSigningConfigPath"
        }
    }
    $projectProfile.app | Add-Member -NotePropertyName 'signingConfigs' -NotePropertyValue @($localSigningConfig) -Force
    foreach ($product in $projectProfile.app.products) {
        $product | Add-Member -NotePropertyName 'signingConfig' -NotePropertyValue $localSigningConfig.name -Force
    }
    $temporaryProfile = ConvertTo-Json -InputObject $projectProfile -Depth 10
    [IO.File]::WriteAllText($projectProfilePath, $temporaryProfile, [Text.UTF8Encoding]::new($false))
    Write-Host "Using ignored local signing config: $localSigningConfigPath" -ForegroundColor Cyan
}

try {
    Push-Location $repoRoot
    try {
        & $nodeExe @hapArgs
        $hapBuildExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    if ($null -ne $projectProfileBackup) {
        [IO.File]::WriteAllBytes($projectProfilePath, $projectProfileBackup)
    }
}
if ($hapBuildExitCode -ne 0) { throw "PC HAP build failed in $BuildMode mode" }

$outputDir = Join-Path $repoRoot "entry\build\$productName\outputs\default"
$unsignedHap = Join-Path $outputDir 'entry-default-unsigned.hap'
if (-not (Test-Path -LiteralPath $unsignedHap)) { throw "HAP output missing: $unsignedHap" }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($unsignedHap)
try {
    $nativeAbis = @($archive.Entries |
        Where-Object { $_.FullName -match '^libs/([^/]+)/[^/]+\.so$' } |
        ForEach-Object { if ($_.FullName -match '^libs/([^/]+)/') { $Matches[1] } } |
        Select-Object -Unique)
    if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -ne 'arm64-v8a') {
        throw "HAP ABI mismatch: expected arm64-v8a, found $($nativeAbis -join ', ')"
    }
} finally {
    $archive.Dispose()
}

$signedHap = Join-Path $outputDir 'entry-default-signed.hap'
$appOutputDir = Join-Path $repoRoot 'build\outputs\default'
$unsignedApp = Get-AppOutput -OutputDirectory $appOutputDir -SignatureState unsigned
$signedApp = Get-AppOutput -OutputDirectory $appOutputDir -SignatureState signed
Test-AppNativeAbi -AppPath $unsignedApp
if ($null -ne $signedApp) {
    Test-AppNativeAbi -AppPath $signedApp
}
if (Test-Path -LiteralPath $localSigningConfigPath) {
    if (-not (Test-Path -LiteralPath $signedHap) -or $null -eq $signedApp) {
        throw 'Signing is configured, but signed HAP and APP outputs were not both generated'
    }
}
Write-Host "BUILD SUCCESS [$BuildMode, arm64-v8a]" -ForegroundColor Green
Write-Host "Unsigned HAP: $unsignedHap" -ForegroundColor Cyan
Write-Host "Unsigned APP: $unsignedApp" -ForegroundColor Cyan
if (Test-Path -LiteralPath $signedHap) {
    Write-Host "Signed HAP: $signedHap" -ForegroundColor Cyan
} else {
    Write-Host 'Signed HAP not generated. Create ignored signing.local.json5 before device deployment.' -ForegroundColor Yellow
}
if ($null -ne $signedApp) {
    Write-Host "Signed APP: $signedApp" -ForegroundColor Cyan
} else {
    Write-Host 'Signed APP not generated. Production signing is required before AppGallery upload.' -ForegroundColor Yellow
}

if ($Metadata) {
    $metadataDir = Join-Path $repoRoot 'build\outputs\metadata'
    $artifactDir = Join-Path $repoRoot 'build\outputs\release'
    $licenseDir = Join-Path $artifactDir 'licenses'
    New-Item -ItemType Directory -Force -Path $metadataDir | Out-Null
    New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
    $artifactDirPrefix = [IO.Path]::GetFullPath($artifactDir).TrimEnd('\') + '\'
    $licenseDirFull = [IO.Path]::GetFullPath($licenseDir)
    if (-not $licenseDirFull.StartsWith($artifactDirPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release license directory is outside the artifact directory: $licenseDirFull"
    }
    if (Test-Path -LiteralPath $licenseDir) {
        Remove-Item -LiteralPath $licenseDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
    $manifestPath = Join-Path $metadataDir 'build-manifest.json'
    $releaseUnsignedHap = Join-Path $artifactDir "LeanTTY-$ReleaseId-arm64-v8a-unsigned.hap"
    Copy-Item -LiteralPath $unsignedHap -Destination $releaseUnsignedHap -Force
    $releaseUnsignedApp = Join-Path $artifactDir "LeanTTY-$ReleaseId-arm64-v8a-unsigned.app"
    Copy-Item -LiteralPath $unsignedApp -Destination $releaseUnsignedApp -Force
    $releaseSignedHap = $null
    $releaseSignedApp = $null
    if (Test-Path -LiteralPath $signedHap) {
        $releaseSignedHap = Join-Path $artifactDir "LeanTTY-$ReleaseId-arm64-v8a-signed.hap"
        Copy-Item -LiteralPath $signedHap -Destination $releaseSignedHap -Force
    }
    if ($null -ne $signedApp) {
        $releaseSignedApp = Join-Path $artifactDir "LeanTTY-$ReleaseId-arm64-v8a-signed.app"
        Copy-Item -LiteralPath $signedApp -Destination $releaseSignedApp -Force
    }

    $signatureVerification = $null
    if ($null -ne $releaseSignedHap -and $null -ne $releaseSignedApp) {
        if (-not (Test-Path -LiteralPath $javaExe) -or -not (Test-Path -LiteralPath $signToolJar)) {
            throw 'DevEco signature verification tool is missing'
        }
        $expectedProfile = $localSigningConfig.material.profile
        $hapCertificateOutput = Join-Path $metadataDir 'hap-signing-cert-chain.cer'
        $hapProfileOutput = Join-Path $metadataDir 'hap-signing-profile.p7b'
        $appCertificateOutput = Join-Path $metadataDir 'app-signing-cert-chain.cer'
        $appProfileOutput = Join-Path $metadataDir 'app-signing-profile.p7b'
        $signatureVerification = [ordered]@{
            hap = Invoke-SignatureVerification `
                -ArtifactPath $releaseSignedHap `
                -CertificateOutput $hapCertificateOutput `
                -ProfileOutput $hapProfileOutput `
                -ExpectedProfile $expectedProfile
            app = Invoke-SignatureVerification `
                -ArtifactPath $releaseSignedApp `
                -CertificateOutput $appCertificateOutput `
                -ProfileOutput $appProfileOutput `
                -ExpectedProfile $expectedProfile
        }
    }

    $noticeSources = [ordered]@{
        'LICENSE-Apache-2.0.txt' = (Join-Path $repoRoot 'LICENSE')
        'THIRD_PARTY_NOTICES.md' = (Join-Path $repoRoot 'docs\THIRD_PARTY_NOTICES.md')
        'RUST_DEPENDENCIES.md' = (Join-Path $repoRoot 'docs\RUST_DEPENDENCIES.md')
        'OFL-1.1.txt' = (Join-Path $repoRoot 'docs\OFL-1.1.txt')
    }
    $noticeArtifacts = @()
    foreach ($noticeName in $noticeSources.Keys) {
        $noticeSource = $noticeSources[$noticeName]
        if (-not (Test-Path -LiteralPath $noticeSource)) {
            throw "Required release notice missing: $noticeSource"
        }
        $noticeDestination = Join-Path $licenseDir $noticeName
        Copy-Item -LiteralPath $noticeSource -Destination $noticeDestination -Force
        $noticeArtifacts += [ordered]@{
            path = Get-RepoRelativePath $noticeDestination
            sha256 = (Get-FileHash -LiteralPath $noticeDestination -Algorithm SHA256).Hash
        }
    }

    $rustLicenseDir = Join-Path $licenseDir 'rust'
    New-Item -ItemType Directory -Force -Path $rustLicenseDir | Out-Null
    Push-Location (Join-Path $repoRoot 'leantty_ssh')
    try {
        $cargoMetadataJson = & cargo metadata --locked --offline `
            --filter-platform aarch64-unknown-linux-ohos --format-version 1
        $cargoMetadataExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($cargoMetadataExitCode -ne 0) {
        throw 'Unable to resolve locked ARM64 Rust dependencies for release notices'
    }
    $cargoMetadata = ($cargoMetadataJson -join "`n") | ConvertFrom-Json
    $registryPackages = @($cargoMetadata.packages |
        Where-Object { $_.source -like 'registry+*' } |
        Sort-Object name, version)
    if ($registryPackages.Count -eq 0) {
        throw 'No locked ARM64 Rust registry dependencies found for release notices'
    }

    $rustPackageNotices = @()
    foreach ($package in $registryPackages) {
        if (-not $package.license -and -not $package.license_file) {
            throw "Rust package has no license metadata: $($package.name) $($package.version)"
        }

        $packageSourceDir = Split-Path -Parent $package.manifest_path
        $licenseFiles = @(Get-ChildItem -LiteralPath $packageSourceDir -File |
            Where-Object {
                $_.Name -match '^(?i:LICENSE|LICENCE|COPYING|COPYRIGHT|NOTICE|UNLICENSE)'
            })
        if ($package.license_file) {
            $declaredLicenseFile = Join-Path $packageSourceDir $package.license_file
            if (-not (Test-Path -LiteralPath $declaredLicenseFile -PathType Leaf)) {
                throw "Declared Rust license file is missing: $declaredLicenseFile"
            }
            if ($licenseFiles.FullName -notcontains $declaredLicenseFile) {
                $licenseFiles += Get-Item -LiteralPath $declaredLicenseFile
            }
        }
        $licenseFiles = @($licenseFiles | Sort-Object FullName -Unique)

        $fallbackNotice = $null
        if ($licenseFiles.Count -eq 0) {
            switch -Regex ($package.license) {
                '^MIT$' { $fallbackNotice = '../THIRD_PARTY_NOTICES.md'; break }
                '^Apache-2\.0$' { $fallbackNotice = '../LICENSE-Apache-2.0.txt'; break }
                '^(MIT OR Apache-2\.0|Apache-2\.0 OR MIT|MIT/Apache-2\.0)$' {
                    $fallbackNotice = '../THIRD_PARTY_NOTICES.md and ../LICENSE-Apache-2.0.txt'
                    break
                }
                default {
                    throw "Rust package has no distributable license file: $($package.name) $($package.version)"
                }
            }
        }

        $packageDirName = "$($package.name)-$($package.version)"
        $packageLicenseDir = Join-Path $rustLicenseDir $packageDirName
        $copiedLicensePaths = @()
        if ($licenseFiles.Count -gt 0) {
            New-Item -ItemType Directory -Force -Path $packageLicenseDir | Out-Null
            $usedNames = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            foreach ($licenseFile in $licenseFiles) {
                $destinationName = $licenseFile.Name
                if (-not $usedNames.Add($destinationName)) {
                    $destinationName = "$($usedNames.Count)-$destinationName"
                    [void]$usedNames.Add($destinationName)
                }
                $licenseDestination = Join-Path $packageLicenseDir $destinationName
                Copy-Item -LiteralPath $licenseFile.FullName -Destination $licenseDestination -Force
                $copiedLicensePaths += Get-RepoRelativePath $licenseDestination
                $noticeArtifacts += [ordered]@{
                    path = Get-RepoRelativePath $licenseDestination
                    sha256 = (Get-FileHash -LiteralPath $licenseDestination -Algorithm SHA256).Hash
                }
            }
        }

        $rustPackageNotices += [ordered]@{
            name = $package.name
            version = $package.version
            license = $package.license
            licenseFile = $package.license_file
            authors = @($package.authors)
            repository = $package.repository
            files = $copiedLicensePaths
            fallbackNotice = $fallbackNotice
        }
    }
    $rustNoticeIndexPath = Join-Path $rustLicenseDir 'packages.json'
    Set-Content -LiteralPath $rustNoticeIndexPath `
        -Value (ConvertTo-Json -InputObject $rustPackageNotices -Depth 4) -Encoding UTF8
    $noticeArtifacts += [ordered]@{
        path = Get-RepoRelativePath $rustNoticeIndexPath
        sha256 = (Get-FileHash -LiteralPath $rustNoticeIndexPath -Algorithm SHA256).Hash
    }

    $gitCommit = (git -C $repoRoot rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve Git commit for build manifest' }
    $gitStatus = @(git -C $repoRoot status --porcelain 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve Git dirty state for build manifest' }

    $manifest = [ordered]@{
        schemaVersion = 2
        releaseId = $ReleaseId
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
        git = [ordered]@{
            commit = $gitCommit
            dirty = ($gitStatus.Count -gt 0)
        }
        product = $productName
        buildMode = $BuildMode
        abi = 'arm64-v8a'
        nativeSo = [ordered]@{
            path = Get-RepoRelativePath $nativeSo
            sha256 = (Get-FileHash -LiteralPath $nativeSo -Algorithm SHA256).Hash
        }
        unsignedHap = [ordered]@{
            path = Get-RepoRelativePath $releaseUnsignedHap
            sha256 = (Get-FileHash -LiteralPath $releaseUnsignedHap -Algorithm SHA256).Hash
        }
        signedHap = $null
        unsignedApp = [ordered]@{
            path = Get-RepoRelativePath $releaseUnsignedApp
            sha256 = (Get-FileHash -LiteralPath $releaseUnsignedApp -Algorithm SHA256).Hash
        }
        signedApp = $null
        signatureVerification = $signatureVerification
        notices = $noticeArtifacts
    }
    if ($null -ne $releaseSignedHap) {
        $manifest['signedHap'] = [ordered]@{
            path = Get-RepoRelativePath $releaseSignedHap
            sha256 = (Get-FileHash -LiteralPath $releaseSignedHap -Algorithm SHA256).Hash
        }
    }
    if ($null -ne $releaseSignedApp) {
        $manifest['signedApp'] = [ordered]@{
            path = Get-RepoRelativePath $releaseSignedApp
            sha256 = (Get-FileHash -LiteralPath $releaseSignedApp -Algorithm SHA256).Hash
        }
    }
    Set-Content -LiteralPath $manifestPath -Value (ConvertTo-Json -InputObject $manifest -Depth 4) -Encoding UTF8
    Write-Host "Manifest: $manifestPath" -ForegroundColor Cyan
}
