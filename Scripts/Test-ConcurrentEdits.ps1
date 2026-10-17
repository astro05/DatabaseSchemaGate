<#
.SYNOPSIS
    Blocks merge requests that edit a .sql file someone else changed after the branch was created (SPEC-005).
.DESCRIPTION
    The merge base is the developer's working version of each file. If any commit on the target branch
    after the merge base touched a .sql file the branch also modified, the combined object has never been
    reviewed as a whole: fail with E_STALE_BASE until the branch is rebased onto the target.
.PARAMETER TargetBranch
    Branch the merge request targets. Defaults to CI_MERGE_REQUEST_TARGET_BRANCH_NAME; empty = not a merge request, skip.
.PARAMETER RepoPath
    Git repository to check. Defaults to the project root.
#>
[CmdletBinding()]
param (
    [string]$TargetBranch = $env:CI_MERGE_REQUEST_TARGET_BRANCH_NAME,
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
    Write-Host "INFO: Not a merge request pipeline (no target branch); concurrent edit check skipped." -ForegroundColor Gray
    exit 0
}

function Invoke-Git { & git -C $RepoPath -c core.quotepath=off @args 2>$null }

Invoke-Git fetch -q origin "+refs/heads/${TargetBranch}:refs/remotes/origin/${TargetBranch}"
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: E_GIT_FAILED: cannot fetch origin/$TargetBranch." -ForegroundColor Red; exit 1 }

$base = Invoke-Git merge-base HEAD "origin/$TargetBranch"
if ($LASTEXITCODE -ne 0 -or -not $base) { Write-Host "ERROR: E_GIT_FAILED: no merge base with origin/$TargetBranch (shallow clone? set GIT_DEPTH: 0)." -ForegroundColor Red; exit 1 }

# Only modified files can be stale; a new file has no earlier version.
# ponytail: renames are not followed (git log --follow takes one path); add when renamed objects matter.
$modified = @(Invoke-Git diff --name-only --diff-filter=M $base HEAD -- '*.sql')

$staleCount = 0
foreach ($file in $modified) {
    $commits = @(Invoke-Git log --format='%h %an: %s' "$base..origin/$TargetBranch" -- $file)
    if ($commits.Count -gt 0) {
        $staleCount++
        Write-Host "ERROR  [$file]: E_STALE_BASE: changed on $TargetBranch after you branched:" -ForegroundColor Red
        $commits | ForEach-Object { Write-Host "         $_" -ForegroundColor Red }
    }
}

Write-Host "Checked $($modified.Count) modified SQL file(s) against origin/${TargetBranch}: $staleCount stale."
if ($staleCount -gt 0) {
    Write-Host "Rebase onto $TargetBranch (git pull --rebase origin $TargetBranch), review the combined object(s), then push again." -ForegroundColor Yellow
    exit 1
}
exit 0
