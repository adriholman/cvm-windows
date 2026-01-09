#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated release script for cvm
.DESCRIPTION
    Creates a git tag and pushes to GitHub. GitHub Actions will automatically create the release archive.
    Requires git to be installed and configured.
.PARAMETER Version
    Version to release (reads from VERSION file if not provided)
.PARAMETER Push
    Actually push to GitHub (default: false for safety - shows what would happen)
.EXAMPLE
    .\release.ps1 -Push
    # Creates v1.1.0 tag and pushes to GitHub
.EXAMPLE
    .\release.ps1 -Version 1.2.0 -Push
    # Creates v1.2.0 tag and pushes to GitHub
#>
param(
    [string]$Version,
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

# Read version from file if not provided
if (-not $Version) {
    $versionFile = Join-Path $projectRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        Write-Error-Custom "VERSION file not found"
        exit 1
    }
    $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
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
    Write-Host $gitStatus
    Write-Error-Custom "Please commit all changes before releasing"
    exit 1
}
Write-Success "Working directory is clean"

# Step 2: Check if tag already exists
Write-Step "Checking if tag already exists..."
$tagExists = & git tag | Where-Object { $_ -eq $tag }
if ($tagExists) {
    Write-Error-Custom "Tag $tag already exists"
    exit 1
}
Write-Success "Tag $tag does not exist"

# Step 3: Create git tag
Write-Step "Creating git tag $tag..."
& git tag -a $tag -m "Release version $Version"
Write-Success "Created tag $tag"

# Step 4: Summary and push confirmation
Write-Header "RELEASE READY"
Write-Host "Version:      $Version" -ForegroundColor Cyan
Write-Host "Tag:          $tag" -ForegroundColor Cyan
Write-Host "Git Status:   Tag created (not pushed)" -ForegroundColor Yellow

if (-not $Push) {
    Write-Host "`n⚠️  DRY RUN MODE" -ForegroundColor Yellow
    Write-Host "To push to GitHub, run:" -ForegroundColor Yellow
    Write-Host "  .\release.ps1 -Push" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commands that WOULD be executed:" -ForegroundColor Yellow
    Write-Host "  git push origin $tag" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To delete this test tag, run:" -ForegroundColor Yellow
    Write-Host "  git tag -d $tag" -ForegroundColor Gray
    exit 0
}

# Step 5: Push tag to GitHub
Write-Step "Pushing tag to GitHub..."
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
