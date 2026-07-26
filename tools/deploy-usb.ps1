<#
.SYNOPSIS
  Compatibility wrapper for USB-only HarmonyOS PC deployment.
.DESCRIPTION
  The default development entry is tools/dev-pc.ps1. This wrapper preserves
  the old command while requiring the selected HDC target to use USB.
#>
param(
    [string]$Target = '',
    [string]$HapPath = '',
    [switch]$SkipBuild,
    [switch]$NoLaunch,
    [switch]$FollowLogs
)

$ErrorActionPreference = 'Stop'
$arguments = @{ Target = $Target; HapPath = $HapPath; RequireUsb = $true }
if ($SkipBuild) { $arguments['SkipBuild'] = $true }
if ($NoLaunch) { $arguments['NoLaunch'] = $true }
if ($FollowLogs) { $arguments['FollowLogs'] = $true }

& (Join-Path $PSScriptRoot 'dev-pc.ps1') @arguments
if ($LASTEXITCODE -ne 0) { throw 'USB PC deployment failed' }
