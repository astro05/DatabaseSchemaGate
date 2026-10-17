<#
.SYNOPSIS
    Verification test suite for SPEC-005 (Concurrent Edit Guard for SQL Objects).
.DESCRIPTION
    Builds throwaway Git repositories (bare origin + developer clones) that replay the two-developer
    dbo.demoSP scenario, runs Scripts/Test-ConcurrentEdits.ps1 against them, and checks the CI wiring.
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$passCount = 0
$failCount = 0
$psCmd = if (Get-Command 'pwsh' -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$checkPath = Join-Path $ProjectRoot "Scripts/Test-ConcurrentEdits.ps1"
$ciContent = Get-Content (Join-Path $ProjectRoot ".gitlab-ci.yml") -Raw

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

# Path has a space on purpose (EC-07)
$spFile = "dbo.demoSP copy.sql"
$spV1 = @"
CREATE PROCEDURE [dbo].[demoSP] @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Section A: customer validation
    SELECT 'A-v1';
    -- spacer 1
    -- spacer 2
    -- spacer 3
    -- spacer 4
    -- Section B: order calculation
    SELECT 'B-v1';
END
"@

# Wraps the real git binary (Windows and Linux) and fails the test on any git error
$gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
function git { & $gitExe @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

# Creates origin (bare) with main = v1 of demoSP + other.sql, plus clones 'b' (Developer B) and 'a' (Developer A)
function New-Scenario {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("spec005-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root | Out-Null
    git init -q --bare -b main (Join-Path $root 'origin.git')
    foreach ($dev in 'b', 'a') {
        git clone -q (Join-Path $root 'origin.git') (Join-Path $root $dev)
        git -C (Join-Path $root $dev) config user.name "Developer $($dev.ToUpper())"
        git -C (Join-Path $root $dev) config user.email "$dev@example.com"
        git -C (Join-Path $root $dev) config core.autocrlf false
        if ($dev -eq 'b') {
            Set-Content -Path (Join-Path $root "b/$spFile") -Value $spV1
            Set-Content -Path (Join-Path $root 'b/other.sql') -Value 'SELECT 1;'
            git -C (Join-Path $root 'b') add -A
            git -C (Join-Path $root 'b') commit -q -m 'v1'
            git -C (Join-Path $root 'b') push -q origin main
        }
    }
    git -C (Join-Path $root 'b') checkout -q -b feature-b
    return $root
}

function Edit-Commit([string]$Repo, [string]$File, [string]$From, [string]$To, [string]$Message) {
    $path = Join-Path $Repo $File
    $text = if (Test-Path $path) { (Get-Content $path -Raw) -replace [regex]::Escape($From), $To } else { $To }
    Set-Content -Path $path -Value $text -NoNewline
    git -C $Repo add -A
    git -C $Repo commit -q -m $Message
}

# Developer A changes a file on main after B branched
function Push-DeveloperA([string]$Root, [string]$File, [string]$From, [string]$To) {
    $a = Join-Path $Root 'a'
    git -C $a pull -q origin main
    Edit-Commit $a $File $From $To 'A: edit section A'
    git -C $a push -q origin main
}

function Invoke-Check([string]$Repo, [string]$Target = 'main') {
    $cmd = "`$env:CI_MERGE_REQUEST_TARGET_BRANCH_NAME = `$null; & '$checkPath' -TargetBranch '$Target' -RepoPath '$Repo'"
    $out = & $psCmd -NoProfile -Command $cmd 2>&1 | Out-String
    return @{ Exit = $LASTEXITCODE; Out = $out }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Executing SPEC-005 Verification Suite" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# AC-01 + AC-03 share one scenario: stale first, then rebased
$root = New-Scenario
try {
    Edit-Commit (Join-Path $root 'b') $spFile "SELECT 'B-v1';" "SELECT 'B-v2';" 'B: edit section B'
    Push-DeveloperA $root $spFile "SELECT 'A-v1';" "SELECT 'A-v2';"

    Assert-Condition "Branch from v1 edits demoSP after main changed it: E_STALE_BASE names file and commit" "SPEC-005 AC-01" {
        $r = Invoke-Check (Join-Path $root 'b')
        return ($r.Exit -eq 1) -and ($r.Out -match 'E_STALE_BASE') -and ($r.Out -match [regex]::Escape($spFile)) -and ($r.Out -match 'Developer A: A: edit section A')
    }

    Assert-Condition "After rebase onto main, the same branch passes" "SPEC-005 AC-03" {
        git -C (Join-Path $root 'b') pull -q --rebase origin main
        $r = Invoke-Check (Join-Path $root 'b')
        return ($r.Exit -eq 0) -and ($r.Out -match '0 stale')
    }
} finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }

# AC-02: different files on each side
$root = New-Scenario
try {
    Edit-Commit (Join-Path $root 'b') $spFile "SELECT 'B-v1';" "SELECT 'B-v2';" 'B: edit section B'
    Push-DeveloperA $root 'other.sql' 'SELECT 1;' 'SELECT 2;'
    Assert-Condition "Main changed a different .sql file: passes" "SPEC-005 AC-02" {
        $r = Invoke-Check (Join-Path $root 'b')
        return ($r.Exit -eq 0)
    }
} finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }

# AC-04: new file only, and no .sql change at all, while main changed demoSP
$root = New-Scenario
try {
    Push-DeveloperA $root $spFile "SELECT 'A-v1';" "SELECT 'A-v2';"
    Assert-Condition "Branch only adds a new .sql file or changes no .sql file: passes" "SPEC-005 AC-04" {
        Edit-Commit (Join-Path $root 'b') 'README.md' '' 'notes' 'B: docs only'
        $r1 = Invoke-Check (Join-Path $root 'b')
        Edit-Commit (Join-Path $root 'b') 'dbo.newSP.sql' '' 'SELECT 3;' 'B: new file'
        $r2 = Invoke-Check (Join-Path $root 'b')
        return ($r1.Exit -eq 0) -and ($r2.Exit -eq 0)
    }

    # AC-08: target branch that does not exist on origin
    Assert-Condition "Target branch cannot be fetched: E_GIT_FAILED" "SPEC-005 AC-08" {
        $r = Invoke-Check (Join-Path $root 'b') 'no-such-branch'
        return ($r.Exit -eq 1) -and ($r.Out -match 'E_GIT_FAILED')
    }
} finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }

# AC-05: not a merge request pipeline
Assert-Condition "No target branch: exits 0 with info message" "SPEC-005 AC-05" {
    $out = & $psCmd -NoProfile -Command "`$env:CI_MERGE_REQUEST_TARGET_BRANCH_NAME = `$null; & '$checkPath'" 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0) -and ($out -match 'Not a merge request pipeline')
}

# AC-06: CI job wiring
Assert-Condition ".gitlab-ci.yml runs check_concurrent_edits in validate for merge requests with full history" "SPEC-005 AC-06" {
    $job = [regex]::Match($ciContent, '(?ms)^check_concurrent_edits:.*?(?=^\S)').Value
    return ($job -match 'stage:\s*validate') -and ($job -match 'GIT_DEPTH:\s*"0"') -and
        ($job -match 'Scripts/Test-ConcurrentEdits\.ps1') -and ($job -match 'merge_request_event') -and ($job -notmatch 'CI_COMMIT_BRANCH')
}

# AC-07: serialized deploys
Assert-Condition "deploy_dev uses resource_group deploy-dev" "SPEC-005 AC-07" {
    $job = [regex]::Match($ciContent, '(?ms)^deploy_dev:.*?(?=^\S|\z)').Value
    return ($job -match 'resource_group:\s*deploy-dev')
}

Write-Host ""
Write-Host "-----------------------------------------"
Write-Host "Test Results: $passCount Passed, $failCount Failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -gt 0) { exit 1 }
exit 0
