<#
.SYNOPSIS
    Automated SQL Safety Validator CLI entrypoint.
.DESCRIPTION
    Analyzes SQL scripts prior to database execution and blocks potentially destructive
    operations (UPDATE/DELETE without WHERE, DROP DATABASE, permanent DROP TABLE, TRUNCATE,
    DROP COLUMN, DROP PROCEDURE/VIEW) per SPEC-003 and policy configurations.
.PARAMETER TargetFiles
    List of explicit SQL file paths to validate.
.PARAMETER TargetPath
    Directory path to scan for SQL files if TargetFiles is not specified.
.PARAMETER Environment
    Target deployment environment ('Development', 'Test', 'Staging', 'Production'). Defaults to 'Production'.
.PARAMETER Approvals
    Hashtable or comma-separated string of specific operational approval overrides (e.g. @{ allowDropDatabase = $true } or "allowDropDatabase=true").
.PARAMETER ReportPath
    Optional output file path to write JSON validation results.
.PARAMETER ApprovalListPath
    CI approval mode (SPEC-002 CHK-14): approval comments and -Approvals don't count, and every block or
    requireApproval statement is written to this file, one per line. Syntax errors exit 1 without the file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$TargetFiles,

    [Parameter(Mandatory = $false)]
    [string]$TargetPath = 'Databases',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Development', 'Test', 'Staging', 'Production')]
    [string]$Environment = 'Production',

    [Parameter(Mandatory = $false)]
    $Approvals = @{},

    [Parameter(Mandatory = $false)]
    [string]$ReportPath,

    [Parameter(Mandatory = $false)]
    [string]$ApprovalListPath
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# A list left over from an earlier run must never unlock an approval
if ($ApprovalListPath) { Remove-Item -Path $ApprovalListPath -ErrorAction SilentlyContinue }

# Import modules
. (Join-Path $ScriptDir "SqlSafety/Config/ConfigManager.ps1")
. (Join-Path $ScriptDir "SqlSafety/Parser/ScriptDomParser.ps1")
. (Join-Path $ScriptDir "SqlSafety/Rules/SafetyRulesEngine.ps1")
. (Join-Path $ScriptDir "SqlSafety/Reporting/ReportFormatter.ps1")

# Approvals arrive as a hashtable, or as "name=true,name=false" from the command line
$parsedApprovals = @{}
if ($Approvals -is [hashtable]) {
    $parsedApprovals = $Approvals
} elseif ($Approvals -is [string]) {
    foreach ($pair in ($Approvals -split ',')) {
        if ($pair -match '^\s*([\w-]+)\s*=\s*(true|false)\s*$') {
            $parsedApprovals[$matches[1]] = ($matches[2] -eq 'true')
        }
    }
}

$config = Load-SafetyConfig -Environment $Environment -CliApprovals $parsedApprovals

# Resolve files to scan
$filesToScan = @()
if ($TargetFiles -and $TargetFiles.Count -gt 0) {
    foreach ($tf in $TargetFiles) {
        if (Test-Path $tf) {
            $filesToScan += (Get-Item $tf)
        }
    }
} else {
    $scanDir = Join-Path $ProjectRoot $TargetPath
    if (Test-Path $scanDir) {
        $filesToScan = Get-ChildItem -Path $scanDir -Filter *.sql -Recurse -File | Where-Object { $_.Extension -eq '.sql' }
    }
}

if ($filesToScan.Count -eq 0) {
    Write-Host "No SQL files found to validate." -ForegroundColor Yellow
    exit 0
}

# Fail closed: without the T-SQL parser nothing can be checked reliably
if (-not (Import-ScriptDom)) {
    Write-Host "ERROR: E_PARSER_UNAVAILABLE: Microsoft.SqlServer.TransactSql.ScriptDom.dll not found. Install SqlPackage (dotnet tool install -g microsoft.sqlpackage) or build Databases.sln once." -ForegroundColor Red
    exit 1
}

$allViolations = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($file in $filesToScan) {
    $relPath = if ($file.FullName.StartsWith($ProjectRoot)) {
        $file.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
    } else {
        $file.FullName
    }

    $content = Get-Content -Path $file.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { continue }

    $parseResult = Invoke-SqlSafetyParse -SqlContent $content -FileName $relPath
    $fileViolations = Evaluate-SqlSafetyRules -ParseResult $parseResult -Config $config

    foreach ($v in $fileViolations) {
        $allViolations.Add($v)
    }
}

if ($ApprovalListPath) {
    # In CI a person approves (SPEC-002 CHK-14), so approval comments and -Approvals don't count
    foreach ($v in $allViolations) { if ($v.Action -in 'block', 'requireApproval') { $v.IsApproved = $false } }
}

$isPassed = Format-SqlSafetyConsoleReport -Violations $allViolations -ScannedFileCount $filesToScan.Count

if ($ReportPath) {
    Export-SqlSafetyReportJson -Violations $allViolations -ScannedFileCount $filesToScan.Count -OutputPath $ReportPath
}

# Syntax errors can't be approved, so they get no list
if ($ApprovalListPath -and -not $isPassed -and $allViolations.RuleId -notcontains 'E_SYNTAX_PARSE_ERROR') {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ApprovalListPath) | Out-Null
    $allViolations | Where-Object { $_.Action -in 'block', 'requireApproval' } |
        ForEach-Object { "$($_.File):$($_.Line) $($_.RuleId) $($_.StatementSnippet -replace '\s+', ' ')" } |
        Set-Content -Path $ApprovalListPath
    Write-Host "Needs a person's approval in CI; listed in $ApprovalListPath" -ForegroundColor Yellow
}

if (-not $isPassed) {
    exit 1
}

exit 0
