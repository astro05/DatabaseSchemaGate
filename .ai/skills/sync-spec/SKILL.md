---
name: sync-spec
description: Detect drift between code changes and their owning specs; classify each drift as a code defect or a spec gap and produce a reconciliation report.
---

# Skill: sync-spec

**Use when:** reviewing a PR, after a bug fix, or whenever code and spec may disagree.

## Steps

1. **Collect the changes:** `git diff --name-only <base>...HEAD` (default base: the main branch).
2. **Map files to specs:** for each changed path under `src/` or `tests/`, find the spec whose §2.1 Module Placement owns it. A file no spec owns is an **orphan**, which counts as drift.
3. **Compare each owning spec with the code:**
   - §3 contracts: operation names, input and output fields, types, optionality, enums, HTTP routes and status codes.
   - §4.2 error codes: the codes the code raises vs. the codes the spec lists, in both directions.
   - §4.1 invariants: is each one still enforced?
   - §5: does each `Test Reference` exist, and do tests reference ACs that exist?
   - New dependencies or architectural choices that are missing from §2.4.
4. **Classify each drift:**
   - **Code defect:** the spec is right and the code is wrong. Fix the code through loop step 2 (failing test first).
   - **Spec gap:** the code reveals intended behavior that the spec lacks. Propose an amendment as an Open Question or a diff, **with no semantic edit to an Approved spec without human approval.**
   - **Orphan:** code with no spec. Either a spec gets written (`new-spec`), or the code gets deleted.
5. **Report:**

   | Spec | Section | Code location | Drift | Class | Proposed action |
   |---|---|---|---|---|---|

6. Exit condition: the report is empty, or every row has an owner and an action.
