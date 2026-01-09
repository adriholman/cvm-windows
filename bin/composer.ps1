param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Script:DownloadTimeoutSec = 45
$Script:DownloadRetries   = 3
$Script:RetryDelaySec     = 3

function Get-UserHome { [Environment]::GetFolderPath('UserProfile') }
function Get-CvmRoot { Join-Path (Get-UserHome) ".cvm" }
function Get-VersionsDir { Join-Path (Get-CvmRoot) 'versions' }
function Get-ConfigPath { Join-Path (Get-CvmRoot) 'config.json' }

function Write-Info($m) { Write-Host "[composer] $m" -ForegroundColor Cyan }
function Write-Err($m) { Write-Host "[composer] ERROR: $m" -ForegroundColor Red }

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
    if ($fallback -and $fallback -ne $primary) { $endpoints += @{ Url = $fallback; ShaUrl = $shaFallback } }
    return $endpoints
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
        if (-not (Test-Path -LiteralPath $Destination)) { throw "Download completed without creating $Destination" }
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

function Ensure-VersionInstalled([string]$version) {
    $phar = Get-PharPath $version
    if (Test-Path -LiteralPath $phar) { return $phar }
    
    $versionDir = Split-Path $phar -Parent
    if (-not (Test-Path -LiteralPath $versionDir)) { [void](New-Item -ItemType Directory -Path $versionDir) }

    Download-ComposerArtifact -Version $version -PharPath $phar -VersionDir $versionDir
    Write-Info "Downloaded: $phar"
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
