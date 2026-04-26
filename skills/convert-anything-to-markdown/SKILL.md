---
name: convert-anything-to-markdown
description: Convert many local file types into Markdown with microsoft/markitdown. Use when Codex needs to turn a PDF, DOCX, PPTX, XLSX, image, HTML file, audio file, JSON/XML/CSV, ZIP, or other supported file into Markdown for Obsidian, LLM input, note taking, summarization, or knowledge-base cleanup. Trigger on requests like "convert this to Markdown", "extract this file as Markdown", "turn this document into md", or "make this usable in Obsidian".
---

# Convert Anything To Markdown

Use this skill to convert a single local file into a Markdown file with a stable wrapper around `microsoft/markitdown`.

## Core Workflow

1. Confirm the input is a local file path.
2. If the user gave a remote URL, download it first or confirm where the downloaded file should live before converting it.
3. Prefer the bundled script at `scripts/convert_to_markdown.py` instead of ad hoc inline commands.
4. By default, write the output next to the source file with the same basename and a `.md` extension.
5. If the user only wants a preview, write to a temporary `.md` file first and then read or summarize that file.

## Run The Script

Use:

```bash
python scripts/convert_to_markdown.py <input_path>
python scripts/convert_to_markdown.py <input_path> --output <output_path>
```

Behavior:

- Validate that the input path exists and points to a file.
- Auto-install `markitdown[all]` with `python -m pip install "markitdown[all]"` if the package is missing.
- Convert with the Python API first.
- Write UTF-8 Markdown to disk.
- Print the absolute output path and whether auto-install happened.

## Output Rules

- Default output path: same directory as the source file, same basename, `.md` suffix.
- If the requested output path does not end in `.md`, keep the user's path exactly as given.
- Overwrite the target file if it already exists.

## Failure Handling

- If the path does not exist, stop with a clear file-not-found error.
- If the path is a directory, stop and ask for a single file instead.
- If conversion fails because the format is unsupported or the source is malformed, report that directly.
- If the source is very large, binary-heavy, or media-rich, warn that extraction quality and runtime may vary.
- Do not enable OCR, OpenAI image description, Azure Document Intelligence, or other optional cloud-enhanced paths unless the user explicitly asks for them.

## Notes

- Keep v1 focused on one file at a time.
- Do not add batch conversion, directory recursion, or remote-service parameters unless the user asks.
- If the resulting Markdown is noisy, keep the file and then help the user clean or restructure it as a separate step.
