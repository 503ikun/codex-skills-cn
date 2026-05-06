const fs = require('fs/promises');
const path = require('path');
const { chromium } = require('D:/小红书/node_modules/playwright');

const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const userDataDir = 'C:/Users/Administrator/codex-wps-profile';
const startDate = '2025-09-01';
const endDate = '2026-04-28';
const rootFolderName = `询价采购全过程归档_差异化规则版_${startDate}至${endDate}`;
const baseDir = path.join(process.cwd(), 'output', `询价采购全过程归档_差异化规则版_${startDate}至${endDate}`);
const evidenceCsv = path.join(baseDir, '差异化归档证据明细.csv');
const checklistCsv = path.join(baseDir, '项目详细归档清单.csv');
const cloudCsv = path.join(process.cwd(), 'output', `询价采购全过程归档_${startDate}至${endDate}`, '云端归档清单.csv');

function parseArgs(argv) {
  const args = { execute: false, dryRun: true, limit: 0 };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--execute') {
      args.execute = true;
      args.dryRun = false;
    } else if (a === '--dry-run') {
      args.execute = false;
      args.dryRun = true;
    } else if (a === '--limit') {
      args.limit = Number(argv[++i]);
    } else if (a === '--help' || a === '-h') {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${a}`);
    }
  }
  return args;
}

function usage() {
  return [
    'Usage:',
    '  node wps_procurement_archive_cloud_copy.js --dry-run',
    '  node wps_procurement_archive_cloud_copy.js --execute',
    '  node wps_procurement_archive_cloud_copy.js --execute --limit 20',
  ].join('\n');
}

function parseCsv(text) {
  text = text.replace(/^\uFEFF/, '');
  const rows = [];
  let row = [];
  let cell = '';
  let quote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === '"' && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') {
        quote = false;
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      quote = true;
    } else if (ch === ',') {
      row.push(cell);
      cell = '';
    } else if (ch === '\n') {
      if (cell.endsWith('\r')) cell = cell.slice(0, -1);
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += ch;
    }
  }
  if (cell || row.length) {
    row.push(cell);
    rows.push(row);
  }
  const headers = rows.shift() || [];
  return rows.filter(r => r.some(Boolean)).map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] || ''])));
}

function csvEscape(value) {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function sanitizeFolderName(name) {
  return String(name || '未命名')
    .replace(/[\\/:*?"<>|]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120) || '未命名';
}

function fileIdFromKey(key) {
  const m = String(key || '').match(/file_(\d+)/);
  return m ? Number(m[1]) : 0;
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchJson(page, url, options = {}) {
  return page.evaluate(async ({ url, options }) => {
    const res = await fetch(url, {
      credentials: 'include',
      headers: { 'content-type': 'application/json' },
      ...options,
    });
    const text = await res.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      json = { text };
    }
    return { status: res.status, json };
  }, { url, options });
}

async function getPersonalGroupId(page) {
  const res = await fetchJson(page, 'https://drive.kdocs.cn/api/v3/groups/special');
  if (res.status !== 200 || !res.json.id) throw new Error('Cannot determine WPS personal cloud group. Is WPS logged in?');
  return Number(res.json.id);
}

async function listFolder(page, groupId, parentId) {
  const files = [];
  let offset = 0;
  for (let i = 0; i < 80; i++) {
    const url = `https://drive.kdocs.cn/api/v5/groups/${groupId}/files?parentid=${parentId}&count=100&offset=${offset}`;
    const res = await fetchJson(page, url);
    if (res.status !== 200 || !Array.isArray(res.json.files)) break;
    files.push(...res.json.files);
    if (!res.json.next_offset || res.json.next_offset < 0) break;
    offset = res.json.next_offset;
  }
  return files;
}

async function createFolder(page, groupId, parentId, name) {
  const body = { groupid: groupId, parentid: parentId, name, parsed: true, owner: true };
  const res = await fetchJson(page, 'https://drive.kdocs.cn/api/v5/files/folder', {
    method: 'POST',
    body: JSON.stringify(body),
  });
  const info = res.json.fileinfo || res.json;
  if (res.status !== 200 || (!info.fileid && !info.id)) {
    throw new Error(`Create folder failed: ${res.status} ${JSON.stringify(res.json).slice(0, 300)}`);
  }
  return Number(info.fileid || info.id);
}

async function ensureFolder(page, groupId, parentId, name, execute, cache) {
  const key = `${groupId}|${parentId}|${name}`;
  if (cache.has(key)) return cache.get(key);
  const existing = (await listFolder(page, groupId, parentId)).find(f => f.ftype === 'folder' && f.fname === name);
  if (existing) {
    const result = { id: Number(existing.id || existing.fileid), status: 'existing' };
    cache.set(key, result);
    return result;
  }
  if (!execute) {
    const result = { id: 0, status: 'would_create' };
    cache.set(key, result);
    return result;
  }
  const result = { id: await createFolder(page, groupId, parentId, name), status: 'created' };
  cache.set(key, result);
  return result;
}

function buildSourceMap(cloudRows) {
  const map = new Map();
  for (const row of cloudRows) {
    const key = row['WPS key'];
    if (!key) continue;
    map.set(key, {
      sourceGroupId: Number(row['源groupid'] || 0),
      sourceParentId: Number(row['源parentid'] || 0),
    });
  }
  return map;
}

function buildCopyRows(evidenceRows, sourceMap) {
  const rows = [];
  const localOnly = [];
  const seen = new Set();
  for (const row of evidenceRows) {
    const wpsKey = row['WPS key'] || '';
    const fileId = fileIdFromKey(wpsKey);
    const project = sanitizeFolderName(row['项目']);
    const stage = sanitizeFolderName(row['流程阶段']);
    const name = row['文件名'];
    if (!fileId) {
      localOnly.push({
        source: row['来源'],
        date: row['日期'],
        project,
        stage,
        name,
        localPath: row['本地路径'],
        reason: '无 WPS key，本轮不上传，仅列入待补',
      });
      continue;
    }
    const source = sourceMap.get(wpsKey) || {};
    const sourceGroupId = Number(source.sourceGroupId || 0);
    const sourceParentId = Number(source.sourceParentId || row['源parentid'] || 0);
    if (!sourceGroupId || !sourceParentId && sourceParentId !== 0) {
      localOnly.push({
        source: row['来源'],
        date: row['日期'],
        project,
        stage,
        name,
        localPath: row['本地路径'],
        reason: '缺少源 groupid/parentid，无法调用云端复制',
      });
      continue;
    }
    const dedupeKey = `${wpsKey}|${project}|${stage}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    rows.push({
      date: row['日期'],
      project,
      stage,
      name,
      wpsKey,
      fileId,
      sourceGroupId,
      sourceParentId,
      targetFolderId: 0,
      operation: 'pending',
      result: '',
      taskuuid: '',
      error: '',
    });
  }
  rows.sort((a, b) => a.project.localeCompare(b.project, 'zh-CN') || a.stage.localeCompare(b.stage, 'zh-CN') || a.date.localeCompare(b.date) || a.name.localeCompare(b.name, 'zh-CN'));
  return { rows, localOnly };
}

function groupBatches(rows) {
  const groups = new Map();
  for (const row of rows) {
    if (row.operation !== 'copy') continue;
    const key = [row.sourceGroupId, row.sourceParentId, row.targetFolderId].join('|');
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  const batches = [];
  for (const group of groups.values()) {
    for (let i = 0; i < group.length; i += 20) batches.push(group.slice(i, i + 20));
  }
  return batches;
}

async function runBatch(page, batch) {
  const first = batch[0];
  const body = {
    fileids: batch.map(x => x.fileId),
    groupid: first.sourceGroupId,
    parentid: first.sourceParentId,
    dst_groupid: first.targetGroupId,
    dst_parentid: first.targetFolderId,
    duplicated_name_model: 'rename',
  };
  const start = await fetchJson(page, 'https://drive.kdocs.cn/api/v5/files/batch/task/copy', {
    method: 'POST',
    body: JSON.stringify(body),
  });
  if (start.status !== 200 || start.json.result !== 'ok' || !start.json.taskuuid) {
    const err = `start_failed ${start.status} ${JSON.stringify(start.json).slice(0, 500)}`;
    for (const row of batch) {
      row.result = '失败';
      row.error = err;
    }
    return;
  }
  const taskuuid = start.json.taskuuid;
  let progress = null;
  for (let i = 0; i < 100; i++) {
    await delay(700);
    progress = await fetchJson(page, `https://drive.kdocs.cn/api/v5/files/batch/task/progress?taskuuid=${encodeURIComponent(taskuuid)}`);
    if (progress.json && (progress.json.status === 'success' || progress.json.status === 'failed')) break;
  }
  const ok = progress && progress.json && progress.json.status === 'success';
  for (const row of batch) {
    row.taskuuid = taskuuid;
    row.result = ok ? '已复制' : '失败';
    row.error = ok ? '' : JSON.stringify(progress && progress.json || {}).slice(0, 500);
  }
}

async function writeCsv(file, headers, rows) {
  const lines = [headers.map(h => h.title).join(',')];
  for (const row of rows) lines.push(headers.map(h => csvEscape(row[h.key])).join(','));
  await fs.writeFile(file, '\uFEFF' + lines.join('\r\n'), 'utf8');
}

function counts(rows, key) {
  const map = new Map();
  for (const row of rows) map.set(row[key], (map.get(row[key]) || 0) + 1);
  return [...map.entries()].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0]), 'zh-CN'));
}

function section(entries) {
  return entries.length ? entries.map(([k, v]) => `- ${k}: ${v}`).join('\n') : '- 无';
}

async function writeOutputs(args, rows, localOnly, folderStatus, copiedCounts) {
  const modeLabel = args.execute ? 'execute' : 'dry-run';
  const copyCsv = path.join(baseDir, `WPS云端分类复制清单_${modeLabel}.csv`);
  const logMd = path.join(baseDir, `WPS云端分类执行日志_${modeLabel}.md`);
  const localOnlyCsv = path.join(baseDir, '本地样本待补清单.csv');

  await writeCsv(copyCsv, [
    { title: '日期', key: 'date' },
    { title: '项目', key: 'project' },
    { title: '流程阶段', key: 'stage' },
    { title: '文件名', key: 'name' },
    { title: 'WPS key', key: 'wpsKey' },
    { title: '源groupid', key: 'sourceGroupId' },
    { title: '源parentid', key: 'sourceParentId' },
    { title: '目标folderid', key: 'targetFolderId' },
    { title: '操作', key: 'operation' },
    { title: '结果', key: 'result' },
    { title: 'taskuuid', key: 'taskuuid' },
    { title: '错误', key: 'error' },
  ], rows);

  await writeCsv(localOnlyCsv, [
    { title: '来源', key: 'source' },
    { title: '日期', key: 'date' },
    { title: '项目', key: 'project' },
    { title: '流程阶段', key: 'stage' },
    { title: '文件名', key: 'name' },
    { title: '本地路径', key: 'localPath' },
    { title: '原因', key: 'reason' },
  ], localOnly);

  const failures = rows.filter(x => x.result === '失败');
  const log = [
    '# WPS 云端分类执行日志',
    '',
    `- 模式: ${modeLabel}`,
    `- 云端归档根目录: ${rootFolderName}`,
    `- 输入证据清单: ${evidenceCsv}`,
    `- 检查清单: ${checklistCsv}`,
    `- 待复制云端文件: ${rows.length}`,
    `- 本地样本待补: ${localOnly.length}`,
    `- 复制清单: ${copyCsv}`,
    `- 本地样本待补清单: ${localOnlyCsv}`,
    '',
    '## 目录状态',
    section(Object.entries(folderStatus)),
    '',
    '## 按项目统计',
    section(counts(rows, 'project')),
    '',
    '## 按阶段统计',
    section(counts(rows, 'stage')),
    '',
    '## 目标目录复扫数量',
    section(Object.entries(copiedCounts)),
    '',
    '## 失败条目',
    failures.length ? failures.map(x => `- ${x.project}/${x.stage} | ${x.wpsKey} | ${x.name} | ${x.error}`).join('\n') : '- 无',
    '',
  ].join('\n');
  await fs.writeFile(logMd, '\uFEFF' + log, 'utf8');
  return { copyCsv, logMd, localOnlyCsv };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(usage());
    return;
  }

  const [evidenceRows, cloudRows] = await Promise.all([
    fs.readFile(evidenceCsv, 'utf8').then(parseCsv),
    fs.readFile(cloudCsv, 'utf8').then(parseCsv),
  ]);
  const sourceMap = buildSourceMap(cloudRows);
  let { rows, localOnly } = buildCopyRows(evidenceRows, sourceMap);
  if (args.limit > 0) rows = rows.slice(0, args.limit);

  if (!args.execute) {
    const folderStatus = { [rootFolderName]: 'would_create_or_reuse' };
    for (const row of rows) {
      folderStatus[row.project] = 'would_create_or_reuse';
      folderStatus[`${row.project}/${row.stage}`] = 'would_create_or_reuse';
      row.operation = 'dry_run_copy';
      row.result = 'dry-run 未执行';
    }
    const outputs = await writeOutputs(args, rows, localOnly, folderStatus, {});
    console.log(JSON.stringify({
      mode: 'dry-run',
      rootFolderName,
      cloudCopyRows: rows.length,
      localOnlyRows: localOnly.length,
      projects: Object.fromEntries(counts(rows, 'project')),
      stages: Object.fromEntries(counts(rows, 'stage')),
      outputs,
    }, null, 2));
    return;
  }

  const context = await chromium.launchPersistentContext(userDataDir, {
    executablePath: chromePath,
    headless: true,
    viewport: { width: 1440, height: 1000 },
  });
  const folderStatus = {};
  const copiedCounts = {};
  try {
    const page = await context.newPage();
    await page.goto('https://www.kdocs.cn/latest', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await delay(4000);
    const targetGroupId = await getPersonalGroupId(page);
    const folderCache = new Map();
    const root = await ensureFolder(page, targetGroupId, 0, rootFolderName, args.execute, folderCache);
    folderStatus[rootFolderName] = root.status;

    const projectFolders = new Map();
    const stageFolders = new Map();
    for (const row of rows) {
      let projectFolder = projectFolders.get(row.project);
      if (!projectFolder) {
        projectFolder = await ensureFolder(page, targetGroupId, root.id, row.project, args.execute, folderCache);
        projectFolders.set(row.project, projectFolder);
        folderStatus[row.project] = projectFolder.status;
      }
      const stageKey = `${row.project}/${row.stage}`;
      let stageFolder = stageFolders.get(stageKey);
      if (!stageFolder) {
        stageFolder = await ensureFolder(page, targetGroupId, projectFolder.id, row.stage, args.execute, folderCache);
        stageFolders.set(stageKey, stageFolder);
        folderStatus[stageKey] = stageFolder.status;
      }
      row.targetGroupId = targetGroupId;
      row.targetFolderId = stageFolder.id;
      row.operation = args.execute ? 'copy' : 'dry_run_copy';
      row.result = args.execute ? '待执行' : 'dry-run 未执行';
    }

    if (args.execute) {
      const batches = groupBatches(rows);
      let done = 0;
      for (const batch of batches) {
        await runBatch(page, batch);
        done += batch.length;
        if (done % 100 === 0 || done === rows.length) {
          console.log(JSON.stringify({ phase: 'copy_progress', done, total: rows.length }));
        }
      }
      for (const [stageKey, folder] of stageFolders.entries()) {
        if (!folder.id) continue;
        copiedCounts[stageKey] = (await listFolder(page, targetGroupId, folder.id)).filter(f => f.ftype !== 'folder').length;
      }
    }

    const outputs = await writeOutputs(args, rows, localOnly, folderStatus, copiedCounts);
    console.log(JSON.stringify({
      mode: args.execute ? 'execute' : 'dry-run',
      rootFolderName,
      cloudCopyRows: rows.length,
      localOnlyRows: localOnly.length,
      projects: Object.fromEntries(counts(rows, 'project')),
      stages: Object.fromEntries(counts(rows, 'stage')),
      outputs,
    }, null, 2));
  } finally {
    await context.close();
  }
}

main().catch(err => {
  console.error(err.stack || err.message || err);
  process.exit(1);
});
