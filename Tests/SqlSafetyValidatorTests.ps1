<#
.SYNOPSIS
    Verification test suite for SPEC-003 (AC-01 through AC-18).
.DESCRIPTION
    Verifies SQL Safety Validator rules (SQL001 through SQL009), AST parser,
    temporary table exceptions, environment policy gates, granular approval flags,
    and standardized violation reporting.
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$passCount = 0
$failCount = 0
$psCmd = if (Get-Command 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$validatorScript = Join-Path $ProjectRoot "Scripts/Test-SqlSafety.ps1"

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
Write-Host " Executing SPEC-003 Verification Suite" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$tempDir = Join-Path $ProjectRoot "Tests/TempSqlSafety"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

try {
    # Helper to invoke validator on SQL snippet
    function Invoke-Validator([string]$SqlContent, [string]$Environment = "Production", [hashtable]$Approvals = @{}) {
        $tempFile = Join-Path $tempDir ([System.IO.Path]::GetRandomFileName() + ".sql")
        Set-Content -Path $tempFile -Value $SqlContent -Encoding UTF8
        
        $approvalsArg = ""
        if ($Approvals -and $Approvals.Count -gt 0) {
            $pairList = @()
            foreach ($k in $Approvals.Keys) {
                $pairList += "$k=$($Approvals[$k])"
            }
            $approvalsArg = "-Approvals '$([string]::Join(',', $pairList))'"
        }

        $cmdStr = "& '$validatorScript' -TargetFiles @('$tempFile') -Environment '$Environment' $approvalsArg"
        $stdout = & $psCmd -NoProfile -Command $cmdStr 2>&1
        $exitCode = $LASTEXITCODE

        if (Test-Path $tempFile) {
            Remove-Item -Force $tempFile
        }

        return [PSCustomObject]@{
            ExitCode = $exitCode
            Output   = ($stdout -join "`n")
        }
    }

    # AC-01: UPDATE without WHERE triggers SQL001 (CRITICAL, blocks)
    Assert-Condition "UPDATE without WHERE triggers SQL001 and fails validation" "SPEC-003 AC-01" {
        $res = Invoke-Validator -SqlContent "UPDATE dbo.Customer SET IsActive = 0;"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL001') -and ($res.Output -match 'CRITICAL')
    }

    # AC-02: UPDATE with valid WHERE clause is permitted
    Assert-Condition "UPDATE with WHERE clause passes validation" "SPEC-003 AC-02" {
        $res = Invoke-Validator -SqlContent "UPDATE dbo.Customer SET IsActive = 0 WHERE CustomerId = 1001;"
        return ($res.ExitCode -eq 0) -and ($res.Output -notmatch 'SQL001')
    }

    # AC-03: DELETE without WHERE triggers SQL002 (CRITICAL, blocks)
    Assert-Condition "DELETE without WHERE triggers SQL002 and fails validation" "SPEC-003 AC-03" {
        $res = Invoke-Validator -SqlContent "DELETE FROM dbo.Customer;"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL002') -and ($res.Output -match 'CRITICAL')
    }

    # AC-04: DELETE with broad condition WHERE 1 = 1 triggers SQL002
    Assert-Condition "DELETE with broad condition WHERE 1 = 1 triggers SQL002" "SPEC-003 AC-04" {
        $res1 = Invoke-Validator -SqlContent "DELETE FROM dbo.Customer WHERE 1 = 1;"
        $res2 = Invoke-Validator -SqlContent "DELETE FROM dbo.Customer WHERE 1=1;"
        return ($res1.ExitCode -ne 0) -and ($res1.Output -match 'SQL002') -and ($res2.ExitCode -ne 0) -and ($res2.Output -match 'SQL002')
    }

    # AC-05: DROP DATABASE in Production triggers SQL003 and blocks unconditionally
    Assert-Condition "DROP DATABASE in Production triggers SQL003 and is blocked" "SPEC-003 AC-05" {
        $res = Invoke-Validator -SqlContent "DROP DATABASE SalesDB;" -Environment "Production"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL003') -and ($res.Output -match 'CRITICAL')
    }

    # AC-06: DROP DATABASE in Development with allowDropDatabase passes
    Assert-Condition "DROP DATABASE in Development with explicit approval passes" "SPEC-003 AC-06" {
        $res = Invoke-Validator -SqlContent "DROP DATABASE DevSandboxDB;" -Environment "Development" -Approvals @{ allowDropDatabase = $true }
        return ($res.ExitCode -eq 0) -and ($res.Output -match 'APPROVED|ALLOW')
    }

    # AC-07: DROP TABLE on permanent table triggers SQL004 (HIGH, blocks)
    Assert-Condition "DROP TABLE on permanent table triggers SQL004 and is blocked" "SPEC-003 AC-07" {
        $res = Invoke-Validator -SqlContent "DROP TABLE dbo.Customer;"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL004') -and ($res.Output -match 'HIGH')
    }

    # AC-08: DROP TABLE on temporary tables (# and ##) is permitted
    Assert-Condition "DROP TABLE on temporary tables (#Temp, ##GlobalTemp) is allowed" "SPEC-003 AC-08" {
        $sql = @"
DROP TABLE #TempCustomer;
DROP TABLE ##GlobalTempCustomer;
"@
        $res = Invoke-Validator -SqlContent $sql
        return ($res.ExitCode -eq 0) -and ($res.Output -match 'Temporary table')
    }

    # AC-09: TRUNCATE TABLE in Production triggers SQL005 (HIGH, blocks)
    Assert-Condition "TRUNCATE TABLE in Production triggers SQL005 and is blocked" "SPEC-003 AC-09" {
        $res = Invoke-Validator -SqlContent "TRUNCATE TABLE dbo.Customer;" -Environment "Production"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL005') -and ($res.Output -match 'HIGH')
    }

    # AC-10: ALTER TABLE ... ADD COLUMN is non-destructive and allowed
    Assert-Condition "ALTER TABLE ADD COLUMN is recognized as non-destructive and allowed" "SPEC-003 AC-10" {
        $res = Invoke-Validator -SqlContent "ALTER TABLE dbo.Customer ADD Email VARCHAR(200);"
        return ($res.ExitCode -eq 0) -and ($res.Output -notmatch 'ERROR|BLOCK')
    }

    # AC-11: ALTER TABLE ... DROP COLUMN triggers SQL007 (HIGH, requires approval)
    Assert-Condition "ALTER TABLE DROP COLUMN triggers SQL007 and requires approval" "SPEC-003 AC-11" {
        $res = Invoke-Validator -SqlContent "ALTER TABLE dbo.Customer DROP COLUMN Email;"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL007') -and ($res.Output -match 'HIGH')
    }

    # AC-12: DROP PROCEDURE and DROP VIEW trigger SQL008 and SQL009
    Assert-Condition "DROP PROCEDURE and DROP VIEW trigger SQL008 and SQL009 in Staging/Prod" "SPEC-003 AC-12" {
        $sql = @"
DROP PROCEDURE dbo.usp_GetCustomer;
DROP VIEW dbo.CustomerSummary;
"@
        $res = Invoke-Validator -SqlContent $sql -Environment "Production"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL008') -and ($res.Output -match 'SQL009')
    }

    # AC-13: Granular approval flags only approve the matching operation
    Assert-Condition "Granular approval flags approve only targeted operations" "SPEC-003 AC-13" {
        $sql = @"
UPDATE dbo.Customer SET IsActive = 0;
DROP TABLE dbo.Customer;
"@
        # Approving only unconditional update must NOT approve drop table
        $res = Invoke-Validator -SqlContent $sql -Approvals @{ allowUnconditionalUpdate = $true; allowDropTable = $false }
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL004')
    }

    # AC-14: Syntax errors fail closed with E_SYNTAX_PARSE_ERROR
    Assert-Condition "Syntax parse errors fail closed with E_SYNTAX_PARSE_ERROR" "SPEC-003 AC-14" {
        $res = Invoke-Validator -SqlContent "SELECT FROM WHERE WHERE ;;"
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'E_SYNTAX_PARSE_ERROR|Syntax error')
    }

    # AC-15: String literals or comments containing WHERE do not fool parser
    Assert-Condition "WHERE in string literal does not satisfy UPDATE WHERE requirement" "SPEC-003 AC-15" {
        $sql = "UPDATE dbo.Customer SET Note = 'WHERE CustomerId = 1001';"
        $res = Invoke-Validator -SqlContent $sql
        return ($res.ExitCode -ne 0) -and ($res.Output -match 'SQL001')
    }

    # AC-16: Standardized violation report format
    Assert-Condition "Violation report formats file, line number, SQL operation, and reason" "SPEC-003 AC-16" {
        $sql = @"
-- line 1
-- line 2
UPDATE dbo.Customer SET IsActive = 0;
"@
        $res = Invoke-Validator -SqlContent $sql
        return ($res.Output -match 'File:') -and ($res.Output -match 'Line:\s*3') -and ($res.Output -match 'SQL001') -and ($res.Output -match 'Severity:\s*CRITICAL')
    }

    # AC-17: Development relaxes TRUNCATE / DROP PROCEDURE / DROP VIEW but still gates DROP TABLE
    Assert-Condition "Development allows TRUNCATE, DROP PROCEDURE and DROP VIEW but still gates DROP TABLE" "SPEC-003 AC-17" {
        $relaxed = Invoke-Validator -SqlContent "TRUNCATE TABLE dbo.Customer;`nDROP PROCEDURE dbo.usp_GetCustomer;`nDROP VIEW dbo.CustomerSummary;" -Environment "Development"
        $gated = Invoke-Validator -SqlContent "DROP TABLE dbo.Customer;" -Environment "Development"
        return ($relaxed.ExitCode -eq 0) -and ($gated.ExitCode -ne 0) -and ($gated.Output -match 'SQL004')
    }

    # AC-18: Without the ScriptDom parser the validator fails closed instead of guessing
    Assert-Condition "Missing ScriptDom parser fails closed with E_PARSER_UNAVAILABLE" "SPEC-003 AC-18" {
        $copy = Join-Path $tempDir "ScriptsWithoutScriptDom"
        Copy-Item -Recurse -Path (Join-Path $ProjectRoot "Scripts") -Destination $copy
        # Simulate a machine without ScriptDom: the copy's loader always reports it missing
        Add-Content -Path (Join-Path $copy "SqlSafety/Parser/ScriptDomParser.ps1") -Value "`nfunction Import-ScriptDom { return `$false }"
        $sqlFile = Join-Path $tempDir "parser_check.sql"
        Set-Content -Path $sqlFile -Value "UPDATE dbo.Customer SET IsActive = 0 WHERE CustomerId = 1;"
        $out = & $psCmd -NoProfile -File (Join-Path $copy "Test-SqlSafety.ps1") -TargetFiles $sqlFile 2>&1 | Out-String
        return ($LASTEXITCODE -ne 0) -and ($out -match 'E_PARSER_UNAVAILABLE')
    }

    # AC-19: approval-list mode lists every risky statement, comment or not; a syntax error can't be approved
    Assert-Condition "-ApprovalListPath lists risky statements despite approval comments and skips syntax errors" "SPEC-003 AC-19" {
        $list = Join-Path $tempDir "approval-required.txt"
        $check = {
            param([string]$Sql)
            $file = Join-Path $tempDir "approval_check.sql"
            Set-Content -Path $file -Value $Sql
            & $psCmd -NoProfile -File $validatorScript -TargetFiles $file -ApprovalListPath $list *>$null
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE; List = $(if (Test-Path $list) { Get-Content $list -Raw }) }
        }
        $risky = & $check "-- @manual-approve: yearly reset`nUPDATE dbo.Customer SET IsActive = 0;`nDROP TABLE dbo.Customer;"
        $syntax = & $check "SELECT FROM WHERE WHERE ;;"
        $safe = & $check "ALTER TABLE dbo.Customer ADD Email VARCHAR(200);`nDROP TABLE #TempCustomer;"
        return ($risky.ExitCode -eq 1) -and ($risky.List -match 'SQL001') -and ($risky.List -match 'SQL004') -and
            ($syntax.ExitCode -eq 1) -and (-not $syntax.List) -and ($safe.ExitCode -eq 0) -and (-not $safe.List)
    }

} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
}

Write-Host ""
Write-Host "-----------------------------------------" -ForegroundColor Gray
$summaryColor = if ($failCount -gt 0) { 'Red' } else { 'Green' }
Write-Host "Test Results: $passCount Passed, $failCount Failed." -ForegroundColor $summaryColor

if ($failCount -gt 0) {
    exit 1
}

exit 0
