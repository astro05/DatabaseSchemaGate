# 00 — Spec-Driven Rules (Invariants)

These rules override every other file in this repository. Only an explicit instruction from a human maintainer in the current session overrides them.
If a rule blocks you, **stop and ask**. Never work around it.

## Core invariants

1. **Spec precedes code.** No production code under `src/` may exist without an `Approved` spec that describes its behavior.
2. **The spec is the source of truth.** If code and spec disagree, the code is wrong until the spec is changed through the loop below.
3. **No silent drift.** Every behavior change lands together with its spec change, in the same PR.
4. **Traceability.** Every acceptance criterion (AC) maps to at least one test, and every test in `tests/` names the `SPEC-ID AC-ID` it verifies.
5. **Humans approve.** Agents may draft and propose. Only a human maintainer moves a spec to `Approved` or `Deprecated`.
6. **Existing code is grandfathered.** In a project that adopted this kit after code already existed, unspecified code may stay as it is. The first change to a module's behavior requires a spec for that module (at least the behavior being changed) before any code edit.

---

## The developer loop

Run this loop for **every** change that affects behavior. Do not skip or reorder steps.

```
[1 Read Spec] -> [2 Write Failing Spec Test] -> [3 Implement] -> [4 Verify] -> [5 Update Spec Changelog]
       ^                                                                                   |
       +------------------------- spec gap found at any step -----------------------------+
```

### 1. Read Spec
- Open `specs/SPEC-INDEX.md`. Find the spec that owns the module you will touch.
- Read the whole spec and every spec in its `Dependencies`.
- **Gate:** the status must be `Approved`.
  - `Draft` → stop and hand off to `spec-architect` or a human.
  - No owning spec → run the `.ai/skills/new-spec` skill, then stop for approval.
  - The request isn't covered by the spec → amend the spec first (a spec change needs approval), then restart.

### 2. Write Failing Spec Test
- For each AC in scope, write a test in `tests/` whose name includes the IDs, e.g. `SPEC-001 AC-03: rejects expired token`.
- Run it. It **must fail, and fail for the right reason**: an assertion failure, not an import, syntax, or setup error.
- Put the test path in the spec's Verification Matrix → `Test Reference` column.

### 3. Implement
- Write the minimum code that makes the failing tests pass.
- Put code only in the module and layer named in spec §2.
- Use the contracts in spec §3 **exactly**: names, types, optionality, error codes.
- If you find a gap or ambiguity in the spec: stop, add it to spec §1.4 Open Questions, and return to step 1. **Never fill the gap with your own guess.**

### 4. Verify
- The **full** test suite passes, not only the new tests.
- `.ai/scripts/validate-specs.sh` exits 0.
- Walk spec §4: every invariant, error mode, and edge case is covered by a passing test.
- Set the AC rows you covered to `Verified` in the Verification Matrix.

### 5. Update Spec Changelog
- Add an entry to `specs/NNN-*/changelog.md`: date, version, change type, ACs affected, PR/commit.
- Bump `Version` and `Last Updated` in the spec metadata (semver: MAJOR = breaking contract, MINOR = additive, PATCH = clarification).
- Update the spec's row in `specs/SPEC-INDEX.md`: Status, Coverage, Last Updated.

---

## Absolute bans

| Ban | What it means | Do this instead |
|---|---|---|
| **No phantom APIs** | Never call, import, configure, or document a function, endpoint, field, flag, env var, or package that you have not verified exists in this repo or its locked dependencies. | Grep or read the code first. If it doesn't exist and is needed, that is a spec change. |
| **No unrecorded architectural decisions** | Adding a dependency, layer, datastore, protocol, external service, background job, cache, or cross-module call without a record. | Record it in spec §2.4 Decisions (decision, alternatives, rationale) **before** implementing. |
| **No undocumented breaking changes** | Changing a §3 contract in a way that breaks existing callers or stored data. | MAJOR version bump, a changelog entry tagged `BREAKING`, migration notes, and every dependent spec in `SPEC-INDEX.md` reviewed. |
| **No self-approval** | An agent setting `Status: Approved`. | Hand off to a human maintainer. |
| **No test weakening** | Deleting, skipping, or loosening a test, or editing an AC, to make a build green. | Fix the code, or change the spec through the loop with approval. |
| **No orphan code** | Code with no spec, or tests with no AC reference. | Trace it to a spec, or delete it. |

---

## When unsure

Stop and ask a specific question. A question costs minutes; drift costs weeks.
