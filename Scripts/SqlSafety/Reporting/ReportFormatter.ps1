<#
.SYNOPSIS
    Report formatter for SQL Safety Validation.
    Formats terminal console output and the optional JSON report.
#>

function Format-SqlSafetyConsoleReport {
    param(
        [AllowEmptyCollection()]
        [array]$Violations = @(),
        [int]$ScannedFileCount = 0
    )

    Write-Host "Database Safety Validation" -ForegroundColor Cyan
    Write-Host "--------------------------------" -ForegroundColor Gray

    $blockedCount = 0
    $unapprovedCount = 0
    $allowedCount = 0

    foreach ($v in $Violations) {
        $isSafe = ($v.Action -eq "allow") -or $v.IsApproved

        if ($isSafe) {
            $allowedCount++
            Write-Host "[ALLOW] $($v.RuleId) $($v.RuleName)" -ForegroundColor Green
            if ($v.File) { Write-Host "  File: $($v.File)" -ForegroundColor Gray }
            if ($v.Line -gt 0) { Write-Host "  Line: $($v.Line)" -ForegroundColor Gray }
            Write-Host ""
            Write-Host "  $($v.StatementSnippet)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Reason: $($v.Reason)" -ForegroundColor Gray
            Write-Host "  Action: ALLOW (Approved: $($v.IsApproved))" -ForegroundColor Green
            Write-Host ""
        } else {
            if ($v.Action -eq "block") { $blockedCount++ }
            else { $unapprovedCount++ }

            $symbolColor = if ($v.Severity -eq "CRITICAL") { 'Red' } else { 'Yellow' }
            Write-Host "✗ $($v.RuleId) $($v.RuleName)" -ForegroundColor $symbolColor
            if ($v.File) { Write-Host "  File: $($v.File)" -ForegroundColor Gray }
            if ($v.Line -gt 0) { Write-Host "  Line: $($v.Line)" -ForegroundColor Gray }
            Write-Host ""
            Write-Host "  $($v.StatementSnippet)" -ForegroundColor White
            Write-Host ""
            Write-Host "  Severity: $($v.Severity)" -ForegroundColor $symbolColor
            Write-Host "  Action: $(if ($v.Action -eq 'requireApproval') { 'REQUIRE APPROVAL' } else { 'BLOCK' })" -ForegroundColor Red
            Write-Host "  Reason: $($v.Reason)" -ForegroundColor Gray
            Write-Host ""
        }
    }

    $failed = ($blockedCount -gt 0) -or ($unapprovedCount -gt 0)
    Write-Host "--------------------------------" -ForegroundColor Gray
    if ($failed) {
        Write-Host "Pipeline failed." -ForegroundColor Red
        Write-Host "Database deployment was not executed." -ForegroundColor Red
        Write-Host "Summary: Scanned $ScannedFileCount file(s), $blockedCount blocked, $unapprovedCount unapproved, $allowedCount allowed." -ForegroundColor Yellow
    } else {
        Write-Host "Pipeline validation passed." -ForegroundColor Green
        Write-Host "Summary: Scanned $ScannedFileCount file(s), 0 violations detected." -ForegroundColor Green
    }

    return (-not $failed)
}

function Export-SqlSafetyReportJson {
    param(
        [AllowEmptyCollection()]
        [array]$Violations = @(),
        [int]$ScannedFileCount = 0,
        [string]$OutputPath
    )

    $reportObj = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToUniversalTime().ToString('s')
        ScannedFiles     = $ScannedFileCount
        TotalViolations  = $Violations.Count
        BlockedCount     = ($Violations | Where-Object { $_.Action -eq 'block' -and -not $_.IsApproved }).Count
        UnapprovedCount  = ($Violations | Where-Object { $_.Action -eq 'requireApproval' -and -not $_.IsApproved }).Count
        AllowedCount     = ($Violations | Where-Object { $_.Action -eq 'allow' -or $_.IsApproved }).Count
        IsPassed         = (($Violations | Where-Object { -not $_.IsApproved -and ($_.Action -in @('block', 'requireApproval')) }).Count -eq 0)
        Violations       = $Violations
    }

    $json = $reportObj | ConvertTo-Json -Depth 5
    Set-Content -Path $OutputPath -Value $json -Encoding UTF8
}
