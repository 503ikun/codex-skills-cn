# Prompt Templates

## Topic Markdown Template

Use this structure for new topic files:

```markdown
# Title: <short workshop-style research title>

## Keywords
keyword 1, keyword 2, keyword 3

## TL;DR
One or two sentences describing the research direction and desired contribution.

## Abstract
One short paragraph describing the problem, why it matters, the experiment direction, and the intended novelty.
```

## Topic Writing Heuristics

- Keep the title workshop-like rather than product-marketing-like.
- Use 3-6 concise keywords.
- Write the `TL;DR` as a direct problem statement plus proposed angle.
- In the abstract, mention the domain, failure mode or gap, method direction, and the value of the result.

## Good Trigger Prompts

- `Use $paper-auto-writing to act as my subscription-session paper writer and help me draft this paper in chat.`
- `Use $paper-auto-writing to check whether this machine can prepare or run AI-Scientist-v2.`
- `Use $paper-auto-writing to create a topic file for retrieval-augmented code generation evaluation.`
- `Use $paper-auto-writing to build the ideation and experiment commands for this topic file.`
- `Use $paper-auto-writing to summarize this experiments directory and tell me why no PDF was produced.`

## Subscription-Session Prompts

- `Use $paper-auto-writing to generate three research ideas for this topic and pick the strongest one.`
- `Use $paper-auto-writing to turn this idea into a workshop-style abstract and introduction.`
- `Use $paper-auto-writing to critique this draft like a reviewer and then rewrite it.`
- `Use $paper-auto-writing to produce a full Markdown paper draft from this brief.`

## Suggested Defaults

### Conservative ideation

- `--max-num-generations 8`
- `--num-reflections 3`
- `--model gpt-5.2-codex`

Use this when you want a cheaper and faster first pass.

### Broader ideation

- `--max-num-generations 20`
- `--num-reflections 5`
- `--model gpt-5.2-codex`

Use this when novelty exploration matters more than speed.

### Output review checklist

When summarizing a run, always check for:

- final PDF
- `unified_tree_viz.html`
- latest log files
- failed or incomplete stages
- likely next action
