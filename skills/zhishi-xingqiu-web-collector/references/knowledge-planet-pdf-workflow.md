# Knowledge Planet PDF Workflow

Use this reference when a Knowledge Planet group contains file-area PDFs that must be downloaded, converted, OCRed when needed, and merged into one Obsidian-ready Markdown note.

## When To Use

- The user asks for "all content" from a Knowledge Planet group and mentions PDFs, files, attachments, paid articles, or公众号补档.
- The browser is already logged in and the current account can access the group.
- The expected output is one classified Markdown note, not one note per PDF.

Do not bypass permissions. Only collect content visible or downloadable through the current account.

## Directory Contract

Create one intermediate task directory, usually under `chatgpt/<task_slug>/`.

Recommended layout:

- `pdfs/`: downloaded source PDFs
- `pdf_markdown/`: one Markdown file per PDF
- `page_snapshots/`: optional visible-page screenshots or copied page captures
- `file_api_aggregate.json`: Knowledge Planet file API response, normalized or raw
- `pdf_download_log.json`: one entry per attempted PDF download
- `pdf_ocr_log.json`: one entry per attempted PDF conversion/OCR
- `final_pdf_summary_build_log.json`: final assembly log

Only the final merged Markdown should be written to the user's destination vault/folder.

## Standard Run Order

1. Capture the visible group page first with `capture_browser_content.py` when page posts/comments are part of the request.
2. Recover the group id from `https://wx.zsxq.com/group/<group_id>`.
3. Fetch the group file API and download PDFs with `capture_zsxq_pdfs.py`.
4. Convert PDFs with `convert_pdfs_with_ocr.py`.
5. Build the final classified note with `build_zsxq_pdf_summary.py`.
6. Validate the final note for article counts, non-empty body sections, and UI noise.

## Commands

Use an existing API JSON when it has already been captured:

```powershell
python scripts/capture_zsxq_pdfs.py `
  --group-url "https://wx.zsxq.com/group/<group_id>" `
  --files-api-json "chatgpt/<task_slug>/file_api_probe.json" `
  --target-dir "chatgpt/<task_slug>"
```

Fetch the API directly when you have a valid browser cookie header:

```powershell
python scripts/capture_zsxq_pdfs.py `
  --group-url "https://wx.zsxq.com/group/<group_id>" `
  --cookie-header "<copied Cookie header>" `
  --target-dir "chatgpt/<task_slug>"
```

Convert downloaded PDFs, using `$convert-anything-to-markdown` first and local OCR if the result is empty:

```powershell
python scripts/convert_pdfs_with_ocr.py `
  --pdf-dir "chatgpt/<task_slug>/pdfs" `
  --output-dir "chatgpt/<task_slug>/pdf_markdown"
```

Build one classified Markdown note:

```powershell
python scripts/build_zsxq_pdf_summary.py `
  --task-dir "chatgpt/<task_slug>" `
  --output-dir "仓库" `
  --file-stem "<星球名>-知识星球全量内容汇总-YYYY-MM-DD" `
  --title "<星球名>知识星球全量内容汇总" `
  --source-url "https://wx.zsxq.com/group/<group_id>" `
  --capture-log "chatgpt/<task_slug>/<capture>.capture.json"
```

## Conversion Policy

- Run `convert-anything-to-markdown/scripts/convert_to_markdown.py` first.
- If the resulting Markdown has too little meaningful text, treat it as a scanned PDF and run local OCR.
- OCR fallback uses local dependencies only, such as `pypdfium2` and `rapidocr_onnxruntime`.
- Do not use cloud OCR, OpenAI image description, or remote document intelligence unless the user explicitly asks.

## Classification And Markdown Shape

Default final shape:

```md
# <星球名>知识星球全量内容汇总

## 目录
## 采集概况
## 一、入口与认识渠道
### 文章 1｜...
#### 原帖
#### 可见评论
#### 正文
## 二、约会设计与关系推进
## 三、礼物与关系维护
## 四、观念补充与旧文存档
## 附录：页面可复制内容与采集日志
```

If the default categories do not fit the corpus, pass `--category-map-json` with a JSON object mapping category headings to title keywords.

## Cleaning Rules

Remove obvious non-content:

- PDF conversion headers and OCR metadata
- page markers such as `? 1 ?`, `## Page 1`
- repeated source lines and per-page watermarks when they are not part of the article
- `主题加载中`, `查看详情`, `展开全部`, `迅雷下载助手`
- browser navigation, Knowledge Planet sidebar labels, plugin banners

Preserve uncertain article text rather than deleting aggressively.

## Failure Handling

- A failed PDF download or OCR conversion must not stop the whole task.
- Record failures in the relevant log and in the final note's "采集日志与缺失项" section.
- Keep successful PDFs and converted Markdown even if later files fail.

## Validation Checklist

- Final Markdown exists in the requested output directory.
- Article count matches the file API PDF count, unless failures are explicitly logged.
- Every successful PDF has one `#### 正文` section.
- Main Obsidian outline is not polluted by page markers.
- No common UI noise remains: `主题加载中`, `查看详情`, `展开全部`, `迅雷下载助手`, `? 1 ?`, `?? PDF?`.
