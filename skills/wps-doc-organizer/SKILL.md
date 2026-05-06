---
name: wps-doc-organizer
description: 整理 WPS/金山文档云端文件。Use when Codex needs to scan WPS Cloud / 金山文档 by date range, generate dry-run CSV/Markdown classification plans, copy cloud files into new WPS category folders without deleting originals, or perform the procurement archive workflow for 询价采购全过程归档 including project/stage checklists, differential procurement rules, and WPS cloud copy execution. Trigger on Chinese requests like “WPS文档整理”, “整理 WPS 云文档”, “按日期归类金山文档”, “询价采购全过程归档”, “采购档案整理”, “按归档清单分类 WPS 文件”.
---

# WPS 文档整理

## Core Workflows

Use this skill for two related workflows:

1. **General WPS classification**: scan WPS Cloud by date range, classify files by user-provided categories, and optionally copy cloud files into category folders.
2. **Procurement archive workflow**: classify procurement materials by project and archive stage, generate differential checklists, then optionally copy WPS cloud files into `项目/流程阶段` folders.

All execute modes copy files only. Never delete, move, overwrite, or rename source WPS files.

## Safety Rules

- Default to dry-run. Use `--execute` only after the user explicitly asks to perform WPS cloud copying.
- Execute mode creates missing WPS folders and copies files with WPS duplicate handling set to automatic rename.
- Do not upload local-only files. Put local files without WPS key into a待补清单.
- Group WPS copy jobs by source group, source parent, and target folder to avoid WPS batch task failures.
- Record every failure in the Markdown log and continue with remaining batches.
- If WPS login is missing or expired, stop and ask the user to log in through the Chrome profile.
- If a Chrome process using `C:\Users\Administrator\codex-wps-profile` is stuck from a prior automation run, only stop those automation-profile Chrome processes before retrying.

Default runtime assumptions:

- Chrome: `C:\Program Files\Google\Chrome\Application\chrome.exe`
- Chrome profile: `C:\Users\Administrator\codex-wps-profile`
- Node/Playwright dependency used by bundled scripts: `D:\小红书\node_modules\playwright`
- Output directory: current working directory unless the script defines a more specific output path.

## General WPS Classification

Use `scripts/wps_classify_execute.js` for deterministic category-based WPS organization.

The script uses logged-in Chrome profile cookies to call:

- `drive.kdocs.cn/api/v5/roaming` for scan
- `drive.kdocs.cn/api/v3/groups/special` for the personal cloud group
- WPS folder list/create APIs under personal cloud
- `drive.kdocs.cn/api/v5/files/batch/task/copy` for cloud copy

Collect these from the user before running:

- date range: `--start-date YYYY-MM-DD` and `--end-date YYYY-MM-DD`
- classification directories: JSON file passed with `--categories`
- uncertain bucket: `--uncertain-category`, usually `待确认`

Dry-run example:

```powershell
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_classify_execute.js' `
  --start-date 2025-09-01 `
  --end-date 2026-04-28 `
  --categories 'C:\path\categories.json' `
  --uncertain-category 待确认 `
  --dry-run
```

After the user confirms the dry-run plan, replace `--dry-run` with `--execute`.

The general script writes:

- `WPS归类清单_<start-date>至<end-date>.csv`
- `WPS归类执行日志.md`

The CSV includes file name, date, source location, proposed category, operation, WPS key, source group/parent, target folder, result, task UUID, and error.

## Procurement Archive Workflow

Use this workflow when the user asks to organize procurement records, especially `询价采购全过程归档`, `采购档案整理`, `按归档清单分类`, or asks to separate files by project and process stage.

Run the scripts from the working folder where outputs should be generated. The three scripts are designed as a pipeline:

1. `scripts/wps_procurement_archive_dryrun.js`
   - Scans WPS cloud for procurement-related files in the fixed historical range embedded in the script.
   - Cross-checks local sample files under `C:\Users\Administrator\Desktop\新建文件夹`.
   - Writes `云端归档清单.csv`, `本地样本核对清单.csv`, `缺件检查报告.md`, `工作流封装规则.md`, and `询价采购全过程归档模板.md`.

2. `scripts/wps_procurement_archive_differentiated.js`
   - Reads the dry-run outputs.
   - Applies differential procurement rules by procurement type.
   - Writes `项目详细归档清单.csv`, `差异化归档证据明细.csv`, `按项目归档检查报告.md`, and an updated `工作流封装规则.md`.

3. `scripts/wps_procurement_archive_cloud_copy.js`
   - Reads `差异化归档证据明细.csv` and the original `云端归档清单.csv`.
   - Creates a new WPS cloud root folder named like `询价采购全过程归档_差异化规则版_<start>至<end>`.
   - Copies WPS cloud files into `项目/流程阶段` folders.
   - Writes `WPS云端分类复制清单_<mode>.csv`, `WPS云端分类执行日志_<mode>.md`, and `本地样本待补清单.csv`.

Recommended sequence:

```powershell
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_procurement_archive_dryrun.js'
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_procurement_archive_differentiated.js'
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_procurement_archive_cloud_copy.js' --dry-run
```

Only after the user confirms the dry-run:

```powershell
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_procurement_archive_cloud_copy.js' --execute
```

For a small execute test, use:

```powershell
node 'C:\Users\Administrator\.codex\skills\wps-doc-organizer\scripts\wps_procurement_archive_cloud_copy.js' --execute --limit 20
```

## Procurement Archive Rules

Apply the user's business facts before mechanical missing-file checks:

- `完整公开询价`: LED 芯片、SMT 整线生产设备、压铸件等. Check decision, approval, procurement-file legal review, announcement, response/guarantee, opening/evaluation, public notice, award notice, contract approval, order/settlement.
- `低值零星采购`: steel plate, fire equipment, and similar small purchases below 20000 yuan. Check purchase approval, contract or purchase confirmation if applicable, acceptance note, delivery/hand-over note, payment/reimbursement. Do not require announcement, public notice, evaluation report, award notice, or response guarantee.
- `招标代理配合归档`: driving power supply. Response guarantee is handled by the tendering agent, so do not mark it as a missing file for the company. Archive announcements, addenda, public notices, seal-use cooperation files, and later contract files. Mark contract as pending if not signed.
- `系统内委托`: decoration/factory renovation. Check decision materials, entrustment basis, contract/agreement, implementation records, acceptance/rectification, and settlement. Do not require the full public inquiry chain.
- `未执行或暂缓`: labor outsourcing service and lens silicone ring when the user says execution has not started. Archive only formed meeting/proposal/preparation files and do not generate downstream missing-file findings.

Use `99_待确认` and `补充证据` as real folders. Do not merge them into main process stages.

## References

- See `references/classification-rules.md` before changing the general filename keyword classifier.
- Keep project-specific procurement facts in `SKILL.md` concise. Put long rule tables or examples into `references/` only when needed.
