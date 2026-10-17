# 02 — Code Quality

## Typing
- Use the strictest type-checker settings the stack offers (e.g. TS `strict`, mypy/pyright `strict`). Fix type errors; never silence them.
- No `any` / untyped escape hatches unless a comment explains why. Never use one at a module boundary.
- Types for spec §3 contracts are normative: field names, optionality, and enums match the spec exactly.
- Model "might be absent" explicitly (`Option`, `T | null`). Never use sentinel values.

## Error contracts
- Every error that can cross a module boundary is a typed error with a stable `code` from spec §4.2.
- Never throw strings or generic errors across a boundary. Never swallow errors: handle them, wrap them with context, or propagate them.
- `interfaces/` maps internal errors to the external representation defined in spec §3. Stack traces and internal messages never reach callers.
- Expected failures (validation, not-found, conflict) are values or typed errors. They are not crashes.

## Testing
- **Naming:** each test's name includes `SPEC-NNN AC-NN`, so every test traces to the spec.
- **Structure:** Arrange / Act / Assert, one behavior per test.
- **Determinism:** no real network, wall clock, or randomness. Inject them through ports.
- **Pyramid:** unit tests for `domain/` and `core/`, integration tests for `data/` adapters against real or containerized dependencies, and E2E tests only for critical user flows listed in the spec.
- **Coverage target:** every AC, invariant, error code, and edge case in spec §4 and §5 is tested. Line coverage is a smell detector, not the goal.
- Fix flaky tests or delete them through the spec loop. Never retry them until they pass.

## Style
- The stack's formatter and linter are law. Run them before committing.
- Small functions, intention-revealing names, no dead code, no commented-out code.
- Comments explain *why*, never *what*.
- Only add a dependency when the spec's §2.4 records it.

## Definition of Done
- [ ] Failing test was written first and now passes
- [ ] Full suite, type-check, lint, and `.ai/scripts/validate-specs.sh` pass
- [ ] Spec Verification Matrix, changelog, and `SPEC-INDEX.md` are updated
- [ ] No new TODOs without a linked spec Open Question
