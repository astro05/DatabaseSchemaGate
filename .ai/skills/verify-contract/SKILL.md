---
name: verify-contract
description: Check that the implementation's types, operations, and error codes match a spec's §3 contracts and §4.2 error modes exactly, and that each is tested.
---

# Skill: verify-contract

**Use when:** before marking ACs `Verified`, during review, and after refactors.

## Steps

1. **Extract the contract** from the spec: §3.1 types (fields, types, optionality, constraints), §3.2 operations (input, output, errors, auth, idempotency), §3.3 persistence, and §4.2 error codes.
2. **Locate the implementation** under the paths in spec §2.1. Grep for each type and operation name. **A spec'd item with no implementation counts as a finding; never assume it exists.**
3. **Check each item:**
   - [ ] Name matches exactly
   - [ ] Every field is present, with no extra public fields
   - [ ] Types and optionality match; there are no implicit nulls
   - [ ] Constraints (length, range, regex, enum) are enforced at the boundary
   - [ ] Every listed error code is raised in its trigger condition, and no unlisted codes are raised
   - [ ] The auth requirement is enforced
   - [ ] Idempotency holds when claimed
   - [ ] Persistence keys, uniqueness, and indexes match §3.3
4. **Check the tests:** every operation and error code has at least one test whose name references an AC.
5. **Use machine checks where the stack has them:** if the contracts exist as schemas (OpenAPI, JSON Schema, protobuf), validate the implementation against them with the stack's tooling, and record the command in `.ai/ai.md` §5.
6. **Report:** `PASS`, or a table of findings:

   | Spec item | Expected (spec) | Actual (code location) | Fix |
   |---|---|---|---|
