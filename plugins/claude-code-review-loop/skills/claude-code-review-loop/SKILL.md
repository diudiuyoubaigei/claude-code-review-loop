---
name: claude-code-review-loop
description: Use this skill for non-trivial coding tasks when the user wants Codex to save context by delegating implementation to normal Claude Code CLI. Codex should plan briefly, dispatch work to Claude Code, review the actual diff, request fixes when needed, run validation, and only accept passing work.
---

# Claude Code Review Loop

Use normal Claude Code CLI, like a human would from the terminal.

## Workflow

1. Codex reads only enough context to write a clear task.
2. Codex splits the work into independent scopes before dispatch:
   - Split when tasks touch different files or packages and can be validated separately.
   - Do not parallelize overlapping file ownership, shared migrations, or refactors that need one ordered diff.
   - Each workstream gets its own prompt with owned files, acceptance criteria, and validation.
3. Codex dispatches Claude Code runs:
   - Small single-scope tasks may use the synchronous helper:

```powershell
& "<skill_dir>\scripts\dispatch-claude.ps1" -WorkingDirectory "<repo>" -Prompt "<task prompt>" -TimeoutSeconds 7200 -RetryCount 1 -PermissionMode bypassPermissions
```

   - Multi-part or long-running tasks should use the background helpers. Start one run per workstream, and launch independent workstreams in parallel:

```powershell
& "<skill_dir>\scripts\start-claude-dispatch.ps1" -WorkingDirectory "<repo>" -Prompt "<task prompt>" -PermissionMode bypassPermissions
```

4. While background runs are active, Codex monitors them every 10 minutes:

```powershell
& "<skill_dir>\scripts\check-claude-dispatch.ps1" -RunId "<run-id>" -WaitSeconds 600
```

   After each check, Codex sends a brief update with:
   - which workstreams are still running or completed
   - changed files or diff progress
   - any blocker worth surfacing

5. Claude Code may inspect files, edit code, and run focused validation.
6. Codex reviews the real working-tree diff and chooses/runs final validation.
7. If the diff has bugs, unrelated churn, broad refactors, missing error handling, or failed validation, Codex rejects it with specific feedback and dispatches a correction.
8. Stop after 3 failed review rounds on the same workstream and ask the user for direction.

## Waiting Rules

- Do not park the main session behind one silent multi-hour dispatch when the task is large enough to split.
- Prefer background dispatch plus 10-minute checks for long-running work so the user sees progress.
- Use parallel dispatch only for truly independent scopes. Separate prompts are mandatory.
- For synchronous dispatch, set the tool timeout to at least 7200000 ms and use 1800 seconds only for small tasks.
- If a background run stops making file progress across multiple checks, inspect the diff, narrow the prompt, and resume in a smaller workstream.

## Dispatch Prompt

Keep prompts short but specific:

- what to change
- relevant files or areas
- acceptance criteria
- keep changes scoped
- follow existing patterns
- run relevant validation
- do not commit, push, or deploy
- report changed files and validation result
- keep working until the task is complete or blocked; do not stop just because the task is taking time

Codex may edit directly only for tiny mechanical fixes, final integration, or when the user explicitly asks Codex to take over.
