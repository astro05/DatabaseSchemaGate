<#
.SYNOPSIS
    Extracts a DACPAC or schema from an existing SQL Server database.
.DESCRIPTION
    Uses SqlPackage to extract schema definition into a baseline DACPAC artifact.
.PARAMETER Database
    Name of the live database to extract. It need not be under Databases/ yet (onboarding).
.PARAMETER ConnectionString
    Target SQL Server connection string. If omitted, uses DEV_CONNECTION_STRING_<DATABASE> or appsettings.local.json.
.PARAMETER TargetFile
    Output path for extracted DACPAC. Defaults to artifacts/<Database>.Extracted.dacpac.
.PARAMETER IncludeData
    Whether to extract table data. Defaults to false (schema-only).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Database,

    [Parameter(Mandatory = $false)]
    [string]$ConnectionString,

    [Parameter(Mandatory = $false)]
    [string]$TargetFile,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeData = $false
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'Common.ps1')

# Resolve TargetFile
if ([string]::IsNullOrWhiteSpace($TargetFile)) {
    $TargetFile = "artifacts/$Database.Extracted.dacpac"
}

$ConnectionString = Resolve-ConnectionString -Database $Database -ConnectionString $ConnectionString
if (-not $ConnectionString) {
    Write-Error "No ConnectionString provided for database $Database."
    exit 1
}
$sqlPackageExe = Get-SqlPackagePath

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Extracting Database Schema for $Database via SqlPackage" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Ensure target directory exists
$resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $TargetFile))
$targetDir = Split-Path -Parent $resolvedTarget
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
}

$extractArgs = @(
    '/Action:Extract',
    "/SourceConnectionString:$ConnectionString",
    "/TargetFile:$resolvedTarget",
    "/p:ExtractAllTableData=$($IncludeData.ToString().ToLower())",
    '/p:IgnorePermissions=true',
    '/p:IgnoreUserLoginMappings=true',
    '/p:VerifyExtraction=false'
)

Write-Host "Using SqlPackage at: $sqlPackageExe" -ForegroundColor Gray
Write-Host "Target DACPAC: $resolvedTarget" -ForegroundColor Gray
Write-Host "Starting extraction process for $Database..." -ForegroundColor Yellow

& $sqlPackageExe @extractArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "SqlPackage extraction failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (Test-Path $resolvedTarget) {
    $fi = Get-Item $resolvedTarget
    Write-Host ""
    Write-Host "Extraction Complete for $Database!" -ForegroundColor Green
    Write-Host "Output DACPAC: $($fi.FullName)" -ForegroundColor Green
    Write-Host "File Size: $([math]::Round($fi.Length / 1MB, 2)) MB" -ForegroundColor Green
}
