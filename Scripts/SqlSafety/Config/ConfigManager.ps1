<#
.SYNOPSIS
    Safety policy for SQL Safety Validation: the action of each rule per environment, plus approval flags.
#>

# Rules whose action depends on the environment; the other rules use Get-DefaultSafetyConfig everywhere
$script:EnvironmentRuleActions = @{
    Development = @{ dropDatabase = 'requireApproval'; dropTable = 'requireApproval'; truncateTable = 'allow';           dropProcedure = 'allow';           dropView = 'allow' }
    Test        = @{ dropDatabase = 'requireApproval'; dropTable = 'requireApproval'; truncateTable = 'requireApproval'; dropProcedure = 'allow';           dropView = 'allow' }
    Staging     = @{ dropDatabase = 'block';           dropTable = 'block';           truncateTable = 'block';           dropProcedure = 'requireApproval'; dropView = 'requireApproval' }
    Production  = @{ dropDatabase = 'block';           dropTable = 'block';           truncateTable = 'block';           dropProcedure = 'requireApproval'; dropView = 'requireApproval' }
}

function Get-DefaultSafetyConfig {
    return @{
        databaseSafety = @{
            environment = "Production"
            rules = @{
                updateWithoutWhere = @{ action = "block" }
                deleteWithoutWhere = @{ action = "block" }
                dropDatabase       = @{ action = "block" }
                dropTable          = @{ action = "block" }
                dropTemporaryTable = @{ action = "allow" }
                truncateTable      = @{ action = "block" }
                dropColumn         = @{ action = "requireApproval" }
                dropProcedure      = @{ action = "requireApproval" }
                dropView           = @{ action = "requireApproval" }
            }
            approvals = @{
                allowUnconditionalUpdate = $false
                allowUnconditionalDelete = $false
                allowDropDatabase       = $false
                allowDropTable          = $false
                allowTruncateTable      = $false
                allowDropColumn         = $false
            }
        }
    }
}

function Load-SafetyConfig {
    param(
        [string]$Environment = "Production",
        [hashtable]$CliApprovals = @{}
    )

    $config = Get-DefaultSafetyConfig
    if ($Environment) {
        $config.databaseSafety.environment = $Environment
    }

    foreach ($k in $CliApprovals.Keys) {
        $config.databaseSafety.approvals[$k] = [bool]$CliApprovals[$k]
    }

    $envActions = $script:EnvironmentRuleActions[$config.databaseSafety.environment]
    if ($envActions) {
        foreach ($rule in $envActions.Keys) {
            $config.databaseSafety.rules[$rule] = @{ action = $envActions[$rule] }
        }
    }

    # INV-06: Production ALWAYS blocks DROP DATABASE, regardless of approval flags
    if ($config.databaseSafety.environment -eq 'Production') {
        $config.databaseSafety.approvals["allowDropDatabase"] = $false
    }

    return $config
}
