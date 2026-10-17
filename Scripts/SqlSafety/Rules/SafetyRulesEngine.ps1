<#
.SYNOPSIS
    Rule evaluation engine for SQL Safety Validator.
    Implements rules SQL001 through SQL009 on the ScriptDom AST.
#>

function New-RuleViolation {
    param(
        [string]$RuleId,
        [string]$RuleName,
        [string]$File,
        [int]$Line,
        [int]$Column,
        [string]$StatementSnippet,
        [string]$Severity,
        [string]$Action,
        [string]$Reason,
        [bool]$IsApproved = $false
    )

    return [PSCustomObject]@{
        RuleId           = $RuleId
        RuleName         = $RuleName
        File             = $File
        Line             = $Line
        Column           = $Column
        StatementSnippet = $StatementSnippet
        Severity         = $Severity
        Action           = $Action
        Reason           = $Reason
        IsApproved       = $IsApproved
    }
}

function Check-InlineApproval {
    param(
        [string]$SqlContent,
        [int]$StartOffset,
        [string]$RuleId
    )

    # Check up to 500 characters preceding the statement
    $lookbackStart = [Math]::Max(0, $StartOffset - 500)
    $length = $StartOffset - $lookbackStart
    if ($length -le 0) { return $false }

    $precedingText = $SqlContent.Substring($lookbackStart, $length)
    if ($precedingText -match '(?i)--\s*@manual-approve:') {
        return $true
    }
    if ($precedingText -match "(?i)--\s*@allow-rule:\s*$RuleId") {
        return $true
    }

    return $false
}

function Evaluate-SqlSafetyRules {
    param(
        [Parameter(Mandatory = $true)]
        $ParseResult,
        [Parameter(Mandatory = $true)]
        $Config
    )

    $violations = [System.Collections.Generic.List[PSCustomObject]]::new()
    $rawContent = $ParseResult.RawSqlContent
    $fileName = $ParseResult.FileName
    $approvals = $Config.databaseSafety.approvals
    $rulesConfig = $Config.databaseSafety.rules
    $env = $Config.databaseSafety.environment

    if (-not $ParseResult.IsSuccess) {
        # Syntax error -> fail closed
        foreach ($err in $ParseResult.Errors) {
            $violations.Add((New-RuleViolation `
                -RuleId "E_SYNTAX_PARSE_ERROR" `
                -RuleName "SQL Syntax Error" `
                -File $fileName `
                -Line $err.Line `
                -Column $err.Column `
                -StatementSnippet "Syntax error near line $($err.Line), column $($err.Column)" `
                -Severity "CRITICAL" `
                -Action "block" `
                -Reason "Syntax parse error encountered: $($err.Message). Pipeline fails safe by default." `
                -IsApproved $false))
        }
        return $violations
    }

    # Evaluate ScriptDom AST statements
    foreach ($stmt in $ParseResult.Statements) {
        $line = $stmt.StartLine
        $col = $stmt.StartColumn
        $snippet = ""
        if ($stmt.StartOffset -ge 0 -and $stmt.FragmentLength -gt 0 -and ($stmt.StartOffset + $stmt.FragmentLength -le $rawContent.Length)) {
            $snippet = $rawContent.Substring($stmt.StartOffset, $stmt.FragmentLength).Trim()
        } else {
            $snippet = $stmt.ToString()
        }

        # ----------------------------------------------------------------------
        # SQL001: UPDATE without WHERE
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.UpdateStatement]) {
            if ($null -eq $stmt.UpdateSpecification.WhereClause) {
                $ruleCfg = $rulesConfig["updateWithoutWhere"]
                $action = if ($ruleCfg) { $ruleCfg.action } else { "block" }
                $hasApproval = [bool]$approvals["allowUnconditionalUpdate"] -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL001")
                
                $violations.Add((New-RuleViolation `
                    -RuleId "SQL001" `
                    -RuleName "UPDATE without WHERE" `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "CRITICAL" `
                    -Action $action `
                    -Reason "SQL001: UPDATE statement without WHERE clause detected. Operation blocked to prevent unintended modification of all rows." `
                    -IsApproved $hasApproval))
            }
        }

        # ----------------------------------------------------------------------
        # SQL002: DELETE without WHERE or broad condition (WHERE 1=1)
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.DeleteStatement]) {
            $whereClause = $stmt.DeleteSpecification.WhereClause
            $isUnconditional = ($null -eq $whereClause)
            $isBroadCondition = $false

            if (-not $isUnconditional) {
                $whereSnippet = $snippet
                if ($whereSnippet -match '(?i)\bWHERE\s+1\s*=\s*1\b') {
                    $isBroadCondition = $true
                }
            }

            if ($isUnconditional -or $isBroadCondition) {
                $ruleCfg = $rulesConfig["deleteWithoutWhere"]
                $action = if ($ruleCfg) { $ruleCfg.action } else { "block" }
                $hasApproval = [bool]$approvals["allowUnconditionalDelete"] -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL002")
                $reason = if ($isBroadCondition) {
                    "SQL002: High-risk DELETE statement with broad condition (e.g. 1=1) detected."
                } else {
                    "SQL002: DELETE statement without WHERE clause detected. Operation blocked to prevent deletion of all rows."
                }

                $rName = if ($isBroadCondition) { "DELETE with Broad Condition (1=1)" } else { "DELETE without WHERE" }
                $violations.Add((New-RuleViolation `
                    -RuleId "SQL002" `
                    -RuleName $rName `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "CRITICAL" `
                    -Action $action `
                    -Reason $reason `
                    -IsApproved $hasApproval))
            }
        }

        # ----------------------------------------------------------------------
        # SQL003: DROP DATABASE
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.DropDatabaseStatement]) {
            $ruleCfg = $rulesConfig["dropDatabase"]
            $action = if ($ruleCfg) { $ruleCfg.action } else { "block" }
            
            # In Production/Staging: always block. In Dev/Test: allow only if allowDropDatabase = true
            $hasApproval = $false
            if ($env -in @("Development", "Test")) {
                $hasApproval = [bool]$approvals["allowDropDatabase"]
            }
            if ($hasApproval) {
                $action = "allow"
            }

            $violations.Add((New-RuleViolation `
                -RuleId "SQL003" `
                -RuleName "DROP DATABASE" `
                -File $fileName `
                -Line $line `
                -Column $col `
                -StatementSnippet $snippet `
                -Severity "CRITICAL" `
                -Action $action `
                -Reason "SQL003: DROP DATABASE operation detected. Database deletion is prohibited by the automated deployment pipeline." `
                -IsApproved $hasApproval))
        }

        # ----------------------------------------------------------------------
        # SQL004: DROP TABLE (Permanent vs Temporary)
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.DropTableStatement]) {
            foreach ($tblObj in $stmt.Objects) {
                $tblName = $tblObj.BaseIdentifier.Value
                if ($tblName.StartsWith("#")) {
                    # Temporary table exception
                    $ruleCfg = $rulesConfig["dropTemporaryTable"]
                    $action = if ($ruleCfg) { $ruleCfg.action } else { "allow" }
                    
                    $violations.Add((New-RuleViolation `
                        -RuleId "SQL004-T" `
                        -RuleName "DROP TABLE (Temporary)" `
                        -File $fileName `
                        -Line $line `
                        -Column $col `
                        -StatementSnippet $snippet `
                        -Severity "LOW" `
                        -Action $action `
                        -Reason "Temporary table detected ($tblName). Operation is allowed." `
                        -IsApproved $true))
                } else {
                    # Permanent table
                    $ruleCfg = $rulesConfig["dropTable"]
                    $action = if ($ruleCfg) { $ruleCfg.action } else { "block" }
                    $hasApproval = [bool]$approvals["allowDropTable"] -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL004")

                    $violations.Add((New-RuleViolation `
                        -RuleId "SQL004" `
                        -RuleName "DROP TABLE (Permanent)" `
                        -File $fileName `
                        -Line $line `
                        -Column $col `
                        -StatementSnippet $snippet `
                        -Severity "HIGH" `
                        -Action $action `
                        -Reason "SQL004: Permanent table DROP detected ($tblName). Operation blocked to prevent permanent data loss." `
                        -IsApproved $hasApproval))
                }
            }
        }

        # ----------------------------------------------------------------------
        # SQL005: TRUNCATE TABLE
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.TruncateTableStatement]) {
            $ruleCfg = $rulesConfig["truncateTable"]
            $action = if ($ruleCfg) { $ruleCfg.action } else { "block" }
            $hasApproval = [bool]$approvals["allowTruncateTable"] -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL005")

            $violations.Add((New-RuleViolation `
                -RuleId "SQL005" `
                -RuleName "TRUNCATE TABLE" `
                -File $fileName `
                -Line $line `
                -Column $col `
                -StatementSnippet $snippet `
                -Severity "HIGH" `
                -Action $action `
                -Reason "SQL005: TRUNCATE TABLE operation detected. Operation requires explicit approval before execution." `
                -IsApproved $hasApproval))
        }

        # ----------------------------------------------------------------------
        # SQL006 & SQL007: ALTER TABLE DROP COLUMN / CONSTRAINT (ADD is additive: no violation)
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.AlterTableDropTableElementStatement]) {
            $hasDropColumn = $false
            $hasDropConstraint = $false

            foreach ($el in $stmt.AlterTableDropTableElements) {
                $typeStr = $el.TableElementType.ToString()
                if ($typeStr -eq "Column") {
                    $hasDropColumn = $true
                } else {
                    $hasDropConstraint = $true
                }
            }

            if ($hasDropColumn) {
                $ruleCfg = $rulesConfig["dropColumn"]
                $action = if ($ruleCfg) { $ruleCfg.action } else { "requireApproval" }
                $hasApproval = [bool]$approvals["allowDropColumn"] -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL007")

                $violations.Add((New-RuleViolation `
                    -RuleId "SQL007" `
                    -RuleName "DROP COLUMN" `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "HIGH" `
                    -Action $action `
                    -Reason "SQL007: ALTER TABLE DROP COLUMN operation detected. Destructive schema change requires explicit approval." `
                    -IsApproved $hasApproval))
            } elseif ($hasDropConstraint) {
                $ruleCfg = $rulesConfig["dropColumn"]
                $action = if ($ruleCfg) { $ruleCfg.action } else { "requireApproval" }
                $hasApproval = (Check-InlineApproval $rawContent $stmt.StartOffset "SQL006")

                $violations.Add((New-RuleViolation `
                    -RuleId "SQL006" `
                    -RuleName "DROP CONSTRAINT" `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "HIGH" `
                    -Action $action `
                    -Reason "SQL006: ALTER TABLE DROP CONSTRAINT operation detected. Destructive schema change requires explicit approval." `
                    -IsApproved $hasApproval))
            }
        }

        # ----------------------------------------------------------------------
        # SQL008: DROP PROCEDURE
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.DropProcedureStatement]) {
            $ruleCfg = $rulesConfig["dropProcedure"]
            $action = if ($ruleCfg) { $ruleCfg.action } else { "requireApproval" }
            if ($env -in @("Development", "Test")) { $action = "allow" }
            $hasApproval = ($action -eq "allow") -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL008")

            if ($action -ne "allow") {
                $violations.Add((New-RuleViolation `
                    -RuleId "SQL008" `
                    -RuleName "DROP PROCEDURE" `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "MEDIUM" `
                    -Action $action `
                    -Reason "SQL008: DROP PROCEDURE operation detected. Requires explicit validation and approval in this environment." `
                    -IsApproved $hasApproval))
            }
        }

        # ----------------------------------------------------------------------
        # SQL009: DROP VIEW
        # ----------------------------------------------------------------------
        if ($stmt -is [Microsoft.SqlServer.TransactSql.ScriptDom.DropViewStatement]) {
            $ruleCfg = $rulesConfig["dropView"]
            $action = if ($ruleCfg) { $ruleCfg.action } else { "requireApproval" }
            if ($env -in @("Development", "Test")) { $action = "allow" }
            $hasApproval = ($action -eq "allow") -or (Check-InlineApproval $rawContent $stmt.StartOffset "SQL009")

            if ($action -ne "allow") {
                $violations.Add((New-RuleViolation `
                    -RuleId "SQL009" `
                    -RuleName "DROP VIEW" `
                    -File $fileName `
                    -Line $line `
                    -Column $col `
                    -StatementSnippet $snippet `
                    -Severity "MEDIUM" `
                    -Action $action `
                    -Reason "SQL009: DROP VIEW operation detected. Requires explicit validation and approval in this environment." `
                    -IsApproved $hasApproval))
            }
        }
    }

    return $violations
}
