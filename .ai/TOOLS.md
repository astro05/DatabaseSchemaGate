# Using `.ai/` with any AI tool

> For humans. AI agents: read `.ai/ai.md` instead.

No tool loads `.ai/` automatically. You tell the tool to use it at the start of each session.
This works the same way in Claude Code, Codex, OpenCode, Antigravity, Cursor, Copilot, Gemini CLI, Aider, and any other agent that can read files.

## 0. Install in a project

1. Copy the whole `.ai/` folder into the project root.
2. Review `.ai/hooks/policy.md`, which lists what agents may never do (git push, destructive DB commands, secrets, …), and adjust it for this project. In its first session, the agent implements it in its own tool's settings and asks you to approve the diff.
3. Start the first session with:
   ```
   Work with the .ai folder: read .ai/ai.md and initialize this project.
   ```
4. The agent runs `init-project`. It creates `specs/`, detects your paths and commands, and drafts SPEC-001. Review that spec and approve it.

This works for new and existing projects. In an existing project, current code is left alone until a task changes it.

## 1. Start every session with

```
Work with the .ai folder: read .ai/ai.md first and follow its reading order.
Task: <your task>
```

In tools that support `@` file mentions (most of them), `@.ai/ai.md` attaches the file directly:

```
@.ai/ai.md  Task: <your task>
```

## 2. Pick a persona or skill for the task

| Want | Say |
|---|---|
| Turn an idea into a spec | "Act as `.ai/agents/spec-architect.md`. New spec for: <feature>" |
| Scaffold a spec folder | "Run the skill `.ai/skills/new-spec/SKILL.md` for: <module>" |
| Implement | "Act as `.ai/agents/core-engineer.md`. Implement SPEC-NNN AC-01..AC-03" |
| Write tests | "Act as `.ai/agents/test-engineer.md` for SPEC-NNN" |
| Check code vs. spec | "Run `.ai/skills/sync-spec/SKILL.md` on this branch" |
| Check contracts | "Run `.ai/skills/verify-contract/SKILL.md` for SPEC-NNN" |
| Security review | "Act as `.ai/agents/security-auditor.md` and review this diff" |

## 3. Long sessions

Agents forget instructions as context fills up. If an agent starts skipping the spec loop, say:
```
Re-read .ai/rules/00-spec-driven-rules.md and continue.
```

## 4. Approve specs yourself

Agents only draft specs. You change `Status: Draft` → `Approved` in `specs/NNN-*/spec.md` and `specs/SPEC-INDEX.md`, then tell the agent to implement.
