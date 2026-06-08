---
name: claude-code-review-loop
description: Use this skill for non-trivial coding tasks when the user wants Codex to save context by delegating implementation to normal Claude Code CLI. Codex should plan briefly, dispatch work to Claude Code, review the actual diff, request fixes when needed, run validation, and only accept passing work.
---

# Claude Code Review Loop

Use normal Claude Code CLI, like a human would from the terminal.

## Workflow

1. Codex reads only enough context to write a clear task.
2. Codex dispatches implementation to Claude Code:

```powershell
& "<skill_dir>\scripts\dispatch-claude.ps1" -WorkingDirectory "<repo>" -Prompt "<task prompt>"
```

3. Claude Code may inspect files, edit code, and run focused validation.
4. Codex reviews the real working-tree diff and chooses/runs final validation.
5. If the diff has bugs, unrelated churn, broad refactors, missing error handling, or failed validation, Codex rejects it with specific feedback and dispatches a correction.
6. Stop after 3 failed review rounds and ask the user for direction.

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

Codex may edit directly only for tiny mechanical fixes, final integration, or when the user explicitly asks Codex to take over.
