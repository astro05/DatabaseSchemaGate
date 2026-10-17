<#
.SYNOPSIS
    Publishes a DACPAC or generates an idempotent deployment script for a target database environment.
.DESCRIPTION
    Uses SqlPackage to deploy or generate differential T-SQL scripts against target SQL Server instances.
.PARAMETER Database
    Database to deploy (a folder name under Databases/), or 'All' to deploy every database in turn.
    With 'All' every database is attempted and the run fails if any of them failed.
.PARAMETER TargetEnvironment
    The target environment: 'Development', 'Staging', or 'Production'. Defaults to 'Development'.
.PARAMETER ConnectionString
    Optional override for target SQL Server connection string.
.PARAMETER DacpacPath
    Optional override path to input DACPAC. If omitted, resolves bin/Release/<Database>.dacpac.
.PARAMETER GenerateScriptOnly
    If set, generates a differential migration script without applying changes directly.
.PARAMETER BlockOnPossibleDataLoss
    Whether to halt if a change could cause table or column data loss. Defaults to $true.
.PARAMETER ChangedFiles
    Files changed by the deployed commit. Defaults to the commit's file list from git.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Database,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Development', 'Staging', 'Production')]
    [string]$TargetEnvironment = 'Development',

    [Parameter(Mandatory = $false)]
    [string]$ConnectionString,

    [Parameter(Mandatory = $false)]
    [string]$DacpacPath,

    [Parameter(Mandatory = $false)]
    [switch]$GenerateScriptOnly = $false,

    [Parameter(Mandatory = $false)]
    [bool]$BlockOnPossibleDataLoss = $true,

    [Parameter(Mandatory = $false)]
    [string[]]$ChangedFiles = @()
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'Common.ps1')

if ($Database -eq 'All') {
    # One connection string or DACPAC can't serve every database
    if ($ConnectionString -or $DacpacPath) { throw '-ConnectionString and -DacpacPath need a single -Database, not All.' }
    $failed = @(Invoke-ForEachDatabase $PSCommandPath $PSBoundParameters)
    if ($failed) { Write-Host "Deployment failed for: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
    exit 0
}
$Database = Resolve-DatabaseName $Database

$ConnectionString = Resolve-ConnectionString -Database $Database -TargetEnvironment $TargetEnvironment -ConnectionString $ConnectionString
if (-not $ConnectionString) {
    Write-Error "No ConnectionString provided for database $Database, environment: $TargetEnvironment"
    exit 1
}
$resolvedDacpac = Resolve-DacpacPath -Database $Database -DacpacPath $DacpacPath
$sqlPackageExe = Get-SqlPackagePath

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Deploying Database: $Database ($TargetEnvironment)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "DACPAC: $resolvedDacpac" -ForegroundColor Gray
Write-Host "BlockOnPossibleDataLoss: $BlockOnPossibleDataLoss" -ForegroundColor Gray

$artifactsDir = Join-Path $ProjectRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
$deployReportPath = Join-Path $artifactsDir "$Database-$TargetEnvironment-DeployReport.xml"
$scriptOutputPath = Join-Path $artifactsDir "$Database-$TargetEnvironment-DeployScript.sql"

if ($GenerateScriptOnly) {
    Write-Host "Action: Generate Differential Deployment Script" -ForegroundColor Yellow
    $actionArgs = @('/Action:Script', "/OutputPath:$scriptOutputPath")
} else {
    Write-Host "Action: Publish DACPAC to Target Database" -ForegroundColor Yellow
    $actionArgs = @('/Action:Publish')
}
$argsList = $actionArgs + @(
    "/SourceFile:$resolvedDacpac",
    "/TargetConnectionString:$ConnectionString",
    "/DeployReportPath:$deployReportPath",
    "/p:BlockOnPossibleDataLoss=$($BlockOnPossibleDataLoss.ToString().ToLower())",
    '/p:DropObjectsNotInSource=false',
    '/p:GenerateSmartDefaults=true'
)

$deployedAtUtc = [DateTime]::UtcNow
$status = 'FAILED'
$errorMessage = $null
$deployReportSummary = $null
$exitCode = 0

try {
    & $sqlPackageExe @argsList
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        $status = 'SUCCESS'
        Write-Host ""
        Write-Host "Deployment operation succeeded for $Database!" -ForegroundColor Green
    } else {
        $errorMessage = "SqlPackage deployment failed with exit code $exitCode."
    }
} catch {
    $exitCode = 1
    $errorMessage = $_.Exception.ToString()
}

$completedAtUtc = [DateTime]::UtcNow

if (Test-Path $deployReportPath) {
    Write-Host "Deploy Report generated at: $deployReportPath" -ForegroundColor Green
    try {
        [xml]$xml = Get-Content $deployReportPath -Raw
        $summaryParts = @($xml.DeploymentReport.Operations.Operation | ForEach-Object { "$($_.Name): $(($_.Item | Measure-Object).Count)" })
        if ($summaryParts.Count -gt 0) { $deployReportSummary = $summaryParts -join '; ' }
    } catch {}
}
if ($GenerateScriptOnly -and (Test-Path $scriptOutputPath)) {
    Write-Host "Deployment Script generated at: $scriptOutputPath" -ForegroundColor Green
}

# Record SUCCESS / FAILED in the target database: one dbo.DeploymentLog row per .sql file the commit changed
# under Databases/<Database>/ (ScriptRunner scripts are logged by Invoke-ScriptRunner.ps1)
if (-not $GenerateScriptOnly) {
    $metadata = Get-DeploymentMetadata
    if (-not $ChangedFiles) {
        # Diff against the first parent: for a merge commit `git show` lists no files, this lists everything the merge brought in
        if ($metadata.CommitSha -notin 'local', 'unknown') { $ChangedFiles = @(Get-GitOutput diff --name-only "$($metadata.CommitSha)^1" $metadata.CommitSha) }
        if (-not $ChangedFiles) { $ChangedFiles = @(Get-GitOutput log -1 --pretty= --name-only) }
    }

    $dbPrefix = "^Databases/$([regex]::Escape($Database))/.*\.sql$"
    $scriptsToLog = @($ChangedFiles | Where-Object { ($_ -replace '\\', '/') -match "(?i)$dbPrefix" } | ForEach-Object { [System.IO.Path]::GetFileName($_) })

    if ($scriptsToLog.Count -eq 0) {
        Write-Host "No .sql file changes under Databases/$Database in commit; skipping dbo.DeploymentLog entry per policy." -ForegroundColor Gray
    } else {
        try {
            $conn = New-SqlConnection $ConnectionString
            try {
                Initialize-DeploymentLog $conn
                foreach ($scriptName in $scriptsToLog) {
                    Add-DeploymentLogRow $conn ($metadata + @{
                        DatabaseName        = $Database
                        TargetEnvironment   = $TargetEnvironment
                        Status              = $status
                        DeployedAtUtc       = $deployedAtUtc
                        CompletedAtUtc      = $completedAtUtc
                        DurationSeconds     = [Math]::Max(0, [int][Math]::Round(($completedAtUtc - $deployedAtUtc).TotalSeconds))
                        ScriptName          = $scriptName
                        DacpacVersion       = [System.IO.Path]::GetFileName($resolvedDacpac)
                        ErrorMessage        = $errorMessage
                        DeployReportSummary = $deployReportSummary
                    })
                    Write-Host "Deployment execution logged to [dbo].[DeploymentLog] ($status, ScriptName: $scriptName)." -ForegroundColor Cyan
                }
            } finally {
                $conn.Close()
            }
        } catch {
            Write-Warning "Could not record deployment to [dbo].[DeploymentLog]: $($_.Exception.Message)"
        }
    }
}

if ($status -eq 'FAILED') {
    Write-Error "Deployment failed for database $Database ($TargetEnvironment): $errorMessage"
    exit $(if ($exitCode -ne 0) { $exitCode } else { 1 })
}
