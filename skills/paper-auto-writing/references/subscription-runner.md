# Subscription Runner

## Purpose

Use this reference when the user wants to rely on the active Codex subscription session instead of configuring API credentials for local Python scripts.

## What This Mode Is

This mode treats the current Codex conversation as the reasoning and writing engine.
Codex performs the research-writing workflow step by step in chat and optionally saves artifacts to local Markdown files.

## What This Mode Is Not

- It is not a bridge that turns the subscription session into a local API.
- It is not a way to let `AI-Scientist-v2` call this chat window directly.
- It does not execute the full upstream autonomous experiment pipeline.

## Default Workflow

1. Define the topic and desired output.
2. Produce a topic brief.
3. Generate several candidate ideas.
4. Select one idea and explain why.
5. Draft the paper structure.
6. Expand sections into prose.
7. Critique the draft like a reviewer.
8. Revise and polish the draft.

## Good Tasks For This Mode

- topic exploration
- paper angle comparison
- title and abstract drafting
- introduction and related work drafting
- method framing
- experiment-plan drafting
- reviewer-style feedback
- rewriting for clarity, tone, or publishability

## Limits

- No local Python script can inherit the chat session as a hidden backend.
- Claims about experiments must stay grounded in user-provided evidence, local files, or explicit assumptions.
- If no real experiment results exist, clearly label experiment sections as plans, hypothetical results, or placeholders.

## Output Style

Prefer concrete artifacts over meta discussion:

- Markdown-ready drafts
- section-by-section revisions
- comparison tables when choosing among ideas
- explicit assumption labels where evidence is missing
