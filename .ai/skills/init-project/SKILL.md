---
name: init-project
description: First run of the .ai kit in a project (new or existing). Creates specs/, records the project's real paths and commands, and drafts SPEC-001 as the baseline.
---

# Skill: init-project

**Use when:** `specs/SPEC-INDEX.md` does not exist. Run it once per project.

## Steps

1. **Detect the project.** Read the root manifest files (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `*.csproj`, …), the README, and the top-level folders. Note these, **verified, not guessed**:
   - Language, framework, package manager
   - Source root and tests root (if they exist)
   - Test, lint, and type-check commands (from scripts, Makefile, or CI config)
   - Existing architecture: the folder layout and how it maps onto `domain / core / data / interfaces` (rule 01)
2. **Create the index:**
   ```bash
   mkdir -p specs
   cp .ai/templates/spec-index-template.md specs/SPEC-INDEX.md
   ```
   Fill in **Project paths** with what you found. For a new project, keep the defaults `src/` and `tests/`, and leave the commands as `TBD`.
3. **Draft SPEC-001 with the `new-spec` skill** (slug `core-system`):
   - **New project:** the system baseline. Leave the product vision and tech stack as §1.4 Open Questions.
   - **Existing project:** describe the system *as it is today*, not as it should be. Document the current architecture in §2, list the main modules with their existing paths in §2.1, and record the existing stack choices in §2.4 Decisions.
4. **Existing code is grandfathered.** Don't write specs for every module up front. A module gets its own spec the first time a task changes its behavior (rule 00).
5. **Validate:** `bash .ai/scripts/validate-specs.sh` must exit 0.
6. **Report to the human:** what you detected, the open questions, and that SPEC-001 is waiting for their review. **Don't change any code.**
