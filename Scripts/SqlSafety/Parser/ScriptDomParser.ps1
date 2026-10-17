<#
.SYNOPSIS
    T-SQL AST syntax parser utilizing Microsoft.SqlServer.TransactSql.ScriptDom.
#>

$script:ScriptDomLoaded = $false

function Import-ScriptDom {
    if ($script:ScriptDomLoaded) { return $true }

    if ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Microsoft.SqlServer.TransactSql.ScriptDom" }) {
        $script:ScriptDomLoaded = $true
        return $true
    }

    # NuGet cache, dotnet tools (microsoft.sqlpackage ships ScriptDom), then a local SQL Server install.
    # Within each folder, DLLs built for the running PowerShell's framework are tried first.
    $homeDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    $roots = @((Join-Path $homeDir ".nuget/packages"), (Join-Path $homeDir ".dotnet/tools"), "C:\Program Files\Microsoft SQL Server") | Where-Object { Test-Path $_ }
    $tfmPattern = if ($PSVersionTable.PSEdition -eq 'Core') { 'net(8|9|10)\.0' } else { 'net472' }

    $candidates = foreach ($root in $roots) {
        $dlls = @(Get-ChildItem -Path $root -Recurse -Force -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $dlls | Where-Object { $_ -match $tfmPattern }
        $dlls | Where-Object { $_ -notmatch $tfmPattern }
    }

    foreach ($path in $candidates) {
        try {
            [System.Reflection.Assembly]::LoadFrom($path) | Out-Null
            $script:ScriptDomLoaded = $true
            return $true
        } catch {
            # Try next
        }
    }

    return $false
}

function Get-AstStatementsRecursive {
    param($Node)
    $list = [System.Collections.ArrayList]::new()
    if ($null -eq $Node) { return $list }

    if ($Node -is [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlStatement]) {
        [void]$list.Add($Node)
    }

    if ($Node.Batches) {
        foreach ($b in $Node.Batches) {
            foreach ($item in @(Get-AstStatementsRecursive $b)) { [void]$list.Add($item) }
        }
    }
    if ($Node.Statements) {
        foreach ($s in $Node.Statements) {
            foreach ($item in @(Get-AstStatementsRecursive $s)) { [void]$list.Add($item) }
        }
    }
    if ($Node.StatementList) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.StatementList)) { [void]$list.Add($item) }
    }
    if ($Node.ThenStatement) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.ThenStatement)) { [void]$list.Add($item) }
    }
    if ($Node.ElseStatement) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.ElseStatement)) { [void]$list.Add($item) }
    }
    if ($Node.Statement) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.Statement)) { [void]$list.Add($item) }
    }
    if ($Node.TryStatements) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.TryStatements)) { [void]$list.Add($item) }
    }
    if ($Node.CatchStatements) {
        foreach ($item in @(Get-AstStatementsRecursive $Node.CatchStatements)) { [void]$list.Add($item) }
    }

    return $list
}

# Parses with ScriptDom (Test-SqlSafety.ps1 loads it first and fails closed without it).
# Parse errors, or the parser itself failing, return IsSuccess = $false so validation blocks.
function Invoke-SqlSafetyParse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlContent,
        [string]$FileName = ""
    )

    $parseErrors = @()
    $statements = @()
    try {
        $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser]::new($true)
        $errors = [System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]::new()
        $fragment = $parser.Parse([System.IO.StringReader]::new($SqlContent), [ref]$errors)
        $parseErrors = @($errors | ForEach-Object { [PSCustomObject]@{ Line = $_.Line; Column = $_.Column; Message = $_.Message } })
        if ($parseErrors.Count -eq 0) { $statements = Get-AstStatementsRecursive -Node $fragment }
    } catch {
        $parseErrors = @([PSCustomObject]@{ Line = 1; Column = 1; Message = "ScriptDom parser failed: $($_.Exception.Message)" })
    }

    return [PSCustomObject]@{
        IsSuccess     = ($parseErrors.Count -eq 0)
        Errors        = $parseErrors
        Statements    = $statements
        RawSqlContent = $SqlContent
        FileName      = $FileName
    }
}
