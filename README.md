# Claude Code Review Loop

一个很小的 Codex 工作流插件：让 **Claude Code CLI 负责写代码**，让 **Codex 负责规划、审查 diff、跑验证和验收**。

它不是 Claude MCP，也不依赖 Claude 的 subagent。它只是把人类平时在终端里使用 Claude Code 的方式固化成一个 Codex skill。

## 适合谁

适合想把重复、耗上下文的实现工作交给 Claude Code，同时仍然让 Codex 把关质量的人。

典型用法：

- Codex 读少量上下文，拆出明确任务
- Codex 调用本机 `claude -p`
- Claude Code 修改项目文件并做初步验证
- Codex 检查真实 diff
- 不合格就退回给 Claude Code 返工
- 最多 3 轮失败后停下来让用户决定

## 前置条件

你需要先在本机安装并登录 Claude Code CLI：

```powershell
claude --version
```

如果这条命令能正常输出版本号，就可以使用本插件。

## 平台说明

当前版本内置的是 PowerShell 调度脚本，主要面向 Windows 用户。macOS/Linux 用户如果已经安装 PowerShell 也可以尝试使用；否则可以按同样逻辑改成 shell 脚本：进入项目目录，然后执行 `claude --permission-mode acceptEdits -p "<task prompt>"`。

## 安装

把这个仓库作为 Codex 插件市场添加：

```powershell
codex plugin marketplace add <你的 GitHub 仓库地址>
codex plugin add claude-code-review-loop --marketplace claude-code-review-loop
```

本地测试时也可以直接添加当前目录：

```powershell
codex plugin marketplace add C:\path\to\claude-code-review-loop
codex plugin add claude-code-review-loop --marketplace claude-code-review-loop
```

安装后重启或刷新 Codex，让 skill 生效。

## 使用方式

你可以直接对 Codex 说：

```text
用 Claude Code Review Loop 修复这个 bug。
```

或者：

```text
这个功能让 Claude Code 写，Codex 负责审 diff 和测试。
```

也可以把下面这段加入自己的全局 `AGENTS.md`，让它更主动：

```markdown
For non-trivial coding tasks, default to using normal Claude Code CLI as the implementation executor to save Codex tokens. Codex should briefly plan, dispatch a clear scoped task via the Claude Code Review Loop skill, then review the actual diff, run validation, and accept or reject the result.
```

## 工作流

1. Codex 只读取足够写清任务的上下文。
2. Codex 调用插件脚本，把任务交给 Claude Code CLI。
3. Claude Code 在项目里正常读文件、改代码、跑必要验证。
4. Codex 检查真实 diff，而不是只相信 Claude Code 的总结。
5. 如果发现逻辑问题、无关改动、错误处理缺失、测试失败，就明确拒绝并要求返工。
6. 同一个任务最多返工 3 次，仍不通过就停下来让用户决定。

## 插件内容

```text
marketplace.json
plugins/
  claude-code-review-loop/
    .codex-plugin/plugin.json
    skills/
      claude-code-review-loop/
        SKILL.md
        agents/openai.yaml
        scripts/dispatch-claude.ps1
```

核心脚本只有一件事：在目标项目目录里执行普通 Claude Code CLI。

```powershell
claude --permission-mode bypassPermissions -p "<task prompt>"
```

## 等待时间和权限

Claude Code 在真实项目里可能跑很久，尤其是需要读代码、改多文件、跑测试的时候。这个插件默认给 Claude Code 更长的执行窗口：

```powershell
& ".\plugins\claude-code-review-loop\skills\claude-code-review-loop\scripts\dispatch-claude.ps1" `
  -WorkingDirectory "C:\path\to\your\repo" `
  -Prompt "修复这个问题，并运行相关验证" `
  -TimeoutSeconds 7200 `
  -RetryCount 1 `
  -PermissionMode bypassPermissions
```

默认策略：

- `TimeoutSeconds = 7200`：最多等待 2 小时。
- `RetryCount = 1`：超时后自动重试 1 次。
- `PermissionMode = bypassPermissions`：尽量避免 Claude Code 因权限确认卡住。

如果你希望更保守，可以改成：

```powershell
-PermissionMode acceptEdits
```

拍教程时建议强调：`bypassPermissions` 适合你信任的本地项目；不熟悉的仓库、第三方代码或敏感目录建议用 `acceptEdits`。

Codex 调用这个脚本时，也要给工具本身设置足够长的 timeout。不要用默认的短等待时间，否则 Codex 可能会误判“Claude 卡住了”。

## 设计取舍

这个插件刻意不做这些事：

- 不接 Claude MCP
- 不创建 Claude subagent
- 不自动 commit、push、deploy
- 不跳过 Codex 的 diff 审查
- 不试图接管所有简单小修

越简单，越稳定，也越适合拍教程。

## 拍视频时建议强调

- 这个插件的目标是节省 Codex 上下文，不是让 Codex 放弃审查。
- Claude Code 负责实现，但最终责任仍在 Codex 的 diff review 和测试。
- 第一次使用前一定要确认 `claude --version` 可用。
- Claude Code 可能需要 30 分钟到 2 小时，不要太早判定失败。
- 为了减少卡权限，默认使用 `bypassPermissions`；演示时要提醒只在可信项目中使用。
- 如果项目很大，Codex 应该先给 Claude Code 明确文件范围和验收标准。
- 不建议让 Claude Code 自动提交或部署；这些动作最好由 Codex 最后确认。

## 常见问题

### 这是不是 Claude MCP？

不是。它使用普通 Claude Code CLI。

### 为什么不用 Claude subagent？

因为这里的目标是稳定和简单。普通 CLI 更接近人类真实使用方式，也更容易排查问题。

### Claude Code 改坏了怎么办？

Codex 会审查真实 diff。不合格就拒绝并要求返工，最多 3 轮。

### 能不能让 Codex 自己写？

可以。非常小的机械改动、最终整合、或者你明确要求 Codex 接手时，Codex 可以直接修改。

## License

MIT
