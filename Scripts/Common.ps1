<#
.SYNOPSIS
    Helpers shared by the database scripts: connection strings, DACPAC and SqlPackage lookup,
    SqlClient connections, Git/CI metadata, and dbo.DeploymentLog writes. Dot-source it.
#>

# A managed database is a folder Databases/<Name>/ holding <Name>.sqlproj
function Get-DatabaseNames {
    $root = Join-Path (Split-Path -Parent $PSScriptRoot) 'Databases'
    @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).sqlproj") } | ForEach-Object Name)
}

# The managed database's name as spelled on disk; throws E_DATABASE_NOT_FOUND for any other name
function Resolve-DatabaseName([string]$Database) {
    $name = Get-DatabaseNames | Where-Object { $_ -eq $Database } | Select-Object -First 1
    if (-not $name) { throw "E_DATABASE_NOT_FOUND: no Databases/$Database/$Database.sqlproj. Managed databases: $((Get-DatabaseNames) -join ', ')" }
    return $name
}

# -Database All: runs the script once per managed database with the same parameters and returns the
# names of the databases whose run failed. Every database runs, even after a failure.
function Invoke-ForEachDatabase([string]$ScriptPath, [System.Collections.IDictionary]$Parameters) {
    foreach ($db in Get-DatabaseNames) {
        $runParams = [hashtable]::new($Parameters, [StringComparer]::OrdinalIgnoreCase)
        $runParams.Database = $db
        $global:LASTEXITCODE = 0
        try { & $ScriptPath @runParams | Out-Host } catch { Write-Host "ERROR [$db]: $($_.Exception.Message)" -ForegroundColor Red; $global:LASTEXITCODE = 1 }
        if ($LASTEXITCODE -ne 0) { $db }
    }
}

function Get-GitOutput {
    try {
        $out = & git -C (Split-Path -Parent $PSScriptRoot) @args 2>$null
        if ($LASTEXITCODE -eq 0) { $out }
    } catch {}
}

# Explicit value, then the CI variable (DEV_/STG_/PROD_CONNECTION_STRING_<DATABASE>), then the
# git-ignored appsettings.local.json for local runs. Returns $null when nothing is configured.
# <DATABASE> is the name upper-cased with every character other than A-Z, 0-9 and _ replaced by _.
function Resolve-ConnectionString([string]$Database, [string]$TargetEnvironment = 'Development', [string]$ConnectionString) {
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        $prefix = @{ Development = 'DEV'; Staging = 'STG'; Production = 'PROD' }[$TargetEnvironment]
        $envVarName = "${prefix}_CONNECTION_STRING_$($Database.ToUpper() -replace '[^A-Z0-9_]', '_')"
        $ConnectionString = [Environment]::GetEnvironmentVariable($envVarName)
        if ($ConnectionString) { Write-Host "Loaded ConnectionString from environment variable ($envVarName)" -ForegroundColor Gray }
    }

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        $localSettings = Join-Path (Split-Path -Parent $PSScriptRoot) 'appsettings.local.json'
        if (Test-Path $localSettings) {
            $ConnectionString = (Get-Content $localSettings -Raw | ConvertFrom-Json).ConnectionStrings.$Database.$TargetEnvironment
            if ($ConnectionString) { Write-Host "Loaded ConnectionString from appsettings.local.json ($Database.$TargetEnvironment)" -ForegroundColor Gray }
        }
    }

    # GitLab can only mask values without ';' or spaces, so CI variables hold the connection string Base64-encoded
    if ($ConnectionString -and ($ConnectionString -notmatch '(;|Server=|Data Source=)')) {
        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConnectionString))
            if ($decoded -match '(Server=|Data Source=|Initial Catalog=|Database=)') {
                $ConnectionString = $decoded
                Write-Host "Decoded Base64 ConnectionString for $TargetEnvironment ($Database)" -ForegroundColor Gray
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) { return $null }

    # Each database needs its own connection string: never run against another catalog
    if ($ConnectionString -match '(?i)(?:Initial Catalog|Database)\s*=\s*([^;]+)') {
        $catalog = $matches[1].Trim().Trim('[]"')
        if ($catalog -and ($catalog -ne $Database)) {
            throw "E_DATABASE_MISMATCH: ConnectionString targets database '$catalog', but '$Database' requires its own dedicated connection string."
        }
    }
    return $ConnectionString
}

# -DacpacPath (relative to the repo root) if given, else bin/Release then bin/Debug
function Resolve-DacpacPath([string]$Database, [string]$DacpacPath) {
    $root = Split-Path -Parent $PSScriptRoot
    $candidates = if ($DacpacPath) { @(Join-Path $root $DacpacPath) } else { @('Release', 'Debug' | ForEach-Object { Join-Path $root "bin/$_/$Database.dacpac" }) }
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { throw "DACPAC for $Database not found at: $($candidates -join ', '). Run Scripts/BuildDatabase.ps1 first." }
    return [System.IO.Path]::GetFullPath($found)
}

function Get-SqlPackagePath {
    $command = Get-Command 'sqlpackage' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $toolsDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dotnet/tools'
    $tool = 'sqlpackage.exe', 'sqlpackage' | ForEach-Object { Join-Path $toolsDir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($tool) { return $tool }
    return 'sqlpackage'
}

# Opened SqlConnection from whichever SqlClient this PowerShell can load
function New-SqlConnection([string]$ConnectionString) {
    $connType = $null
    try {
        Add-Type -AssemblyName System.Data -ErrorAction SilentlyContinue
        $connType = [Type]::GetType("System.Data.SqlClient.SqlConnection, System.Data")
    } catch {}
    if (-not $connType) {
        try { $connType = [Type]::GetType("Microsoft.Data.SqlClient.SqlConnection, Microsoft.Data.SqlClient") } catch {}
    }
    if (-not $connType) {
        $searchPaths = @($env:HOME, $env:USERPROFILE, '/root/.dotnet/tools') | Where-Object { $_ -and (Test-Path $_) }
        $dll = Get-ChildItem -Path $searchPaths -Filter "Microsoft.Data.SqlClient.dll" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) {
            try {
                Add-Type -Path $dll.FullName -ErrorAction SilentlyContinue
                $connType = [Type]::GetType("Microsoft.Data.SqlClient.SqlConnection, Microsoft.Data.SqlClient")
            } catch {}
        }
    }

    $conn = if ($connType) { [Activator]::CreateInstance($connType, @($ConnectionString)) } else { New-Object System.Data.SqlClient.SqlConnection($ConnectionString) }
    $conn.Open()
    return $conn
}

# Commit and pipeline columns of dbo.DeploymentLog: GitLab CI variables first, local git otherwise
function Get-DeploymentMetadata {
    function FirstOf($ciValue, [string[]]$gitArgs, $default) {
        if ($ciValue) { return $ciValue }
        $out = Get-GitOutput @gitArgs | Select-Object -First 1
        if ($out) { return "$out".Trim() }
        return $default
    }

    return @{
        CommitSha      = FirstOf $env:CI_COMMIT_SHA       @('rev-parse', 'HEAD')                 'local'
        CommitShortSha = FirstOf $env:CI_COMMIT_SHORT_SHA @('rev-parse', '--short', 'HEAD')      'local'
        CommitBranch   = FirstOf $env:CI_COMMIT_REF_NAME  @('rev-parse', '--abbrev-ref', 'HEAD') 'local'
        CommitTitle    = FirstOf $env:CI_COMMIT_TITLE     @('log', '-1', '--pretty=%s')          $null
        CommitAuthor   = FirstOf $env:CI_COMMIT_AUTHOR    @('log', '-1', '--pretty=%an <%ae>')   $env:USERNAME
        PipelineId     = $env:CI_PIPELINE_ID
        PipelineUrl    = $env:CI_PIPELINE_URL
        JobId          = $env:CI_JOB_ID
        TriggeredBy    = if ($env:GITLAB_USER_NAME) { "$($env:GITLAB_USER_NAME) <$($env:GITLAB_USER_EMAIL)>" } elseif ($env:GITLAB_USER_LOGIN) { $env:GITLAB_USER_LOGIN } else { $env:USERNAME }
    }
}

# Creates dbo.DeploymentLog when the DACPAC has not been deployed yet (same columns as Databases/<Database>/Tables/dbo.DeploymentLog.sql)
function Initialize-DeploymentLog($Connection) {
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @"
IF OBJECT_ID(N'[dbo].[DeploymentLog]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[DeploymentLog]
    (
        [DeploymentId]        BIGINT IDENTITY(1, 1) NOT NULL,
        [DatabaseName]        VARCHAR(100)          NOT NULL,
        [TargetEnvironment]   VARCHAR(50)           NOT NULL,
        [Status]              VARCHAR(20)           NOT NULL,
        [DeployedAtUtc]       DATETIME2(7)          NOT NULL CONSTRAINT [DF_DeploymentLog_DeployedAtUtc] DEFAULT (SYSUTCDATETIME()),
        [CompletedAtUtc]      DATETIME2(7)          NULL,
        [DurationSeconds]     INT                   NULL,
        [ScriptName]          NVARCHAR(260)         NULL,
        [CommitSha]           VARCHAR(40)           NOT NULL,
        [CommitShortSha]      VARCHAR(10)           NOT NULL,
        [CommitBranch]        VARCHAR(100)          NOT NULL,
        [CommitTitle]         NVARCHAR(500)         NULL,
        [CommitAuthor]        NVARCHAR(150)         NULL,
        [PipelineId]          VARCHAR(50)           NULL,
        [PipelineUrl]         VARCHAR(500)          NULL,
        [JobId]               VARCHAR(50)           NULL,
        [TriggeredBy]         NVARCHAR(150)         NULL,
        [DacpacVersion]       VARCHAR(100)          NULL,
        [ErrorMessage]        NVARCHAR(MAX)         NULL,
        [DeployReportSummary] NVARCHAR(MAX)         NULL,
        CONSTRAINT [PK_DeploymentLog] PRIMARY KEY CLUSTERED ([DeploymentId] ASC)
    );
END
ELSE IF COL_LENGTH(N'[dbo].[DeploymentLog]', N'ScriptName') IS NULL
BEGIN
    ALTER TABLE [dbo].[DeploymentLog] ADD [ScriptName] NVARCHAR(260) NULL;
END
"@
    $cmd.ExecuteNonQuery() | Out-Null
}

# INSERT INTO [dbo].[DeploymentLog]: keys of $Row are column names (code-defined, never user input); empty values become NULL
function Add-DeploymentLogRow($Connection, [hashtable]$Row) {
    $columns = @($Row.Keys)
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "INSERT INTO [dbo].[DeploymentLog] ($(($columns | ForEach-Object { "[$_]" }) -join ', ')) VALUES ($(($columns | ForEach-Object { "@$_" }) -join ', '));"
    foreach ($column in $columns) {
        $value = $Row[$column]
        $cmd.Parameters.AddWithValue("@$column", $(if ($null -eq $value -or "$value" -eq '') { [DBNull]::Value } else { $value })) | Out-Null
    }
    $cmd.ExecuteNonQuery() | Out-Null
}
