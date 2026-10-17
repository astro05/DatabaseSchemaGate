# SPEC-001 Changelog

| Date | Version | Type | Change | ACs | Ref |
|---|---|---|---|---|---|
| 2026-10-07 | 0.1.0 | created | Initial baseline specification drafted from SRS | AC-01..AC-11 | srs.md |
| 2026-10-07 | 0.1.0 | verified | Implemented foundation and verified all acceptance criteria | AC-01..AC-11 | Tests/VerificationTests.ps1 |
| 2026-10-07 | 0.2.0 | changed | Restrict GitLab CI deployment to DEV environment only (remove deploy_test and deploy_prod) | AC-07 | .gitlab-ci.yml |
| 2026-10-07 | 0.3.0 | changed | Update schema definitions and verification criteria to reflect current schema objects | AC-01..AC-04 | Tests/VerificationTests.ps1 |
| 2026-10-08 | 1.0.0 | BREAKING | Multi-database architecture (two databases under Databases/), .NET Framework 4.8.1 upgrade, and manual approval gate for unconditional UPDATE queries | AC-01..AC-15 | spec/001-core-system |
| 2026-10-08 | 1.0.1 | changed | Target .NET Framework 4.8 (v4.8) for out-of-the-box Visual Studio 2022 developer pack compatibility | AC-15 | Tests/VerificationTests.ps1 |
| 2026-10-08 | 1.0.2 | changed | Support ALTER and CREATE OR ALTER syntax in stored procedures with pre-build normalization and dynamic deployment resolution | AC-01..AC-03 | Scripts/BuildDatabase.ps1 |
| 2026-10-08 | 1.0.3 | changed | Implement automated deployment logging to dbo.DeploymentLog table on SUCCESS and FAILED outcomes | AC-06, AC-07 | Scripts/DeployDatabase.ps1 |
| 2026-10-11 | 1.0.4 | changed | Update .NET SDK version target to .NET 10 (global.json, CI image mcr.microsoft.com/dotnet/sdk:10.0, ScriptDom parser) | AC-01, AC-15 | .gitlab-ci.yml, global.json |
| 2026-10-11 | 2.0.0 | BREAKING | Remove .NET Framework v4.8 TargetFrameworkVersion requirement (G9, D6, INV-08, AC-15 and targetFramework contract field): obsolete legacy SSDT property in SDK-style Microsoft.Build.Sql projects; re-adding it reintroduces legacy properties (see docs/Development.md) | AC-15 | Tests/VerificationTests.ps1 |
| 2026-10-11 | 2.1.0 | changed | An unconditional UPDATE that fails validation can still be deployed when a person runs the manual CI override for failed validation (G7, INV-06) | — | Tests/VerificationTests.ps1 |
| 2026-10-11 | 2.2.0 | changed | UPDATE without WHERE: a `-- @manual-approve:` comment approves it in `Databases/`; in a `ScriptRunner/` script a person approves it in CI before it runs, comment or not (G7, A4, D4, INV-06) | — | Tests/VerificationTests.ps1 |
| 2026-10-17 | 3.0.0 | BREAKING | Generalized for any SQL Server database: databases are discovered from `Databases/<Name>/<Name>.sqlproj` instead of a fixed list, scripts accept `-Database All`, `-Database` is required by DeployDatabase/DetectDrift/ExtractDatabase, CI variables are `DEV_CONNECTION_STRING_<DATABASE>`, and `SampleDb` is the shipped example (G8, INV-07, §3.4) | AC-02, AC-03, AC-11, AC-14 | Tests/VerificationTests.ps1 |
| 2026-10-17 | 3.0.1 | fixed | `ValidateDatabase.ps1` no longer reads the word `use` in a comment as a `USE <db>` statement, which failed objects extracted from existing databases | AC-04 | Tests/VerificationTests.ps1 |
