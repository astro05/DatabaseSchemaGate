# SPEC-005 Changelog

| Date | Version | Type | Change | ACs | Ref |
|---|---|---|---|---|---|
| 2026-10-11 | 0.1.0 | created | Initial draft: block merge requests that edit a .sql file changed on the target branch after the branch point; serialize deploy_dev | AC-01..AC-08 | — |
| 2026-10-11 | 0.1.0 | verified | Implemented Scripts/Test-ConcurrentEdits.ps1, check_concurrent_edits CI job, deploy_dev resource_group, and verification suite | AC-01..AC-08 | Tests/ConcurrentEditTests.ps1 |
| 2026-10-17 | 0.1.1 | changed | Examples use the generic `SampleDb` database | — | — |
