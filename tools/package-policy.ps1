function Assert-LeanTTYReleasePackageExcludesAcceptanceMarkers {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [string[]]$Markers = @(
            'ACCEPTANCE_INPUT_SUBMIT',
            'ACCEPTANCE_WARM_TAB_EVICTED',
            'Acceptance: Rebuild Renderer',
            'Acceptance renderer',
            'terminateRendererForAcceptance',
            'pasteClipboardForAcceptance',
            'logAcceptanceInputSubmit',
            'acceptanceInputSequence'
        )
    )

    $resolvedPackage = [IO.Path]::GetFullPath($PackagePath)
    if (-not (Test-Path -LiteralPath $resolvedPackage -PathType Leaf)) {
        throw "Release package is missing: $resolvedPackage"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($resolvedPackage)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.Length -eq 0) { continue }
            $stream = $entry.Open()
            try {
                $memory = [IO.MemoryStream]::new()
                try {
                    $stream.CopyTo($memory)
                    $bytes = $memory.ToArray()
                } finally {
                    $memory.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
            $singleByteText = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
            $utf16Text = [Text.Encoding]::Unicode.GetString($bytes)
            foreach ($marker in $Markers) {
                if ($singleByteText.IndexOf($marker, [StringComparison]::Ordinal) -ge 0 -or
                    $utf16Text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
                    throw "Release package contains acceptance-only marker '$marker' in $($entry.FullName)"
                }
            }
        }
    } finally {
        $archive.Dispose()
    }
}
