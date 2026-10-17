# ScriptRunner / SampleDb

One-off SQL scripts that run **once each**, in file-name order, against the **`SampleDb`** database only, after its DACPAC is deployed. Every database gets its own folder: `ScriptRunner/<Database>/`.

Use this folder for data work the DACPAC can't express: seeding or fixing rows, backfilling a new column, dropping an object you deleted from `Databases/`. Schema objects (tables, procedures, views, functions) belong in `Databases/SampleDb/`.

## Rules

1. **Name scripts so they sort in run order**, e.g. `20261017-0900_seed_status_codes.sql`. The file name is the script's identity: editing a script after it ran changes nothing, and renaming it makes it run again.
2. **Run once, log once.** Each script that runs or fails gets one row in `[dbo].[DeploymentLog]` (`ScriptName`, `Status` = `SUCCESS`/`FAILED`, commit and pipeline details). Scripts with a row are skipped next time. A failed script is rolled back and never retried: ship the fix as a new file.
3. **One transaction per script**, split into batches on lines containing only `GO`. Statements SQL Server refuses inside a transaction (`ALTER DATABASE`, `BACKUP`, `CREATE FULLTEXT INDEX` ...) fail; run those by hand with `-NoTransaction`.
4. **Isolation.** `USE SampleDb;` / `USE [SampleDb];` is allowed; `USE` of any other database, and connection credentials, fail validation.
5. **Approval in CI.** On `main`, scripts that have not run yet are checked first. A risky statement (`UPDATE`/`DELETE` without `WHERE`, `DROP TABLE`, `TRUNCATE` ...) waits until someone allowed to merge to `main` runs the manual `deploy_dev_approved` job, even with a `-- @manual-approve:` comment.

## Try it locally

```powershell
.\Scripts\Invoke-ScriptRunner.ps1 -Database SampleDb -DryRun      # list and validate, no database contact
.\Scripts\Invoke-ScriptRunner.ps1 -Database SampleDb -CheckOnly   # what CI would ask approval for
.\Scripts\Invoke-ScriptRunner.ps1 -Database SampleDb              # run new scripts against Development
```

See [docs/ScriptRunner.md](../../docs/ScriptRunner.md).
