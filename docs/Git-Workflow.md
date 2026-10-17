# Git Workflow

Git is the source of truth: a database object that is not in Git does not officially exist, and every change reaches a database only through a merge into `main`.

## 1. One-time repository setup

### Protect `main` (GitLab → Settings → Repository → Protected branches)

| Setting | Value | Why |
|---|---|---|
| Allowed to merge | Maintainers (or your release group) | These people can also run the manual `deploy_dev_approved` job |
| Allowed to push and merge | **No one** | Every change goes through a merge request, so the concurrent-edit check and review always run |
| Allowed to force push | Off | |

### Merge requests (Settings → Merge requests)

| Setting | Value | Why |
|---|---|---|
| Merge method | **Merge commit with semi-linear history** | A merge request can only merge when it contains the latest `main`, so the checks ran on exactly what lands |
| Pipelines must succeed | On | Validation, build and tests gate the merge |
| Approvals (optional) | At least 1 | A second pair of eyes on schema changes |

### CI/CD variables

Connection strings are set up once per database. See [CI/CD](CI-CD.md#3-connection-string-variables).

## 2. Day to day

```powershell
git switch main; git pull
git switch -c feat/customer-email          # one topic per branch

# edit Databases/<Database>/... and/or ScriptRunner/<Database>/...
.\Scripts\ValidateDatabase.ps1; .\Scripts\BuildDatabase.ps1

git add -A
git commit -m "feat: add Email to dbo.Customer"
git push -u origin HEAD                    # then open a merge request into main
```

The merge request pipeline validates, builds and tests. After review and a green pipeline, merge. The `main` pipeline then deploys to Development.

### Branch names

| Kind | Pattern | Example |
|---|---|---|
| Schema or data change | `feat/<topic>`, `fix/<topic>` | `feat/customer-email`, `fix/usp-getorders-null` |
| Spec change | `spec/NNN-<slug>` | `spec/004-script-runner` |
| Tooling | `chore/<topic>` | `chore/ci-staging` |

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `<type>: <imperative summary>`, with type `feat`, `fix`, `refactor`, `docs`, `test`, `chore` or `spec`. When the change implements a spec, name it in the scope and the footer:

```text
feat(SPEC-004): run ScriptRunner for every managed database

Spec: SPEC-004 AC-18
```

## 3. When someone changed the same object: `E_STALE_BASE`

Git merges two edits of one stored procedure without a conflict when they touch different lines. Nobody has reviewed the combined procedure, though, and it may no longer make sense. So in merge requests, `check_concurrent_edits` fails when a `.sql` file you **modified** was also changed on the target branch after you branched:

```text
ERROR  [Databases/Sales/StoredProcedures/dbo.usp_GetOrders.sql]: E_STALE_BASE: changed on main after you branched:
         a1b2c3d Jane Doe: fix: filter cancelled orders
```

Fix it by bringing your branch up to date and reviewing the whole object:

```powershell
git pull --rebase origin main      # resolve conflicts if any
# open the file and read the complete object with both changes; fix what no longer fits
git push --force-with-lease
```

The check passes once your branch contains the latest `main`. New files never trigger it, because they have no earlier version. Renamed files are not followed.

## 4. Hotfixes made directly in a database

Sometimes production is fixed in SSMS first. Bring Git back in line the same day:

1. Make the same change in the object's file on a `fix/...` branch, and merge it normally.
2. Confirm nothing else differs: `.\Scripts\DetectDrift.ps1 -Database <Name> -ConnectionString "<that server>"` (exit `0` = no drift).

Until step 1 lands, the next deploy to that database puts Git's version back.

## 5. Never commit

- Connection strings, passwords, keys. `appsettings.local.json`, `appsettings.json` and `.env*` are git-ignored; `ValidateDatabase.ps1` and the tests also reject credentials in `.sql` files. If a secret was pushed, **change the password first**, then clean up history.
- Build output: `bin/`, `obj/`, `artifacts/`, `*.dacpac` (git-ignored).
- `USE <database>` in `Databases/` files: the deploy chooses the database.

## 6. Working with AI coding agents

The repository includes instructions for AI agents (`AGENTS.md`, `GEMINI.md`, `.ai/`). They follow spec-driven development: behavior is defined in `specs/` first, every test names the `SPEC-ID AC-ID` it verifies, and agents leave committing and pushing to you. Check the specs with:

```bash
bash .ai/scripts/validate-specs.sh
```
