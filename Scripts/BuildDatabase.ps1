<#
.SYNOPSIS
    Builds the SQL Database Projects or solution into DACPAC artifacts.
.DESCRIPTION
    Runs dotnet build on Databases.sln or specific database project and verifies output artifact existence.
.PARAMETER Configuration
    Build configuration: 'Debug' or 'Release'. Defaults to 'Release'.
.PARAMETER Database
    Database to build (a folder name under Databases/), or 'All' for Databases.sln. Defaults to 'All'.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [Parameter(Mandatory = $false)]
    [string]$Database = 'All'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'Common.ps1')
if ($Database -ne 'All') { $Database = Resolve-DatabaseName $Database }

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Building Database Projects ($Configuration)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Scope: $Database" -ForegroundColor Gray

$targetFile = if ($Database -eq 'All') {
    Join-Path $ProjectRoot 'Databases.sln'
} else {
    Join-Path $ProjectRoot "Databases/$Database/$Database.sqlproj"
}

if (-not (Test-Path $targetFile)) {
    Write-Error "Build target file not found at: $targetFile"
    exit 1
}

# Automatically normalize ALTER / CREATE OR ALTER to declarative CREATE PROCEDURE for DacFx compilation
$scanDir = Join-Path $ProjectRoot 'Databases'
$normalizedBackups = @{}
if (Test-Path $scanDir) {
    $spFiles = Get-ChildItem -Path $scanDir -Filter *.sql -Recurse -File
    foreach ($f in $spFiles) {
        $c = Get-Content -Path $f.FullName -Raw
        if ($c -match '(?i)\b(CREATE\s+OR\s+ALTER|ALTER)\s+PROCEDURE\b') {
            $normalizedBackups[$f.FullName] = $c
            $updated = $c -replace '(?i)\b(CREATE\s+OR\s+ALTER|ALTER)\s+PROCEDURE\b', 'CREATE PROCEDURE'
            Set-Content -Path $f.FullName -Value $updated -NoNewline
            Write-Host "Temporarily normalized stored procedure in: $($f.Name) to CREATE PROCEDURE for DacFx build." -ForegroundColor Gray
        }
    }
}

try {
    $buildArgs = @(
        'build',
        $targetFile,
        '-c', $Configuration,
        '-v', 'minimal'
    )

    Write-Host "Running: dotnet $($buildArgs -join ' ')" -ForegroundColor Gray
    & dotnet @buildArgs
    $buildExitCode = $LASTEXITCODE
}
finally {
    # Restore original files so developer working copy and git status are preserved
    foreach ($filePath in $normalizedBackups.Keys) {
        Set-Content -Path $filePath -Value $normalizedBackups[$filePath] -NoNewline
    }
}

if ($buildExitCode -ne 0) {
    Write-Error "Database project build failed with exit code $buildExitCode"
    exit $buildExitCode
}

# Verify output DACPAC artifacts
$databases = if ($Database -eq 'All') { Get-DatabaseNames } else { @($Database) }
$expectedDacpacs = $databases | ForEach-Object { Join-Path $ProjectRoot "bin/$Configuration/$_.dacpac" }

Write-Host ""
Write-Host "Build Successful!" -ForegroundColor Green
$missing = 0
foreach ($dacpac in $expectedDacpacs) {
    if (Test-Path $dacpac) {
        $fi = Get-Item $dacpac
        Write-Host "Artifact: $($fi.FullName) ($([math]::Round($fi.Length / 1KB, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Expected artifact not found at: $dacpac. Is the project in Databases.sln? (dotnet sln Databases.sln add --in-root Databases/<Name>/<Name>.sqlproj)" -ForegroundColor Red
        $missing++
    }
}
if ($missing -gt 0) { exit 1 }
