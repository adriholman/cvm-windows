<#
.SYNOPSIS
    cvm - Composer Version Manager for Windows
.DESCRIPTION
    Composer version manager that allows installing and using multiple versions.
    Supports channels (1, 2, stable, preview) and exact versions (e.g., 2.7.1).
.PARAMETER Args
    Arguments passed to the script
#>
param([Parameter(ValueFromRemainingArguments)][string[]]$Args)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot 'cvm-common.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "cvm-common.psm1 not found next to cvm.ps1"
    exit 1
}
Import-Module -Force -DisableNameChecking $modulePath

function Parse-GlobalOptions {
    param([string[]]$InputArgs)
    $quiet = $false
    $verbose = $false
    $skipVerify = $false
    $cacheRoot = $null
    $useLocalApp = $false
    $rest = @()

    $i = 0
    while ($i -lt $InputArgs.Count) {
        $arg = $InputArgs[$i]
        switch ($arg) {
            '--quiet' { $quiet = $true; $i++; continue }
            '-q'      { $quiet = $true; $i++; continue }
            '--verbose' { $verbose = $true; $i++; continue }
            '-v'        { $verbose = $true; $i++; continue }
            '--no-verify' { $skipVerify = $true; $i++; continue }
            '--cache-root' {
                if ($i + 1 -ge $InputArgs.Count) { throw "--cache-root requires a path" }
                $cacheRoot = $InputArgs[$i + 1]
                $i += 2
                continue
            }
            { $_ -in @('--use-localappdata','--use-localapp') } { $useLocalApp = $true; $i++; continue }
            '--' { $rest += $InputArgs[($i + 1)..($InputArgs.Count - 1)]; break }
            default { $rest += $InputArgs[$i..($InputArgs.Count - 1)]; break }
        }
        if ($rest.Count -gt 0) { break }
    }

    if ($rest.Count -eq 0 -and $i -lt $InputArgs.Count) {
        $rest += $InputArgs[$i..($InputArgs.Count - 1)]
    }

    return [ordered]@{
        Quiet = $quiet
        Verbose = $verbose
        SkipVerify = $skipVerify
        CacheRoot = $cacheRoot
        UseLocalAppData = $useLocalApp
        Rest = $rest
    }
}

function Show-Help {
@'
cvm - Composer Version Manager for Windows

USAGE:
  cvm [global-options] install <version>         Install a Composer version
  cvm [global-options] default <version>         Set the global default version
  cvm [global-options] list                      List installed versions
  cvm [global-options] which                     Show current version and its source
  cvm [global-options] version                   Show cvm version
  cvm [global-options] selfupdate [--check]      Update to latest version (--check to see available)
  cvm [global-options] clean [--all] [--keep v]  Remove cached versions
  cvm [global-options] <args>                    Run composer with resolved version

GLOBAL OPTIONS:
  --quiet | -q          Reduce output (also respects $env:CVM_QUIET=1)
  --verbose | -v        Extra logs (also $env:CVM_VERBOSE=1)
  --no-verify           Skip checksum download/validation (or $env:CVM_NO_VERIFY=1)
  --cache-root <path>   Use custom cache root (or $env:CVM_CACHE_ROOT)
  --use-localappdata    Store cache under %LOCALAPPDATA%\cvm (or $env:CVM_USE_LOCALAPPDATA=1)

SUPPORTED VERSIONS:
  1        Latest Composer 1.x
  2        Latest Composer 2.x
  stable   Latest stable
  preview  Latest preview/beta
  x.y.z    Specific version (e.g., 2.7.1)

CONFIGURATION:
  Environment: $env:CVM_VERSION
  Project file: .composer-version
  Global default: %USERPROFILE%\.cvm\config.json (or custom cache root)

For more info: https://github.com/adriholman/cvm-windows
'@ | Write-Host
}

#region Commands

function Cmd-Install([string]$version) {
    if (-not $version) {
        Write-Err "Missing version"
        Write-Host "Usage: cvm install <1|2|stable|preview|x.y.z>" -ForegroundColor Yellow
        exit 1
    }
    Install-ComposerVersionIfNeeded $version | Out-Null
    Write-Info "Installation completed: $version"
}

function Cmd-Default([string]$version) {
    if (-not $version) {
        Write-Err "Missing version"
        Write-Host "Usage: cvm default <1|2|stable|preview|x.y.z>" -ForegroundColor Yellow
        exit 1
    }

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

function Cmd-SelfUpdate {
    param(
        [switch]$Check
    )

    # Get current version
    $versionFile = Join-Path $PSScriptRoot '..\VERSION'
    $currentVersion = if (Test-Path -LiteralPath $versionFile) { 
        (Get-Content -LiteralPath $versionFile -Raw).Trim() 
    } else { 
        '0.0.0' 
    }

    Write-Info "Checking for updates... (current: $currentVersion)"

    # Fetch latest release from GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $apiUrl = 'https://api.github.com/repos/adriholman/cvm-windows/releases/latest'
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop
        $latestVersion = $response.tag_name -replace '^v', ''
        $downloadUrl = $response.assets | Where-Object { $_.name -eq 'cvm-release.zip' } | Select-Object -ExpandProperty browser_download_url
        
        if (-not $downloadUrl) {
            Write-Err "Latest release found but no cvm-release.zip asset found"
            return
        }

        Write-Info "Latest available: $latestVersion"
        
        # Compare versions
        try {
            $current = [version]$currentVersion
            $latest = [version]$latestVersion
            if ($latest -le $current) {
                Write-Info "You are already running the latest version ($currentVersion)"
                return
            }
        } catch {
            Write-VerboseMsg "Could not compare versions as [version] objects, doing string comparison"
        }

        if ($Check) {
            Write-Host "Update available: $currentVersion -> $latestVersion" -ForegroundColor Yellow
            Write-Host "Run: cvm selfupdate (without --check)" -ForegroundColor Cyan
            return
        }

        # Download and extract release
        Write-Info "Downloading cvm $latestVersion from GitHub..."
        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "cvm-release-$latestVersion.zip"
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "cvm-extract-$latestVersion"

        try {
            # Download
            Invoke-DownloadFile -Url $downloadUrl -Destination $tempZip
            
            # Extract
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempDir)
            
            # Install files
            $targetRoot = Get-CvmRoot
            $targetBin = Join-Path $targetRoot 'bin'
            New-CvmDirectory $targetBin

            $files = @('cvm.ps1', 'composer.ps1', 'cvm-common.psm1', 'setup-path.ps1')
            foreach ($f in $files) {
                $src = Join-Path $tempDir $f
                if (-not (Test-Path -LiteralPath $src)) {
                    throw "File $f not found in release archive"
                }
                # setup-path.ps1 goes to root, others to bin
                $dst = if ($f -eq 'setup-path.ps1') { 
                    Join-Path $targetRoot $f 
                } else { 
                    Join-Path $targetBin $f 
                }
                Copy-Item -LiteralPath $src -Destination $dst -Force
                Write-VerboseMsg "Updated $f"
            }

            # Update VERSION file
            $versionDst = Join-Path $targetRoot 'VERSION'
            Set-Content -LiteralPath $versionDst -Value $latestVersion -Encoding UTF8 -NoNewline
            Write-VerboseMsg "Updated VERSION to $latestVersion"

            Write-Info "Update successful! Restart your shell to load the new version."
            Write-Host "New version: $latestVersion" -ForegroundColor Green

        } finally {
            # Cleanup
            if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

    } catch {
        Write-Err "Could not check for updates: $($_.Exception.Message)"
        Write-Host "You can manually download releases from: https://github.com/adriholman/cvm-windows/releases" -ForegroundColor Yellow
    }
}


function Cmd-Clean {
    param(
        [switch]$All,
        [string[]]$Keep
    )

    $installed = @(Get-InstalledVersions)
    if (-not $installed -or $installed.Count -eq 0) {
        Write-Info "No cached versions to clean"
        return
    }

    $keepSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($k in $Keep) { $null = $keepSet.Add($k) }

    if (-not $All) {
        $null = $keepSet.Add((Get-DefaultVersion))
        $null = $keepSet.Add((Resolve-DesiredVersion))
    }

    $removed = @()
    $freed = 0L
    foreach ($v in $installed) {
        if ($keepSet.Contains($v)) { continue }
        $dir = Split-Path (Get-PharPath $v) -Parent
        if (Test-Path -LiteralPath $dir) {
            $size = (Get-ChildItem -LiteralPath $dir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            $removed += $v
            if ($size) { $freed += [int64]$size }
        }
    }

    if ($removed.Count -eq 0) {
        Write-Info "Nothing to clean"
    } else {
        Write-Info "Removed: $($removed -join ', ')"
        if ($freed -gt 0) { Write-Info "Freed $(Format-Size $freed)" }
    }
}

#endregion

#region Main

if (-not $Args) { $Args = @() } else { $Args = @($Args) }
$parsed = Parse-GlobalOptions $Args
Set-CvmContext -Quiet:$parsed.Quiet -Verbose:$parsed.Verbose -SkipVerify:$parsed.SkipVerify -CacheRoot $parsed.CacheRoot -UseLocalAppData:$parsed.UseLocalAppData -Prefix '[cvm]'
$Args = $parsed.Rest

if (-not $Args -or $Args.Count -eq 0) {
    Show-Help
    exit 0
}

$cmd = $Args[0].ToLowerInvariant()

switch ($cmd) {
    'install' { Cmd-Install -version $Args[1]; exit 0 }
    'default' { Cmd-Default -version $Args[1]; exit 0 }
    'list'    { Cmd-List; exit 0 }
    'which'   { Cmd-Which; exit 0 }
    'version' { Cmd-Version; exit 0 }
    'selfupdate' {
        $selfArgs = @()
        if ($Args.Count -gt 1) { $selfArgs = $Args[1..($Args.Count - 1)] }
        $check = $false
        foreach ($a in $selfArgs) {
            if ($a -eq '--check' -or $a -eq '-c') { $check = $true }
        }
        Cmd-SelfUpdate -Check:$check
        exit 0
    }
    'clean' {
        $cleanArgs = @()
        if ($Args.Count -gt 1) { $cleanArgs = $Args[1..($Args.Count - 1)] }
        $all = $false
        $keep = @()
        for ($i = 0; $i -lt $cleanArgs.Length; $i++) {
            switch ($cleanArgs[$i]) {
                '--all' { $all = $true }
                '--keep' {
                    if ($i + 1 -ge $cleanArgs.Length) { Write-Err "--keep requires a version"; exit 1 }
                    $keep += $cleanArgs[$i + 1]
                    $i++
                }
                default { }
            }
        }
        Cmd-Clean -All:$all -Keep $keep
        exit 0
    }
    { $_ -in @('help', '--help', '-h', '-?') } { Show-Help; exit 0 }
    default {
        $version = Resolve-DesiredVersion
        $phar = Install-ComposerVersionIfNeeded $version
        $php = Get-PhpExe
        Test-PhpVersionSupport -PhpExe $php -composerSpec $version
        Write-Info "Using Composer $version"
        & $php $phar @Args
        exit $LASTEXITCODE
    }
}

#endregion
