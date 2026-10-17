# Agent Policy

What AI agents may **not** do in this project, whichever tool they run in.

- **Humans edit this file. Agents never do.**
- **Agents:** obey every rule below, whether or not your tool can enforce it. Then implement the rules in your tool's settings, as described in *Applying this policy*.

**Formats** (keep them, so every tool reads the rules the same way)
- Rule: `- **id** — ``regex`` — reason`. Regexes are JavaScript and case-insensitive. They match anywhere in the command or content.
- Path: `` - `glob` ``. Globs are relative to the project root: `**` = any depth, `*` = within one folder, no `/` = match the file name anywhere, a leading `!` = exception.
- Switch: `- [x] **id** — description`. `[x]` = on, `[ ]` = off.

---

## Applying this policy (agents)

**When:** your first session in a project, after this file changes, or whenever your tool's settings don't reflect it.

1. **Map each section to your tool's strongest control:**

   | Section | Implement as |
   |---|---|
   | Shell: deny | Deny rules for those commands. Native rules usually match command prefixes, so cover **at least** everything the regex matches. When unsure, block more. |
   | Shell: ask | Require-approval rules. If your tool can't prompt for approval, use deny rules. |
   | Files: protect | Deny edit/write rules (read-only). |
   | Files: deny read | Deny both read and edit/write rules, and add the files to your tool's ignore list if it has one. |
   | Files: no modify existing | A pre-edit hook that blocks edits to files that already exist. Without hooks, require approval for edits there. |
   | Content: deny | A pre-write hook, if your tool has one. Otherwise check before every write. |
   | Spec rules | Follow them yourself. Run `bash .ai/scripts/validate-specs.sh` before finishing. |

2. **Use only settings you have verified** in your tool's current docs or its existing config files. If you're unsure a key exists, don't write it; tell the human (rule 00: no phantom APIs).
   Example for Claude Code, in `.claude/settings.json`:
   ```json
   { "permissions": {
       "deny": ["Bash(git push:*)", "Bash(terraform destroy:*)", "Read(./.env)", "Read(./.env.*)", "Edit(./.ai/**)"],
       "ask":  ["Bash(npm install:*)", "Bash(npx prisma migrate deploy:*)"] } }
   ```
3. **Write project-level config only, never global user config.** Show the human the exact diff and wait for approval before writing it. Never loosen existing settings that are stricter than this policy.
4. **Report coverage** to the human: one row per section, saying whether it is enforced by the tool, partially enforced (and how), or followed manually.

---

## Shell: deny

Commands an agent must never run. A human runs them.

- **git-commit** — ``\bgit\b[^;&|]*\bcommit\b`` — Agents never commit. A human reviews and commits manually (rule 03).
- **git-push** — ``\bgit\b[^;&|]*\bpush\b`` — Agents never push. A human pushes manually (rule 03).
- **git-branch** — ``\bgit\b[^;&|]*\b(branch|checkout\s+-b|switch\s+-c)\b`` — Agents never create, delete, switch, or manage branches. A human does this manually (rule 03).
- **git-skip-hooks** — ``--no-verify\b|\bgit\b[^;&|]*\bcommit\b[^;&|]*\s-n\b`` — Bypassing git hooks is banned (rule 03).
- **git-rewrite-history** — ``\bgit\b[^;&|]*\b(reset\s+--hard|rebase|filter-branch|filter-repo|commit\b[^;&|]*--amend|clean\s+-\w*f|branch\s+-D)\b`` — Rewriting history, deleting branches, or discarding work is human-only (rule 03).
- **db-drop** — ``\b(drop\s+(table|database|schema|view|index|collection)|truncate\s+(table\s+)?[\w."]+)\b|dropDatabase\s*\(|\.drop\s*\(\s*\)`` — Dropping or truncating database objects is human-only.
- **db-delete-all** — ``\bdelete\s+from\s+[\w."]+\s*(;|"|'|$)`` — DELETE without WHERE wipes a table. Human-only.
- **db-alter-drop** — ``\balter\s+table\b[^;]*\bdrop\b`` — Dropping columns or constraints is destructive. Put it in a spec'd migration; a human applies it.
- **db-reset-tools** — ``\b(prisma\s+migrate\s+reset|prisma\s+db\s+push\b[^;&|]*--(force-reset|accept-data-loss)|rails\s+db:(drop|reset|purge|schema:load)|rake\s+db:(drop|reset|purge)|manage\.py\s+(flush|reset_db)|sequelize(-cli)?\s+db:drop|typeorm\s+schema:drop|knex\s+migrate:rollback\b[^;&|]*--all|alembic\s+downgrade\s+base|dropdb|mongosh?\b[^;&|]*dropDatabase|redis-cli\b[^;&|]*\bflush(all|db)|drizzle-kit\s+drop)\b`` — Resets or destroys database data. Only a human runs it.
- **infra-destroy** — ``\b(terraform\s+(destroy|apply\b[^;&|]*-destroy)|pulumi\s+destroy|kubectl\s+delete|helm\s+(uninstall|delete)|docker\s+(system|volume)\s+prune|docker\s+volume\s+rm|docker[\s-]+compose\b[^;&|]*\bdown\b[^;&|]*\s-v)\b`` — Destroying infrastructure or volumes is human-only.
- **publish-deploy** — ``\b((npm|pnpm|yarn)\s+publish|cargo\s+publish|twine\s+upload|gh\s+release\s+create|gh\s+pr\s+merge|fly(ctl)?\s+deploy)\b|\b(vercel|netlify)\b[^;&|]*--prod\b`` — Publishing, merging, or deploying is human-only.
- **rm-root** — ``\brm\s+(-\w+\s+)*-\w*r\w*\s+(-\w+\s+)*["']?(/|~|\$HOME|\.\.?)["']?(\s|$|/\*?(\s|$))`` — Recursive delete of /, ~, . or .. is banned.
- **secrets-read** — ``\b(cat|type|less|more|head|tail|bat|Get-Content|gc)\b[^;&|]*\.env(?!\.(example|sample|template))\b`` — Agents never read secrets files (rule 01).
- **pipe-to-shell** — ``\b(curl|wget|iwr|Invoke-WebRequest)\b[^;&]*\|\s*(sudo\s+)?(ba|z)?sh\b|\|\s*iex\b`` — Piping remote scripts into a shell is banned.
- **sudo** — ``(^|[;&|]\s*)sudo\b`` — No privilege escalation. Ask the human to run it.

## Shell: ask

Commands that need a human's approval each time. Tools that can't prompt for approval treat these as **deny**.

- **add-dependency** — ``\b(npm\s+(i|install|add)\s+[^-\s]|(pnpm|yarn|bun)\s+add\b|pip3?\s+install\s+(?!-r\b|-e\s+\.)\S|(uv|poetry|cargo)\s+add\b|go\s+get\b|gem\s+install\b|dotnet\s+add\b[^;&|]*\bpackage\b|composer\s+require\b)`` — Adds a dependency. Rule 02: allowed only if the spec records it in §2.4.
- **db-migrate** — ``\b(prisma\s+(migrate\s+(deploy|dev)|db\s+push)|(rails|rake)\s+db:(migrate|rollback)|manage\.py\s+migrate|alembic\s+(upgrade|downgrade)|knex\s+migrate:|sequelize(-cli)?\s+db:migrate|typeorm\s+migration:(run|revert)|flyway\s+migrate|liquibase\s+update|drizzle-kit\s+(push|migrate))`` — Changes a database schema.

## Files: protect

Agents may read these but never create, edit, move, or delete them. The single exception is writing your tool's settings during *Applying this policy*, after the human approves the diff.

- `.ai/**`
- `.claude/settings.json`
- `.claude/settings.local.json`
- `.gemini/settings.json`
- `.cursor/**`
- `.codex/**`
- `opencode.json`

## Files: deny read

Secrets. Agents never read or write these.

- `.env`
- `.env.*`
- `!.env.example`
- `!.env.sample`
- `!.env.template`
- `*.pem`
- `*.key`
- `*.p12`
- `*.pfx`
- `id_rsa*`
- `id_ed25519*`
- `.npmrc`
- `.pypirc`
- `credentials.json`

## Files: no modify existing

Applied migrations are history. Agents may add new files here, but never edit or delete existing ones. Write a new migration instead.

- `**/migrations/**`
- `**/db/migrate/**`
- `**/alembic/versions/**`

## Content: deny

Agents never write text matching these patterns, in any file.

- **private-key** — ``-----BEGIN [A-Z ]*PRIVATE KEY-----`` — Private key. Secrets come from env or a secret manager (rule 01).
- **aws-key** — ``\bAKIA[0-9A-Z]{16}\b`` — AWS access key (rule 01).
- **github-token** — ``\bgh[pousr]_[A-Za-z0-9]{36}\b`` — GitHub token (rule 01).

## Spec rules

Checks from the SDD kit. Turn them off only for projects that don't use `specs/`.

- [x] **spec-gate** — Code under the source root only inside paths an Approved spec owns (§2.1). No code before `init-project`.
- [x] **no-self-approval** — Agents never set a spec to Approved or Deprecated.
- [x] **validate-on-stop** — `.ai/scripts/validate-specs.sh` must pass before the agent finishes.
