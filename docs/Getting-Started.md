# Getting Started

This guide takes you from a fresh clone to your own database deployed from Git. It takes about 30 minutes.

1. [Install the tools](#1-install-the-tools)
2. [Build the sample](#2-build-the-sample)
3. [Put your database in the repository](#3-put-your-database-in-the-repository): new, additional, or existing
4. [Prepare SQL Server](#4-prepare-sql-server)
5. [Connect from your machine](#5-connect-from-your-machine)
6. [Deploy for the first time](#6-deploy-for-the-first-time)
7. [Next steps](#7-next-steps)

---

## 1. Install the tools

| Tool | Version | Install |
|---|---|---|
| .NET SDK | 10.0+ (pinned in `global.json`) | <https://dotnet.microsoft.com/download> |
| PowerShell | 7.x (`pwsh`) | <https://aka.ms/powershell> (Windows PowerShell 5.1 runs most scripts, CI uses 7.4) |
| SqlPackage | 162.5.57+ | `dotnet tool install -g microsoft.sqlpackage` |
| Git | any recent | <https://git-scm.com> |
| Editor (optional) | | VS Code with *SQL Database Projects* and *SQL Server (mssql)*: the repository recommends them. Visual Studio 2026 also opens `Databases.sln`. |

Check:

```powershell
dotnet --version; pwsh -v; sqlpackage /Version
```

## 2. Build the sample

```powershell
git clone <your repository URL>
cd DatabaseSchemaGate
dotnet restore Databases.sln          # once after cloning (Visual Studio does not restore these projects)
.\Scripts\BuildDatabase.ps1           # -> bin/Release/SampleDb.dacpac
.\Scripts\ValidateDatabase.ps1        # -> Scanned N SQL file(s): 0 error(s).
.\Tests\VerificationTests.ps1         # -> Test Results: 17 Passed, 0 Failed.
```

If these pass, your machine is ready.

## 3. Put your database in the repository

A **managed database** is a folder `Databases/<Name>/` holding `<Name>.sqlproj`, listed in `Databases.sln`. `<Name>` must be the database's real name on SQL Server: deployments go to the database of that name, and connection strings must name it. Every script and the pipeline discover managed databases from this layout, so you never edit a list.

The `.sqlproj` takes its name from its file name, so you can copy a project and rename the file without editing it.

Pick the case that fits.

### A. Start a new database: rename the sample

Replace `Sales` with your database name:

```powershell
dotnet sln Databases.sln remove Databases/SampleDb/SampleDb.sqlproj
Rename-Item Databases/SampleDb Sales
Rename-Item Databases/Sales/SampleDb.sqlproj Sales.sqlproj
Rename-Item ScriptRunner/SampleDb Sales
dotnet sln Databases.sln add --in-root Databases/Sales/Sales.sqlproj
.\Scripts\BuildDatabase.ps1           # -> bin/Release/Sales.dacpac
```

Keep `Tables/dbo.DeploymentLog.sql` (the audit table) and `Deployment/`. Delete or keep the example procedure `dbo.usp_GetDeploymentHistory`. Update the database name in `ScriptRunner/Sales/README.md`.

### B. Add another database

```powershell
New-Item -ItemType Directory Databases/HR/Tables, ScriptRunner/HR | Out-Null
Copy-Item Databases/SampleDb/SampleDb.sqlproj Databases/HR/HR.sqlproj
Copy-Item Databases/SampleDb/Deployment Databases/HR/Deployment -Recurse
Copy-Item Databases/SampleDb/Tables/dbo.DeploymentLog.sql Databases/HR/Tables/
dotnet sln Databases.sln add --in-root Databases/HR/HR.sqlproj
.\Scripts\BuildDatabase.ps1           # builds every database
```

Copy from whichever database you still have if `SampleDb` is gone. If you forget `dotnet sln add`, the build fails with *Is the project in Databases.sln?*.

### C. Onboard an existing live database

Extract the live schema into one `.sql` file per object, then wrap it in a project:

```powershell
# 1. Extract into a new folder. Users and permissions are left out on purpose.
sqlpackage /Action:Extract `
  /SourceConnectionString:"Server=myserver;Initial Catalog=Sales;Integrated Security=True;TrustServerCertificate=True;" `
  /TargetFile:"Databases/Sales" `
  /p:ExtractTarget=ObjectType /p:IgnorePermissions=true /p:IgnoreUserLoginMappings=true

# 2. Add the project file, deployment scripts and audit table
Copy-Item Databases/SampleDb/SampleDb.sqlproj Databases/Sales/Sales.sqlproj
Copy-Item Databases/SampleDb/Deployment Databases/Sales/Deployment -Recurse
New-Item -ItemType Directory -Force Databases/Sales/Tables, ScriptRunner/Sales | Out-Null
Copy-Item Databases/SampleDb/Tables/dbo.DeploymentLog.sql Databases/Sales/Tables/
dotnet sln Databases.sln add --in-root Databases/Sales/Sales.sqlproj

# 3. Build and check
.\Scripts\BuildDatabase.ps1 -Database Sales
.\Scripts\ValidateDatabase.ps1 -Database Sales
.\Scripts\Test-SqlSafety.ps1 -TargetPath Databases/Sales
```

Then clean up what the checks report:

- **Build errors** (`SQL71501` unresolved reference) usually mean references to another database or to `master`. Add a [database reference](https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/database-references), or remove the dead object.
- **Validation errors** list legacy code that breaks the [rules](DatabaseRules.md): add `SET NOCOUNT ON;`, schema-qualify names. The validator applies procedure, table, view and function rules by folder name, so the folders must be named `StoredProcedures`, `Tables`, `Views` and `Functions`. If SqlPackage wrote `Stored Procedures` (with a space), rename that folder.
- **Security objects** (users, roles, schemas owned by users) often differ per environment. Keep only those that are the same everywhere; manage the rest outside the project.
- **A large database** is easier to clean up in a few merge requests: commit the extract first, then fix one folder per merge request.

Before the first deploy, compare Git with the live database. The only difference should be the new `dbo.DeploymentLog` table:

```powershell
.\Scripts\DetectDrift.ps1 -Database Sales   # exit code 2 and a list of differences when they differ
```

### Target SQL Server version

Each `.sqlproj` sets the target platform in `<DSP>`. The default is SQL Server 2022:

| Target | `DSP` value |
|---|---|
| SQL Server 2025 | `Microsoft.Data.Tools.Schema.Sql.Sql170DatabaseSchemaProvider` |
| SQL Server 2022 (default) | `Microsoft.Data.Tools.Schema.Sql.Sql160DatabaseSchemaProvider` |
| SQL Server 2019 | `Microsoft.Data.Tools.Schema.Sql.Sql150DatabaseSchemaProvider` |
| SQL Server 2017 | `Microsoft.Data.Tools.Schema.Sql.Sql140DatabaseSchemaProvider` |
| Azure SQL Database | `Microsoft.Data.Tools.Schema.Sql.SqlAzureV12DatabaseSchemaProvider` |

SqlPackage refuses to deploy a DACPAC built for a newer platform than the target server. Set `DSP` to the oldest version you deploy to.

## 4. Prepare SQL Server

### A server to try it on

Any SQL Server you can reach works. For a throwaway local one, run SQL Server in Docker:

```bash
docker run -d --name sql -p 1433:1433 -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=<Strong!Passw0rd>" mcr.microsoft.com/mssql/server:2022-latest
```

Connection string: `Server=localhost,1433;Initial Catalog=SampleDb;User ID=sa;Password=<Strong!Passw0rd>;TrustServerCertificate=True;`

### A login for deployments

Use one dedicated login per environment, never a person's account. Create the database yourself, then let the login own its schema:

```sql
-- On the server
CREATE DATABASE [Sales];
CREATE LOGIN [deploy_sales] WITH PASSWORD = '<strong password>';
GO
-- In the database
USE [Sales];
CREATE USER [deploy_sales] FOR LOGIN [deploy_sales];
ALTER ROLE [db_owner] ADD MEMBER [deploy_sales];
```

- Deploying needs rights to create and alter any object, and to create and write `dbo.DeploymentLog`: `db_owner` of that database covers it.
- If the database does not exist, the first deploy creates it, which needs the server role `dbcreator`. Creating it yourself (above) avoids granting that.
- Drift detection and extraction only read the schema. `db_owner` works; a narrower read-only login may work too, see the [SqlPackage documentation](https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage).
- The CI runner must reach the server on its port (1433 by default) through any firewall.

## 5. Connect from your machine

Every script that talks to a database takes the **first** connection string it finds:

1. `-ConnectionString "<value>"` on the command line
2. The environment variable `DEV_CONNECTION_STRING_<DATABASE>`: `STG_` for `-TargetEnvironment Staging`, `PROD_` for `Production`. `<DATABASE>` is the name upper-cased, with characters other than `A-Z`, `0-9` and `_` replaced by `_` (database `Sales-EU` → `DEV_CONNECTION_STRING_SALES_EU`). The value may be Base64-encoded.
3. `appsettings.local.json` in the repository root

For daily work, create `appsettings.local.json`. It is git-ignored, so it never reaches the repository:

```json
{
  "ConnectionStrings": {
    "Sales": {
      "Development": "Server=localhost,1433;Initial Catalog=Sales;Integrated Security=True;TrustServerCertificate=True;",
      "Staging": "Server=stg-sql01;Initial Catalog=Sales;User ID=deploy_sales;Password=<password>;Encrypt=True;"
    },
    "HR": {
      "Development": "Server=localhost,1433;Initial Catalog=HR;Integrated Security=True;TrustServerCertificate=True;"
    }
  }
}
```

Common connection strings:

| Authentication | Connection string |
|---|---|
| Windows (integrated) | `Server=myserver;Initial Catalog=Sales;Integrated Security=True;TrustServerCertificate=True;` |
| SQL login | `Server=myserver;Initial Catalog=Sales;User ID=deploy_sales;Password=<password>;Encrypt=True;TrustServerCertificate=True;` |
| Named instance | `Server=myserver\SQLEXPRESS;Initial Catalog=Sales;...` |
| Azure SQL | `Server=tcp:myserver.database.windows.net,1433;Initial Catalog=Sales;User ID=<user>;Password=<password>;Encrypt=True;` |

`Initial Catalog` must be the database itself: a connection string naming another database is rejected with `E_DATABASE_MISMATCH`. Use `TrustServerCertificate=True` only for servers with self-signed certificates.

## 6. Deploy for the first time

```powershell
.\Scripts\BuildDatabase.ps1

# Preview: writes the SQL it would run, changes nothing
.\Scripts\DeployDatabase.ps1 -Database Sales -GenerateScriptOnly
#   -> artifacts/Sales-Development-DeployScript.sql and artifacts/Sales-Development-DeployReport.xml

# Deploy
.\Scripts\DeployDatabase.ps1 -Database Sales           # one database
.\Scripts\DeployDatabase.ps1 -Database All             # every database (what CI does)

# Run new one-off scripts from ScriptRunner/Sales (none yet)
.\Scripts\Invoke-ScriptRunner.ps1 -Database Sales
```

Then check the result in SQL Server:

```sql
SELECT TOP (20) * FROM [dbo].[DeploymentLog] ORDER BY [DeploymentId] DESC;
EXEC [dbo].[usp_GetDeploymentHistory];   -- if you kept the example procedure
```

`dbo.DeploymentLog` gets one row per `.sql` file under `Databases/<Database>/` that the **current commit** changed compared with its parent (for a merge commit: everything the merge brought in). A deploy of a commit that changed no such file deploys normally but writes no row.

What a deploy never does:

- It never **drops** an object whose file you deleted. Drop it with a [ScriptRunner](ScriptRunner.md) script.
- It never runs a change that **could lose data** (dropping a column that holds data, shrinking a type). See [Development](Development.md#4-changes-that-could-lose-data).

## 7. Next steps

1. Commit and push. See [Git Workflow](Git-Workflow.md).
2. Set up the pipeline and its connection-string variables. See [CI/CD](CI-CD.md).
3. Learn the daily routine. See [Development](Development.md).
