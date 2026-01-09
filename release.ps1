#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated release script for cvm
.DESCRIPTION
    Creates a git tag and pushes to GitHub. GitHub Actions will automatically create the release archive.
    Requires git to be installed and configured.
.PARAMETER Version
    Version to release (reads from VERSION file if not provided)
.PARAMETER Major
    Auto-increment major version (X.0.0)
.PARAMETER Minor
    Auto-increment minor version (X.Y.0)
.PARAMETER Patch
    Auto-increment patch version (X.Y.Z)
.PARAMETER Push
    Actually push to GitHub (default: false for safety - shows what would happen)
.EXAMPLE
    .\release.ps1 -Patch -Push
    # Increments patch (1.1.5 -> 1.1.6) and pushes to GitHub
.EXAMPLE
    .\release.ps1 -Minor -Push
    # Increments minor (1.1.5 -> 1.2.0) and pushes to GitHub
.EXAMPLE
    .\release.ps1 -Version 2.0.0 -Push
    # Uses explicit version 2.0.0 and pushes to GitHub
#>
param(
    [string]$Version,
    [switch]$Major,
    [switch]$Minor,
    [switch]$Patch,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Header([string]$Message) {
    Write-Host "`n" + ('=' * 70) -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Write-Step([string]$Message) {
    Write-Host "`n→ $Message" -ForegroundColor Yellow
}

function Write-Success([string]$Message) {
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom([string]$Message) {
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Check if git is available
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitPath) {
    Write-Error-Custom "git is not installed or not in PATH"
    exit 1
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $scriptDir
$versionFile = Join-Path $projectRoot 'VERSION'

# Check for mutually exclusive increment flags
$incrementFlags = @(@($Major, $Minor, $Patch) | Where-Object { $_ })
if ($incrementFlags.Count -gt 1) {
    Write-Error-Custom "Cannot use -Major, -Minor, and -Patch together. Choose one."
    exit 1
}

if ($Version -and $incrementFlags.Count -gt 0) {
    Write-Error-Custom "Cannot use -Version with -Major/-Minor/-Patch. Choose one approach."
    exit 1
}

# Read current version from file
if (-not (Test-Path -LiteralPath $versionFile)) {
    Write-Error-Custom "VERSION file not found"
    exit 1
}
$currentVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()

# Auto-increment or use provided/current version
if ($Major -or $Minor -or $Patch) {
    try {
        $ver = [version]$currentVersion
        if ($Major) {
            $Version = "$($ver.Major + 1).0.0"
        } elseif ($Minor) {
            $Version = "$($ver.Major).$($ver.Minor + 1).0"
        } elseif ($Patch) {
            $Version = "$($ver.Major).$($ver.Minor).$($ver.Build + 1)"
        }
        Write-Host "Auto-increment: $currentVersion -> $Version" -ForegroundColor Cyan
    } catch {
        Write-Error-Custom "Failed to parse current version '$currentVersion' as semantic version"
        exit 1
    }
} elseif (-not $Version) {
    # Use current version from file
    $Version = $currentVersion
}

Write-Header "CVM RELEASE AUTOMATION v$Version"

# Validate version format
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error-Custom "Invalid version format: $Version (expected: X.Y.Z)"
    exit 1
}

$tag = "v$Version"

# Step 1: Check git status
Write-Step "Checking git status..."
$gitStatus = & git status --porcelain
if ($gitStatus) {
    Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
    Write-Host ($gitStatus -join "`n")
    Write-Error-Custom "Please commit all changes before releasing"
    exit 1
}
Write-Success "Working directory is clean"

# Step 2: Check if tag already exists
Write-Step "Checking if tag already exists..."
$tagExists = & git tag | Where-Object { $_ -eq $tag }
if ($tagExists) {
    Write-Host "Tag $tag already exists locally" -ForegroundColor Yellow
    if (-not $Push) {
        Write-Host "Dry run: no changes made. Delete with 'git tag -d $tag' if you want to recreate." -ForegroundColor Yellow
    } else {
        Write-Host "Will reuse existing local tag and push it." -ForegroundColor Yellow
    }
} else {
    Write-Success "Tag $tag does not exist"
}

# Step 3: Create git tag (only when pushing and tag not present)
if ($Push -and -not $tagExists) {
    Write-Step "Creating git tag $tag..."
    
    # Update and commit VERSION file if it was auto-incremented
    if ($Major -or $Minor -or $Patch) {
        Set-Content -LiteralPath $versionFile -Value $Version -Encoding UTF8 -NoNewline
        Write-Success "Updated VERSION file to $Version"
        
        & git add VERSION
        & git commit -m "Bump version to $Version"
        Write-Success "Committed VERSION update"
    }
    
    & git tag -a $tag -m "Release version $Version"
    Write-Success "Created tag $tag"
}

# Step 4: Summary and push confirmation
Write-Header "RELEASE READY"
Write-Host "Version:      $Version" -ForegroundColor Cyan
Write-Host "Tag:          $tag" -ForegroundColor Cyan
Write-Host "Git Status:   $(if ($Push) { 'Tag ready to push' } else { 'No changes (dry run)' })" -ForegroundColor Yellow

if (-not $Push) {
    Write-Host "`n⚠️  DRY RUN MODE" -ForegroundColor Yellow
    Write-Host "To create and push, run:" -ForegroundColor Yellow
    Write-Host "  .\release.ps1 $(if ($Major) { '-Major' } elseif ($Minor) { '-Minor' } elseif ($Patch) { '-Patch' }) -Push" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commands that WOULD be executed:" -ForegroundColor Yellow
    if ($Major -or $Minor -or $Patch) { 
        Write-Host "  Set-Content VERSION '$Version'" -ForegroundColor Gray
        Write-Host "  git add VERSION" -ForegroundColor Gray
        Write-Host "  git commit -m 'Bump version to $Version'" -ForegroundColor Gray
    }
    if (-not $tagExists) { Write-Host "  git tag -a $tag -m 'Release version $Version'" -ForegroundColor Gray }
    if ($Major -or $Minor -or $Patch) { Write-Host "  git push origin main" -ForegroundColor Gray }
    Write-Host "  git push origin $tag" -ForegroundColor Gray
    exit 0
}

# Step 5: Push tag to GitHub
Write-Step "Pushing tag to GitHub..."

# Push VERSION commit if it was auto-incremented
if (($Major -or $Minor -or $Patch) -and -not $tagExists) {
    Write-Host "  • git push origin main"
    & git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to push VERSION update"
        exit 1
    }
}

Write-Host "  • git push origin $tag"
& git push origin $tag
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Failed to push tag"
    exit 1
}
Write-Success "Pushed tag $tag"

# Step 6: Success
Write-Header "✓ RELEASE PUBLISHED"
Write-Host "Release v$Version tag has been pushed!" -ForegroundColor Green
Write-Host ""
Write-Host "What happens next:" -ForegroundColor Yellow
Write-Host "  1. GitHub Actions detects the new tag" -ForegroundColor Cyan
Write-Host "  2. Workflow creates cvm-release.zip automatically" -ForegroundColor Cyan
Write-Host "  3. Release is published with the archive attached" -ForegroundColor Cyan
Write-Host "  4. Users can then run: cvm selfupdate" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitor progress at:" -ForegroundColor Yellow
Write-Host "  https://github.com/adriholman/cvm-windows/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host "View release (once ready):" -ForegroundColor Yellow
Write-Host "  https://github.com/adriholman/cvm-windows/releases/tag/$tag" -ForegroundColor Cyan
Write-Host ""
