# Spec Index

The registry of every spec. **Read it first in every task** (see `.ai/ai.md`).
`.ai/scripts/validate-specs.sh` fails if a spec folder is missing from this table, or if its Status here differs from the spec's own metadata.

## Project paths

Every `.ai/` file writes `src/` and `tests/`. They mean the paths below.

| Key | Path |
|---|---|
| Source root | `src/` |
| Tests root | `tests/` |
| Test command | TBD |
| Lint / type-check command | TBD |

## Specs

| Spec ID | Module | Status | Version | Coverage | Owner | Last Updated | Depends On |
|---|---|---|---|---|---|---|---|

## Column definitions

- **Spec ID**: `SPEC-NNN`, matching folder `specs/NNN-slug/`. IDs are never reused.
- **Module**: the folder slug, which is also the module name under the source root.
- **Status**: `Draft` · `Approved` · `Deprecated`. It must match the spec's metadata. Only humans change it.
- **Version**: the spec's semver.
- **Coverage**: `Verified ACs / Total ACs` from the spec's §5 Verification Matrix. `validate-specs.sh` prints it.
- **Owner**: the person who approves changes to this spec.
- **Last Updated**: `YYYY-MM-DD` of the last changelog entry.
- **Depends On**: Spec IDs this spec consumes, or `none`. Review these when making a breaking change.

Keep deprecated specs in the table with Status `Deprecated`, and name the replacement in their changelog.
