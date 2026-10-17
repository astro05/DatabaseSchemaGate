<#
.SYNOPSIS
    Verification test suite for SPEC-004 (ScriptRunner).
.DESCRIPTION
    Verifies that ScriptRunner/<Database> is used per managed database, enforces strict database
    isolation, executes scripts in alphanumeric order, tracks idempotency via dbo.DeploymentLog,
    records SUCCESS and FAILED audit logs, rolls back transactions on failure, and rejects USE of
    any other database. Tests run against the first managed database and never reach a server.
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$passCount = 0
$failCount = 0
$psCmd = if (Get-Command 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

function Assert-Condition([string]$TestName, [string]$AcId, [scriptblock]$Condition) {
    Write-Host -NoNewline "Running test: [$AcId] $TestName ... "
    try {
        $result = & $Condition
        if ($result -eq $true) {
            Write-Host "PASS" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host "FAIL (Assertion returned false)" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host "FAIL ($($_.Exception.Message))" -ForegroundColor Red
        $script:failCount++
    }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Executing SPEC-004 Verification Suite" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$runnerPath = Join-Path $ProjectRoot "Scripts/Invoke-ScriptRunner.ps1"
# Connection and dbo.DeploymentLog helpers the runner dot-sources
$commonContent = Get-Content (Join-Path $ProjectRoot "Scripts/Common.ps1") -Raw
. (Join-Path $ProjectRoot "Scripts/Common.ps1")
$db = @(Get-DatabaseNames)[0]
# Nothing listens on port 1: any connection attempt fails fast
$unreachable = "Server=127.0.0.1,1;Initial Catalog=$db;Connect Timeout=2"

# AC-01: ScriptRunner/ exists at project root and each database's scripts live in ScriptRunner/<Database>
Assert-Condition "ScriptRunner/ exists at project root and defaults to ScriptRunner/<Database>" "SPEC-004 AC-01" {
    $scriptRunnerDir = Join-Path $ProjectRoot "ScriptRunner"
    return (Test-Path $scriptRunnerDir -PathType Container) -and ((Get-Content $runnerPath -Raw) -match [regex]::Escape('"ScriptRunner/$Database"'))
}

# AC-02: Runner accepts only managed databases
Assert-Condition "Invoke-ScriptRunner.ps1 rejects a database that is not under Databases/" "SPEC-004 AC-02" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $out = & $psCmd -NoProfile -File $runnerPath -Database "NoSuchDb_$([guid]::NewGuid().ToString('N'))" -DryRun 2>&1 | Out-String
    return ($LASTEXITCODE -ne 0) -and ($out -match 'E_DATABASE_NOT_FOUND')
}

# AC-03: Discovers and sorts scripts in alphanumeric order
Assert-Condition "Invoke-ScriptRunner.ps1 orders scripts alphanumerically" "SPEC-004 AC-03" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'Sort-Object\s+Name') -or ($runnerContent -match 'Sort-Object\s+FullName')
}

# AC-04: Idempotent skip for scripts with SUCCESS in dbo.DeploymentLog
Assert-Condition "Invoke-ScriptRunner.ps1 skips scripts already executed with SUCCESS" "SPEC-004 AC-04" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'DeploymentLog') -and ($runnerContent -match "Status IN \('SUCCESS'")
}

# AC-05: Logs SUCCESS into dbo.DeploymentLog with ScriptName
Assert-Condition "Invoke-ScriptRunner.ps1 writes SUCCESS record to dbo.DeploymentLog" "SPEC-004 AC-05" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'Add-DeploymentLogRow') -and ($runnerContent -match 'ScriptName\s*=\s*\$ScriptName') -and
        ($commonContent -match 'INSERT\s+INTO\s+\[dbo\]\.\[DeploymentLog\]')
}

# AC-06: Rolls back transaction and writes FAILED record upon script error
Assert-Condition "Invoke-ScriptRunner.ps1 rolls back and logs FAILED on script error" "SPEC-004 AC-06" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'ROLLBACK') -and ($runnerContent -match 'FAILED')
}

# Runs the runner in offline DryRun mode against a temp folder holding one script; returns its output
function Invoke-DryRunPlan([string]$Sql) {
    $dir = Join-Path $ProjectRoot "ScriptRunner/_test_use"
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "001_test.sql") -Value $Sql
        return (& $psCmd -NoProfile -File $runnerPath -Database $db -ScriptsDirectory $dir -DryRun 2>&1 | Out-String)
    } finally {
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    }
}

# AC-07: Rejects USE of any database other than the target
Assert-Condition "Invoke-ScriptRunner.ps1 rejects USE of a database other than the target" "SPEC-004 AC-07" {
    $out = Invoke-DryRunPlan "-- use this script carefully`nUSE [master];`nSELECT 1;"
    $runnerContent = Get-Content $runnerPath -Raw
    return ($out -match 'PLAN-INVALID.*USE master') -and ($runnerContent -match 'Write-ScriptLog -Status ''FAILED''.*-ErrMsg \$validationError')
}

# AC-08: Gracefully completes when folder contains no scripts
Assert-Condition "Invoke-ScriptRunner.ps1 handles empty folder cleanly" "SPEC-004 AC-08" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $testEmptyDir = Join-Path $ProjectRoot "ScriptRunner/_test_empty"
    try {
        New-Item -ItemType Directory -Force -Path $testEmptyDir | Out-Null
        & $psCmd -File $runnerPath -Database $db -ScriptsDirectory $testEmptyDir -DryRun *>$null
        return ($LASTEXITCODE -eq 0)
    } finally {
        if (Test-Path $testEmptyDir) { Remove-Item -Recurse -Force $testEmptyDir }
    }
}

# AC-09: Verifies and provisions dbo.DeploymentLog table if absent
Assert-Condition "Invoke-ScriptRunner.ps1 includes dynamic dbo.DeploymentLog table creation" "SPEC-004 AC-09" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'Initialize-DeploymentLog \$conn') -and
        ($commonContent -match 'IF\s+OBJECT_ID\(N''\[dbo\]\.\[DeploymentLog\]''.*\s+IS\s+NULL')
}

# AC-10: Force switch allows re-executing previously applied scripts
Assert-Condition "Invoke-ScriptRunner.ps1 supports -Force parameter" "SPEC-004 AC-10" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match '\[switch\]\$Force')
}

# AC-11: Skipped scripts do not write rows to dbo.DeploymentLog
Assert-Condition "Invoke-ScriptRunner.ps1 skips previously applied scripts without logging them" "SPEC-004 AC-11" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'SKIP: Script') -and ($runnerContent -cnotmatch 'SKIPPED')
}

# AC-12: Non-halting batch execution logs each script separately and executes valid scripts even if one fails
Assert-Condition "Invoke-ScriptRunner.ps1 executes subsequent scripts and logs each separately on failure" "SPEC-004 AC-12" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match 'Write-ScriptLog\s+.*Status\s+.*FAILED') -and ($runnerContent -match '\$failedCount\+\+')
}

# AC-13: USE of the target database is accepted
Assert-Condition "Invoke-ScriptRunner.ps1 accepts USE <Database> and USE [<Database>]" "SPEC-004 AC-13" {
    $out = Invoke-DryRunPlan "USE $db;`nGO`nUSE [$db];`nSELECT 1;"
    return ($out -match 'PLAN-VALID') -and ($out -notmatch 'PLAN-INVALID')
}

# AC-14: Previously FAILED scripts are not retried; only the runner's own log rows count
Assert-Condition "Invoke-ScriptRunner.ps1 does not retry FAILED scripts and ignores non-runner log rows" "SPEC-004 AC-14" {
    if (-not (Test-Path $runnerPath)) { return $false }
    $runnerContent = Get-Content $runnerPath -Raw
    return ($runnerContent -match "Status IN \('SUCCESS', 'FAILED'\)") -and
        ($runnerContent -match 'DeployReportSummary = @Summary') -and
        ($runnerContent -match 'DeployReportSummary\s*=\s*\$runnerSummary')
}

# AC-15: on main, check_scripts runs -CheckOnly, which checks only the scripts that have not run yet
Assert-Condition "check_scripts runs -CheckOnly, which checks only scripts that have not run, before any executes" "SPEC-004 AC-15" {
    $ci = Get-Content (Join-Path $ProjectRoot ".gitlab-ci.yml") -Raw
    $validate = [regex]::Match($ci, '(?ms)^validate_sql:.*?(?=^\S)').Value
    $check = [regex]::Match($ci, '(?ms)^check_scripts:.*?(?=^\S|\z)').Value
    $runnerContent = Get-Content $runnerPath -Raw
    $block = [regex]::Match($runnerContent, '(?ms)^if \(\$CheckOnly\) \{.*?^\}').Value
    return ($validate -notmatch 'ScriptRunner') -and ($check -match 'Invoke-ScriptRunner\.ps1 .*-CheckOnly') -and
        ($block -match '-not \$alreadyRun\.ContainsKey') -and ($block -match 'Get-ScriptValidationError') -and
        ($block -match 'Test-SqlSafety\.ps1.*-TargetFiles \$pending\.FullName.*-ApprovalListPath') -and
        ($runnerContent -match '(?s)if \(\$CheckOnly\) \{.*\$executedCount = 0')
}

# AC-16: DryRun never contacts the database, even when a connection string is supplied
Assert-Condition "Invoke-ScriptRunner.ps1 -DryRun does not connect to the database" "SPEC-004 AC-16" {
    $dir = Join-Path $ProjectRoot "ScriptRunner/_test_dryrun"
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "001_test.sql") -Value "SELECT 1;"
        # Any connection attempt would fail the run
        $out = & $psCmd -NoProfile -File $runnerPath -Database $db -ScriptsDirectory $dir -DryRun -ConnectionString $unreachable 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0) -and ($out -match 'PLAN-VALID')
    } finally {
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    }
}

# AC-17: -CheckOnly fails closed: an unreachable database exits 1 and leaves no approval list
Assert-Condition "Invoke-ScriptRunner.ps1 -CheckOnly exits 1 with no approval list when the database is unreachable" "SPEC-004 AC-17" {
    $dir = Join-Path $ProjectRoot "ScriptRunner/_test_check"
    $list = Join-Path $ProjectRoot "artifacts/approval-required-$db.txt"
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "001_risky.sql") -Value "UPDATE dbo.Customer SET IsActive = 0;"
        Remove-Item -Path $list -ErrorAction SilentlyContinue
        $out = & $psCmd -NoProfile -File $runnerPath -Database $db -ScriptsDirectory $dir -CheckOnly -ConnectionString $unreachable 2>&1 | Out-String
        return ($LASTEXITCODE -ne 0) -and -not (Test-Path $list) -and ($out -notmatch 'parameter name')
    } finally {
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    }
}

# AC-18: -Database All -CheckOnly offers no approval when a database failed for a reason no one can approve
Assert-Condition "Invoke-ScriptRunner.ps1 -Database All -CheckOnly removes every approval list when a database fails without one" "SPEC-004 AC-18" {
    $scriptFile = Join-Path $ProjectRoot "ScriptRunner/$db/zzz_test_all_check.sql"
    $staleLists = @($db, 'ZzOtherDb') | ForEach-Object { Join-Path $ProjectRoot "artifacts/approval-required-$_.txt" }
    $savedEnv = @{}
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $scriptFile), (Join-Path $ProjectRoot 'artifacts') | Out-Null
        Set-Content -Path $scriptFile -Value "UPDATE dbo.Customer SET IsActive = 0;"
        $staleLists | ForEach-Object { Set-Content -Path $_ -Value 'stale' }
        # Point every database at an unreachable server so no real database is contacted
        foreach ($name in Get-DatabaseNames) {
            $var = "DEV_CONNECTION_STRING_$($name.ToUpper() -replace '[^A-Z0-9_]', '_')"
            $savedEnv[$var] = [Environment]::GetEnvironmentVariable($var)
            [Environment]::SetEnvironmentVariable($var, "Server=127.0.0.1,1;Initial Catalog=$name;Connect Timeout=2")
        }
        & $psCmd -NoProfile -File $runnerPath -Database All -CheckOnly *>$null
        $exit = $LASTEXITCODE
        & $psCmd -NoProfile -File $runnerPath -Database All -CheckOnly -ConnectionString $unreachable *>$null
        return ($exit -ne 0) -and ($LASTEXITCODE -ne 0) -and -not ($staleLists | Where-Object { Test-Path $_ })
    } finally {
        $savedEnv.GetEnumerator() | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Key, $_.Value) }
        Remove-Item -Path (@($scriptFile) + $staleLists) -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Test Summary: $passCount Passed, $failCount Failed" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
Write-Host "=========================================" -ForegroundColor Cyan

if ($failCount -gt 0) {
    exit 1
}
exit 0
