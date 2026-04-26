---
name: "continuous-dialogue"
description: "Run long, connected, multi-round conversations that need pacing, continuity, checkpoints, and final structured capture. Use when Codex needs to continue a dialogue round by round, especially in Chrome or a browser-based ChatGPT/Projects workflow, wait for each reply to finish before asking the next question, capture each round outside the browser, and deliver the result as Markdown or an Obsidian-ready note."
---

# Continuous Dialogue

Use this skill when Codex needs to carry a conversation across many linked rounds, preserve continuity, and turn the result into a structured Markdown deliverable.

This skill is now optimized for Chrome + ChatGPT web workflows, while still supporting general multi-round dialogue work.

## Core Workflow

1. Clarify the target outcome.
   Capture the conversation goal, intended audience, expected number of rounds, desired tone, and final artifact.
2. Choose the execution surface.
   Prefer the logged-in browser surface the user explicitly named.
3. Re-anchor the page before each meaningful action.
   Confirm the correct Chrome window, target tab or project, usable input box, and reply controls.
4. Validate the model and reasoning configuration.
   For ChatGPT web, prefer the newest frontier reasoning model visible in the UI and the highest visible reasoning or thinking intensity. If the user explicitly names a model such as `gpt-5.4`, first verify that the UI shows it; if not, record a fallback to the highest visible option.
5. Run one validation round first.
   Send one question, wait for the reply to fully finish, and confirm the answer can be recovered outside the browser.
6. Continue one round at a time.
   Ask only one question per round. Do not enter the next round until the previous answer has been fully recovered.
7. Capture outputs continuously.
   Save each round outside the browser as soon as it completes.
8. Normalize into a Markdown artifact.
   Deliver a high-density summary first, then preserve the full dialogue as an appendix.

## Browser-First Path

Use this path when the user explicitly wants Codex to operate in Chrome or another browser, especially ChatGPT web or ChatGPT Projects.

Workflow:

- Re-anchor the correct Chrome window before every browser action.
- Confirm the target page is readable through UI Automation before sending text.
- Use one question per round.
- Wait for each answer to complete before asking the next question.
- Recover each answer outside the browser immediately after completion.
- Keep an external checkpoint so UI drift does not destroy the final deliverable.

For the Windows + Chrome + ChatGPT web execution details, read [references/chrome-chatgpt-windows.md](references/chrome-chatgpt-windows.md).

For repeatable UI Automation actions, prefer the bundled PowerShell helper at [scripts/chrome-chatgpt-uia.ps1](scripts/chrome-chatgpt-uia.ps1) instead of rewriting long inline PowerShell every time.

## Execution Paths

### Primary: Chrome + ChatGPT Web

Use this path when the user wants Codex to continue a conversation inside ChatGPT web or Projects.

Required posture:

- Re-anchor the active Chrome window before each step.
- Verify model and reasoning intensity before the first validation round.
- Validate one round end to end before attempting a longer run.
- Capture each round outside the browser immediately.

### Fallback A: Same Surface, Slower Pace

Use this path when the browser is usable but unstable.

Workflow:

- Re-anchor after every drift or failure.
- Slow down to one controlled round at a time.
- Prefer short controlled inputs over large pasted batches.
- Re-copy the latest reply only after verifying the newest reply region.

### Fallback B: Local Completion With Preserved Deliverable

Use this path when the external surface is too unstable to trust.

Workflow:

- Preserve the same round sequence locally in the current thread.
- Keep the intended structure, continuity, and final artifact.
- Note the fallback clearly so the user can later replay the dialogue in the original browser surface if needed.

## Continuity Rules

- Carry forward the user goal, constraints, open questions, and prior conclusions from one round to the next.
- Make each new round explicitly build on what the previous round resolved.
- If a round stalls, restate the current objective and the next unanswered question.
- Stop and re-anchor when the active surface no longer matches the intended project, tab, or site.
- In browser workflows, do not consider a round complete until the answer is both visibly complete and externally recovered.

## Browser Guardrails

- Prefer Windows UI Automation through `functions.shell_command` for Chrome + ChatGPT on Windows.
- Verify the target window before any input or button action.
- For ChatGPT web, do not hardcode a single model string unless the user explicitly requires it.
- Prefer the highest visible reasoning mode available in the UI.
- If the requested model or reasoning mode is missing, record the fallback instead of pretending it exists.
- Treat “reply finished” and “reply captured” as separate checkpoints.
- If copied content does not match the current round topic, treat it as a failed recovery and retry after re-anchoring.

## Capture Rules

Save every completed round in an external checkpoint with this shape:

```json
[
  {
    "round": 1,
    "question": "...",
    "answer": "...",
    "conclusion": "...",
    "next_basis": "..."
  }
]
```

Do not wait until the end to reconstruct rounds from memory.

## Standard Output Shape

The final deliverable should usually include:

- conversation goal
- round plan
- continuity rules or operating assumptions
- a high-density summary
- a reusable framework, checklist, or template
- complete multi-round dialogue
- next steps

## Markdown Artifact Pattern

When the user wants notes, Markdown, or an Obsidian-ready result, prefer this structure:

```md
# Title

## High-Density Conclusions
## Rough Valuation
## Financial Report Tracking Framework
## Judgment Revision Mechanism
## Full Dialogue
## Round 1
## Round 2
...
```

Default artifact strategy:

- Put the compressed working note first.
- Put the full round-by-round original dialogue after it.
- Preserve complete answers instead of replacing them with summaries.
- If the user asks for Obsidian-friendly output, default to a `.md` file.
