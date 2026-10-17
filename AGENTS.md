# Antigravity Agent Instructions — Spec-Driven Development

This repository follows the **.ai Spec-Driven Development (SDD)** process.
Specifications in `specs/` are the single source of truth; code is an implementation of them.

## 0. Session Entrypoint & Reading Order
At the start of every session:
1. **Entrypoint:** Read `.ai/ai.md`.
2. **Safety Policy:** Obey `.ai/hooks/policy.md` (strictly non-negotiable).
3. **Core Invariants:** Obey `.ai/rules/00-spec-driven-rules.md` (strictly non-negotiable).
4. **Architectural & Quality Rules:** Obey `.ai/rules/01-architecture-rules.md`, `.ai/rules/02-code-quality.md`, `.ai/rules/03-git-workflow.md`.
5. **Spec Registry:** Consult `specs/SPEC-INDEX.md` to identify the owning spec before editing any code.
6. **Task Persona:** Adopt the persona in `.ai/agents/` matching your current task.

Before writing or editing code, confirm to the user in one line which spec and persona you are using.

## 1. Core Invariants
- **Spec precedes code:** No production code under `src/` may exist without an `Approved` spec.
- **Humans approve:** Agents only draft specs (`Status: Draft`). Never approve a spec yourself.
- **Traceability:** Every test in `tests/` must name the `SPEC-ID AC-ID` it verifies.
- **No git actions:** Agents never run `git commit`, `git push`, or branch commands (`git branch`, `git checkout -b`, `git switch -c`). Maintenance operations are strictly human-only.
- **Done definition:** Tests pass and `bash .ai/scripts/validate-specs.sh` exits 0.

## 2. Personas (.ai/agents/)
- **New feature / vague request / amend spec:** `.ai/agents/spec-architect.md`
- **Implement approved spec / refactor:** `.ai/agents/core-engineer.md`
- **Write / fix tests / reproduce bugs:** `.ai/agents/test-engineer.md`
- **Security review / auth / secrets / PII:** `.ai/agents/security-auditor.md`

## 3. Skills (.ai/skills/)
Registered via `.agents/skills.json`:
- `init-project`: Initialize `specs/` and draft SPEC-001 when `specs/SPEC-INDEX.md` is missing.
- `new-spec`: Scaffold a new spec folder and register in `specs/SPEC-INDEX.md`.
- `sync-spec`: Reconcile code and spec discrepancies.
- `verify-contract`: Verify implementation and test coverage against spec contracts.
