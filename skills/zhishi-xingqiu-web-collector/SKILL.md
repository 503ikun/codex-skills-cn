---
name: zhishi-xingqiu-web-collector
description: Capture Knowledge Planet (知识星球), Xiaoetong (小鹅通), paid columns, member courses, browser-visible web content, and logged-in Chrome/CDP/API-visible content into Markdown, including text, images, scrolling, pagination, de-duplication, and Markdown assembly. Use when Codex needs to save Knowledge Planet posts, Xiaoetong articles/courses, paid-course member bundles, web articles, feeds, list pages, or browser-visible content into a user-specified folder as Markdown notes with linked assets.
---

# 知识星球（网页信息采集器）

Use this skill to turn Knowledge Planet or other browser-visible web content into a new Markdown note in a user-specified directory.

This skill is optimized for browser capture workflows such as Knowledge Planet pages, article pages, feeds, knowledge platforms, paginated lists, and long scrolling pages. It is not the default skill for desktop-wide OCR or arbitrary native applications.

Also use this skill for Knowledge Planet file-area/PDF tasks when the user asks to collect PDFs, paid-article backups, or all group-visible content into one Markdown note. In that mode, combine the browser capture workflow with the PDF download, Markdown conversion, OCR fallback, and classified summary workflow described below.

Also use this skill for Xiaoetong paid columns, paid courses, member products, "我的已购" pages, and long course catalogs when the user is already logged in and asks to back up or organize content they can normally view. Prefer the logged-in Chrome + CDP/API workflow when UI scrolling/copying is slow, when returning from an item refreshes the catalog, or when a paid member product contains many nested columns/courses.

## High-Speed Paid Course/CDP Path

Use this path before long UI automation when the page is Xiaoetong, a paid column, a course catalog, a member product, or any browser-visible paid knowledge platform with many items.

1. Safety boundary.
   Use only the current logged-in browser session and content the account can normally see. Do not bypass login, payment, CAPTCHA, rate limits, or permission checks. Do not scan broad browser history/cache.
2. Baseline and entitlement check.
   Capture the visible page URL, title, body text, screenshot, and Network sample. If the catalog tab is empty but the user owns the product, inspect "我的已购" and learning-record APIs before assuming no content exists.
3. Choose the fastest supported route.
   Prefer page-context `fetch(..., { credentials: "include" })` over mouse copying. For linear paid article columns, use detail plus previous/next APIs. For member products/course bundles, build a resource tree from member-column/single/course APIs, then fetch each detail.
4. Save incrementally.
   Write raw JSON and progress JSONL after every batch. Resume from existing raw records instead of restarting.
5. Build the final Markdown.
   For company/article research, use company/industry builders. For courses/member bundles, use one themed folder, a master index, and one Markdown per parent course/column; sort lessons old-to-new.
6. Stop debugging Chrome.
   When paused or complete, explicitly stop only the Chrome process launched with `--remote-debugging-port=9222`.

For the full decision tree and Xiaoetong API hints, read [references/cdp-paid-course-workflow.md](references/cdp-paid-course-workflow.md).

## Core Workflow

1. Confirm the destination directory.
   Require an explicit target directory unless the user already gave one.
2. Re-anchor the browser window.
   Prefer the current foreground browser window and the visible active tab.
3. Capture one baseline round first.
   Copy the visible page text, save a visible-page screenshot, and record the current URL.
4. Continue page expansion.
   Prefer scrolling first. If scrolling stops producing new content, probe for pagination and continue on the next page when possible.
5. Preserve images.
   Prefer direct image URL downloads when the page text exposes them. If not, keep visible-page screenshots so the Markdown still preserves image-bearing page state.
6. Merge and de-duplicate.
   Remove UI noise, combine repeated copies, and keep the longer or richer version of repeated blocks.
7. Build a single Markdown output.
   Save one Markdown file plus a sibling asset folder containing screenshots and any downloaded images.

## Knowledge Planet PDF Workflow

Use this path when a Knowledge Planet group contains PDFs or file-area material that should be embedded as full text in one Markdown note.

Default order:

1. Confirm the destination directory and intermediate task directory.
   Use `chatgpt/<task_slug>/` for intermediate files and write only the final Markdown into the user's requested output directory.
2. Re-anchor the logged-in Chrome tab.
   Record the current Knowledge Planet group URL and group id. Do not open a separate logged-out browser session.
3. Capture the main feed when posts/comments are part of the requested scope.
   Use `scripts/capture_browser_content.py` and keep its capture log for the final appendix.
4. Capture file-area PDFs.
   Use `scripts/capture_zsxq_pdfs.py` with either a copied browser cookie header or an already saved files API JSON.
5. Convert PDFs to Markdown.
   Use `scripts/convert_pdfs_with_ocr.py`, which calls `$convert-anything-to-markdown` first and falls back to local OCR when the converted text is empty or too short.
6. Build the classified summary.
   Use `scripts/build_zsxq_pdf_summary.py` to create one final Markdown containing the original post, visible comments, cleaned PDF body, and collection logs.

For the full operating contract, read [references/knowledge-planet-pdf-workflow.md](references/knowledge-planet-pdf-workflow.md).

### PDF Output Shape

The final Markdown should use this structure by default:

```md
# <星球名>知识星球全量内容汇总

## 目录
## 采集概况
## 一、入口与认识渠道
## 二、约会设计与关系推进
## 三、礼物与关系维护
## 四、观念补充与旧文存档
## 附录：页面可复制内容与采集日志
```

Each article section should contain:

- `### 文章 N｜标题`
- `#### 原帖`
- `#### 可见评论` when comments are available
- `#### 正文`

When the default categories do not fit the corpus, pass a `--category-map-json` file to the summary builder. Do not summarize or rewrite the source article text unless the user asks; only clean obvious OCR and UI noise.

## Default Behavior

- Require an explicit destination directory from the user.
- Use the current foreground browser page as the capture source.
- Write one Markdown file per task by default.
- Save image assets in a sibling resource directory and reference them from Markdown with relative paths.
- Scroll before attempting pagination.
- Stop only after repeated rounds show no new content and pagination probing cannot advance further.

## Browser Capture Path

Use the main script at [scripts/capture_browser_content.py](scripts/capture_browser_content.py) to collect raw rounds.

Default collection order:

1. Activate the browser window by title substring.
2. Copy the current URL from the address bar.
3. Click into the page body and copy the full selectable page text.
4. Save a visible-page screenshot.
5. Extract and download directly exposed image URLs when possible.
6. Scroll through the page in controlled steps.
7. If several rounds are unchanged, probe pagination via keyboard focus for labels such as `下一页` or `next`.
8. Save a structured capture log.

Use the assembly script at [scripts/build_markdown.py](scripts/build_markdown.py) to transform the capture log into the final Markdown note.

## PDF/File-Area Scripts

Use these scripts for Knowledge Planet groups with downloadable PDFs:

- [scripts/capture_zsxq_pdfs.py](scripts/capture_zsxq_pdfs.py): parse group id, fetch or reuse the file API result, download PDFs, and write `file_api_aggregate.json` plus `pdf_download_log.json`.
- [scripts/convert_pdfs_with_ocr.py](scripts/convert_pdfs_with_ocr.py): batch-convert PDFs with `$convert-anything-to-markdown` first; if the result has too little meaningful text, render pages locally and OCR them.
- [scripts/build_zsxq_pdf_summary.py](scripts/build_zsxq_pdf_summary.py): merge file API metadata, topic text, visible comments, converted PDF Markdown, and optional browser capture text into one classified Markdown note.

Example:

```powershell
python scripts/capture_zsxq_pdfs.py --group-url "https://wx.zsxq.com/group/<group_id>" --cookie-header "<Cookie header>" --target-dir "chatgpt/<task_slug>"
python scripts/convert_pdfs_with_ocr.py --pdf-dir "chatgpt/<task_slug>/pdfs" --output-dir "chatgpt/<task_slug>/pdf_markdown"
python scripts/build_zsxq_pdf_summary.py --task-dir "chatgpt/<task_slug>" --output-dir "仓库" --file-stem "<星球名>-知识星球全量内容汇总-YYYY-MM-DD" --title "<星球名>知识星球全量内容汇总" --source-url "https://wx.zsxq.com/group/<group_id>"
```

## Output Shape

The generated Markdown should usually include:

- title
- capture time
- source URL
- browser window hint
- total content block count
- capture coverage summary
- content blocks
- downloaded images
- visible-page screenshots

Default section style:

```md
# Title

- 采集时间：
- 来源页面：
- 目标目录：
- 总内容块数：

## 内容块 1

...

## 图片资源

![](assets/...)

## 页面截图

![](assets/...)
```

## Noise Removal Rules

Treat obvious UI strings as noise unless the page clearly uses them as real content:

- navigation labels
- `查看详情`
- `展开全部`
- `写评论`
- `主题加载中`
- `没有更多了`
- extension banners
- repeated site chrome text

Prefer keeping uncertain content over deleting it aggressively.

For PDF/OCR outputs, also remove:

- conversion headers and OCR metadata
- page markers such as `? 1 ?` or `## Page 1`
- repeated source/watermark lines that occur on every page
- empty OCR placeholders

## Pagination Rules

When scrolling stops producing new material:

1. Probe keyboard focus with `Tab`.
2. Look for clipboard-visible labels such as `下一页`, `next`, `>`, or `›`.
3. Press `Enter` only when the probe suggests a real next-page control.
4. Re-capture the page after navigation and continue scrolling.

If pagination cannot be advanced safely, record that in the capture log and finish with the material already collected.

## Validation

After editing this skill:

1. Run `python scripts/capture_browser_content.py --help`
2. Run `python scripts/build_markdown.py --help`
3. Run `python scripts/capture_zsxq_pdfs.py --help`
4. Run `python scripts/convert_pdfs_with_ocr.py --help`
5. Run `python scripts/build_zsxq_pdf_summary.py --help`
6. Run `python scripts/capture_paid_course_cdp.py --help`
7. Run `python scripts/build_company_article_markdown.py --help`
8. Run `python scripts/build_paid_course_markdown.py --help`
9. Run `python C:\Users\Administrator\.codex\skills\.system\skill-creator\scripts\quick_validate.py <skill-dir>`

For browser-specific operating details and field semantics, read [references/browser-capture-workflow.md](references/browser-capture-workflow.md).
For Knowledge Planet file-area/PDF operating details, read [references/knowledge-planet-pdf-workflow.md](references/knowledge-planet-pdf-workflow.md).
