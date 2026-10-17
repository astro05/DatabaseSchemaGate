# DatabaseSchemaGate

**Database-as-Code for Microsoft SQL Server.** Keep every table, view, function and stored procedure of one or more databases in Git, and let CI/CD check, build and deploy them. Risky changes wait for a person's approval, and every deployment is recorded in the database itself.

It works with any SQL Server database: put each database in `Databases/<Name>/` and the scripts and pipeline pick it up. No database names are hardcoded. The repository ships one example database, `SampleDb`, which you rename or replace.

---

## What you get

| Area | What it does |
|---|---|
| Schema as code | Each database is an SDK-style SQL project (`Microsoft.Build.Sql`) that .NET builds into a DACPAC. One `.sql` file per object. Procedures may be written as `CREATE`, `ALTER` or `CREATE OR ALTER`. |
| Coding standards | `ValidateDatabase.ps1` rejects `USE`, credentials, procedures without `SET NOCOUNT ON`, unqualified object names, and `UPDATE` without `WHERE` unless marked `-- @manual-approve: <reason>`. |
| SQL safety | `Test-SqlSafety.ps1` parses T-SQL with Microsoft's ScriptDom parser and flags rules SQL001 to SQL009 (`UPDATE`/`DELETE` without `WHERE`, `DROP DATABASE`/`TABLE`/`COLUMN`/`PROCEDURE`/`VIEW`, `TRUNCATE`) per environment. It fails closed on syntax errors. |
| Safe deployment | SqlPackage publishes each DACPAC. Changes that could lose data are blocked, deleted objects are never dropped automatically, and only one deploy runs at a time. |
| One-off scripts | `ScriptRunner/<Database>/` holds data scripts that each run **once**, in file-name order, in their own transaction. |
| Human approval | On `main`, a new one-off script with a risky statement stops the automatic deploy until someone allowed to merge runs the manual `deploy_dev_approved` job. |
| Audit log | `dbo.DeploymentLog` in each database gets one row per changed object file and per one-off script: status, timing, commit, author and pipeline. |
| Concurrent edits | A merge request fails (`E_STALE_BASE`) when a `.sql` file you changed was also changed on the target branch after you branched. |
| Connection safety | Each database has its own connection string, and one that names another database is rejected. CI reads them from masked, protected variables. |
| Drift detection | `DetectDrift.ps1` compares a live database with Git (exit code 2 on drift). `ExtractDatabase.ps1` extracts a live database. |

## How it works

```text
 Developer ──► branch ──► merge request ──► validate ─► build DACPACs ─► tests ──► merge to main
                                                                                       │
 main:  validate ─► build ─► tests + check new one-off scripts                         │
                                   │                                                   ▼
                     no risky statement ──► deploy_dev ──► Development SQL Server ◄────┘
                     risky statement ─────► approval_required ──► manual deploy_dev_approved
```

Deploy = publish every DACPAC, then run the new one-off scripts. Every step is a PowerShell script you can also run on your machine.

## Quick start

```powershell
git clone <this repository>; cd DatabaseSchemaGate
dotnet tool install -g microsoft.sqlpackage
.\Scripts\BuildDatabase.ps1            # builds bin/Release/SampleDb.dacpac
.\Scripts\ValidateDatabase.ps1         # coding standards
.\Tests\VerificationTests.ps1          # spec verification suite
```

Then follow **[Getting Started](docs/Getting-Started.md)** to point it at your own SQL Server database, and **[CI/CD](docs/CI-CD.md)** to run it in GitLab.

## Requirements

- [.NET SDK 10.0+](https://dotnet.microsoft.com/download) (pinned in `global.json`)
- PowerShell 7 (`pwsh`)
- [SqlPackage](https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download) 162.5.57+ (`dotnet tool install -g microsoft.sqlpackage`)
- SQL Server or Azure SQL. Projects target SQL Server 2022 (`<DSP>` `Sql160` in the `.sqlproj`); change `DSP` per project for another version (see [Getting Started](docs/Getting-Started.md#target-sql-server-version)).
- GitLab with a Docker runner for the included pipeline

## Repository layout

```text
Databases/
└── SampleDb/                 # one folder per database: <Name>/<Name>.sqlproj
    ├── Tables/               # one object per file, e.g. dbo.DeploymentLog.sql
    ├── StoredProcedures/     # SET NOCOUNT ON; schema-qualified names
    └── Deployment/           # PreDeployment.sql / PostDeployment.sql, bundled into the DACPAC
ScriptRunner/
└── SampleDb/                 # one-off data scripts, each run once against SampleDb
Scripts/                      # Build, Validate, Test-SqlSafety, Deploy, Invoke-ScriptRunner, DetectDrift, Extract
Tests/                        # verification suites; each test names the SPEC-ID AC-ID it checks
specs/                        # specifications (spec-driven development; see specs/SPEC-INDEX.md)
docs/                         # guides (below)
.ai/, .agents/, AGENTS.md     # instructions for AI coding agents
Databases.sln                 # every database project
.gitlab-ci.yml                # CI/CD pipeline
```

## Documentation

| Guide | Read it to |
|---|---|
| [Getting Started](docs/Getting-Started.md) | Install the tools, connect to SQL Server, add or onboard your database, deploy for the first time |
| [Development](docs/Development.md) | Change tables and procedures day to day, run checks, handle data-loss changes, detect drift |
| [Git Workflow](docs/Git-Workflow.md) | Branches, merge requests, protecting `main`, the concurrent-edit check |
| [CI/CD](docs/CI-CD.md) | Set up runners and connection-string variables, approve risky scripts, add more environments |
| [ScriptRunner](docs/ScriptRunner.md) | Write one-off data scripts that run once and are audited |
| [Database Rules](docs/DatabaseRules.md) | The standards every object must follow |
| [Architecture](docs/Architecture.md) | How the pieces fit together |
| [Troubleshooting](docs/Troubleshooting.md) | Error codes and fixes |

## License

[MIT](LICENSE)
