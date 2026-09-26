<#
.SYNOPSIS
  Builds the Constellar MSI. Run on Windows with the WiX .NET tool available.

.DESCRIPTION
  Produces a per-user installer: the game lands in
  %LocalAppData%\Programs\Constellar with a Start menu shortcut, so installing
  it needs no administrator rights.

.EXAMPLE
  dotnet tool install --global wix --version 6.0.2
  .\packaging\windows\build-msi.ps1 -Version 0.1.0 -ExePath .\build\windows\Constellar.exe -OutDir .\dist
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [string]$OutDir = 'dist'
)

$ErrorActionPreference = 'Stop'

# An MSI ProductVersion is three numeric fields, so a tag like v0.1.0 has to be
# stripped of its v and of anything after the patch number.
$clean = $Version -replace '^v', ''
if ($clean -notmatch '^\d+\.\d+\.\d+') {
  throw "Version '$Version' is not major.minor.patch; an MSI cannot express it."
}
$msiVersion = $Matches[0]

if (-not (Test-Path $ExePath)) { throw "No executable at $ExePath" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$exeFull = (Resolve-Path $ExePath).Path
$outFile = Join-Path (Resolve-Path $OutDir).Path "constellar_${clean}_windows_x64.msi"
$wxs     = Join-Path $PSScriptRoot 'constellar.wxs'

Write-Host "Building $outFile (product version $msiVersion)"

& wix build $wxs `
  -arch x64 `
  -define "Version=$msiVersion" `
  -define "ExePath=$exeFull" `
  -out $outFile

if ($LASTEXITCODE -ne 0) { throw "wix build failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $outFile)) { throw "wix reported success but produced no file" }

Write-Host "Built $outFile"
