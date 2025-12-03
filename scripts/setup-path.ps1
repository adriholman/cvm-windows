<#
.SYNOPSIS
    Installer/uninstaller for cvm (Composer Version Manager)
.DESCRIPTION
    Copies the main script to %USERPROFILE%\.cvm\bin and configures PATH.
    Optionally adds aliases to the PowerShell profile.
.PARAMETER Action
    Action to perform: install, uninstall, alias-only
.PARAMETER AddAlias
    Adds aliases (cvm, composer) to the PowerShell profile
#>
param(
    [ValidateSet('install','uninstall')]
    [string]$Action = 'install'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$UserHome = [Environment]::GetFolderPath('UserProfile')
$TargetBin = Join-Path $UserHome ".cvm\bin"
$ProfilePath = $PROFILE

function Ensure-Dir($p) { 
    if (-not (Test-Path -LiteralPath $p)) { 
        [void](New-Item -ItemType Directory -Path $p) 
    } 
}

function Write-Info($m) { 
    Write-Host "[setup] $m" -ForegroundColor Cyan 
}

function Update-UserPath([string]$dir, [switch]$Remove) {
    $current = [Environment]::GetEnvironmentVariable('Path','User')
    $sep = ';'
    $parts = @($current -split ';' | Where-Object { $_ -ne '' })
    $exists = $parts -contains $dir
    
    if ($Remove) {
        if ($exists) { 
            $parts = $parts | Where-Object { $_ -ne $dir } 
            Write-Info "Removing from user PATH: $dir"
        } else {
            Write-Info "User PATH does not contain: $dir (already removed)"
            return
        }
    } else {
        if (-not $exists) { 
            $parts = @($dir) + $parts 
            Write-Info "Adding to user PATH: $dir"
        } else {
            Write-Info "User PATH already contains: $dir"
            return
        }
    }
    
    $newPath = ($parts -join $sep)
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:Path = "$newPath;$([Environment]::GetEnvironmentVariable('Path','Machine'))"
}

## Alias setup removed: cvm is used directly via PATH.

switch ($Action) {
    'install' {
        Ensure-Dir $TargetBin
        
        # Copy script from repo to user directory
        $repoScript = Join-Path $PSScriptRoot '..\bin\cvm.ps1'
        if (-not (Test-Path -LiteralPath $repoScript)) {
            Write-Error "bin\cvm.ps1 not found in repository. Run this script from the repo root."
            exit 1
        }
        
        $targetScript = Join-Path $TargetBin 'cvm.ps1'
        Copy-Item -LiteralPath $repoScript -Destination $targetScript -Force
        Write-Info "Copied bin\cvm.ps1 -> $targetScript"

        # Also deploy composer launcher
        $repoComposer = Join-Path $PSScriptRoot '..\bin\composer.ps1'
        if (-not (Test-Path -LiteralPath $repoComposer)) {
            Write-Error "bin\composer.ps1 not found in repository."
            exit 1
        }
        $targetComposer = Join-Path $TargetBin 'composer.ps1'
        Copy-Item -LiteralPath $repoComposer -Destination $targetComposer -Force
        Write-Info "Copied bin\composer.ps1 -> $targetComposer"
        
        # Copy VERSION file
        $repoVersion = Join-Path $PSScriptRoot '..\VERSION'
        if (Test-Path -LiteralPath $repoVersion) {
            $cvmRoot = Split-Path $TargetBin -Parent
            $targetVersion = Join-Path $cvmRoot 'VERSION'
            Copy-Item -LiteralPath $repoVersion -Destination $targetVersion -Force
            Write-Info "Copied VERSION -> $targetVersion"
        }
        
        # Create .cmd wrappers for cross-shell compatibility
        $cvmCmd = Join-Path $TargetBin 'cvm.cmd'
        $composerCmd = Join-Path $TargetBin 'composer.cmd'
        Set-Content -Path $cvmCmd -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0cvm.ps1`" %*" -Encoding ASCII
        Set-Content -Path $composerCmd -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0composer.ps1`" %*" -Encoding ASCII
        Write-Info "Created .cmd wrappers for cross-shell compatibility"
        
        # Add to PATH
        Update-UserPath -dir $TargetBin
        
        Write-Host "`n✓ Installation completed" -ForegroundColor Green
        Write-Host "  Script installed in: $targetScript" -ForegroundColor Gray
        Write-Host "  Open a NEW terminal to use 'cvm' and 'composer'" -ForegroundColor Yellow
    }
    
    'uninstall' {
        $targetScript = Join-Path $TargetBin 'cvm.ps1'
        if (Test-Path -LiteralPath $targetScript) {
            Remove-Item -LiteralPath $targetScript -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $targetScript"
        }

        $targetComposer = Join-Path $TargetBin 'composer.ps1'
        if (Test-Path -LiteralPath $targetComposer) {
            Remove-Item -LiteralPath $targetComposer -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $targetComposer"
        }
        
        # Remove .cmd wrappers
        $cvmCmd = Join-Path $TargetBin 'cvm.cmd'
        $composerCmd = Join-Path $TargetBin 'composer.cmd'
        if (Test-Path -LiteralPath $cvmCmd) {
            Remove-Item -LiteralPath $cvmCmd -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $cvmCmd"
        }
        if (Test-Path -LiteralPath $composerCmd) {
            Remove-Item -LiteralPath $composerCmd -Force -ErrorAction SilentlyContinue
            Write-Info "Removed: $composerCmd"
        }

        # Remove PATH entry
        Update-UserPath -dir $TargetBin -Remove

        # Clean all cvm data: bin, versions, config
        $cvmRoot = Split-Path $TargetBin -Parent
        $versionsDir = Join-Path $cvmRoot 'versions'
        if (Test-Path -LiteralPath $versionsDir) {
            Write-Info "Removing versions cache: $versionsDir"
            Remove-Item -LiteralPath $versionsDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $TargetBin) {
            Write-Info "Removing bin directory: $TargetBin"
            Remove-Item -LiteralPath $TargetBin -Recurse -Force -ErrorAction SilentlyContinue
        }
        $configPath = Join-Path $cvmRoot 'config.json'
        if (Test-Path -LiteralPath $configPath) {
            Write-Info "Removing config: $configPath"
            Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        }
        # Remove root if empty (or force removal)
        if (Test-Path -LiteralPath $cvmRoot) {
            try {
                Remove-Item -LiteralPath $cvmRoot -Recurse -Force -ErrorAction SilentlyContinue
                Write-Info "Removed root: $cvmRoot"
            } catch { }
        }

        Write-Host "`n✓ Uninstallation completed (all cvm files removed)" -ForegroundColor Green
    }
    
    default { }
}
