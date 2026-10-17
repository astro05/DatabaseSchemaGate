<#
.SYNOPSIS
    Static analysis and lint validator for database source objects.
.DESCRIPTION
    Enforces naming standards, schema qualification, unconditional UPDATE approval rules,
    and SQL Server best practices defined in SPEC-001 and SPEC-002.
.PARAMETER TargetPath
    Path to scan for SQL files. Defaults to 'Databases'.
.PARAMETER Database
    Database to validate (a folder name under Databases/), or 'All'. Defaults to 'All'.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TargetPath = 'Databases',

    [Parameter(Mandatory = $false)]
    [string]$Database = 'All'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Determine scan directory
$ScanDirectory = Join-Path $ProjectRoot $TargetPath

if ($Database -ne 'All' -and (Test-Path (Join-Path $ScanDirectory $Database))) {
    $ScanDirectory = Join-Path $ScanDirectory $Database
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Validating SQL Database Standards" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Target: $ScanDirectory" -ForegroundColor Gray
Write-Host "Database Scope: $Database" -ForegroundColor Gray

if (-not (Test-Path $ScanDirectory)) {
    Write-Host "No database folder found at $ScanDirectory; skipping scan." -ForegroundColor Yellow
    exit 0
}

$sqlFiles = Get-ChildItem -Path $ScanDirectory -Filter *.sql -Recurse -File | Where-Object { $_.Extension -eq '.sql' }

$errors = 0

foreach ($file in $sqlFiles) {
    $relPath = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
    $content = Get-Content -Path $file.FullName -Raw

    # 1. Ban USE [database] statements (SSDT invariant); comments are stripped so prose like '-- use this' passes
    $code = $content -replace '(?s)/\*.*?\*/', '' -replace '--[^\r\n]*', ''
    if ($code -match '\bUSE\s+\[?[\w]+\]?\s*;?') {
        Write-Host "ERROR  [$relPath]: Contains 'USE <db>' statement. Database context must not be hardcoded in DACPAC projects." -ForegroundColor Red
        $errors++
    }

    # 2. Ban credentials / connection strings
    if ($content -match '(?i)(Password\s*=|User\s+ID\s*=|Initial\s+Catalog\s*=)') {
        Write-Host "ERROR  [$relPath]: Potential connection string or credential detected." -ForegroundColor Red
        $errors++
    }

    # 3. Schema Qualification & Standards for Object Definitions
    if ($file.DirectoryName -like "*StoredProcedures*") {
        # Check SET NOCOUNT ON
        if ($content -notmatch '(?i)SET\s+NOCOUNT\s+ON') {
            Write-Host "ERROR  [$relPath]: Stored procedure missing required 'SET NOCOUNT ON;' statement (SPEC-001 AC-02)." -ForegroundColor Red
            $errors++
        }

        # Check mandatory schema qualification (supports CREATE, ALTER, and CREATE OR ALTER)
        if ($content -notmatch '(?i)(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)PROCEDURE\s+\[?\w+\]?\.\[?\w+\]?') {
            Write-Host "ERROR  [$relPath]: Schema name is mandatory for Stored Procedure definition (e.g. [dbo].[usp_Name])." -ForegroundColor Red
            $errors++
        }
    }

    # 4. Mandatory Schema Qualification for Table Definitions
    if ($file.DirectoryName -like "*Tables*") {
        if ($content -match '(?i)CREATE\s+TABLE\s+') {
            if ($content -notmatch '(?i)CREATE\s+TABLE\s+\[?\w+\]?\.\[?\w+\]?') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for Table definition (e.g. [dbo].[TblName])." -ForegroundColor Red
                $errors++
            }
        }
    }

    # 5. Mandatory Schema Qualification for Views & Functions
    if ($file.DirectoryName -like "*Views*" -and $content -match '(?i)(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)VIEW\s+') {
        if ($content -notmatch '(?i)(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)VIEW\s+\[?\w+\]?\.\[?\w+\]?') {
            Write-Host "ERROR  [$relPath]: Schema name is mandatory for View definition (e.g. [dbo].[ViewName])." -ForegroundColor Red
            $errors++
        }
    }
    if ($file.DirectoryName -like "*Functions*" -and $content -match '(?i)(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)FUNCTION\s+') {
        if ($content -notmatch '(?i)(CREATE\s+(OR\s+ALTER\s+)?|ALTER\s+)FUNCTION\s+\[?\w+\]?\.\[?\w+\]?') {
            Write-Host "ERROR  [$relPath]: Schema name is mandatory for Function definition (e.g. [dbo].[fn_Name])." -ForegroundColor Red
            $errors++
        }
    }

    # 6. Mandatory Schema Qualification for All SQL Actions (DDL & DML)
    $cleanedContent = $content -replace '(?s)/\*.*?\*/', ''
    $statements = $cleanedContent -split '(?i);\s*|\bGO\b'

    foreach ($stmt in $statements) {
        $stmtTrim = $stmt.Trim()
        if ([string]::IsNullOrWhiteSpace($stmtTrim)) { continue }

        $stmtNoComments = ($stmtTrim -split "`r?`n" | Where-Object { $_ -notmatch '^\s*--' }) -join "`n"
        $stmtCode = $stmtNoComments -replace "'([^']|'')*'", "''"

        # Check UPDATE action
        if ($stmtCode -match '(?i)\bUPDATE\s+(?!STATISTICS\b)(?<target>[\w\.\[\]]+)\s+SET\b') {
            $target = $matches['target'].Trim()
            if ($target -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for UPDATE action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # Check DELETE action
        if ($stmtCode -match '(?i)\bDELETE\s+(FROM\s+)?(?<target>[\w\.\[\]#]+)') {
            $target = $matches['target'].Trim()
            if ($target -and -not $target.StartsWith('#') -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for DELETE action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # Check INSERT action
        if ($stmtCode -match '(?i)\bINSERT\s+(INTO\s+)?(?<target>[\w\.\[\]#@]+)\s*(\(|\bSELECT\b|\bVALUES\b|\bDEFAULT\b)') {
            $target = $matches['target'].Trim()
            if ($target -and -not $target.StartsWith('#') -and -not $target.StartsWith('@') -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for INSERT action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # Check TRUNCATE action
        if ($stmtCode -match '(?i)\bTRUNCATE\s+TABLE\s+(?<target>[\w\.\[\]]+)') {
            $target = $matches['target'].Trim()
            if ($target -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for TRUNCATE action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # Check ALTER TABLE action
        if ($stmtCode -match '(?i)\bALTER\s+TABLE\s+(?<target>[\w\.\[\]]+)') {
            $target = $matches['target'].Trim()
            if ($target -and -not $target.StartsWith('#') -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for ALTER TABLE action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # Check DROP TABLE action
        if ($stmtCode -match '(?i)\bDROP\s+TABLE\s+(IF\s+EXISTS\s+)?(?<target>[\w\.\[\]#]+)') {
            $target = $matches['target'].Trim()
            if ($target -and -not $target.StartsWith('#') -and $target -notmatch '\.') {
                Write-Host "ERROR  [$relPath]: Schema name is mandatory for DROP TABLE action. Target '$target' must be schema-qualified (e.g. [dbo].$target)." -ForegroundColor Red
                $errors++
            }
        }

        # 7. Unconditional UPDATE Protection (UPDATE query without WHERE clause requires manual approval)
        if ($stmtCode -match '(?i)\bUPDATE\s+(?!STATISTICS\b)[\w\.\[\]]+\s+SET\b') {
            if ($stmtCode -notmatch '(?i)\bWHERE\b') {
                if ($stmtTrim -notmatch '(?i)--\s*@manual-approve:') {
                    Write-Host "ERROR  [$relPath]: Unconditional UPDATE detected without manual approval comment '-- @manual-approve: <reason>'." -ForegroundColor Red
                    $errors++
                } else {
                    Write-Host "INFO   [$relPath]: Approved unconditional UPDATE detected with manual approval annotation." -ForegroundColor Yellow
                }
            }
        }
    }
}

Write-Host ""
Write-Host "-----------------------------------------" -ForegroundColor Gray
$color = if ($errors -gt 0) { 'Red' } else { 'Green' }
Write-Host "Scanned $($sqlFiles.Count) SQL file(s): $errors error(s)." -ForegroundColor $color

if ($errors -gt 0) {
    exit 1
}

exit 0
