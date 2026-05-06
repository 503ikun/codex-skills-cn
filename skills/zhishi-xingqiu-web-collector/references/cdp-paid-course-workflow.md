# CDP Paid Course Workflow

Use this workflow for Xiaoetong (小鹅通), paid columns, course catalogs, member products, "我的已购" entries, and other logged-in browser-visible article platforms when ordinary UI scrolling/copying is too slow or loses list position.

## Safety contract

- Use only the account/session the user has already logged into and can normally view.
- Do not bypass login, payment, CAPTCHA, rate limits, or access controls.
- Do not scan broad browser history or unrelated cache; target only the current page, host, and discovered page requests.
- Before any long run, tell the user the PID, task directory, progress log, and exact stop command.
- Stop the Chrome debugging process explicitly when capture is complete or paused.

## Decision tree

1. Start with visible-page capture for a baseline.
   Record current URL, visible text, screenshots, and a small sample of article entries.
2. If returning from an article refreshes the catalog, try the new-tab approach.
   Keep the catalog tab in place, copy/open each visible article in a new tab, capture text, close the tab, then scroll once to the next batch.
3. If article count is large or UI capture is still slow, use CDP.
   Restart or open Chrome with a local debugging port and the same logged-in profile. Connect to the current page, inspect DOM text and Network responses, and identify list/detail APIs.
4. Prefer page-context API calls.
   Run `fetch(..., { credentials: "include" })` in the page context so requests use only the logged-in session that the page itself has.
5. Traverse with platform APIs when available.
   On Xiaoetong, detail and previous/next endpoints may expose a complete article chain. Use a 3-5 article sample first, then run sequential traversal with progress logging and low delay.
6. Handle member-product exceptions.
   If the product page says it has many updates but its catalog tab shows `暂无内容`, do not assume the membership is empty. Open or query "我的已购" to find the purchased product, then follow the `redirect_url` back to the product and inspect member APIs such as `member.column_items`, `member.single_items`, and `column.items`.
7. Fall back progressively.
   If APIs cannot be reused, extract article URLs/resource IDs from DOM or Network responses and navigate one page at a time with CDP. Only return to mouse/UI automation for image-only or broken records.

## Chrome debugging launch

Use the real local Chrome path and the user's existing profile. Chrome may reject remote debugging on a default profile unless `--user-data-dir` is explicit.

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --remote-debugging-port=9222 `
  --remote-debugging-address=127.0.0.1 `
  --remote-allow-origins=* `
  --user-data-dir="$env:LOCALAPPDATA\Google\Chrome\User Data" `
  --profile-directory=Default `
  --no-first-run `
  --no-default-browser-check `
  "<source-url>"
```

Check and stop only that debugging Chrome:

```powershell
Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" |
  Where-Object { $_.CommandLine -like '*remote-debugging-port=9222*' } |
  Select-Object ProcessId, CommandLine

$pids = Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" |
  Where-Object { $_.CommandLine -like '*remote-debugging-port=9222*' } |
  Select-Object -ExpandProperty ProcessId
if ($pids) { Stop-Process -Id $pids -Force }
```

## Script workflow

Use `scripts/capture_paid_course_cdp.py` for CDP capture.

1. Probe network and DOM:

```powershell
python scripts/capture_paid_course_cdp.py probe `
  --source-url "<source-url>" `
  --host-marker "<host>" `
  --product-id "<p_xxx>" `
  --task-dir "chatgpt/<task-slug>" `
  --navigate `
  --scroll-rounds 8
```

2. Sample a few article details:

```powershell
python scripts/capture_paid_course_cdp.py sample-details `
  --source-url "<source-url>" `
  --host-marker "<host>" `
  --product-id "<p_xxx>" `
  --task-dir "chatgpt/<task-slug>" `
  --raw "raw.json" `
  --start-id "i_xxx" `
  --max-articles 5
```

3. Traverse sequentially:

```powershell
python scripts/capture_paid_course_cdp.py traverse `
  --source-url "<source-url>" `
  --host-marker "<host>" `
  --product-id "<p_xxx>" `
  --task-dir "chatgpt/<task-slug>" `
  --raw "raw.json" `
  --start-id "i_xxx" `
  --direction previous `
  --max-new 500 `
  --delay 0.2 `
  --progress-log "cdp-api-capture-progress.jsonl"
```

4. Normalize older UI-captured records through the API:

```powershell
python scripts/capture_paid_course_cdp.py normalize-existing `
  --source-url "<source-url>" `
  --host-marker "<host>" `
  --product-id "<p_xxx>" `
  --task-dir "chatgpt/<task-slug>" `
  --raw "raw.json" `
  --delay 0.2
```

5. Build company/industry Markdown:

```powershell
python scripts/build_company_article_markdown.py `
  --raw "chatgpt/<task-slug>/raw.json" `
  --output-dir "<final-output-dir>" `
  --file-stem "<final-file-stem>" `
  --title "<title>" `
  --source-url "<source-url>" `
  --industry-map-json "chatgpt/<task-slug>/industry-map.json" `
  --company-research-md "<optional-company-research.md>" `
  --report "chatgpt/<task-slug>/final-build-report.json" `
  --download-images
```

6. Capture a Xiaoetong member-product/course-bundle tree:

```powershell
python scripts/capture_paid_course_cdp.py capture-member-tree `
  --source-url "<member-product-url>" `
  --host-marker "<host>" `
  --product-id "<p_xxx>" `
  --task-dir "chatgpt/<task-slug>" `
  --raw "member-tree-raw.json" `
  --fetch-details `
  --delay 0.1 `
  --progress-log "member-tree-progress.jsonl"
```

7. Build themed course Markdown folders:

```powershell
python scripts/build_paid_course_markdown.py `
  --raw "chatgpt/<task-slug>/member-tree-raw.json" `
  --output-dir "<final-output-dir>" `
  --title "<course/member title>" `
  --source-url "<member-product-url>" `
  --category-map-json "chatgpt/<task-slug>/category-map.json" `
  --report "chatgpt/<task-slug>/final-build-report.json"
```

## Xiaoetong API hints

Observed Xiaoetong endpoints can change, so treat these as candidates found by probing, not hard guarantees:

- Detail: `POST /xe.course.business_go.get.detail/2.0.0`
- Core info: `POST /xe.course.business_go.core.info.get/2.0.0`
- Previous/next: `POST /xe.course.business_go.resource.loop_resource.get/2.0.0`
- Plain detail fallback: `POST /xe.course.business.get.detail/2.0.0`
- Plain core fallback: `POST /xe.course.business.core.info.get/2.0.0`
- Purchased list: `GET /api/xe.shop.purchased.get/1.0.0?app_id=<app>&page_index=1&page_size=30`
- Learning records: `POST /api/xe.user.learning.records.get/1.0.0`
- Member columns: `POST /xe.course.business.member.column_items.get/2.0.0`
- Member singles: `POST /xe.course.business.member.single_items.get/2.0.0`
- Member courses: `POST /xe.course.business.member.course.get/2.0.0`
- Column lessons/items: `POST /xe.course.business.column.items.get/2.0.0`

Typical form body uses `bizData[...]` keys such as:

- `bizData[resource_id]=i_xxx`
- `bizData[product_id]=p_xxx`
- `bizData[resource_type]=1`

Member/course-bundle endpoints often use plain form keys instead:

- `column_id=p_xxx`
- `page_index=1`
- `page_size=50`
- `isDesc=1`
- detail fallback: `resource_id=a_xxx&product_id=`

Useful fields:

- title: `data.resource_name` or detail title
- date: `data.sale_at` / `data.sale_at_complete`
- body: `data.org_content`
- next/previous: `data.previous.id` and `data.next.id`

## Member product exception notes

Observed on a Xiaoetong lifetime-member product:

- The product detail page displayed a large update count but its catalog tab was empty across `课程 / 专栏 / 单课`.
- "开始学习" on the purchased list routed back to `/detail/<product_id>/5` and then the PC member detail page.
- The real content tree was under `member.column_items.get` with parent columns, while child lessons were under `column.items.get`.
- Standalone member resources were under `member.single_items.get`; group them under `导读与单课`.
- One or a few lessons may return an empty `org_content` despite `code: 0`. Retry once; if still empty, preserve resource metadata and mark `未从详情接口取得可转换正文`.
- Some environments show Chinese paths as mojibake in PowerShell output. Write reusable build/validation scripts as UTF-8 files and run them, instead of embedding Chinese path literals in one-off shell snippets.
- Clean stale output directories before rebuilding final folders, after verifying the resolved absolute path is inside the intended workspace.

## Output and validation

Default intermediate layout:

- `chatgpt/<task-slug>/raw.json`
- `chatgpt/<task-slug>/cdp-network-probe.json`
- `chatgpt/<task-slug>/cdp-api-detail-sample.json`
- `chatgpt/<task-slug>/cdp-api-capture-progress.jsonl`
- `chatgpt/<task-slug>/assets/`
- `chatgpt/<task-slug>/final-build-report.json`
- `chatgpt/<task-slug>/member-tree-raw.json` for member/course-bundle captures.
- `chatgpt/<task-slug>/member-tree-progress.jsonl` for member/course-bundle progress.

Validate before declaring completion:

- raw article count equals final `####` article heading count.
- duplicate key count for `article_date + article_title` is zero.
- same company dates are old-to-new.
- 3-5 sampled articles have matching title, date, URL, beginning, and ending.
- common UI noise such as `返回前一页`, `复制链接`, `发表评论`, `加载中`, `店铺主页` is absent.
- image-only tables are downloaded or linked and explicitly noted if not OCR/structured.
- for member/course bundles, final lesson heading count equals raw `lessons` length.
- same parent course lesson dates are old-to-new.
- single resources do not remain as `__single__`, `??`, or `未命名`; group them under a readable label such as `导读与单课`.
- final folder names are valid UTF-8 paths and no stale previous build artifacts remain.
