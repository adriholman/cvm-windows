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

#region Helper Functions

function Write-Info($msg) {
    Write-Host "[cvm] $msg" -ForegroundColor Cyan
}

function Write-Err($msg) {
    Write-Host "[cvm] ERROR: $msg" -ForegroundColor Red
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

function Test-ExactVersion([string]$version) {
    return $version -match '^\d+\.\d+\.\d+$'
}

function Get-PharPath([string]$version) {
    Join-Path (Join-Path (Get-VersionsDir) $version) 'composer.phar'
}

function Install-ComposerVersion([string]$version) {
    $versionsDir = Get-VersionsDir
    Ensure-Dir $versionsDir
    
    $versionDir = Join-Path $versionsDir $version
    Ensure-Dir $versionDir
    
    $pharPath = Join-Path $versionDir 'composer.phar'
    $url = Get-DownloadUrl $version
    
    if (Test-Path -LiteralPath $pharPath) {
        Write-Info "Already installed: $pharPath"
        return $pharPath
    }
    
    Write-Info "Downloading $url ..."
    
    try {
        # Asegurar TLS 1.2
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        } catch {}
        
        Invoke-WebRequest -Uri $url -OutFile $pharPath -UseBasicParsing
        Write-Info "Downloaded: $pharPath"
        
        # Verify checksum for exact versions
        if (Test-ExactVersion $version) {
            $shaUrl = $url -replace 'composer\.phar$', 'composer.phar.sha256sum'
            $shaFile = Join-Path $versionDir 'composer.phar.sha256sum'
            
            try {
                Invoke-WebRequest -Uri $shaUrl -OutFile $shaFile -UseBasicParsing
                $expected = (Get-Content -LiteralPath $shaFile -Raw).Split()[0].Trim()
                $actual = (Get-FileHash -LiteralPath $pharPath -Algorithm SHA256).Hash.ToLowerInvariant()
                
                if ($expected.ToLowerInvariant() -ne $actual) {
                    Remove-Item -LiteralPath $pharPath -Force -ErrorAction SilentlyContinue
                    throw "Invalid checksum. Expected: $expected, Actual: $actual"
                }
                
                Write-Info "SHA256 checksum verified ✓"
            } catch {
                $errMsg = $_.Exception.Message
                throw "Error verifying checksum: $errMsg"
            }
        } else {
            Write-Info "Channel version - checksum skipped"
        }
        
    } catch {
        if (Test-Path -LiteralPath $pharPath) { 
            Remove-Item -LiteralPath $pharPath -Force -ErrorAction SilentlyContinue 
        }
        $errMsg = $_.Exception.Message
        throw "Error downloading/verifying: $errMsg"
    }
    
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
