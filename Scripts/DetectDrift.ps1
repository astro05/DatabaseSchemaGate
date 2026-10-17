<#
.SYNOPSIS
    Detects database schema drift between a target live database and the Git baseline DACPAC.
.DESCRIPTION
    Generates a DeployReport from SqlPackage to determine any unapproved or manual schema differences.
.PARAMETER Database
    Database to check (a folder name under Databases/).
.PARAMETER ConnectionString
    Target database connection string. If omitted, uses DEV_CONNECTION_STRING_<DATABASE> or appsettings.local.json.
.PARAMETER DacpacPath
    Optional override path to compiled baseline DACPAC. Defaults to bin/Release/<Database>.dacpac.
.PARAMETER ReportPath
    Output path for the XML drift report. Defaults to artifacts/<Database>-DriftReport.xml.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Database,

    [Parameter(Mandatory = $false)]
    [string]$ConnectionString,

    [Parameter(Mandatory = $false)]
    [string]$DacpacPath,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'Common.ps1')
$Database = Resolve-DatabaseName $Database

# Resolve ReportPath
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = "artifacts/$Database-DriftReport.xml"
}

$ConnectionString = Resolve-ConnectionString -Database $Database -ConnectionString $ConnectionString
if (-not $ConnectionString) {
    Write-Error "No ConnectionString provided for database $Database."
    exit 1
}
$resolvedDacpac = Resolve-DacpacPath -Database $Database -DacpacPath $DacpacPath
$sqlPackageExe = Get-SqlPackagePath

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Detecting Schema Drift for $Database" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$resolvedReport = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $ReportPath))
$reportDir = Split-Path -Parent $resolvedReport
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$deployArgs = @(
    '/Action:DeployReport',
    "/SourceFile:$resolvedDacpac",
    "/TargetConnectionString:$ConnectionString",
    "/OutputPath:$resolvedReport",
    '/p:BlockOnPossibleDataLoss=false',
    '/p:DropObjectsNotInSource=false'
)

& $sqlPackageExe @deployArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "DeployReport generation failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

if (Test-Path $resolvedReport) {
    [xml]$xml = Get-Content $resolvedReport
    $operations = $xml.DeploymentReport.Operations.Operation

    if ($operations) {
        Write-Host ""
        Write-Host "SCHEMA DRIFT DETECTED for $Database!" -ForegroundColor Yellow
        Write-Host "Differences between Git baseline and target database:" -ForegroundColor Yellow

        foreach ($op in $operations) {
            Write-Host "  [$($op.Name)]" -ForegroundColor White
            foreach ($item in $op.Item) {
                Write-Host "    - $($item.Value) (Type: $($item.Type))" -ForegroundColor Gray
            }
        }
        Write-Host ""
        Write-Host "Full XML report saved to: $resolvedReport" -ForegroundColor Gray
        exit 2
    } else {
        Write-Host ""
        Write-Host "Zero schema drift detected. Target database $Database matches Git DACPAC perfectly." -ForegroundColor Green
        exit 0
    }
}
