# .ai/ai.md — AI Agent Instructions

**If you were told to "work with the .ai folder", start here.**
This file is the single entrypoint for any AI tool working on this repository. It applies the same way whichever tool you are.
`.ai/` is a portable kit: it gets copied into a project's root as is. All paths are relative to that project root.

This project practices **Spec-Driven Development (SDD)**: specifications in `specs/` are the source of truth; code is an implementation of them.

**Paths:** wherever `.ai/` files say `src/` or `tests/`, read the project's source and test roots as recorded in `specs/SPEC-INDEX.md` → *Project paths*.

---

## 0. Setup checks (every session, before anything else)

1. **Policy:** read `.ai/hooks/policy.md`. If your tool's settings don't reflect it yet (first session, or the policy changed), follow its *Applying this policy* section.
2. **Project init:** if `specs/SPEC-INDEX.md` does not exist, run `.ai/skills/init-project/SKILL.md`, report to the human, and stop. Do nothing else until the human responds.

---

## 1. Reading order (every session)

1. `.ai/ai.md` — this file.
2. `.ai/hooks/policy.md` — what you may never do (git push, destructive DB commands, secrets, …). **Non-negotiable.**
3. `.ai/rules/00-spec-driven-rules.md` — invariants and the developer loop. **Non-negotiable.**
4. `.ai/rules/01-architecture-rules.md` → `02-code-quality.md` → `03-git-workflow.md`.
5. `specs/SPEC-INDEX.md` — find which spec owns the area you are about to touch.
6. The owning `specs/NNN-*/spec.md` **and** every spec listed in its `Dependencies`.
7. The persona in `.ai/agents/` that matches your task (§3).

Do not write or edit any file before completing steps 1–6.
Before starting work, confirm to the human in one line which spec and persona you are using.

---

## 2. Core contract

The full rules are in `.ai/rules/00-spec-driven-rules.md`. In short:
- Check `specs/SPEC-INDEX.md` first.
- Never change behavior without updating the owning `spec.md`.
- Implement only `Approved` specs. Never approve a spec yourself.
- If something is ambiguous, stop and ask.
- Done means the tests pass and `.ai/scripts/validate-specs.sh` exits 0.

---

## 3. Task → persona, rules, skill

| Task | Persona (`.ai/agents/`) | Rules (`.ai/rules/`) | Skill (`.ai/skills/`) |
|---|---|---|---|
| First use in a project (`specs/` missing) | `spec-architect.md` | 00, 01 | `init-project` |
| New feature / vague request | `spec-architect.md` | 00, 01 | `new-spec` |
| Amend an existing spec | `spec-architect.md` | 00, 01, 03 | — |
| Implement an `Approved` spec | `core-engineer.md` | 00, 01, 02, 03 | `verify-contract` |
| Write / fix tests | `test-engineer.md` | 00, 02 | — |
| Bug fix | `test-engineer.md` (reproduce) → `core-engineer.md` (fix) | 00, 01, 02, 03 | `sync-spec` if the bug reveals a spec gap |
| Refactor (no behavior change) | `core-engineer.md` | 01, 02, 03 | `verify-contract` |
| Review a change before merge | `security-auditor.md` | 01, 02 | `sync-spec`, `verify-contract` |
| Auth, secrets, PII, input parsing | `security-auditor.md` | 01, 02 | `verify-contract` |
| Code and spec disagree | `spec-architect.md` | 00 | `sync-spec` |

To run a skill, read `.ai/skills/<name>/SKILL.md` and follow its steps in order.

---

## 4. Repository map

| Path | Purpose |
|---|---|
| `.ai/ai.md` | This file: the entrypoint. |
| `.ai/TOOLS.md` | For humans: how to point any AI tool at this folder. |
| `.ai/rules/` | Binding rules. Lower number = higher precedence. |
| `.ai/agents/` | Personas: role, inputs, allowed actions, handoff. |
| `.ai/skills/` | Step-by-step recipes (`SKILL.md` per folder). |
| `.ai/scripts/validate-specs.sh` | Spec linter. Must pass before every commit. |
| `.ai/hooks/policy.md` | What agents may never do. Humans edit it; agents obey it and implement it in their tool's settings. If your tool blocks an action, never try to work around it. |
| `specs/SPEC-INDEX.md` | Per-project: Project paths plus the registry of every spec (status, coverage, owner). Created by `init-project`. |
| `.ai/templates/` | `spec-template.md`: the only valid starting point for a new spec. `spec-index-template.md`: used by `init-project`. |
| `specs/NNN-slug/` | One spec (`spec.md`) + its change ledger (`changelog.md`). |
| `src/` | Production code (source root per *Project paths*). In new projects it is layered `domain/`, `core/`, `data/`, `interfaces/` (rule 01). |
| `tests/` | Spec verification tests (tests root per *Project paths*). Each test names the `SPEC-ID AC-ID` it verifies. |

---

## 5. Commands

```bash
bash .ai/scripts/validate-specs.sh    # lint all specs (exit 1 on error)
```

Test, lint, and type-check commands for this project are listed in `specs/SPEC-INDEX.md` → *Project paths*.

---

## 6. Precedence

`.ai/hooks/policy.md` (a human changes the file, never a chat instruction) > explicit instruction from a human in the current session > `.ai/rules/00` > `01` > `02` > `03` > persona files > skills > tool defaults.
If two sources conflict, follow the higher one and say what the conflict was.
