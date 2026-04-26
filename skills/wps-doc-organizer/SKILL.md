---
name: wps-doc-organizer
description: 整理 WPS/金山文档云端文件。Use when Codex needs to scan WPS Cloud / 金山文档 by a user-specified date range, classify documents into user-specified business folders, generate dry-run CSV/Markdown plans, and optionally copy files into WPS cloud category folders without deleting originals. Trigger on Chinese requests like “WPS文档整理”, “整理 WPS 云文档”, “按日期归类金山文档”, “把 WPS 文件按目录分类”.
---

# WPS文档整理

## Core Workflow

Use `scripts/wps_classify_execute.js` for deterministic WPS organization. The script uses the logged-in Chrome profile to call WPS web APIs:

- scan: `drive.kdocs.cn/api/v5/roaming`
- personal cloud group: `drive.kdocs.cn/api/v3/groups/special`
- list/create folders under personal cloud
- copy files with `drive.kdocs.cn/api/v5/files/batch/task/copy`

Always collect these from the user before execution:

- date range: `--start-date YYYY-MM-DD` and `--end-date YYYY-MM-DD`
- classification directories: a JSON file passed with `--categories`
- uncertain bucket: `--uncertain-category`, usually `待确认`

If the user has not explicitly asked to execute cloud changes, run `--dry-run` only. Use `--execute` only after the user explicitly asks to perform cloud copying. The script never deletes source records and never overwrites files; WPS duplicate handling uses automatic rename.

## Quick Start

Create a categories JSON file, then run:

```powershell
& 'D:\小红书\tools\node-v24.11.0-win-x64\node.exe' `
  'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_classify_execute.js' `
  --start-date 2025-09-01 `
  --end-date 2026-04-25 `
  --categories 'C:\path\categories.json' `
  --uncertain-category 待确认 `
  --dry-run
```

After the user confirms the dry-run plan, replace `--dry-run` with `--execute`.

Default paths:

- Chrome: `C:\Program Files\Google\Chrome\Application\chrome.exe`
- Chrome profile: `C:\Users\Administrator\codex-wps-profile`
- output: current working directory unless `--out-dir` is provided
- root folder: `WPS文档整理_<start-date>至<end-date>` unless `--root-folder-name` is provided

## Categories

Prefer user-provided categories. The `--categories` file accepts either:

```json
{
  "采购合同与订单": ["采购", "订单", "合同", "报价单"],
  "招投标与评审材料": ["招标", "投标", "评审", "成交", "公示"],
  "待确认": []
}
```

or:

```json
[
  { "name": "采购合同与订单", "keywords": ["采购", "订单", "合同", "报价单"] },
  { "name": "待确认", "keywords": [] }
]
```

If a category has no keywords, infer rough keywords from the directory name. See `references/classification-rules.md` before changing classification behavior.

## Safety Rules

- Dry-run is the default posture. It scans WPS and writes local CSV/Markdown only.
- Execute mode creates missing WPS category folders and copies files; it does not delete, move, or rename originals.
- Group copy jobs by source group, source parent, and target folder to avoid WPS batch task failures.
- Record every failure in the Markdown log and continue with the rest.
- If WPS login is missing or expired, stop and ask the user to log in through the Chrome profile.

## Outputs

The script writes:

- `WPS归类清单_<start-date>至<end-date>.csv`
- `WPS归类执行日志.md`

The CSV includes file name, date, source location, proposed category, operation, WPS key, source group/parent, target folder, result, task UUID, and error.
