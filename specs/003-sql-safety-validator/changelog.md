# SPEC-003 Changelog

| Date | Version | Type | Change | ACs | Ref |
|---|---|---|---|---|---|
| 2026-10-08 | 0.1.0 | created | Initial draft of SQL Safety Validator specification based on pipeline safety requirements | — | — |
| 2026-10-08 | 0.1.0 | implemented | Implement SQL safety rules SQL001-SQL009, ScriptDom AST parser, and YAML approvals | AC-01 to AC-16 | Tests/SqlSafetyValidatorTests.ps1 |
| 2026-10-11 | 1.0.0 | BREAKING | Remove YAML config file and `-ConfigFile` (policy is code; `enabled` flags were never read) and the regex fallback (fail closed with `E_PARSER_UNAVAILABLE`); make the Development column of §3.3 take effect; sync §2.1/§3.2 with the code | AC-13, AC-17, AC-18 | Tests/SqlSafetyValidatorTests.ps1 |
| 2026-10-11 | 1.1.0 | changed | In CI, a failed validation is deployed past only through the manual override of SPEC-002 CHK-14 (INV-01, INV-03, `E_VALIDATION_BLOCKED`) | — | SPEC-002 AC-18 |
| 2026-10-11 | 1.2.0 | changed | `-ApprovalListPath` lists every `block`/`requireApproval` statement for a person's approval in CI, ignoring comments and `-Approvals`; syntax errors get no list (INV-01, INV-03, §3.2, §3.4, `E_VALIDATION_BLOCKED`) | AC-19 | Tests/SqlSafetyValidatorTests.ps1 |
