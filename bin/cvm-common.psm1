Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Context for logging and download behavior
$script:CvmContext = [ordered]@{
    Quiet        = $false
    Verbose      = $false
    SkipVerify   = $false
    UseLocalApp  = $false
    CacheRoot    = $null
    TimeoutSec   = 45
    Retries      = 3
    RetryDelay   = 3
    Prefix       = '[cvm]'
}

function Set-CvmContext {
    param(
        [switch]$Quiet,
        [switch]$Verbose,
        [switch]$SkipVerify,
        [string]$CacheRoot,
        [switch]$UseLocalAppData,
        [string]$Prefix
    )

    $script:CvmContext.Quiet      = $Quiet -or ($env:CVM_QUIET -eq '1')
    $script:CvmContext.Verbose    = $Verbose -or ($env:CVM_VERBOSE -eq '1')
    $script:CvmContext.SkipVerify = $SkipVerify -or ($env:CVM_NO_VERIFY -eq '1')
    $script:CvmContext.UseLocalApp = $UseLocalAppData -or ($env:CVM_USE_LOCALAPPDATA -eq '1') -or ($env:CVM_CACHE_IN_LOCALAPPDATA -eq '1')

    if ($CacheRoot) {
        $script:CvmContext.CacheRoot = $CacheRoot
    } elseif ($env:CVM_CACHE_ROOT) {
        $script:CvmContext.CacheRoot = $env:CVM_CACHE_ROOT
    } elseif ($script:CvmContext.UseLocalApp -and $env:LOCALAPPDATA) {
        $script:CvmContext.CacheRoot = Join-Path $env:LOCALAPPDATA 'cvm'
    } else {
        $script:CvmContext.CacheRoot = Join-Path $env:USERPROFILE '.cvm'
    }

    if ($Prefix) { $script:CvmContext.Prefix = $Prefix }
}

function Write-Info {
    param([string]$Message, [string]$Prefix)
    if ($script:CvmContext.Quiet) { return }
    $p = if ($Prefix) { $Prefix } else { $script:CvmContext.Prefix }
    Write-Host "$p $Message" -ForegroundColor Cyan
}

function Write-VerboseMsg {
    param([string]$Message, [string]$Prefix)
    if (-not $script:CvmContext.Verbose -or $script:CvmContext.Quiet) { return }
    $p = if ($Prefix) { $Prefix } else { $script:CvmContext.Prefix }
    Write-Host "$p $Message" -ForegroundColor DarkGray
}

function Write-Err {
    param([string]$Message, [string]$Prefix)
    $p = if ($Prefix) { $Prefix } else { $script:CvmContext.Prefix }
    Write-Host "$p ERROR: $Message" -ForegroundColor Red
}

function New-CvmDirectory($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        [void](New-Item -ItemType Directory -Path $path -Force)
    }
}

function Get-CvmRoot {
    if (-not $script:CvmContext.CacheRoot) { Set-CvmContext }
    return $script:CvmContext.CacheRoot
}

function Get-VersionsDir { Join-Path (Get-CvmRoot) 'versions' }
function Get-ConfigPath { Join-Path (Get-CvmRoot) 'config.json' }

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
    New-CvmDirectory $root
    $cfg = Get-ConfigPath
    @{ default = $version } | ConvertTo-Json | Set-Content -LiteralPath $cfg -Encoding UTF8
    Write-Info "Default version set: $version"
}

function Resolve-DesiredVersion {
    if ($env:CVM_VERSION) { return $env:CVM_VERSION.Trim() }
    $fileVersion = Find-ComposerVersionFile
    if ($fileVersion) { return $fileVersion }
    return Get-DefaultVersion
}

function Test-ExactVersion([string]$version) { return $version -match '^\d+\.\d+\.\d+$' }

function Get-DownloadUrl([string]$version) {
    switch -Regex ($version) {
        '^1$'             { return 'https://getcomposer.org/download/latest-1.x/composer.phar' }
        '^2$'             { return 'https://getcomposer.org/download/latest-2.x/composer.phar' }
        '^stable$'        { return 'https://getcomposer.org/download/latest-stable/composer.phar' }
        '^preview$'       { return 'https://getcomposer.org/download/latest-preview/composer.phar' }
        '^\d+\.\d+\.\d+$' { return "https://getcomposer.org/download/$version/composer.phar" }
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

function Get-PharPath([string]$version) {
    Join-Path (Get-VersionsDir) (Join-Path $version 'composer.phar')
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Description
    )
    $attempt = 0
    $lastError = $null
    while ($attempt -lt $script:CvmContext.Retries) {
        $attempt++
        try {
            return & $Action
        } catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $script:CvmContext.Retries) { break }
            Start-Sleep -Seconds $script:CvmContext.RetryDelay
        }
    }
    throw "Failed $Description after $($script:CvmContext.Retries) attempts. Last error: $lastError"
}

function Get-ContentLengthBytes([string]$Url) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $request.Timeout = $script:CvmContext.TimeoutSec * 1000
        $response = $request.GetResponse()
        $length = $response.ContentLength
        $response.Close()
        if ($length -gt 0) { return [int64]$length }
    } catch {}
    return $null
}

function Format-Size([int64]$bytes) {
    if ($bytes -ge 1GB) { return "{0:n2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:n2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:n0} KB" -f ($bytes / 1KB) }
    return "{0} B" -f $bytes
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $length = Get-ContentLengthBytes $Url
    if ($length) { Write-VerboseMsg "Size: $(Format-Size $length)" }
    $showProgress = -not $script:CvmContext.Quiet

    $client = $null
    $handler = $null
    $canUseHttpClient = $true
    try {
        if (-not ([type]::GetType('System.Net.Http.HttpClientHandler, System.Net.Http'))) {
            Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        }
        $handler = New-Object System.Net.Http.HttpClientHandler
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($script:CvmContext.TimeoutSec)
    } catch {
        $canUseHttpClient = $false
        Write-VerboseMsg "System.Net.Http not available, using Invoke-WebRequest fallback"
    }

    $stream = $null
    $fileStream = $null
    try {
        if ($canUseHttpClient) {
            $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
            if (-not $response.IsSuccessStatusCode) { throw "HTTP $($response.StatusCode) $($response.ReasonPhrase)" }
            $stream = $response.Content.ReadAsStreamAsync().Result
            $fileStream = [System.IO.FileStream]::new($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = New-Object byte[] 65536
            $totalRead = 0L
            $lastPercent = -1
            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                if ($showProgress -and $length -gt 0) {
                    $percent = [int](($totalRead * 100) / $length)
                    if ($percent -ne $lastPercent) {
                        Write-Progress -Activity "Downloading" -Status "$(Format-Size $totalRead) of $(Format-Size $length)" -PercentComplete $percent
                        $lastPercent = $percent
                    }
                } elseif ($showProgress) {
                    Write-Progress -Activity "Downloading" -Status "$(Format-Size $totalRead)" -PercentComplete -1
                }
            }
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $Destination -TimeoutSec $script:CvmContext.TimeoutSec -UseBasicParsing
        }
        if ($showProgress) { Write-Progress -Activity "Downloading" -Completed }
    } catch {
        if ($showProgress) { Write-Progress -Activity "Downloading" -Completed }
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
        throw "Error downloading from ${Url}: $($_.Exception.Message)"
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

function Test-FileChecksum {
    param(
        [Parameter(Mandatory)][string]$PharPath,
        [Parameter(Mandatory)][string]$ShaUrl,
        [Parameter(Mandatory)][string]$ShaDestination
    )

    Invoke-DownloadFile -Url $ShaUrl -Destination $ShaDestination
    $expected = (Get-Content -LiteralPath $ShaDestination -Raw).Split()[0].Trim()
    $actual = (Get-FileHash -LiteralPath $PharPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected.ToLowerInvariant() -ne $actual) {
        Remove-Item -LiteralPath $PharPath -Force -ErrorAction SilentlyContinue
        throw "Invalid checksum. Expected: $expected, Actual: $actual"
    }
}

function Invoke-ComposerDownload {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PharPath,
        [Parameter(Mandatory)][string]$VersionDir
    )

    $endpoints = Get-DownloadEndpoints $Version
    $lastError = $null
    foreach ($endpoint in $endpoints) {
        try {
            $size = Get-ContentLengthBytes $endpoint.Url
            $sizeText = if ($size) { " (approx $(Format-Size $size))" } else { '' }
            Write-Info "Downloading $($endpoint.Url)$sizeText ..." $script:CvmContext.Prefix
            Invoke-WithRetry -Description "download $Version" -Action { Invoke-DownloadFile -Url $endpoint.Url -Destination $PharPath }
            if ($endpoint.ShaUrl -and -not $script:CvmContext.SkipVerify) {
                $shaFile = Join-Path $VersionDir 'composer.phar.sha256sum'
                Invoke-WithRetry -Description "download checksum for $Version" -Action { Test-FileChecksum -PharPath $PharPath -ShaUrl $endpoint.ShaUrl -ShaDestination $shaFile }
                Write-Info "SHA256 checksum verified" $script:CvmContext.Prefix
            } elseif ($endpoint.ShaUrl) {
                Write-VerboseMsg "Checksum skipped (--no-verify)" $script:CvmContext.Prefix
            } else {
                Write-VerboseMsg "Channel version - checksum skipped" $script:CvmContext.Prefix
            }
            return
        } catch {
            $lastError = $_.Exception.Message
            Write-Err "Attempt failed from $($endpoint.Url): $lastError" $script:CvmContext.Prefix
            if (Test-Path -LiteralPath $PharPath) { Remove-Item -LiteralPath $PharPath -Force -ErrorAction SilentlyContinue }
        }
    }
    throw "Failed to download Composer $Version from all endpoints. Last error: $lastError"
}

function Install-ComposerVersionIfNeeded([string]$version) {
    $versionsDir = Get-VersionsDir
    New-CvmDirectory $versionsDir
    $versionDir = Join-Path $versionsDir $version
    New-CvmDirectory $versionDir
    $pharPath = Join-Path $versionDir 'composer.phar'
    if (Test-Path -LiteralPath $pharPath) { return $pharPath }
    Invoke-ComposerDownload -Version $version -PharPath $pharPath -VersionDir $versionDir
    return $pharPath
}

function Get-InstalledVersions {
    $versionsDir = Get-VersionsDir
    if (-not (Test-Path -LiteralPath $versionsDir)) { return @() }
    $result = @(Get-ChildItem -LiteralPath $versionsDir -Directory | Select-Object -ExpandProperty Name)
    return $result
}

function Get-PhpExe {
    $php = 'php'
    try { $null = & $php -v 2>&1 } catch { throw "PHP CLI not found in PATH. Install PHP and add it to PATH." }
    return $php
}

function Get-PhpVersion([string]$PhpExe) {
    try {
        $versionText = & $PhpExe -r "echo PHP_VERSION;"
        return [version]$versionText
    } catch {
        throw "Unable to read PHP version from $PhpExe"
    }
}

function Get-MinPhpVersionForComposer([string]$composerSpec) {
    if ($composerSpec -match '^1(\.|$)') { return [version]'5.3.2' }
    return [version]'7.2.5'
}

function Test-PhpVersionSupport([string]$PhpExe, [string]$composerSpec) {
    $phpVersion = Get-PhpVersion $PhpExe
    $min = Get-MinPhpVersionForComposer $composerSpec
    if ($phpVersion -lt $min) {
        throw "PHP $phpVersion is too old for Composer $composerSpec. Minimum required: $min"
    }
}

Export-ModuleMember -Function Set-CvmContext, Write-Info, Write-Err, Write-VerboseMsg, New-CvmDirectory, Get-CvmRoot, Get-VersionsDir, Get-ConfigPath, Find-ComposerVersionFile, Get-DefaultVersion, Set-DefaultVersion, Resolve-DesiredVersion, Test-ExactVersion, Get-DownloadEndpoints, Get-PharPath, Invoke-WithRetry, Invoke-DownloadFile, Test-FileChecksum, Invoke-ComposerDownload, Install-ComposerVersionIfNeeded, Get-InstalledVersions, Get-PhpExe, Get-PhpVersion, Get-MinPhpVersionForComposer, Test-PhpVersionSupport, Format-Size, Get-ContentLengthBytes
