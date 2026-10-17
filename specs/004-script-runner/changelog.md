# SPEC-004 Changelog

All changes to `SPEC-004` (Dedicated Database Script Runner & Deployment Audit Logger) are recorded here.

| Date | Version | Type | Change | ACs | Ref |
|---|---|---|---|---|---|
| 2026-10-10 | 0.1.0 | created | Initial draft for the single-database ScriptRunner execution engine and dbo.DeploymentLog audit logger | AC-01–AC-10 | — |
| 2026-10-10 | 0.1.0 | added | Implement Invoke-ScriptRunner.ps1, CI/CD integration, and verification suite | AC-01–AC-10 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-10 | 0.2.0 | changed | Log SKIPPED status into dbo.DeploymentLog when a script is skipped | AC-11 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-11 | 0.3.0 | changed | Isolate script failures per file, log all validation and runtime errors to dbo.DeploymentLog, and continue executing remaining scripts in batch | AC-06, AC-07, AC-12 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-11 | 1.0.0 | BREAKING | Allow `USE` of the target database in scripts (other databases still rejected); stop writing SKIPPED rows to dbo.DeploymentLog so only executed/failed scripts are logged | AC-07, AC-11, AC-13 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-11 | 1.1.0 | changed | Do not retry scripts that previously FAILED (fix forward with a new script file); only count DeploymentLog rows written by the runner when deciding what to skip | AC-14 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-11 | 1.2.0 | changed | CI scans `ScriptRunner/` with the SQL Safety Validator before deploy; `-DryRun` never connects to the database (previously it could write FAILED rows that then blocked the script for good); credentials come from CI variables or the git-ignored `appsettings.local.json` | AC-15, AC-16 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-11 | 1.3.0 | changed | A ScriptRunner script that fails SQL safety validation runs only if someone runs the manual override of SPEC-002 CHK-14 (G9, INV-07) | — | SPEC-002 AC-18 |
| 2026-10-11 | 1.4.0 | changed | `-CheckOnly` checks only the scripts that have not run, so a script that already ran never asks for approval again; CI runs it in `check_scripts` on `main` instead of scanning `ScriptRunner/` in `validate_sql` (G9, INV-07, INV-09) | AC-15, AC-17 | Tests/ScriptRunnerTests.ps1 |
| 2026-10-17 | 2.0.0 | BREAKING | Generalized for any database: `-Database` (required) names any managed database or `All`, scripts live in `ScriptRunner/<Database>`, an unmanaged name fails with `E_DATABASE_NOT_FOUND`; `-CheckOnly` writes `artifacts/approval-required-<Database>.txt` and `-Database All -CheckOnly` removes every list when a database failed without one (G1, G2, G10, INV-09, INV-10) | AC-01, AC-02, AC-07, AC-13, AC-18 | Tests/ScriptRunnerTests.ps1 |
