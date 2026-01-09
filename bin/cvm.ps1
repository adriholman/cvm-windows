<#
.SYNOPSIS
    cvm - Composer Version Manager for Windows
.DESCRIPTION
    Composer version manager that allows installing and using multiple versions.
    Supports channels (1, 2, stable, preview) and exact versions (e.g., 2.7.1).
.PARAMETER Args
    Arguments passed to the script
.EXAMPLE
    cvm install 2
    cvm default stable
    cvm which
    cvm require vendor/package
#>
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Script:DownloadTimeoutSec = 45
$Script:DownloadRetries   = 3
$Script:RetryDelaySec     = 3

#region Helper Functions

function Write-Info($msg) {
    Write-Host "[cvm] $msg" -ForegroundColor Cyan
}

function Write-Err($msg) {
    Write-Host "[cvm] ERROR: $msg" -ForegroundColor Red
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Description,
        [int]$MaxAttempts = $Script:DownloadRetries,
        [int]$DelaySeconds = $Script:RetryDelaySec
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            return & $Action
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $MaxAttempts) { break }
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "Failed $Description after $MaxAttempts attempts. Last error: $lastError"
}

function Ensure-Dir($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        [void](New-Item -ItemType Directory -Path $path -Force)
    }
}

function Get-CvmRoot {
    Join-Path $env:USERPROFILE '.cvm'
}

function Get-VersionsDir {
    Join-Path (Get-CvmRoot) 'versions'
}

function Get-ConfigPath {
    Join-Path (Get-CvmRoot) 'config.json'
}

function Get-DefaultVersion {
    $cfg = Get-ConfigPath
    if (Test-Path -LiteralPath $cfg) {
        try {
            $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
            if ($json.default) { return [string]$json.default }
        } catch {}
    }
    return 'stable'
}

function Set-DefaultVersion([string]$version) {
    $root = Get-CvmRoot
    Ensure-Dir $root
    $cfg = Get-ConfigPath
    @{ default = $version } | ConvertTo-Json | Set-Content -LiteralPath $cfg -Encoding UTF8
    Write-Info "Default version set: $version"
}

function Find-ComposerVersionFile {
    $dir = (Get-Location).Path
    while ($true) {
        $file = Join-Path $dir '.composer-version'
        if (Test-Path -LiteralPath $file) {
            $content = (Get-Content -LiteralPath $file -Raw).Trim()
            if ($content) { return $content }
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Resolve-DesiredVersion {
    # 1. Variable de entorno
    if ($env:CVM_VERSION) { return $env:CVM_VERSION.Trim() }
    
    # 2. Archivo .composer-version
    $fileVersion = Find-ComposerVersionFile
    if ($fileVersion) { return $fileVersion }
    
    # 3. Default global
    return Get-DefaultVersion
}

function Get-DownloadUrl([string]$version) {
    switch -Regex ($version) {
        '^1$'                   { return 'https://getcomposer.org/download/latest-1.x/composer.phar' }
        '^2$'                   { return 'https://getcomposer.org/download/latest-2.x/composer.phar' }
        '^stable$'              { return 'https://getcomposer.org/download/latest-stable/composer.phar' }
        '^preview$'             { return 'https://getcomposer.org/download/latest-preview/composer.phar' }
        '^\d+\.\d+\.\d+$'       { return "https://getcomposer.org/download/$version/composer.phar" }
        default { throw "Invalid version: '$version'. Use: 1, 2, stable, preview or x.y.z" }
    }
}

function Get-DownloadEndpoints([string]$version) {
    $primary = Get-DownloadUrl $version
    $fallback = $null

    switch -Regex ($version) {
        '^1$'       { $fallback = 'https://getcomposer.org/composer-1.phar' }
        '^2$'       { $fallback = 'https://getcomposer.org/composer-2.phar' }
        '^stable$'  { $fallback = 'https://getcomposer.org/composer-stable.phar' }
        '^preview$' { $fallback = 'https://getcomposer.org/composer-preview.phar' }
        '^\d+\.\d+\.\d+$' { $fallback = "https://github.com/composer/composer/releases/download/$version/composer.phar" }
    }

    $shaPrimary = $null
    $shaFallback = $null
    if (Test-ExactVersion $version) {
        $shaPrimary = $primary -replace 'composer\.phar$', 'composer.phar.sha256sum'
        $shaFallback = if ($fallback) { $fallback -replace 'composer\.phar$', 'composer.phar.sha256sum' } else { $null }
    }

    $endpoints = @()
    $endpoints += @{ Url = $primary; ShaUrl = $shaPrimary }
    if ($fallback -and $fallback -ne $primary) {
        $endpoints += @{ Url = $fallback; ShaUrl = $shaFallback }
    }
    return $endpoints
}

function Test-ExactVersion([string]$version) {
    return $version -match '^\d+\.\d+\.\d+$'
}

function Get-PharPath([string]$version) {
    Join-Path (Join-Path (Get-VersionsDir) $version) 'composer.phar'
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [int]$TimeoutSec = $Script:DownloadTimeoutSec
    )

    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec $TimeoutSec
        if (-not (Test-Path -LiteralPath $Destination)) {
            throw "Download completed without creating $Destination"
        }
    } catch {
        $errMsg = $_.Exception.Message
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
        throw "Error downloading from ${Url}: $errMsg"
    }
}

function Verify-Checksum {
    param(
        [Parameter(Mandatory)][string]$PharPath,
        [Parameter(Mandatory)][string]$ShaUrl,
        [Parameter(Mandatory)][string]$ShaDestination,
        [int]$TimeoutSec = $Script:DownloadTimeoutSec
    )

    Invoke-DownloadFile -Url $ShaUrl -Destination $ShaDestination -TimeoutSec $TimeoutSec

    $expected = (Get-Content -LiteralPath $ShaDestination -Raw).Split()[0].Trim()
    $actual = (Get-FileHash -LiteralPath $PharPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($expected.ToLowerInvariant() -ne $actual) {
        Remove-Item -LiteralPath $PharPath -Force -ErrorAction SilentlyContinue
        throw "Invalid checksum. Expected: $expected, Actual: $actual"
    }
}

function Download-ComposerArtifact {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PharPath,
        [Parameter(Mandatory)][string]$VersionDir
    )

    $endpoints = Get-DownloadEndpoints $Version
    $lastError = $null

    foreach ($endpoint in $endpoints) {
        try {
            Write-Info "Downloading $($endpoint.Url) ..."
            Invoke-WithRetry -Description "download $Version" -Action { Invoke-DownloadFile -Url $endpoint.Url -Destination $PharPath -TimeoutSec $Script:DownloadTimeoutSec }

            if ($endpoint.ShaUrl) {
                $shaFile = Join-Path $VersionDir 'composer.phar.sha256sum'
                Invoke-WithRetry -Description "download checksum for $Version" -Action { Verify-Checksum -PharPath $PharPath -ShaUrl $endpoint.ShaUrl -ShaDestination $shaFile -TimeoutSec $Script:DownloadTimeoutSec }
                Write-Info "SHA256 checksum verified"
            } else {
                Write-Info "Channel version - checksum skipped"
            }

            return
        } catch {
            $lastError = $_.Exception.Message
            Write-Err "Attempt failed from $($endpoint.Url): $lastError"
            if (Test-Path -LiteralPath $PharPath) { Remove-Item -LiteralPath $PharPath -Force -ErrorAction SilentlyContinue }
        }
    }

    throw "Failed to download Composer $Version from all endpoints. Last error: $lastError"
}

function Install-ComposerVersion([string]$version) {
    $versionsDir = Get-VersionsDir
    Ensure-Dir $versionsDir
    
    $versionDir = Join-Path $versionsDir $version
    Ensure-Dir $versionDir
    
    $pharPath = Join-Path $versionDir 'composer.phar'

    if (Test-Path -LiteralPath $pharPath) {
        Write-Info "Already installed: $pharPath"
        return $pharPath
    }

    Download-ComposerArtifact -Version $version -PharPath $pharPath -VersionDir $versionDir
    Write-Info "Downloaded: $pharPath"
    return $pharPath
}

function Ensure-VersionInstalled([string]$version) {
    $phar = Get-PharPath $version
    if (-not (Test-Path -LiteralPath $phar)) {
        Write-Info "Installing version: $version"
        $phar = Install-ComposerVersion $version
    }
    return $phar
}

function Get-PhpExe {
    $php = 'php'
    try {
        $null = & $php -v 2>&1
        return $php
    } catch {
        throw "PHP CLI not found in PATH. Install PHP and add it to PATH."
    }
}

function Get-InstalledVersions {
    $versionsDir = Get-VersionsDir
    if (-not (Test-Path -LiteralPath $versionsDir)) { return @() }
    Get-ChildItem -LiteralPath $versionsDir -Directory | Select-Object -ExpandProperty Name
}

#endregion

#region Commands

function Cmd-Install([string]$version) {
    if (-not $version) {
        Write-Err "Missing version"
        Write-Host "Usage: cvm install <1|2|stable|preview|x.y.z>" -ForegroundColor Yellow
        exit 1
    }
    
    Install-ComposerVersion $version | Out-Null
    Write-Info "Installation completed: $version"
}

function Cmd-Default([string]$version) {
    if (-not $version) {
        Write-Err "Missing version"
        Write-Host "Usage: cvm default <1|2|stable|preview|x.y.z>" -ForegroundColor Yellow
        exit 1
    }
    
    # Verify version is installed before setting as default
    $phar = Get-PharPath $version
    if (-not (Test-Path -LiteralPath $phar)) {
        Write-Err "Version '$version' is not installed"
        Write-Host "Install it first: cvm install $version" -ForegroundColor Yellow
        exit 1
    }
    
    Set-DefaultVersion $version
}

function Cmd-List {
    $installed = Get-InstalledVersions
    $default = Get-DefaultVersion
    
    if (-not $installed -or $installed.Count -eq 0) {
        Write-Info "No versions installed"
        Write-Host "Run: cvm install <version>" -ForegroundColor Yellow
        return
    }
    
    Write-Info "Installed versions:"
    foreach ($v in ($installed | Sort-Object)) {
        if ($v -eq $default) {
            Write-Host "  * $v" -ForegroundColor Green
        } else {
            Write-Host "    $v"
        }
    }
}

function Cmd-Which {
    $version = Resolve-DesiredVersion
    $phar = Get-PharPath $version
    $exists = Test-Path -LiteralPath $phar
    
    $source = if ($env:CVM_VERSION) { 
        "env:CVM_VERSION" 
    } elseif (Find-ComposerVersionFile) { 
        ".composer-version" 
    } else { 
        "default global" 
    }
    
    [PSCustomObject]@{
        Source         = $source
        VersionSpec    = $version
        PharExists     = $exists
        PharPath       = if ($exists) { $phar } else { "(not installed)" }
        CacheDirectory = Get-VersionsDir
        ConfigPath     = Get-ConfigPath
    } | Format-List
}

function Cmd-Version {
    $versionFile = Join-Path $PSScriptRoot '..\VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        $ver = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        Write-Host "cvm version $ver" -ForegroundColor Green
    } else {
        Write-Host "cvm version unknown" -ForegroundColor Yellow
    }
}

function Show-Help {
    @'
cvm - Composer Version Manager for Windows

USAGE:
  cvm install <version>    Install a Composer version
  cvm default <version>    Set the global default version
  cvm list                 List installed versions
  cvm which                Show current version and its source
  cvm version              Show cvm version
  cvm <args>               Run composer with resolved version

SUPPORTED VERSIONS:
  1        - Latest Composer 1.x version
  2        - Latest Composer 2.x version
  stable   - Latest stable version
  preview  - Latest preview/beta version
  x.y.z    - Specific version (e.g., 2.7.1)

EXAMPLES:
  cvm install 2
  cvm default stable
  cvm require symfony/console
  cvm --version

CONFIGURATION:
  Environment variable: $env:CVM_VERSION
  Project file:         .composer-version
  Global default:       %USERPROFILE%\.cvm\config.json

For more information: https://github.com/adriholman/cvm
'@ | Write-Host
}

#endregion

#region Main

if (-not $Args -or $Args.Count -eq 0) {
    # No arguments, show help
    Show-Help
    exit 0
}

$cmd = $Args[0].ToLowerInvariant()

switch ($cmd) {
    'install' {
        Cmd-Install -version $Args[1]
        exit 0
    }
    'default' {
        Cmd-Default -version $Args[1]
        exit 0
    }
    'list' {
        Cmd-List
        exit 0
    }
    'which' {
        Cmd-Which
        exit 0
    }
    'version' {
        Cmd-Version
        exit 0
    }
    { $_ -in @('help', '--help', '-h', '-?') } {
        Show-Help
        exit 0
    }
    default {
        # Proxy to composer
        $version = Resolve-DesiredVersion
        $phar = Ensure-VersionInstalled $version
        $php = Get-PhpExe
        
        Write-Info "Using Composer $version"
        
        & $php $phar @Args
        exit $LASTEXITCODE
    }
}

#endregion
