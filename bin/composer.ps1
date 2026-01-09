param([Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot 'cvm-common.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "cvm-common.psm1 not found next to composer.ps1"
    exit 1
}
Import-Module -Force $modulePath
Set-CvmContext -Prefix '[composer]'

$version = Resolve-DesiredVersion
$phar = Ensure-VersionInstalled $version
$php = Get-PhpExe
Assert-PhpVersionSupported -PhpExe $php -composerSpec $version
Write-VerboseMsg "Using Composer $version" '[composer]'

& $php $phar @Args
exit $LASTEXITCODE
