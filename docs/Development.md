# Development Guide

The daily routine for changing database objects. Set up your machine first with [Getting Started](Getting-Started.md).

## 1. The loop

```powershell
git switch -c feat/add-customer-email          # 1. branch (see Git-Workflow.md)
# 2. edit .sql files under Databases/<Database>/
.\Scripts\ValidateDatabase.ps1                 # 3. coding standards
.\Scripts\Test-SqlSafety.ps1                   # 4. destructive-statement scan
.\Scripts\BuildDatabase.ps1                    # 5. compile: catches syntax errors and broken references
.\Scripts\DeployDatabase.ps1 -Database Sales -GenerateScriptOnly   # 6. optional: see the SQL a deploy would run
git add -A; git commit -m "feat: add Customer.Email"; git push -u origin HEAD   # 7. open a merge request
```

The merge request pipeline repeats steps 3 to 5 and runs the test suites. The deploy happens after the merge to `main`.

## 2. Where things go

| You want to | Put it in | Notes |
|---|---|---|
| Add or change a table, view, function, procedure, index, schema, type, sequence or synonym | `Databases/<Database>/<Folder>/<schema>.<Name>.sql` | One object per file. Write the **desired end state** (`CREATE TABLE ...` with every column). SqlPackage works out the `ALTER`. |
| Add a column | Edit the table's `CREATE TABLE` file | Give a new `NOT NULL` column a `DEFAULT`. Without one, SqlPackage fills existing rows with a type default such as `0` or `''` (`GenerateSmartDefaults` is on). |
| Seed or fix data, backfill a column, drop an object | `ScriptRunner/<Database>/<sortable-name>.sql` | Runs once, audited. See [ScriptRunner](ScriptRunner.md). |
| Run something before or after every deploy | `Databases/<Database>/Deployment/PreDeployment.sql` / `PostDeployment.sql` | Runs on **every** deploy, so it must be idempotent (`IF NOT EXISTS ...`). |

Folder names matter: the validator applies procedure rules in `StoredProcedures/`, table rules in `Tables/`, view rules in `Views/` and function rules in `Functions/`.

### Writing a stored procedure

```sql
CREATE OR ALTER PROCEDURE [dbo].[usp_GetCustomer]   -- CREATE, ALTER or CREATE OR ALTER all work
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;                                  -- required

    SELECT [CustomerId], [Name], [Email]
    FROM [dbo].[Customer]                            -- schema-qualified
    WHERE [CustomerId] = @CustomerId;
END;
GO
```

The DACPAC compiler only accepts `CREATE`. `BuildDatabase.ps1` rewrites `ALTER` and `CREATE OR ALTER` to `CREATE` for the build and puts your files back afterwards. Write whichever form you like, and paste the file straight into SSMS when debugging.

The full standards are in [Database Rules](DatabaseRules.md).

## 3. Checks you can run

| Command | What it checks | Fails on |
|---|---|---|
| `.\Scripts\ValidateDatabase.ps1 [-Database <Name>]` | Coding standards in `Databases/` | `USE`, credentials, missing `SET NOCOUNT ON`, unqualified names, `UPDATE` without `WHERE` and without `-- @manual-approve: <reason>` |
| `.\Scripts\Test-SqlSafety.ps1 [-TargetPath <dir>] [-Environment <env>]` | Destructive statements, parsed with ScriptDom (rules SQL001 to SQL009) | Syntax errors, or rules whose action is `block`/`requireApproval` in that environment (default `Production`) |
| `.\Scripts\BuildDatabase.ps1 [-Database <Name>]` | Compiles each project into `bin/Release/<Name>.dacpac` | Syntax errors, unresolved references, a project missing from `Databases.sln` |
| `.\Tests\VerificationTests.ps1` and the other `Tests\*.ps1` | The repository's own behavior against its specs | Any failed `SPEC-ID AC-ID` |

In `Databases/` files, a risky statement that is intended can be approved in the code itself, on the line before it:

```sql
-- @manual-approve: reset all flags after the 2026 migration (ticket OPS-123)
UPDATE [dbo].[Customer] SET [IsFlagged] = 0;
```

`Test-SqlSafety.ps1` also accepts `-- @allow-rule: SQL001` for one rule. These comments do **not** approve [ScriptRunner](ScriptRunner.md) scripts in CI: those always need a person.

## 4. Changes that could lose data

Deploys run with `BlockOnPossibleDataLoss=true`. SqlPackage stops when a change would drop data: removing a column that has values, shrinking a type (`NVARCHAR(200)` → `NVARCHAR(50)`), changing a type, or rebuilding a table in a way that loses rows.

The pipeline then fails in `deploy_dev` and nothing changes. To make such a change on purpose:

1. Move or convert the data that must survive in `Deployment/PreDeployment.sql`, written so it can run again safely (`IF COL_LENGTH(...) IS NOT NULL ...`).
2. Merge it, then deploy that change by hand with the block off, after reviewing the preview:

   ```powershell
   .\Scripts\DeployDatabase.ps1 -Database Sales -GenerateScriptOnly    # read artifacts/Sales-Development-DeployScript.sql
   .\Scripts\DeployDatabase.ps1 -Database Sales -BlockOnPossibleDataLoss $false
   ```

   The merge's `deploy_dev` job fails until you have done this; retry it afterwards to run the rest of the deploy.
3. Repeat for each environment the change reaches.

A **whole object** is different: deleting its `.sql` file never drops it (`DropObjectsNotInSource=false`), so nothing is blocked. Drop the table, view or procedure with a [ScriptRunner](ScriptRunner.md) script in the same merge request; that script needs approval in CI.

## 5. Drift: when the database and Git disagree

Someone changed the database directly (a hotfix in SSMS, a tool, another team):

```powershell
.\Scripts\DetectDrift.ps1 -Database Sales                          # Development
.\Scripts\DetectDrift.ps1 -Database Sales -ConnectionString "..."  # any server
```

- Exit `0`: no drift.
- Exit `2`: drift. The differences are printed and saved to `artifacts/Sales-DriftReport.xml`. Either bring the change into Git through a merge request (if it should stay), or let the next deploy put Git's version back.
- Exit `1`: an error (connection, missing DACPAC: run `BuildDatabase.ps1` first).

Objects that exist only in the database (not in Git) are not reported, because deploys never drop them.

## 6. Extract a live database

```powershell
.\Scripts\ExtractDatabase.ps1 -Database Sales                # schema only -> artifacts/Sales.Extracted.dacpac
.\Scripts\ExtractDatabase.ps1 -Database Sales -IncludeData   # with table data
```

Useful as a backup before a risky change, or to compare in a schema-compare tool. To turn a live database into `.sql` files, see [Getting Started](Getting-Started.md#c-onboard-an-existing-live-database).

## 7. Editors

The `.sqlproj` files are SDK-style (`Microsoft.Build.Sql`), so `dotnet build` is the reference build.

- **VS Code** with *SQL Database Projects* (`ms-mssql.sql-database-projects-vscode`): build, publish, schema compare.
- **Visual Studio 2026** opens and builds `Databases.sln`. Run `dotnet restore Databases.sln` once after cloning: Visual Studio does not restore these projects, and the first build fails with `NETSDK1004` until you do. Each `.sqlproj` sets two properties that apply only inside Visual Studio (`TargetFrameworkMoniker`, `UseTaskHostFactory`) so its SQL Server Data Tools can load and build the SDK project. If a *"Target framework not installed"* dialog appears anyway, choose **Do not load this project**; *Update the target* writes a `TargetFrameworkVersion` that breaks `dotnet build`.
- Do not add `TargetFrameworkVersion`, `TargetFrameworkProfile` or an unconditional `TargetFramework` to a `.sqlproj`.

## 8. Script reference

| Script | Main parameters |
|---|---|
| `BuildDatabase.ps1` | `-Configuration Release\|Debug`, `-Database <Name>\|All` (default `All`) |
| `ValidateDatabase.ps1` | `-Database <Name>\|All`, `-TargetPath` (default `Databases`) |
| `Test-SqlSafety.ps1` | `-TargetPath` or `-TargetFiles`, `-Environment Development\|Test\|Staging\|Production`, `-ReportPath <json>` |
| `DeployDatabase.ps1` | `-Database <Name>\|All` (required), `-TargetEnvironment`, `-ConnectionString`, `-DacpacPath`, `-GenerateScriptOnly`, `-BlockOnPossibleDataLoss` |
| `Invoke-ScriptRunner.ps1` | `-Database <Name>\|All` (required), `-TargetEnvironment`, `-ConnectionString`, `-DryRun`, `-CheckOnly`, `-Force`, `-NoTransaction` |
| `DetectDrift.ps1` | `-Database <Name>` (required), `-ConnectionString`, `-DacpacPath`, `-ReportPath` |
| `ExtractDatabase.ps1` | `-Database <Name>` (required), `-ConnectionString`, `-TargetFile`, `-IncludeData` |
| `Test-ConcurrentEdits.ps1` | `-TargetBranch` (CI sets it in merge requests) |

`-TargetEnvironment` is `Development` (default), `Staging` or `Production`, and picks the `DEV_`/`STG_`/`PROD_` connection string. `-Database All` runs every managed database and fails if any of them failed. It takes no `-ConnectionString`, because each database needs its own.
