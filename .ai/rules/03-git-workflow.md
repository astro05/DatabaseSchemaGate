# 03 — Git Workflow

## Branches & Commits
> **Rule for AI agents:** Agents must **never** run `git commit` or `git push`, and must **never** create, delete, switch, or manage git branches (`git branch`, `git checkout -b`, `git switch -c`). Branching, committing, and pushing are strictly human-only. The agent must provide the exact suggested conventional commit message and command for the human maintainer to execute manually.

| Kind | Pattern | Example |
|---|---|---|
| Spec change | `spec/NNN-slug` | `spec/001-core-system` |
| Implementation | `feat/NNN-slug`, `fix/NNN-slug` | `feat/001-session-create` |
| Chore / tooling | `chore/slug` | `chore/ci-validate-specs` |

## Commits — Conventional Commits with a spec scope
```
<type>(SPEC-NNN): <imperative summary, ≤72 chars>

<why, not what>

Spec: SPEC-NNN AC-01, AC-02
BREAKING CHANGE: <only if a §3 contract breaks; include migration>
```
Types: `spec`, `feat`, `fix`, `test`, `refactor`, `docs`, `chore`.
Use `spec` for commits that only touch `specs/`. Every `feat` or `fix` commit includes a `Spec:` footer.

## Pull requests
1. **Spec first.** Behavior change goes through a spec PR (`spec/…`), which is reviewed and merged with `Status: Approved` by a human, **then** an implementation PR. Small amendments may share one PR only if the spec diff is reviewed first.
2. Each PR description must include: the owning spec(s), ACs covered, test evidence, and a "Spec drift: none / described" line.
3. CI must pass: tests, type-check, lint, `.ai/scripts/validate-specs.sh`.
4. Changes to auth, secrets, PII, or input parsing need a `security-auditor` review.
5. Squash-merge. The squash message follows the commit format above.

## Spec versioning
- Semver in the spec's metadata `Version`: MAJOR = breaking contract, MINOR = additive behavior, PATCH = clarification or typo.
- Every version bump gets a `changelog.md` entry. Never rewrite past changelog entries. Fix mistakes with new entries.
- A spec never gets deleted. Set its status to `Deprecated`, and record its replacement in the index and the changelog.

## Never
- Agents running `git commit` (`git commit ...`). The agent formats the suggested commit command and message, and the human maintainer executes it manually.
- Agents pushing to remote (`git push`). Pushing is strictly human-only.
- Agents creating, switching, or deleting git branches (`git branch`, `git checkout -b`, `git switch -c`). The agent prompts the human maintainer instead.
- Force-push shared branches, or rewrite history on `main`/`master`.
- Commit secrets, `.env` files, credentials, or generated artifacts.
- Bypass hooks or CI (`--no-verify`) without explicit maintainer approval.
