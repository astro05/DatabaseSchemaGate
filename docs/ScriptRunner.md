# ScriptRunner: One-Off Data Scripts

The DACPAC describes what the schema **is**. Some changes are **actions** instead: seed a lookup table, fix bad rows, backfill a new column, drop a table you removed from `Databases/`. Those go in `ScriptRunner/<Database>/`, and run **once** per database, audited, after that database's DACPAC deploy.

## 1. Write a script

```text
ScriptRunner/
└── Sales/
    ├── 20261017-0900_seed_order_status.sql
    └── 20261018-1400_backfill_customer_email.sql
```

```sql
-- 20261018-1400_backfill_customer_email.sql
UPDATE [dbo].[Customer]
SET [Email] = LOWER([LegacyEmail])
WHERE [Email] IS NULL AND [LegacyEmail] IS NOT NULL;
GO
```

Rules:

| Rule | Detail |
|---|---|
| Folder = database | Scripts in `ScriptRunner/Sales/` run only against `Sales`. `Sales` must be a managed database (`Databases/Sales/Sales.sqlproj`). |
| Name = order and identity | Scripts run in alphabetical file-name order, so start names with a timestamp. A script is identified by its **file name**: editing it after it ran changes nothing, renaming it makes it run again. |
| Runs once | A script with a `SUCCESS` or `FAILED` row in `dbo.DeploymentLog` is skipped and not logged again. |
| Never retried | A failed script was rolled back. Fix forward with a **new** file. |
| One transaction per script | The script is split into batches on lines that contain only `GO`, all inside one transaction. `ALTER DATABASE`, `BACKUP`, `CREATE FULLTEXT INDEX` and other statements SQL Server refuses inside a transaction fail; run those by hand with `-NoTransaction`. |
| Isolation | `USE Sales;` / `USE [Sales];` is allowed. `USE` of any other database, and credentials (`Password=`, `User ID=`), fail validation and are logged as `FAILED`. |
| Keep going | One failed script does not stop the others; the run exits 1 at the end. |
| Schema-qualify | Write `[dbo].[Customer]`, not `Customer`. |

## 2. Run it

```powershell
.\Scripts\Invoke-ScriptRunner.ps1 -Database Sales -DryRun       # list and validate; never connects
.\Scripts\Invoke-ScriptRunner.ps1 -Database Sales -CheckOnly    # what CI would ask approval for
.\Scripts\Invoke-ScriptRunner.ps1 -Database Sales               # run new scripts against Development
.\Scripts\Invoke-ScriptRunner.ps1 -Database All                 # every database (what CI does)
.\Scripts\Invoke-ScriptRunner.ps1 -Database Sales -TargetEnvironment Staging
```

| Switch | Effect |
|---|---|
| `-DryRun` | Validates and lists the scripts; never contacts the database |
| `-CheckOnly` | Reads the log, checks only scripts that have not run; risky statements go to `artifacts/approval-required-<Database>.txt`. Executes nothing. |
| `-Force` | Re-runs scripts that already ran. Use with care. |
| `-NoTransaction` | Runs batches without a transaction (for statements SQL Server refuses inside one) |
| `-ScriptsDirectory <dir>` | Reads scripts from another folder (single database only) |

## 3. In CI

On `main`, `check_scripts` runs `-CheckOnly` for every database before anything deploys. A new script with a risky statement (`UPDATE`/`DELETE` without `WHERE`, `DROP TABLE`, `TRUNCATE`, `DROP COLUMN`, `DROP PROCEDURE`/`VIEW`, `DROP DATABASE`) waits until someone allowed to merge to `main` runs the manual `deploy_dev_approved` job, even with a `-- @manual-approve:` comment. See [CI/CD](CI-CD.md#4-approving-risky-one-off-scripts).

The deploy then publishes every DACPAC first and runs the new scripts after, so a script can use columns the same merge added.

## 4. The audit log

Each executed or failed script adds one row to `[dbo].[DeploymentLog]` in its database:

```sql
SELECT [ScriptName], [Status], [DeployedAtUtc], [DurationSeconds], [CommitShortSha], [CommitAuthor], [PipelineUrl], [ErrorMessage]
FROM [dbo].[DeploymentLog]
WHERE [DeployReportSummary] = N'Executed via ScriptRunner for ' + DB_NAME()
ORDER BY [DeploymentId] DESC;
```

The runner creates the table if it is missing. Only rows written by the runner count when it decides what already ran; rows from DACPAC deploys of a file with the same name are ignored.

## 5. Recipes

**Seed a lookup table (safe to repeat):**

```sql
MERGE [dbo].[OrderStatus] AS t
USING (VALUES (1, N'New'), (2, N'Paid'), (3, N'Shipped')) AS s ([OrderStatusId], [Name])
   ON t.[OrderStatusId] = s.[OrderStatusId]
WHEN MATCHED AND t.[Name] <> s.[Name] THEN UPDATE SET [Name] = s.[Name]
WHEN NOT MATCHED THEN INSERT ([OrderStatusId], [Name]) VALUES (s.[OrderStatusId], s.[Name]);
```

**Drop an object you deleted from `Databases/`** (needs approval in CI):

```sql
DROP PROCEDURE IF EXISTS [dbo].[usp_OldReport];
DROP VIEW IF EXISTS [dbo].[vw_OldReport];
```

**Backfill in chunks** to keep the transaction log small on a big table: loop `UPDATE TOP (10000) ... WHERE <not yet done>` until `@@ROWCOUNT = 0`. The whole script is still one transaction; for very large tables run it by hand with `-NoTransaction`.
