#!/usr/bin/env node
/**
 * Antigravity PreToolUse Lifecycle Hook
 * Strictly enforces .ai/hooks/policy.md rules across shell commands and file operations.
 */
const fs = require('fs');
const path = require('path');

let inputData = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', chunk => { inputData += chunk; });
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(inputData);
    const result = evaluateToolCall(payload);
    process.stdout.write(JSON.stringify(result));
  } catch (err) {
    process.stdout.write(JSON.stringify({ decision: 'allow' }));
  }
});

function evaluateToolCall(payload) {
  const toolCall = payload.toolCall || {};
  const name = toolCall.name || '';
  const args = toolCall.args || {};

  // 1. Shell commands (run_command)
  if (name === 'run_command') {
    const cmd = args.CommandLine || '';

    // Shell: deny (15 rules)
    const shellDeny = [
      { id: 'git-commit', pattern: /\bgit\b[^;&|]*\bcommit\b/i, reason: 'Agents never commit. A human reviews and commits manually (rule 03).' },
      { id: 'git-push', pattern: /\bgit\b[^;&|]*\bpush\b/i, reason: 'Agents never push. A human pushes manually (rule 03).' },
      { id: 'git-branch', pattern: /\bgit\b[^;&|]*\b(branch|checkout\s+-b|switch\s+-c)\b/i, reason: 'Agents never create, delete, switch, or manage branches. A human does this manually (rule 03).' },
      { id: 'git-skip-hooks', pattern: /--no-verify\b|\bgit\b[^;&|]*\bcommit\b[^;&|]*\s-n\b/i, reason: 'Bypassing git hooks is banned (rule 03).' },
      { id: 'git-rewrite-history', pattern: /\bgit\b[^;&|]*\b(reset\s+--hard|rebase|filter-branch|filter-repo|commit\b[^;&|]*--amend|clean\s+-\w*f|branch\s+-D)\b/i, reason: 'Rewriting history, deleting branches, or discarding work is human-only (rule 03).' },
      { id: 'db-drop', pattern: /\b(drop\s+(table|database|schema|view|index|collection)|truncate\s+(table\s+)?[\w."]+)\b|dropDatabase\s*\(|\.drop\s*\(\s*\)/i, reason: 'Dropping or truncating database objects is human-only.' },
      { id: 'db-delete-all', pattern: /\bdelete\s+from\s+[\w."]+\s*(;|"|'|$)/i, reason: 'DELETE without WHERE wipes a table. Human-only.' },
      { id: 'db-alter-drop', pattern: /\balter\s+table\b[^;]*\bdrop\b/i, reason: 'Dropping columns or constraints is destructive. Put it in a spec\'d migration; a human applies it.' },
      { id: 'db-reset-tools', pattern: /\b(prisma\s+migrate\s+reset|prisma\s+db\s+push\b[^;&|]*--(force-reset|accept-data-loss)|rails\s+db:(drop|reset|purge|schema:load)|rake\s+db:(drop|reset|purge)|manage\.py\s+(flush|reset_db)|sequelize(-cli)?\s+db:drop|typeorm\s+schema:drop|knex\s+migrate:rollback\b[^;&|]*--all|alembic\s+downgrade\s+base|dropdb|mongosh?\b[^;&|]*dropDatabase|redis-cli\b[^;&|]*\bflush(all|db)|drizzle-kit\s+drop)\b/i, reason: 'Resets or destroys database data. Only a human runs it.' },
      { id: 'infra-destroy', pattern: /\b(terraform\s+(destroy|apply\b[^;&|]*-destroy)|pulumi\s+destroy|kubectl\s+delete|helm\s+(uninstall|delete)|docker\s+(system|volume)\s+prune|docker\s+volume\s+rm|docker[\s-]+compose\b[^;&|]*\bdown\b[^;&|]*\s-v)\b/i, reason: 'Destroying infrastructure or volumes is human-only.' },
      { id: 'publish-deploy', pattern: /\b((npm|pnpm|yarn)\s+publish|cargo\s+publish|twine\s+upload|gh\s+release\s+create|gh\s+pr\s+merge|fly(ctl)?\s+deploy)\b|\b(vercel|netlify)\b[^;&|]*--prod\b/i, reason: 'Publishing, merging, or deploying is human-only.' },
      { id: 'rm-root', pattern: /\brm\s+(-\w+\s+)*-\w*r\w*\s+(-\w+\s+)*["']?(\/|~|\$HOME|\.\.?)["']?(\s|$|\/\*?(\s|$))/i, reason: 'Recursive delete of /, ~, . or .. is banned.' },
      { id: 'secrets-read', pattern: /\b(cat|type|less|more|head|tail|bat|Get-Content|gc)\b[^;&|]*\.env(?!\.(example|sample|template))\b/i, reason: 'Agents never read secrets files (rule 01).' },
      { id: 'pipe-to-shell', pattern: /\b(curl|wget|iwr|Invoke-WebRequest)\b[^;&]*\|\s*(sudo\s+)?(ba|z)?sh\b|\|\s*iex\b/i, reason: 'Piping remote scripts into a shell is banned.' },
      { id: 'sudo', pattern: /(^|[;&|]\s*)sudo\b/i, reason: 'No privilege escalation. Ask the human to run it.' }
    ];

    for (const rule of shellDeny) {
      if (rule.pattern.test(cmd)) {
        return { decision: 'deny', reason: `[policy.md Shell: deny] ${rule.id}: ${rule.reason}` };
      }
    }

    // Shell: ask (approval required)
    const shellAsk = [
      { id: 'add-dependency', pattern: /\b(npm\s+(i|install|add)\s+[^-\s]|(pnpm|yarn|bun)\s+add\b|pip3?\s+install\s+(?!-r\b|-e\s+\.)\S|(uv|poetry|cargo)\s+add\b|go\s+get\b|gem\s+install\b|dotnet\s+add\b[^;&|]*\bpackage\b|composer\s+require\b)/i, reason: 'Adds a dependency. Rule 02: allowed only if the spec records it in §2.4.' },
      { id: 'db-migrate', pattern: /\b(prisma\s+(migrate\s+(deploy|dev)|db\s+push)|(rails|rake)\s+db:(migrate|rollback)|manage\.py\s+migrate|alembic\s+(upgrade|downgrade)|knex\s+migrate:|sequelize(-cli)?\s+db:migrate|typeorm\s+migration:(run|revert)|flyway\s+migrate|liquibase\s+update|drizzle-kit\s+(push|migrate))/i, reason: 'Changes a database schema.' }
    ];

    for (const rule of shellAsk) {
      if (rule.pattern.test(cmd)) {
        return { decision: 'ask', reason: `[policy.md Shell: ask] ${rule.id}: ${rule.reason}` };
      }
    }
  }

  // 2. File targets (view_file, write_to_file, replace_file_content)
  const targetPath = args.AbsolutePath || args.TargetFile || '';
  if (targetPath) {
    const norm = targetPath.replace(/\\/g, '/');
    const base = path.basename(norm);

    // Files: deny read (secrets)
    const isSecret = (/^\.env(\..+)?$/i.test(base) && !/^\.env\.(example|sample|template)$/i.test(base))
      || /\.(pem|key|p12|pfx)$/i.test(base)
      || /^id_rsa/i.test(base)
      || /^id_ed25519/i.test(base)
      || /^\.npmrc$/i.test(base)
      || /^\.pypirc$/i.test(base)
      || /^credentials\.json$/i.test(base);

    if (isSecret) {
      return { decision: 'deny', reason: `[policy.md Files: deny read] Secrets file "${base}" cannot be accessed or modified.` };
    }

    // Modification guards (write_to_file / replace_file_content)
    if (name === 'write_to_file' || name === 'replace_file_content') {
      // Files: protect
      if (/\/\.ai\//i.test(norm) || norm.startsWith('.ai/') || base === '.ai') {
        return { decision: 'deny', reason: '[policy.md Files: protect] Modification of .ai/ directory is forbidden to agents.' };
      }
      if (/\/\.claude\/settings(\.local)?\.json$/i.test(norm) || /\/\.gemini\/settings\.json$/i.test(norm) || /\/\.cursor\//i.test(norm) || /\/\.codex\//i.test(norm) || /opencode\.json$/i.test(norm)) {
        return { decision: 'deny', reason: '[policy.md Files: protect] Tool configuration files are protected.' };
      }

      // Files: no modify existing migrations
      if (name === 'replace_file_content' || (name === 'write_to_file' && fs.existsSync(targetPath))) {
        if (/(\/|^)(migrations|db\/migrate|alembic\/versions)\//i.test(norm)) {
          return { decision: 'deny', reason: '[policy.md Files: no modify existing] Existing migrations are immutable history.' };
        }
      }

      // Content: deny
      const content = args.CodeContent || args.ReplacementContent || '';
      if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(content)) {
        return { decision: 'deny', reason: '[policy.md Content: deny] Private key detected in written content.' };
      }
      if (/\bAKIA[0-9A-Z]{16}\b/.test(content)) {
        return { decision: 'deny', reason: '[policy.md Content: deny] AWS access key detected in written content.' };
      }
      if (/\bgh[pousr]_[A-Za-z0-9]{36}\b/.test(content)) {
        return { decision: 'deny', reason: '[policy.md Content: deny] GitHub token detected in written content.' };
      }
    }
  }

  return { decision: 'allow' };
}
