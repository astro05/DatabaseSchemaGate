<#
.SYNOPSIS
    Verification test suite for SPEC-001 (AC-01 through AC-14).
.DESCRIPTION
    Verifies multi-database project structure (Databases/<Name>/<Name>.sqlproj in Databases.sln),
    solution build, unconditional UPDATE approval guardrails,
    SQL linting rules, destructive change protections, secrets protection, and drift detection.
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$passCount = 0
$failCount = 0
$psCmd = if (Get-Command 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
. (Join-Path $ProjectRoot 'Scripts/Common.ps1')
$databases = @(Get-DatabaseNames)

# Runs ValidateDatabase.ps1 with one extra stored procedure file in a throwaway folder; returns its exit code
function Get-ValidationExitCode([string]$Sql) {
    $tempRoot = Join-Path $ProjectRoot 'Databases/_test_validation'
    try {
        New-Item -ItemType Directory -Force -Path "$tempRoot/StoredProcedures" | Out-Null
        Set-Content -Path "$tempRoot/StoredProcedures/temp_test.sql" -Value $Sql
        & $psCmd -File (Join-Path $ProjectRoot 'Scripts/ValidateDatabase.ps1') *>$null
        return $LASTEXITCODE
    } finally {
        Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
    }
}

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
Write-Host " Executing SPEC-001 Verification Suite" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# AC-01: Multi-Database Object Definitions & Solution Build
Assert-Condition "Database object definitions compile into valid DACPACs via Databases.sln" "SPEC-001 AC-01" {
    $sln = Join-Path $ProjectRoot "Databases.sln"
    $missing = @($databases | Where-Object { -not (Test-Path (Join-Path $ProjectRoot "bin/Release/$_.dacpac")) })
    return (Test-Path $sln) -and ($databases.Count -gt 0) -and ($missing.Count -eq 0)
}

# AC-02: Stored Procedure Standards & Qualification in every managed database
Assert-Condition "Every stored procedure follows SET NOCOUNT ON and schema qualification" "SPEC-001 AC-02" {
    $spFiles = @($databases | ForEach-Object { Get-ChildItem (Join-Path $ProjectRoot "Databases/$_/StoredProcedures") -Filter *.sql -File -ErrorAction SilentlyContinue })
    $bad = @($spFiles | Where-Object {
        $content = Get-Content $_.FullName -Raw
        -not (($content -match '(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)PROCEDURE\s+\[?\w+\]?\.\[?\w+\]?') -and ($content -match 'SET\s+NOCOUNT\s+ON'))
    })
    return ($spFiles.Count -gt 0) -and ($bad.Count -eq 0)
}

# AC-03: Every managed database carries its pre- and post-deployment scripts
Assert-Condition "Every managed database has Deployment/PreDeployment.sql and Deployment/PostDeployment.sql" "SPEC-001 AC-03" {
    $missing = @($databases | Where-Object {
        -not (Test-Path (Join-Path $ProjectRoot "Databases/$_/Deployment/PreDeployment.sql")) -or
        -not (Test-Path (Join-Path $ProjectRoot "Databases/$_/Deployment/PostDeployment.sql"))
    })
    return ($databases.Count -gt 0) -and ($missing.Count -eq 0)
}

# AC-04: Invalid SQL Linter Protection
Assert-Condition "Validation script detects forbidden USE statements, but not the word 'use' in comments" "SPEC-001 AC-04" {
    $commentOnly = "-- Use this procedure for reports`n/* use it */`nCREATE PROCEDURE dbo.usp_Report AS BEGIN SET NOCOUNT ON; SELECT 1; END;"
    return ((Get-ValidationExitCode "USE [master]; CREATE PROCEDURE dbo.InvalidProc AS BEGIN SET NOCOUNT ON; SELECT 1; END;") -ne 0) -and
        ((Get-ValidationExitCode $commentOnly) -eq 0)
}

# AC-05: Stored Procedure SET NOCOUNT ON Enforcement
Assert-Condition "Validation script fails when stored procedure lacks SET NOCOUNT ON" "SPEC-001 AC-05" {
    return (Get-ValidationExitCode "CREATE PROCEDURE dbo.usp_BadSp AS BEGIN SELECT 1; END;") -ne 0
}

# AC-06: Destructive Change Protection Parameter
Assert-Condition "DeployDatabase.ps1 defaults BlockOnPossibleDataLoss to true" "SPEC-001 AC-06" {
    $deployScript = Get-Content (Join-Path $ProjectRoot "Scripts/DeployDatabase.ps1") -Raw
    return ($deployScript -match '\[bool\]\$BlockOnPossibleDataLoss\s*=\s*\$true')
}

# AC-07: Development-Only Deployment in CI/CD
Assert-Condition "GitLab CI configuration deploys only to development environment" "SPEC-001 AC-07" {
    $ciFile = Join-Path $ProjectRoot ".gitlab-ci.yml"
    if (-not (Test-Path $ciFile)) { return $false }
    $ciContent = Get-Content $ciFile -Raw
    return ($ciContent -match 'deploy_dev') -and ($ciContent -notmatch 'deploy_test') -and ($ciContent -notmatch 'deploy_prod')
}

# AC-08: Artifact Promotion (Multi-database DACPACs preserved across jobs)
Assert-Condition "GitLab CI configuration declares artifacts for bin/Release/*.dacpac" "SPEC-001 AC-08" {
    $ciFile = Join-Path $ProjectRoot ".gitlab-ci.yml"
    if (-not (Test-Path $ciFile)) { return $false }
    $ciContent = Get-Content $ciFile -Raw
    return ($ciContent -match 'bin/Release/\*.dacpac')
}

# AC-09: Secrets Protection (Zero credentials committed in Git source tree)
Assert-Condition "No passwords or private keys found in source code" "SPEC-001 AC-09" {
    $scanDir = if (Test-Path (Join-Path $ProjectRoot "Databases")) { Join-Path $ProjectRoot "Databases" } else { Join-Path $ProjectRoot "Database" }
    $sourceFiles = Get-ChildItem -Path $scanDir -Filter *.sql -Recurse
    foreach ($f in $sourceFiles) {
        $text = Get-Content $f.FullName -Raw
        if ($text -match '(?i)(password\s*=|user\s+id\s*=)') { return $false }
    }
    return $true
}

# AC-10: Schema Drift Detection Script Supports -Database Parameter
Assert-Condition "DetectDrift.ps1 script exists and supports DeployReport action and Database parameter" "SPEC-001 AC-10" {
    $driftScript = Join-Path $ProjectRoot "Scripts/DetectDrift.ps1"
    if (-not (Test-Path $driftScript)) { return $false }
    $content = Get-Content $driftScript -Raw
    return ($content -match '/Action:DeployReport') -and ($content -match '\$Database')
}

# AC-11: Database Extraction Script Supports -Database Parameter
Assert-Condition "ExtractDatabase.ps1 script exists and supports SqlPackage extraction and Database parameter" "SPEC-001 AC-11" {
    $extractScript = Join-Path $ProjectRoot "Scripts/ExtractDatabase.ps1"
    if (-not (Test-Path $extractScript)) { return $false }
    $content = Get-Content $extractScript -Raw
    return ($content -match '/Action:Extract') -and ($content -match '\$Database')
}

# AC-12: Unconditional UPDATE without WHERE clause requires manual approval (Fails when unapproved)
Assert-Condition "ValidateDatabase.ps1 fails when UPDATE lacks WHERE clause and has no approval comment" "SPEC-001 AC-12" {
    return (Get-ValidationExitCode "CREATE PROCEDURE dbo.usp_BulkUpdate AS BEGIN SET NOCOUNT ON; UPDATE dbo.TblCustomer SET Status = 1; END;") -ne 0
}

# AC-13: Unconditional UPDATE with manual approval comment passes validation
Assert-Condition "ValidateDatabase.ps1 passes when UPDATE lacks WHERE clause but includes approval comment" "SPEC-001 AC-13" {
    $sqlContent = @"
CREATE PROCEDURE dbo.usp_ApprovedBulkUpdate
AS
BEGIN
    SET NOCOUNT ON;
    -- @manual-approve: Intentional reset of customer status by DBA
    UPDATE dbo.TblCustomer SET Status = 1;
END;
"@
    return (Get-ValidationExitCode $sqlContent) -eq 0
}

# AC-14: Every Databases/<Name>/<Name>.sqlproj is a managed database listed in Databases.sln; other names are rejected
Assert-Condition "Each managed database has its own .sqlproj in Databases.sln and unknown names are rejected" "SPEC-001 AC-14" {
    $sln = Get-Content (Join-Path $ProjectRoot "Databases.sln") -Raw
    $notInSln = @($databases | Where-Object { $sln -notmatch [regex]::Escape("Databases\$_\$_.sqlproj") })
    try { Resolve-DatabaseName "NoSuchDb_$([guid]::NewGuid().ToString('N'))" | Out-Null; $unknownRejected = $false }
    catch { $unknownRejected = $_.Exception.Message -match 'E_DATABASE_NOT_FOUND' }
    return ($databases.Count -gt 0) -and ($notInSln.Count -eq 0) -and $unknownRejected
}

# AC-16: ScriptName column in dbo.DeploymentLog and per-SQL script deployment logging
Assert-Condition "dbo.DeploymentLog contains ScriptName column and DeployDatabase.ps1 logs per .sql file" "SPEC-002 AC-16" {
    $deployScript = Join-Path $ProjectRoot "Scripts/DeployDatabase.ps1"
    $withoutColumn = @($databases | Where-Object {
        $table = Join-Path $ProjectRoot "Databases/$_/Tables/dbo.DeploymentLog.sql"
        -not (Test-Path $table) -or ((Get-Content $table -Raw) -notmatch '\[ScriptName\]\s+NVARCHAR')
    })
    $cDeploy = Get-Content $deployScript -Raw
    $cCommon = Get-Content (Join-Path $ProjectRoot "Scripts/Common.ps1") -Raw
    $hasColDeploy = ($cDeploy -match 'ScriptName\s*=\s*\$scriptName') -and ($cCommon -match '\[ScriptName\]')
    # SPEC-002 1.1.0: only .sql files under Databases/<Database>/ are logged, so ScriptRunner scripts and other databases' files are not
    $hasSqlOnlyFilter = ($cDeploy -match [regex]::Escape('"^Databases/$([regex]::Escape($Database))/.*\.sql$"'))
    # SPEC-002 3.0.1: files come from the diff against the first parent, so a merge commit logs what it merged
    $hasFirstParentDiff = ($cDeploy -match [regex]::Escape('Get-GitOutput diff --name-only "$($metadata.CommitSha)^1" $metadata.CommitSha'))

    return ($databases.Count -gt 0) -and ($withoutColumn.Count -eq 0) -and $hasColDeploy -and $hasSqlOnlyFilter -and $hasFirstParentDiff
}

# AC-17: Dedicated database connections enforced (cross-database connection rejected)
Assert-Condition "DeployDatabase.ps1 enforces dedicated database connections and rejects mismatched Initial Catalog" "SPEC-002 AC-17" {
    $deployScript = Join-Path $ProjectRoot "Scripts/DeployDatabase.ps1"
    $ciFile = Join-Path $ProjectRoot ".gitlab-ci.yml"
    if (-not (Test-Path $deployScript) -or -not (Test-Path $ciFile)) { return $false }

    # 1. CI passes no shared connection string: each database reads its own DEV_CONNECTION_STRING_<DATABASE>
    $ciContent = Get-Content $ciFile -Raw
    $commonContent = Get-Content (Join-Path $ProjectRoot "Scripts/Common.ps1") -Raw
    $ciDedicated = ($ciContent -notmatch '-ConnectionString') -and ($ciContent -match 'DeployDatabase\.ps1 -Database All') -and
        ($commonContent -match [regex]::Escape('"${prefix}_CONNECTION_STRING_$($Database.ToUpper()'))

    if (-not $ciDedicated) { return $false }

    # 2. DeployDatabase.ps1 must fail when Initial Catalog does not match target database
    $mismatchedConn = "Data Source=localhost;Initial Catalog=SomeOtherDatabase;Integrated Security=True;"
    & $psCmd -File $deployScript -Database $databases[0] -ConnectionString $mismatchedConn *>$null
    $mismatchFailed = ($LASTEXITCODE -ne 0)

    # 3. One connection string can't be shared by every database
    & $psCmd -File $deployScript -Database All -ConnectionString $mismatchedConn *>$null
    $sharedRejected = ($LASTEXITCODE -ne 0)

    return $mismatchFailed -and $sharedRejected
}

# AC-18: on main, risky statements in scripts that have not run wait for the manual deploy_dev_approved job
Assert-Condition "GitLab CI asks for approval only when check_scripts lists risky statements" "SPEC-002 AC-18" {
    $ci = Get-Content (Join-Path $ProjectRoot ".gitlab-ci.yml") -Raw
    $job = { param($name) [regex]::Match($ci, "(?ms)^$($name):.*?(?=^\S|\z)").Value }
    $check = & $job 'check_scripts'
    $marker = & $job 'approval_required'
    $deploy = & $job 'deploy_dev_approved'
    $mainOnly = 'rules:\s*- if: \$CI_COMMIT_BRANCH == "main"'
    return ((& $job 'validate_sql') -notmatch 'ScriptRunner') -and ($ci -notmatch 'approve_unconditional_updates') -and
        ($check -match 'stage:\s*test') -and ($check -match 'Invoke-ScriptRunner\.ps1 .*-CheckOnly') -and
        ($check -match 'when:\s*on_failure\s*paths:\s*- artifacts/approval-required-\*\.txt') -and ($check -match $mainOnly) -and
        ($marker -match 'needs:\s*\[check_scripts\]') -and ($marker -match "$mainOnly\s*when: on_failure") -and
        ($marker -match 'cat artifacts/approval-required-\*\.txt') -and
        ($deploy -match 'extends:\s*deploy_dev\s') -and ($deploy -match "$mainOnly\s*when: manual\s*allow_failure: false") -and
        ($deploy -match 'needs:\s*\[approval_required, build_dacpac, test_database\]') -and
        (($check + $marker + $deploy) -notmatch 'merge_request_event')
}

Write-Host ""
Write-Host "-----------------------------------------" -ForegroundColor Gray
$summaryColor = if ($failCount -gt 0) { 'Red' } else { 'Green' }
Write-Host "Test Results: $passCount Passed, $failCount Failed." -ForegroundColor $summaryColor

if ($failCount -gt 0) {
    exit 1
}

exit 0
