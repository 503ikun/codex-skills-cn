# AI-Scientist-v2 Notes

## Purpose

Use this reference when the user explicitly wants the repository-specific workflow and guardrails for `SakanaAI/AI-Scientist-v2` instead of the default subscription-session runner mode.

## Core Pipeline

The repository workflow is:

1. Prepare a topic Markdown file.
2. Run `ai_scientist/perform_ideation_temp_free.py` to generate ideas JSON.
3. Run `launch_scientist_bfts.py` with the generated JSON.
4. Inspect the experiment directory for logs, tree visualization, and the final PDF.

## Expected Topic File Shape

The topic Markdown should include:

- `Title`
- `Keywords`
- `TL;DR`
- `Abstract`

The upstream example is `ai_scientist/ideas/i_cant_believe_its_not_better.md`.

## Example Ideation Command

```bash
python ai_scientist/perform_ideation_temp_free.py \
  --workshop-file "ai_scientist/ideas/my_research_topic.md" \
  --model gpt-4o-2024-05-13 \
  --max-num-generations 20 \
  --num-reflections 5
```

Expected ideation output:

- `ai_scientist/ideas/my_research_topic.json`

## Example Experiment Command

```bash
python launch_scientist_bfts.py \
  --load_ideas "ai_scientist/ideas/my_research_topic.json" \
  --load_code \
  --add_dataset_ref \
  --model_writeup o1-preview-2024-09-12 \
  --model_citation gpt-4o-2024-11-20 \
  --model_review gpt-4o-2024-11-20 \
  --model_agg_plots o3-mini-2025-01-31 \
  --num_cite_rounds 20
```

## Runtime Assumptions

- Upstream expects Linux with NVIDIA GPU, CUDA, and PyTorch.
- Python 3.11 is the documented baseline.
- `OPENAI_API_KEY` or another supported model credential is required.
- `S2_API_KEY` is optional but useful for literature search and citation throughput.

## Codex API Note

This skill can default its generated commands to `gpt-5.2-codex`, but that still requires an OpenAI API key.
Do not assume the Codex desktop session or this chat thread can be used directly by local Python processes without API credentials.
Use this repository-backed path only when the user wants true local pipeline execution.

## Important Files

- `launch_scientist_bfts.py`
- `bfts_config.yaml`
- `ai_scientist/perform_ideation_temp_free.py`
- `ai_scientist/ideas/`
- `experiments/`

## Output Expectations

During a successful run, expect:

- a timestamped directory inside `experiments/`
- logs under `experiments/<run>/logs/`
- `logs/0-run/unified_tree_viz.html`
- a final PDF at `experiments/<run>/<run>.pdf`

## Safety

The upstream repository warns that it executes LLM-written code.
Prefer Docker, an isolated Linux host, or another sandboxed runtime.
Do not present this workflow as safe to run directly on a general-purpose Windows desktop.
