<#
.SYNOPSIS
    SQL script runner for one managed database, with dbo.DeploymentLog auditing.
.DESCRIPTION
    Executes the one-off SQL scripts in ScriptRunner/<Database> against <Database> only.
    Guarantees strict database isolation, executes scripts in alphanumeric order,
    enforces idempotency by silently skipping previously successful scripts, wraps
    scripts in transactions, and logs executed/failed scripts to [dbo].[DeploymentLog].
    'USE <Database>' is allowed; 'USE' of any other database fails validation.
.PARAMETER Database
    A managed database (Databases/<Database>/<Database>.sqlproj), or 'All' to run every database in turn.
.PARAMETER TargetEnvironment
    Target environment: 'Development', 'Staging', or 'Production'. Defaults to 'Development'.
.PARAMETER ConnectionString
    Optional connection string override.
.PARAMETER ScriptsDirectory
    Directory containing SQL scripts. Defaults to 'ScriptRunner/<Database>'.
.PARAMETER DryRun
    Validates and lists the scripts without contacting the database.
.PARAMETER Force
    Re-executes scripts even if previously completed with Status = 'SUCCESS'.
.PARAMETER NoTransaction
    Executes scripts without wrapping inside an explicit transaction.
.PARAMETER CheckOnly
    Reads dbo.DeploymentLog and checks only the scripts that have not run: USE of another database,
    credentials or a syntax error exit 1; risky statements are listed in
    artifacts/approval-required-<Database>.txt and exit 1 (SPEC-002 CHK-14). Never executes scripts or
    writes log rows. With -Database All, every list is removed when any database failed without one.
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
    [string]$ScriptsDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory = $false)]
    [switch]$Force = $false,

    [Parameter(Mandatory = $false)]
    [switch]$NoTransaction = $false,

    [Parameter(Mandatory = $false)]
    [switch]$CheckOnly = $false
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'Common.ps1')

if ($Database -eq 'All') {
    if ($ConnectionString -or $ScriptsDirectory) { throw '-ConnectionString and -ScriptsDirectory need a single -Database, not All.' }
    $failed = @(Invoke-ForEachDatabase $PSCommandPath $PSBoundParameters)
    # A database that failed without an approval list failed for a reason no one can approve: offer no approval at all
    if ($CheckOnly -and ($failed | Where-Object { -not (Test-Path (Join-Path $ProjectRoot "artifacts/approval-required-$_.txt")) })) {
        Remove-Item -Path (Join-Path $ProjectRoot 'artifacts/approval-required-*.txt') -ErrorAction SilentlyContinue
    }
    if ($failed) { Write-Host "ScriptRunner failed for: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
    exit 0
}
$Database = Resolve-DatabaseName $Database

# A list left over from an earlier check must never offer an approval
$approvalListPath = Join-Path $ProjectRoot "artifacts/approval-required-$Database.txt"
if ($CheckOnly -and (Test-Path $approvalListPath)) { Remove-Item -Path $approvalListPath }

# Resolve Scripts directory
if ([string]::IsNullOrWhiteSpace($ScriptsDirectory)) {
    $ScriptsDirectory = Join-Path $ProjectRoot "ScriptRunner/$Database"
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Script Runner: $Database ($TargetEnvironment)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Directory: $ScriptsDirectory" -ForegroundColor Gray
Write-Host "Force Re-apply: $Force" -ForegroundColor Gray
Write-Host "Dry Run: $DryRun" -ForegroundColor Gray

if (-not (Test-Path $ScriptsDirectory)) {
    Write-Host "Directory '$ScriptsDirectory' does not exist. Nothing to execute." -ForegroundColor Yellow
    exit 0
}

# Returns an E_VALIDATION_FAILED message, or $null when the script is safe to run
function Get-ScriptValidationError([string]$ScriptName, [string]$Content) {
    # Strip comments so prose like '-- use this' is not read as a USE statement
    $code = $Content -replace '(?s)/\*.*?\*/', '' -replace '--[^\r\n]*', ''
    $otherDb = [regex]::Matches($code, '(?i)\bUSE\s+\[?(\w+)\]?') |
        ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne $Database } | Select-Object -First 1
    if ($otherDb) {
        return "E_VALIDATION_FAILED: Script '$ScriptName' contains 'USE $otherDb'. Only 'USE $Database' is allowed."
    }
    if ($Content -match '(?i)(Password\s*=|User\s+ID\s*=)') {
        return "E_VALIDATION_FAILED: Script '$ScriptName' contains potential plaintext credentials."
    }
    return $null
}

# Discover and sort scripts alphanumerically
$sqlFiles = @(Get-ChildItem -Path $ScriptsDirectory -Filter *.sql -File | Sort-Object Name)

if ($sqlFiles.Count -eq 0) {
    Write-Host "No .sql scripts found in '$ScriptsDirectory'. 0 scripts to execute." -ForegroundColor Green
    exit 0
}

Write-Host "Discovered $($sqlFiles.Count) script(s) in '$ScriptsDirectory'." -ForegroundColor Cyan

# DryRun only validates and lists the scripts; it never contacts the database
if ($DryRun) {
    Write-Host "DRY-RUN: Inspecting $($sqlFiles.Count) script(s); the database is not contacted." -ForegroundColor Green
    foreach ($file in $sqlFiles) {
        $planError = Get-ScriptValidationError $file.Name (Get-Content -Path $file.FullName -Raw)
        if ($planError) {
            Write-Host "  -> [PLAN-INVALID] $planError" -ForegroundColor Red
        } else {
            Write-Host "  -> [PLAN-VALID] $($file.Name)" -ForegroundColor Gray
        }
    }
    exit 0
}

$ConnectionString = Resolve-ConnectionString -Database $Database -TargetEnvironment $TargetEnvironment -ConnectionString $ConnectionString
if (-not $ConnectionString) {
    Write-Error "No ConnectionString found for database $Database ($TargetEnvironment)."
    exit 1
}

$metadata = Get-DeploymentMetadata
$conn = New-SqlConnection $ConnectionString
Initialize-DeploymentLog $conn

# Marks rows written by this runner, so DeployDatabase.ps1 rows for the same file name are ignored
$runnerSummary = "Executed via ScriptRunner for $Database"

# Query scripts already attempted (idempotency check): SUCCESS and FAILED scripts are never retried
$alreadyRun = @{}
if (-not $Force) {
    $checkSql = "SELECT ScriptName, Status FROM [dbo].[DeploymentLog] WHERE DatabaseName = @DbName AND Status IN ('SUCCESS', 'FAILED') AND ScriptName IS NOT NULL AND DeployReportSummary = @Summary ORDER BY DeploymentId;"
    $cmdCheck = $conn.CreateCommand()
    $cmdCheck.CommandText = $checkSql
    $cmdCheck.Parameters.AddWithValue('@DbName', $Database) | Out-Null
    $cmdCheck.Parameters.AddWithValue('@Summary', $runnerSummary) | Out-Null
    $reader = $cmdCheck.ExecuteReader()
    while ($reader.Read()) {
        # Ordered by DeploymentId, so the last status wins
        $alreadyRun[$reader.GetString(0)] = $reader.GetString(1)
    }
    $reader.Close()
}

# Only scripts that have not run can execute, so only they can need a person's approval
if ($CheckOnly) {
    $conn.Close()
    $pending = @($sqlFiles | Where-Object { -not $alreadyRun.ContainsKey($_.Name) })
    $invalid = @($pending | ForEach-Object { Get-ScriptValidationError $_.Name (Get-Content -Path $_.FullName -Raw) } | Where-Object { $_ })
    if ($invalid) {
        $invalid | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
    if ($pending.Count -eq 0) {
        Write-Host "No pending scripts to check." -ForegroundColor Green
        exit 0
    }
    & (Join-Path $ScriptDir 'Test-SqlSafety.ps1') -TargetFiles $pending.FullName -Environment Production -ApprovalListPath $approvalListPath
    exit $LASTEXITCODE
}

function Write-ScriptLog([string]$Status, [string]$ScriptName, [datetime]$StartUtc, [datetime]$EndUtc, [int]$DurationSec, [string]$ErrMsg) {
    Add-DeploymentLogRow $conn ($metadata + @{
        DatabaseName        = $Database
        TargetEnvironment   = $TargetEnvironment
        Status              = $Status
        DeployedAtUtc       = $StartUtc
        CompletedAtUtc      = $EndUtc
        DurationSeconds     = $DurationSec
        ScriptName          = $ScriptName
        ErrorMessage        = $ErrMsg
        DeployReportSummary = $runnerSummary
    })
}

$executedCount = 0
$skippedCount = 0
$failedCount = 0

try {
    foreach ($file in $sqlFiles) {
        $scriptName = $file.Name

        # 1. Idempotency Check
        if ($alreadyRun.ContainsKey($scriptName) -and -not $Force) {
            Write-Host "SKIP: Script '$scriptName' already ran (last status: $($alreadyRun[$scriptName])). To apply a fix, add a new script file." -ForegroundColor DarkGray
            $skippedCount++
            continue
        }

        # 2. Safety Validation Check
        $scriptContent = Get-Content -Path $file.FullName -Raw
        $validationError = Get-ScriptValidationError $scriptName $scriptContent

        if ($validationError) {
            Write-Host "FAILED (Validation): $validationError" -ForegroundColor Red
            Write-Error $validationError -ErrorAction Continue
            $nowUtc = [DateTime]::UtcNow
            Write-ScriptLog -Status 'FAILED' -ScriptName $scriptName -StartUtc $nowUtc -EndUtc $nowUtc -DurationSec 0 -ErrMsg $validationError
            $failedCount++
            continue
        }

        Write-Host "EXECUTING: '$scriptName' against $Database..." -ForegroundColor Cyan
        $startUtc = [DateTime]::UtcNow

        # Split into batches by GO statement
        $batches = [System.Text.RegularExpressions.Regex]::Split($scriptContent, '(?im)^\s*GO\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)

        $tran = $null
        if (-not $NoTransaction) {
            $tran = $conn.BeginTransaction("TX_$($scriptName -replace '\W', '_')")
        }

        try {
            foreach ($batch in $batches) {
                $batchTrimmed = $batch.Trim()
                if ([string]::IsNullOrWhiteSpace($batchTrimmed)) { continue }

                $cmdRun = $conn.CreateCommand()
                $cmdRun.CommandText = $batchTrimmed
                $cmdRun.CommandTimeout = 300
                if ($tran) { $cmdRun.Transaction = $tran }
                $cmdRun.ExecuteNonQuery() | Out-Null
            }

            if ($tran) {
                $tran.Commit()
            }

            $endUtc = [DateTime]::UtcNow
            $durationSec = [Math]::Max(0, [int][Math]::Round(($endUtc - $startUtc).TotalSeconds))

            Write-ScriptLog -Status 'SUCCESS' -ScriptName $scriptName -StartUtc $startUtc -EndUtc $endUtc -DurationSec $durationSec -ErrMsg $null
            Write-Host "SUCCESS: Script '$scriptName' executed and logged to dbo.DeploymentLog (${durationSec}s)." -ForegroundColor Green
            $executedCount++
        }
        catch {
            $err = "E_SCRIPT_FAILED: $($_.Exception.Message)"
            if ($tran) {
                try { $tran.Rollback() } catch {}
            }
            $endUtc = [DateTime]::UtcNow
            $durationSec = [Math]::Max(0, [int][Math]::Round(($endUtc - $startUtc).TotalSeconds))

            Write-ScriptLog -Status 'FAILED' -ScriptName $scriptName -StartUtc $startUtc -EndUtc $endUtc -DurationSec $durationSec -ErrMsg $err
            Write-Host "FAILED (Runtime): Script '$scriptName' failed. Transaction rolled back. Error: $err" -ForegroundColor Red
            Write-Error $err -ErrorAction Continue
            $failedCount++
            continue
        }

    }

    Write-Host "-----------------------------------------" -ForegroundColor Gray
    Write-Host "ScriptRunner completed: $executedCount executed, $skippedCount skipped, $failedCount failed." -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Yellow' })

    if ($failedCount -gt 0) {
        Write-Error "ScriptRunner finished with $failedCount failed script(s)."
        exit 1
    }
}
finally {
    if ($conn -and $conn.State -eq 'Open') {
        $conn.Close()
    }
}

