---
name: new-spec
description: Scaffold a new spec folder from the SDD template, register it in SPEC-INDEX, and hand off to the spec-architect persona.
---

# Skill: new-spec

**Use when:** a request needs behavior that no existing spec owns (check `specs/SPEC-INDEX.md` first; if a spec already owns it, amend that spec instead).

## Steps

1. **Pick the next ID:** take the highest `NNN` among `specs/[0-9][0-9][0-9]-*/` and add 1. Never reuse an ID.
2. **Pick a slug:** a short kebab-case module name, e.g. `session-scheduling`. It becomes the module folder under `src/*/`.
3. **Create the folder:**
   ```bash
   mkdir -p specs/NNN-slug
   cp .ai/templates/spec-template.md specs/NNN-slug/spec.md
   ```
4. **Fill the metadata:** `ID: SPEC-NNN`, Title, `Status: Draft`, `Version: 0.1.0`, Author, Owner, Dependencies, and today's date for Created and Last Updated.
5. **Create `specs/NNN-slug/changelog.md`:**
   ```markdown
   # SPEC-NNN Changelog

   | Date | Version | Type | Change | ACs | Ref |
   |---|---|---|---|---|---|
   | YYYY-MM-DD | 0.1.0 | created | Initial draft | — | — |
   ```
6. **Register the spec:** add a row to `specs/SPEC-INDEX.md` with Status `Draft` and Coverage `0/N`.
7. **Validate:** run `.ai/scripts/validate-specs.sh`. It must exit 0.
8. **Hand off:** follow `.ai/agents/spec-architect.md` to fill in the content. **Stop before implementation.** A human must approve the spec first.
