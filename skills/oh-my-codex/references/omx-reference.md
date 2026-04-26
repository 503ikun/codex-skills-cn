# OMX Reference

Source snapshot captured on 2026-04-22 from:
- https://github.com/Yeachan-Heo/oh-my-codex
- https://raw.githubusercontent.com/Yeachan-Heo/oh-my-codex/main/README.md
- https://raw.githubusercontent.com/Yeachan-Heo/oh-my-codex/main/package.json

Version snapshot:
- npm package: `oh-my-codex`
- observed version: `0.14.2`
- package description: `Multi-agent orchestration layer for OpenAI Codex CLI`

## What OMX Is

OMX is a workflow layer for OpenAI Codex CLI. It keeps Codex as the execution engine and adds:
- stronger default session startup
- reusable workflow keywords
- guidance through `AGENTS.md`
- durable state under `.omx/`

Do not describe OMX as replacing Codex. Describe it as a runtime/workflow layer around Codex.

## Default Recommended Path

Upstream recommends:
- Node.js 20+
- Codex CLI installed globally
- macOS or Linux as the default supported path

Canonical install:

```bash
npm install -g @openai/codex oh-my-codex
```

Canonical launch:

```bash
omx --madmax --high
```

## Validation Commands

Use these when a user wants setup verification:

```bash
omx doctor
codex login status
omx exec --skip-git-repo-check -C . "Reply with exactly OMX-EXEC-OK"
```

Interpretation:
- `omx doctor` checks install shape and runtime prerequisites.
- `codex login status` checks auth visibility for the active Codex profile.
- `omx exec ...` proves the active runtime can complete a real model call.

## Canonical Workflow

Use this order unless the user asks for a narrower surface:

1. `$deep-interview "..."` for clarifying intent, boundaries, and non-goals
2. `$ralplan "..."` for approving the implementation plan and tradeoffs
3. `$ralph "..."` for persistent completion loops with one owner
4. `$team "..."` for coordinated parallel execution when the work is large enough

Examples from upstream:

```text
$deep-interview "clarify the authentication change"
$ralplan "approve the auth plan and review tradeoffs"
$ralph "carry the approved plan to completion"
$team 3:executor "execute the approved plan in parallel"
```

## Common Surfaces

- `$deep-interview`: clarification and boundary finding
- `$ralplan`: plan review and approval
- `$ralph`: persistent execution
- `$team`: coordinated parallel execution
- `/skills`: browse installed skills

## Operator Surfaces

Useful but not the main onboarding path:
- `omx setup`
- `omx update`
- `omx doctor`
- `omx hud --watch`
- `omx explore --prompt "..."`
- `omx sparkshell ...`
- `omx wiki ...`
- `omx team ...`

## Platform Caveats

State these clearly when relevant:

- Upstream says the recommended default is **macOS or Linux with Codex CLI**.
- Upstream says **native Windows and Codex App are not the default experience**, may break, may behave inconsistently, and currently receive less support.
- Native Windows team mode may rely on `psmux`.
- WSL2 is generally the better Windows-hosted path when users want the tmux-oriented runtime.

## Troubleshooting Guidance

When `omx doctor` looks healthy but execution fails, check:
- the shell/profile that actually launches Codex
- whether the expected `CODEX_HOME` is active
- whether the right `~/.codex/config.toml` is visible
- whether a proxy or custom `openai_base_url` is required

If a team session is stale or dead, upstream suggests:

```bash
omx team shutdown <team-name> --force --confirm-issues
omx cancel
omx doctor --team
```
