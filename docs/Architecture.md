# Architecture

## 1. Overview

A declarative **Database-as-Code** lifecycle for Microsoft SQL Server. Git holds the desired state of every database; tools compare that state with each live database and apply the difference.

```text
Git (Databases/<Name>/*.sql)          ScriptRunner/<Name>/*.sql
        │                                     │
  dotnet build (Microsoft.Build.Sql)          │
        │                                     │
  bin/Release/<Name>.dacpac                   │
        │                                     │
  SqlPackage publish ──► SQL Server ◄── Invoke-ScriptRunner (each new script once)
                             │
                     dbo.DeploymentLog (audit, one per database)
```

Two kinds of change, two mechanisms:

| | Declarative (`Databases/`) | Imperative (`ScriptRunner/`) |
|---|---|---|
| Describes | What objects look like | Something to do once |
| Applied by | SqlPackage, which computes the `ALTER`s | Runs the file as written |
| Runs | Every deploy (no-op when nothing changed) | Once per database, ever |
| Good for | Tables, views, procedures, functions, indexes | Seed and fix data, backfills, drops |

## 2. Managed databases

A managed database is a folder `Databases/<Name>/` holding `<Name>.sqlproj`, listed in `Databases.sln`. Nothing else names databases: `Get-DatabaseNames` in `Scripts/Common.ps1` lists the folders, every script accepts `-Database <Name>` (and the deploy scripts `-Database All`), and the pipeline deploys `All`.

Per database:

| Item | Location |
|---|---|
| Project (SQL Server 2022 by default, `SQL_Latin1_General_CP1_CI_AS`) | `Databases/<Name>/<Name>.sqlproj` |
| Objects, one per file | `Databases/<Name>/Tables/`, `StoredProcedures/`, `Views/`, `Functions/`, ... |
| Pre-/post-deployment scripts (run every deploy) | `Databases/<Name>/Deployment/` |
| Audit table definition | `Databases/<Name>/Tables/dbo.DeploymentLog.sql` |
| One-off scripts | `ScriptRunner/<Name>/` |
| Build output | `bin/<Configuration>/<Name>.dacpac` |
| Connection string | `DEV_/STG_/PROD_CONNECTION_STRING_<NAME>`, or `appsettings.local.json` |

## 3. Scripts

| Script | Role |
|---|---|
| `Common.ps1` | Shared helpers: database discovery, connection strings, DACPAC and SqlPackage lookup, SqlClient, Git/CI metadata, `dbo.DeploymentLog` writes |
| `BuildDatabase.ps1` | Builds projects into DACPACs; temporarily rewrites `ALTER`/`CREATE OR ALTER PROCEDURE` to `CREATE` for the compiler |
| `ValidateDatabase.ps1` | Regex-based coding standards for `Databases/` |
| `Test-SqlSafety.ps1` + `SqlSafety/` | ScriptDom-based destructive-statement rules SQL001 to SQL009, with per-environment actions (`Config/`), parser (`Parser/`), rules (`Rules/`) and reports (`Reporting/`) |
| `DeployDatabase.ps1` | SqlPackage publish (or script-only preview); logs changed files to `dbo.DeploymentLog` |
| `Invoke-ScriptRunner.ps1` | Runs new one-off scripts in transactions; `-CheckOnly` feeds the CI approval gate |
| `DetectDrift.ps1` | SqlPackage DeployReport: exit 2 when a live database differs from Git |
| `ExtractDatabase.ps1` | SqlPackage extract of a live database into a DACPAC |
| `Test-ConcurrentEdits.ps1` | Merge request check against stale edits of the same `.sql` file |

## 4. Safety layers

1. **Static checks** (`validate`): standards and destructive-statement scan of `Databases/`. Failures cannot be overridden.
2. **Compiler** (`build`): every reference must resolve.
3. **Deploy options**: `BlockOnPossibleDataLoss=true`, `DropObjectsNotInSource=false`: no silent data loss, no automatic drops.
4. **Human gate**: risky statements in new one-off scripts wait for the manual `deploy_dev_approved`.
5. **Isolation**: each database has its own connection string; one naming another catalog fails with `E_DATABASE_MISMATCH`. One-off scripts may only `USE` their own database.
6. **Serialization**: one deploy at a time (`resource_group`).
7. **Audit**: `dbo.DeploymentLog` in every database.

## 5. Specifications

Behavior is specified in `specs/` (index: `specs/SPEC-INDEX.md`) and verified by `Tests/`, where each test names the `SPEC-ID AC-ID` it checks:

| Spec | Covers |
|---|---|
| SPEC-001 core-system | Projects, build, deploy, drift, extraction, multi-database layout |
| SPEC-002 schema-checks | Static checks, audit logging, connection isolation, CI approval gate |
| SPEC-003 sql-safety-validator | The ScriptDom safety rules |
| SPEC-004 script-runner | One-off scripts |
| SPEC-005 concurrent-edit-guard | Stale-edit check and deploy serialization |
