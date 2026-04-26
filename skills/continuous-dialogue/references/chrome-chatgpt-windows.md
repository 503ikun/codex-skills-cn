# Chrome + ChatGPT Web on Windows

Use this reference when the user wants Codex to operate inside Chrome on Windows, especially on ChatGPT web or ChatGPT Projects, one round at a time, with external checkpoint capture.

## Environment Preconditions

- Windows desktop environment
- `functions.shell_command` available
- Chrome already installed and already logged into the target site
- PowerShell allowed
- Windows UI Automation assemblies available
- Clipboard access available for reply recovery

## Page Re-Anchoring Strategy

Always re-anchor before input, send, copy, or completion checks.

Preferred sequence:

1. Find the intended Chrome main window by title.
2. If multiple candidates exist, prefer the one whose `MainWindowTitle` best matches the requested tab or project name.
3. Confirm the surface by reading the UI Automation tree.
4. Do not continue until all of the following are true:
   - input box is visible
   - send button or equivalent action exists
   - recent reply region is visible
   - latest reply controls such as `复制回复` or equivalent are visible when expected

Best-effort additional hints:

- Use tab title hints when available.
- Use recent URL hints only as secondary evidence.
- If the page drifts to another project, tab, or site, stop and re-anchor before the next round.

## ChatGPT Configuration Strategy

For ChatGPT web:

- Do not hardcode one model string by default.
- First inspect the visible model switcher entry.
- The entry label may vary by page shape, for example `切换模型` or `模型选择器`.
- Prefer the newest visible frontier reasoning model.
- Then move the reasoning or thinking intensity to the highest visible option.
- If the user explicitly requires `gpt-5.4` or a named mode, verify that the UI actually shows it.
- If the requested model is not present, record a fallback to the highest visible option.

The goal is truthful execution, not pretending a UI state exists.

## Round Execution Rules

- Send exactly one question per round.
- Wait until the answer fully finishes.
- Recover the answer outside the browser before entering the next round.
- Make the next question explicitly build on the previous answer's conclusion, gap, or contradiction.

## Completion Rules

Do not consider a round complete until all of these are satisfied:

- a new user message block exists
- a streaming control such as `停止流式传输` appeared when relevant and later disappeared
- the latest reply region is visible
- copying the latest reply returns content that matches the current round topic

If the copied content clearly belongs to the previous round, treat the recovery as failed and retry after re-anchoring.

## Preferred Recovery Strategy

When available:

1. Confirm the newest reply region visually through UI Automation.
2. Invoke the latest `复制回复` button.
3. Read clipboard text.
4. Verify thematic match with the current round before storing it.

If clipboard copy fails, use a second-layer fallback: extract the latest assistant reply text from the newest reply region in the UI Automation tail. Prefer clipboard when it works; use tail extraction only as a recovery path.

## Failure Recovery Rules

### Send Failure

If the message does not leave the input box:

- Prefer `InvokePattern` on the send button.
- If needed, retry after re-anchoring the input surface.
- Do not assume a click succeeded unless a new user message block appears.

### Wrong Reply Copied

If `复制回复` returns the previous round:

- re-read the page tail
- confirm the newest reply region
- copy again only after the current reply visibly completed

### Topic Drift

If the assistant reply is clearly unrelated:

- mark the round as invalid
- restate the intended topic in the same thread if continuing there
- do not let the drifted reply become the basis for the next round

### Page or Project Drift

If the page is no longer the intended project or tab:

- stop automation
- re-anchor to the correct window or tab
- verify the input box and latest reply region again before continuing

## Checkpoint Format

Store each round in an external checkpoint:

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

Use the checkpoint as the source of truth for final Markdown generation.

## Default Final Markdown Structure

Prefer:

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

Default policy:

- summary first
- full original dialogue after
- preserve full answers
- emit a `.md` file when the user wants Obsidian-friendly output
