param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-UserHome { [Environment]::GetFolderPath('UserProfile') }
function Get-CvmRoot { Join-Path (Get-UserHome) ".cvm" }
function Get-VersionsDir { Join-Path (Get-CvmRoot) 'versions' }
function Get-ConfigPath { Join-Path (Get-CvmRoot) 'config.json' }

function Write-Info($m) { Write-Host "[composer] $m" -ForegroundColor Cyan }
function Write-Err($m) { Write-Host "[composer] ERROR: $m" -ForegroundColor Red }

function Find-ComposerVersionFile {
    $dir = (Get-Location).Path
    while ($true) {
        $vf = Join-Path $dir '.composer-version'
        if (Test-Path -LiteralPath $vf) { return $vf }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-DefaultVersion {
    $cfg = Get-ConfigPath
    if (Test-Path -LiteralPath $cfg) {
        try {
            $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
            if ($json.default) { return [string]$json.default }
        } catch { }
    }
    return 'stable'
}

function Resolve-DesiredVersion {
    if ($env:CVM_VERSION) { return [string]$env:CVM_VERSION }
    $vf = Find-ComposerVersionFile
    if ($vf) { return (Get-Content -LiteralPath $vf -Raw).Trim() }
    return Get-DefaultVersion
}

function Get-PharPath([string]$version) {
    $dir = Join-Path (Get-VersionsDir) $version
    return Join-Path $dir 'composer.phar'
}

function Test-ExactVersion([string]$v) { return $v -match '^\d+\.\d+\.\d+$' }

function Get-DownloadUrl([string]$version) {
    switch -Regex ($version) {
        '^1$'                    { return 'https://getcomposer.org/download/latest-1.x/composer.phar' }
        '^2$'                    { return 'https://getcomposer.org/download/latest-2.x/composer.phar' }
        '^stable$'               { return 'https://getcomposer.org/download/latest-stable/composer.phar' }
        '^preview$'              { return 'https://getcomposer.org/download/latest-preview/composer.phar' }
        '^\d+\.\d+\.\d+$'       { return "https://getcomposer.org/download/$version/composer.phar" }
        default { throw "Invalid version: '$version'. Use: 1, 2, stable, preview or x.y.z" }
    }
}

function Ensure-VersionInstalled([string]$version) {
    $phar = Get-PharPath $version
    if (Test-Path -LiteralPath $phar) { return $phar }
    
    $versionDir = Split-Path $phar -Parent
    if (-not (Test-Path -LiteralPath $versionDir)) { [void](New-Item -ItemType Directory -Path $versionDir) }
    $url = Get-DownloadUrl $version
    Write-Info "Downloading $url ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $phar -UseBasicParsing
        
        if (Test-ExactVersion $version) {
            $shaUrl = $url -replace 'composer\.phar$', 'composer.phar.sha256sum'
            $shaFile = Join-Path $versionDir 'composer.phar.sha256sum'
            Invoke-WebRequest -Uri $shaUrl -OutFile $shaFile -UseBasicParsing
            $expected = (Get-Content -LiteralPath $shaFile -Raw).Split()[0].Trim()
            $actual = (Get-FileHash -LiteralPath $phar -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($expected.ToLowerInvariant() -ne $actual) {
                Remove-Item -LiteralPath $phar -Force -ErrorAction SilentlyContinue
                throw "Invalid checksum. Expected: $expected, Actual: $actual"
            }
            Write-Info "SHA256 checksum verified ✓"
        }
    } catch {
        $errMsg = $_.Exception.Message
        throw "Error downloading/verifying: $errMsg"
    }
    return $phar
}

function Get-PhpExe {
    $php = 'php'
    try { $null = & $php -v 2>&1; return $php } catch { throw "PHP CLI not found in PATH. Install PHP and add it to PATH." }
}

# Main: resolve version and run composer
$version = Resolve-DesiredVersion
$phar = Ensure-VersionInstalled $version
$php = Get-PhpExe

& $php $phar @Args
exit $LASTEXITCODE
