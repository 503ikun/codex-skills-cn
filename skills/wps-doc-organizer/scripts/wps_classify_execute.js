#!/usr/bin/env node
const fs = require('fs/promises');
const path = require('path');

const DEFAULT_NODE_MODULE = 'D:/小红书/node_modules/playwright';
const DEFAULT_CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const DEFAULT_PROFILE = 'C:/Users/Administrator/codex-wps-profile';

function parseArgs(argv) {
  const args = {
    chromePath: DEFAULT_CHROME,
    userDataDir: DEFAULT_PROFILE,
    outDir: process.cwd(),
    dryRun: true,
    execute: false,
    uncertainCategory: '待确认',
    limit: 0,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--start-date') args.startDate = next();
    else if (a === '--end-date') args.endDate = next();
    else if (a === '--categories') args.categoriesPath = next();
    else if (a === '--uncertain-category') args.uncertainCategory = next();
    else if (a === '--out-dir') args.outDir = next();
    else if (a === '--root-folder-name') args.rootFolderName = next();
    else if (a === '--chrome-path') args.chromePath = next();
    else if (a === '--user-data-dir') args.userDataDir = next();
    else if (a === '--limit') args.limit = Number(next());
    else if (a === '--dry-run') { args.dryRun = true; args.execute = false; }
    else if (a === '--execute') { args.execute = true; args.dryRun = false; }
    else if (a === '--help' || a === '-h') args.help = true;
    else throw new Error(`Unknown argument: ${a}`);
  }
  if (!args.rootFolderName && args.startDate && args.endDate) {
    args.rootFolderName = `WPS文档整理_${args.startDate}至${args.endDate}`;
  }
  return args;
}

function usage() {
  return [
    'Usage:',
    '  node wps_classify_execute.js --start-date YYYY-MM-DD --end-date YYYY-MM-DD --categories categories.json --dry-run',
    '  node wps_classify_execute.js --start-date YYYY-MM-DD --end-date YYYY-MM-DD --categories categories.json --execute',
    '',
    'Options:',
    '  --uncertain-category NAME   default: 待确认',
    '  --out-dir PATH             default: current working directory',
    '  --root-folder-name NAME    default: WPS文档整理_<start>至<end>',
    '  --limit N                  process first N matching files, useful for small execute tests',
  ].join('\n');
}

function requireArgs(args) {
  const missing = [];
  for (const key of ['startDate', 'endDate', 'categoriesPath']) {
    if (!args[key]) missing.push(`--${key.replace(/[A-Z]/g, m => '-' + m.toLowerCase())}`);
  }
  if (missing.length) throw new Error(`Missing required arguments: ${missing.join(', ')}`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(args.endDate)) {
    throw new Error('Dates must use YYYY-MM-DD.');
  }
  if (args.startDate > args.endDate) throw new Error('--start-date cannot be after --end-date.');
}

function normalize(s) {
  return String(s || '').toLowerCase().replace(/\s+/g, '');
}

function inferKeywords(name) {
  const n = normalize(name);
  const seeds = [];
  const add = arr => seeds.push(...arr);
  if (/采购|订单|合同|报价/.test(n)) add(['采购', '订单', '合同', '报价', '物资', '原材料']);
  if (/招投标|招标|投标|评审|成交/.test(n)) add(['招标', '投标', '评审', '评标', '成交', '公示', '响应文件']);
  if (/工程|设备|改造/.test(n)) add(['工程', '设备', '改造', '生产线', '验收', '进度']);
  if (/财务|付款|报销|发票/.test(n)) add(['付款', '报销', '发票', '开票', '保证金', '费用']);
  if (/人事|个人|员工/.test(n)) add(['员工', '试用期', '考核', '学历', '身份证', '简历', '人事']);
  if (/学习|论文|资料/.test(n)) add(['论文', '学习', '课程', '教材', '文献', '研究', '书籍']);
  if (/流程|模板|制度/.test(n)) add(['模板', '流程', '制度', '办法', '审批', '台账', '用印', '出差']);
  return [...new Set(seeds)];
}

async function loadCategories(file, uncertainCategory) {
  const raw = JSON.parse(await fs.readFile(file, 'utf8'));
  const entries = Array.isArray(raw)
    ? raw.map(x => ({ name: x.name, keywords: x.keywords || [] }))
    : Object.entries(raw).map(([name, keywords]) => ({ name, keywords: Array.isArray(keywords) ? keywords : [] }));
  if (!entries.some(x => x.name === uncertainCategory)) entries.push({ name: uncertainCategory, keywords: [] });
  return entries.map(x => ({
    name: x.name,
    keywords: (x.keywords && x.keywords.length ? x.keywords : inferKeywords(x.name)).map(normalize).filter(Boolean),
  }));
}

function classify(name, categories, uncertainCategory) {
  const n = normalize(name);
  for (const cat of categories) {
    if (cat.name === uncertainCategory) continue;
    if (cat.keywords.some(k => n.includes(k))) return cat.name;
  }
  return uncertainCategory;
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function cnDate(ms) {
  const parts = new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(ms));
  const get = type => parts.find(p => p.type === type).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function dateFromItem(item) {
  const r = item.roaming || {};
  const f = item.file || {};
  const raw = r.mtime || (f.mtime ? f.mtime * 1000 : 0) || (r.ctime ? r.ctime * 1000 : 0);
  const ms = raw > 1e12 ? raw : raw * 1000;
  return cnDate(ms);
}

function locationOf(item) {
  const r = item.roaming || {};
  if (r.file_src === '我的云文档' || r.file_src_type === 'private') return '我的云文档';
  if (r.file_src === '我收到的') return '我收到的';
  if (r.group_type === 'tmp' || r.file_src_type === 'roaming' || r.file_src === '自动上传文档') return '我的设备';
  return r.file_src || r.original_device_type || '未知位置';
}

function csvEscape(value) {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
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
    try { json = JSON.parse(text); } catch { json = { text }; }
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
  for (let i = 0; i < 50; i++) {
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
  if (res.status !== 200 || !info.fileid && !info.id) {
    throw new Error(`Create folder failed: ${res.status} ${JSON.stringify(res.json).slice(0, 300)}`);
  }
  return Number(info.fileid || info.id);
}

async function ensureFolder(page, groupId, parentId, name, execute) {
  const existing = (await listFolder(page, groupId, parentId)).find(f => f.ftype === 'folder' && f.fname === name);
  if (existing) return { id: Number(existing.id || existing.fileid), status: 'existing' };
  if (!execute) return { id: 0, status: 'missing_dry_run' };
  return { id: await createFolder(page, groupId, parentId, name), status: 'created' };
}

async function fetchInventory(page, args, categories, groupId, folderMap) {
  const rows = [];
  let maxMtime = '';
  for (let pageNo = 0; pageNo < 100; pageNo++) {
    const url = `https://drive.kdocs.cn/api/v5/roaming?include=group_type&count=100${maxMtime ? `&max_mtime=${encodeURIComponent(maxMtime)}` : ''}`;
    const res = await fetchJson(page, url);
    if (res.status !== 200 || !Array.isArray(res.json.list)) {
      throw new Error(`roaming fetch failed: ${res.status} ${JSON.stringify(res.json).slice(0, 300)}`);
    }
    rows.push(...res.json.list);
    const dates = res.json.list.map(dateFromItem).filter(Boolean);
    if (!res.json.next || !res.json.next_mtime) break;
    if (dates.length && dates.every(d => d < args.startDate)) break;
    maxMtime = res.json.next_mtime;
  }

  const seen = new Map();
  for (const item of rows) {
    const r = item.roaming || {};
    const f = item.file || {};
    const fileId = Number(f.fileid || r.fileid);
    const name = r.name || f.fname || '';
    const ftype = f.ftype || '';
    const date = dateFromItem(item);
    if (!fileId || !name || ftype === 'folder') continue;
    if (date < args.startDate || date > args.endDate) continue;
    if (seen.has(fileId)) continue;

    const category = classify(name, categories, args.uncertainCategory);
    const targetFolderId = folderMap[category] || 0;
    const sourceParentId = Number(f.parent_id ?? f.parentid ?? 0);
    const sourceGroupId = Number(f.groupid || r.groupid || 0);
    const alreadyInTarget = targetFolderId && Number(f.parent_id ?? f.parentid ?? 0) === targetFolderId;
    seen.set(fileId, {
      fileId,
      name,
      date,
      location: locationOf(item),
      category,
      sourceGroupId,
      sourceParentId,
      targetGroupId: groupId,
      targetFolderId,
      operation: alreadyInTarget ? 'skip_already_in_target' : args.execute ? 'copy' : 'dry_run_copy',
      result: alreadyInTarget ? '已在目标分类目录' : args.execute ? '待执行' : 'dry-run 未执行',
      taskuuid: '',
      error: '',
    });
  }
  let list = [...seen.values()].sort((a, b) => b.date.localeCompare(a.date) || a.name.localeCompare(b.name));
  if (args.limit > 0) list = list.slice(0, args.limit);
  return list;
}

function groupBatches(items) {
  const groups = new Map();
  for (const item of items) {
    if (item.operation !== 'copy') continue;
    if (!item.targetFolderId) {
      item.result = '失败';
      item.error = '目标分类目录不存在；请先 dry-run 检查，或使用 --execute 创建目录。';
      continue;
    }
    const key = [item.sourceGroupId, item.sourceParentId, item.targetFolderId].join('|');
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(item);
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
    const err = `start_failed ${start.status} ${JSON.stringify(start.json).slice(0, 300)}`;
    for (const item of batch) {
      item.result = '失败';
      item.error = err;
    }
    return;
  }
  const taskuuid = start.json.taskuuid;
  let progress = null;
  for (let i = 0; i < 90; i++) {
    await delay(700);
    progress = await fetchJson(page, `https://drive.kdocs.cn/api/v5/files/batch/task/progress?taskuuid=${encodeURIComponent(taskuuid)}`);
    if (progress.json && (progress.json.status === 'success' || progress.json.status === 'failed')) break;
  }
  const ok = progress && progress.json && progress.json.status === 'success';
  for (const item of batch) {
    item.taskuuid = taskuuid;
    item.result = ok ? '已复制到分类目录' : '失败';
    item.error = ok ? '' : JSON.stringify(progress && progress.json || {}).slice(0, 500);
  }
}

async function writeOutputs(args, items, folderStatus, folderCounts) {
  await fs.mkdir(args.outDir, { recursive: true });
  const suffix = `${args.startDate}至${args.endDate}`;
  const csvPath = path.join(args.outDir, `WPS归类清单_${suffix}.csv`);
  const logPath = path.join(args.outDir, 'WPS归类执行日志.md');
  const headers = ['文件名', '日期', '来源位置', '拟分类', '操作方式', 'WPS key', '源groupid', '源parentid', '目标folderid', '执行结果', 'taskuuid', '失败原因'];
  const lines = [headers.join(',')];
  for (const item of items) {
    lines.push([
      item.name, item.date, item.location, item.category, item.operation, `file_${item.fileId}`,
      item.sourceGroupId, item.sourceParentId, item.targetFolderId, item.result, item.taskuuid, item.error,
    ].map(csvEscape).join(','));
  }
  await fs.writeFile(csvPath, '\ufeff' + lines.join('\r\n'), 'utf8');

  const countBy = key => items.reduce((acc, x) => (acc[x[key]] = (acc[x[key]] || 0) + 1, acc), {});
  const section = obj => Object.entries(obj).map(([k, v]) => `- ${k}: ${v}`).join('\n') || '- 无';
  const failures = items.filter(x => x.result === '失败');
  const log = [
    '# WPS 文档整理执行日志',
    '',
    `- 模式: ${args.execute ? 'execute' : 'dry-run'}`,
    `- 日期范围: ${args.startDate} 至 ${args.endDate}`,
    `- 根目录: ${args.rootFolderName}`,
    `- 总条目: ${items.length}`,
    `- 清单文件: ${csvPath}`,
    '',
    '## 分类目录状态',
    section(folderStatus),
    '',
    '## 按分类统计',
    section(countBy('category')),
    '',
    '## 按来源统计',
    section(countBy('location')),
    '',
    '## 按执行结果统计',
    section(countBy('result')),
    '',
    '## 云端分类目录复扫数量',
    section(folderCounts),
    '',
    '## 失败条目',
    failures.length ? failures.map(x => `- ${x.date} | ${x.category} | file_${x.fileId} | ${x.name} | ${x.error}`).join('\n') : '- 无',
    '',
  ].join('\n');
  await fs.writeFile(logPath, log, 'utf8');
  return { csvPath, logPath };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(usage());
    return;
  }
  requireArgs(args);
  const categories = await loadCategories(args.categoriesPath, args.uncertainCategory);
  const { chromium } = require(DEFAULT_NODE_MODULE);
  const ctx = await chromium.launchPersistentContext(args.userDataDir, {
    executablePath: args.chromePath,
    headless: true,
    viewport: { width: 1440, height: 1000 },
  });
  try {
    const page = await ctx.newPage();
    await page.goto('https://www.kdocs.cn/latest', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await delay(4000);
    const groupId = await getPersonalGroupId(page);
    const root = await ensureFolder(page, groupId, 0, args.rootFolderName, args.execute);
    const folderMap = {};
    const folderStatus = { [args.rootFolderName]: root.status };
    for (const cat of categories) {
      const child = root.id ? await ensureFolder(page, groupId, root.id, cat.name, args.execute) : { id: 0, status: 'missing_dry_run' };
      folderMap[cat.name] = child.id;
      folderStatus[cat.name] = child.status;
    }
    const items = await fetchInventory(page, args, categories, groupId, folderMap);
    if (args.execute) {
      const batches = groupBatches(items);
      let copied = 0;
      for (const batch of batches) {
        await runBatch(page, batch);
        copied += batch.length;
        if (copied % 100 === 0 || copied === items.filter(x => x.operation === 'copy').length) {
          console.log(JSON.stringify({ phase: 'copy_progress', copied }));
        }
      }
    }
    const folderCounts = {};
    if (args.execute) {
      for (const [name, id] of Object.entries(folderMap)) {
        folderCounts[name] = id ? (await listFolder(page, groupId, id)).filter(f => f.ftype !== 'folder').length : 0;
      }
    }
    const outputs = await writeOutputs(args, items, folderStatus, folderCounts);
    console.log(JSON.stringify({
      mode: args.execute ? 'execute' : 'dry-run',
      total: items.length,
      byCategory: items.reduce((acc, x) => (acc[x.category] = (acc[x.category] || 0) + 1, acc), {}),
      outputs,
    }, null, 2));
  } finally {
    await ctx.close();
  }
}

main().catch(err => {
  console.error(err.stack || err.message || err);
  process.exit(1);
});
