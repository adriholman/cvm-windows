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
Import-Module -Force $modulePath

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
  cvm [global-options] install <version>    Install a Composer version
  cvm [global-options] default <version>    Set the global default version
  cvm [global-options] list                 List installed versions
  cvm [global-options] which                Show current version and its source
  cvm [global-options] version              Show cvm version
  cvm [global-options] selfupdate           Copy scripts + VERSION to cache bin
  cvm [global-options] clean [--all] [--keep v]  Remove cached versions
  cvm [global-options] <args>               Run composer with resolved version

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

For more info: https://github.com/adriholman/cvm
'@ | Write-Host
}

#region Commands

function Cmd-Install([string]$version) {
    if (-not $version) {
        Write-Err "Missing version"
        Write-Host "Usage: cvm install <1|2|stable|preview|x.y.z>" -ForegroundColor Yellow
        exit 1
    }
    Ensure-VersionInstalled $version | Out-Null
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
    $targetRoot = Get-CvmRoot
    $targetBin = Join-Path $targetRoot 'bin'
    Ensure-Dir $targetBin

    $files = @('cvm.ps1','composer.ps1','cvm-common.psm1')
    foreach ($f in $files) {
        $src = Join-Path $PSScriptRoot $f
        if (-not (Test-Path -LiteralPath $src)) { throw "$f not found next to cvm.ps1" }
        $dst = Join-Path $targetBin $f
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-VerboseMsg "Copied $f -> $dst"
    }

    $versionSrc = Join-Path $PSScriptRoot '..\VERSION'
    if (Test-Path -LiteralPath $versionSrc) {
        $versionDst = Join-Path $targetRoot 'VERSION'
        Copy-Item -LiteralPath $versionSrc -Destination $versionDst -Force
        Write-VerboseMsg "Copied VERSION -> $versionDst"
    }

    Write-Info "selfupdate completed. Restart shell to ensure PATH reloads."
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
    'selfupdate' { Cmd-SelfUpdate; exit 0 }
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
        $phar = Ensure-VersionInstalled $version
        $php = Get-PhpExe
        Assert-PhpVersionSupported -PhpExe $php -composerSpec $version
        Write-Info "Using Composer $version"
        & $php $phar @Args
        exit $LASTEXITCODE
    }
}

#endregion
