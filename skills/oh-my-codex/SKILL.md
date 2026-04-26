---
name: oh-my-codex
description: Explain, evaluate, install, and operate the oh-my-codex (OMX) workflow layer for OpenAI Codex. Use when users mention oh-my-codex, OMX, `omx` commands, `$deep-interview`, `$ralplan`, `$ralph`, or `$team`, or when they ask in Chinese for OMX工作流, OMX助手, OMX安装, OMX配置, OMX排错, 深度访谈, 规划审批, 持续执行, or 并行团队执行.
---

# Oh My Codex

Use this skill as a practical adapter for the upstream oh-my-codex project. Treat OMX as a workflow layer around Codex, not as a replacement for Codex itself.

## Triage First

1. Identify whether the user wants one of these outcomes:
   - understand what OMX is
   - decide whether OMX fits their environment
   - install or refresh OMX
   - validate or troubleshoot an existing OMX setup
   - translate OMX concepts into an ordinary Codex workflow
2. Check platform fit early.
3. Prefer the canonical commands and workflow names from `references/omx-reference.md`.

## State Platform Fit Clearly

- Say early that upstream recommends **macOS or Linux with Codex CLI** as the default path.
- Say explicitly that **native Windows and Codex App are less supported** and may behave inconsistently.
- If the user is on a less-supported path, do not oversell compatibility. Offer either:
  - best-effort OMX guidance with caveats, or
  - a lighter Codex-only alternative that borrows the same workflow ideas without full OMX runtime adoption.

## Handle The Main Task Types

### Explain OMX

- Describe OMX as a workflow/orchestration layer for Codex.
- Emphasize the canonical flow:
  1. `$deep-interview` for clarification
  2. `$ralplan` for plan approval and tradeoff review
  3. `$ralph` or `$team` for execution
- Mention `.omx/` as the place where OMX stores durable project state.

### Install Or Refresh OMX

- Prefer the shortest path that matches the user's goal.
- Use the upstream quick-start commands from `references/omx-reference.md`.
- Include validation, not just installation:
  - `omx doctor`
  - `codex login status`
  - `omx exec --skip-git-repo-check -C . "Reply with exactly OMX-EXEC-OK"`
- If the user is on Windows or Codex App, explain that passing `omx doctor` does not guarantee a smooth runtime experience in their environment.

### Troubleshoot OMX

- Separate install-shape problems from real execution problems.
- Treat `omx doctor` as structural validation only.
- If execution still fails, inspect auth visibility, `CODEX_HOME`, active config, and any custom base URL or proxy assumptions.
- Prefer quoting the exact command to rerun and the exact file or environment surface to inspect.

### Translate OMX Into Plain Codex

- If the user wants the OMX benefits without adopting the runtime, translate the workflow into plain language:
  - clarify first
  - approve a plan
  - choose persistent single-owner execution or coordinated parallel execution
- Keep the mapping conceptual instead of pretending native OMX features already exist.

## Use References Sparingly

- Read `references/omx-reference.md` when you need canonical commands, workflow order, current package snapshot, or platform caveats.
- Do not paste the whole reference into your response. Summarize only the parts relevant to the user request.
