---
name: paper-auto-writing
description: "Use this skill to drive AI-Scientist-v2 style research workflows in two modes: a subscription-session runner mode where Codex executes the reasoning and writing steps directly in chat, and an optional API-backed mode for the SakanaAI AI-Scientist-v2 repository. Trigger it when the user asks for $paper-auto-writing, AI-Scientist-v2 style research automation, topic file preparation, subscription-based paper drafting, startup command generation, runtime inspection, experiment troubleshooting, or PDF and log summarization."
---

# Paper Auto Writing

## Overview

Use this skill as an execution-oriented wrapper around `AI-Scientist-v2` and an interactive subscription-session paper runner.
Prefer subscription-session mode by default: let Codex perform ideation, outlining, analysis, drafting, critique, and revision directly in this conversation without assuming API credentials.

## Workflow

Follow this workflow in order unless the user explicitly asks for only one stage:

1. Choose the execution mode.
2. Check prerequisites and blockers for that mode.
3. Prepare the topic Markdown, outline, or research brief.
4. Either run the subscription-session workflow in chat or generate API-backed commands.
5. Summarize outputs, draft quality, failures, and next steps.

## Execution Mode Decision

Choose one mode before proposing commands:

- `subscription-runner`: Default mode. Use the current Codex conversation as the reasoning and writing engine. Do not assume any API key or local model bridge. Perform ideation, literature synthesis, paper outlining, drafting, revision, and reviewer-style critique inside the chat.
- `windows-prep`: Windows host without a confirmed Linux GPU runtime. Only prepare files, inspect environment, and generate commands.
- `wsl`: Windows host with WSL2 available. Prefer running Linux-side commands through WSL after validating CUDA and Python there.
- `remote-linux`: A Linux or remote GPU environment that can run the repository directly.

Read [references/runtime-modes.md](references/runtime-modes.md) when the operating context is unclear or mixed.

## Fast Path

For most requests, use this sequence:

1. If the user wants direct help now, use `subscription-runner` and start producing the research artifacts in chat.
2. If the topic file does not exist, generate one with `scripts/init_topic_template.py` or write the content directly in the conversation.
3. If the user explicitly wants repository execution, run `scripts/check_runtime.ps1` on Windows hosts or `scripts/check_runtime.py` on Linux/WSL.
4. Generate a concrete plan with `scripts/build_run_plan.py` only for the API-backed path.
5. If the user provides an experiment output directory, summarize it with `scripts/summarize_outputs.py`.

## Subscription-Runner Workflow

Use this as the default path when the user wants to rely on the Codex subscription session instead of API execution.

1. Clarify the research topic, target output, and desired paper style from the conversation.
2. Produce the topic brief or topic Markdown.
3. Generate candidate ideas, compare them, and pick one direction in chat.
4. Draft the paper structure section by section:
   - title
   - abstract
   - introduction
   - related work
   - method
   - experiment plan or analysis plan
   - limitations
   - conclusion
5. Critique the draft from a reviewer perspective and revise it.
6. If useful, save intermediate artifacts to local Markdown files in the user workspace.

Do not pretend this mode is equivalent to running the full upstream automated experiment pipeline.
Frame it as a Codex-guided manual execution of the research-writing workflow.

## Repository Expectations

Assume the target repository is `SakanaAI/AI-Scientist-v2` when the user chooses the API-backed path.
That path is tightly integrated with these repository entrypoints:

- `ai_scientist/perform_ideation_temp_free.py`
- `launch_scientist_bfts.py`
- `bfts_config.yaml`
- `ai_scientist/ideas/*.md`
- `experiments/<timestamp_idea>/`

Read [references/ai-scientist-v2.md](references/ai-scientist-v2.md) when you need the exact phase order, file roles, or known caveats.

## Command Planning Rules

- Prefer `subscription-runner` unless the user explicitly asks to execute the repository pipeline.
- Never imply that pure Windows can safely run the full GPU paper-generation pipeline.
- Prefer explicit paths in every generated command.
- Surface blockers before showing optimistic next steps.
- Warn that the repository executes LLM-written code and should run in an isolated environment.
- Treat `S2_API_KEY` as optional but mention rate-limit and citation tradeoffs if it is missing.
- Never claim that the subscription session can be mounted as a local API backend for Python scripts.

## Topic File Preparation

When the user asks to start a new research run, ensure a Markdown topic file exists with these sections:

- `Title`
- `Keywords`
- `TL;DR`
- `Abstract`

Use `scripts/init_topic_template.py` to create or normalize the file.
Read [references/prompt-templates.md](references/prompt-templates.md) for topic-writing patterns and parameter presets.

## API-Backed Run Planning

Use `scripts/build_run_plan.py` to produce a decision-ready plan for:

- ideation command
- paper-generation command
- required environment variables
- expected output files
- likely blockers for the current machine

Treat its output as the default command source only for the API-backed path.

## Subscription Output Expectations

In `subscription-runner` mode, produce one or more of these artifacts directly in chat or as local Markdown files:

- topic brief
- title options
- abstract draft
- outline
- full paper draft
- reviewer-style critique
- revision list
- final polished version

When needed, explicitly say which steps were completed manually by Codex in the subscription session versus which ones would require the upstream repository.

## Output Review

When the user points to an `experiments/...` directory:

1. Run `scripts/summarize_outputs.py`.
2. Report whether a PDF exists.
3. Report whether tree-search visualization and logs exist.
4. Highlight failure signals, incomplete stages, and the next recovery step.

## References

- [references/ai-scientist-v2.md](references/ai-scientist-v2.md): Repository-specific workflow, commands, outputs, and cautions.
- [references/subscription-runner.md](references/subscription-runner.md): Default in-chat workflow that uses the Codex subscription session instead of API execution.
- [references/runtime-modes.md](references/runtime-modes.md): Decision rules for Windows, WSL2, and remote Linux GPU setups.
- [references/prompt-templates.md](references/prompt-templates.md): Topic templates, prompting heuristics, and command presets.

## Scripts

- `scripts/check_runtime.ps1`: Windows host inspection for Python, WSL, GPU, API keys, and common repo paths.
- `scripts/check_runtime.py`: Cross-platform runtime inspection for Linux, WSL, or remote hosts.
- `scripts/init_topic_template.py`: Create a valid AI-Scientist-v2 topic Markdown file.
- `scripts/build_run_plan.py`: Generate exact next-step commands without executing them.
- `scripts/summarize_outputs.py`: Summarize experiment folders, PDFs, HTML visualizations, and logs.
