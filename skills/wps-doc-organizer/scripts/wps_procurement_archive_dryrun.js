const fs = require('fs/promises');
const path = require('path');

const { chromium } = require('D:/小红书/node_modules/playwright');

const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const userDataDir = 'C:/Users/Administrator/codex-wps-profile';
const startDate = '2025-09-01';
const endDate = '2026-04-28';
const localSampleRoot = 'C:/Users/Administrator/Desktop/新建文件夹';
const outDir = path.join(process.cwd(), 'output', `询价采购全过程归档_${startDate}至${endDate}`);

const projects = [
  { name: 'SMT整线生产设备', patterns: [/SMT/i, /贴片机/, /锡膏/, /钢网/, /整线生产设备/] },
  { name: '铝基板', patterns: [/铝基板/] },
  { name: '透镜', patterns: [/透镜/] },
  { name: '压铸件', patterns: [/压铸件/, /散热器/] },
  { name: '驱动电源', patterns: [/驱动电源/, /公母防水接头/, /防水接头/] },
  { name: '试验及辅助设备', patterns: [/试验.*辅助设备/, /辅助设备/, /试验设备/, /循环照明器具生产线/] },
  { name: 'LED芯片', patterns: [/LED.*芯片/i, /芯片/, /灯珠/] },
  { name: '原材料集中采购', patterns: [/原材料/, /五合同包/, /合同包一/, /合同包二/, /合同包三/, /合同包四/, /合同包五/] },
  { name: '生产线综合采购', patterns: [/可循环利用照明器具生产线/, /照明器具生产线/, /灯具工厂/, /循环光源/, /循环利用照明器具/, /光源设备工厂/] },
  { name: '劳务外包服务', patterns: [/劳务外包/] },
  { name: '钢板', patterns: [/钢板/] },
  { name: '消防设备', patterns: [/消防/, /灭火器/] },
  { name: '透镜硅胶圈', patterns: [/硅胶圈/, /密封圈/] },
  { name: '装修及厂房改造', patterns: [/装修/, /厂房/, /改造工程/, /古田/] },
];

const procurementNeedles = [
  /采购/, /询价/, /合同/, /订单/, /报价/, /审批/, /审查意见/, /法审/, /公告/, /公示/, /成交/,
  /通知书/, /保证金/, /响应/, /投标/, /开标/, /评审/, /流标/, /补遗/, /变更/, /质疑/, /异议/,
  /办公会/, /会议纪要/, /议题/, /情况汇报/, /付款/, /报销/, /结算/, /验收/, /预付款/,
  ...projects.flatMap(p => p.patterns),
];

const stages = [
  {
    code: '01_决策立项',
    required: true,
    patterns: [/办公会/, /专题会/, /会议纪要/, /议题/, /情况汇报/, /备案/, /预算/, /设备清单/, /工程量/],
  },
  {
    code: '02_采购准备',
    required: true,
    patterns: [/采购审批/, /审批表/, /采购申请/, /申请表/, /报价方案/, /报价单/, /询价记录/, /最高限价/, /控制价/],
  },
  {
    code: '03_询价文件及法审',
    required: true,
    patterns: [/询价.*文件/, /采购文件/, /招标文件/, /集中预采购项目/, /预采购项目/, /审查意见.*询价/, /审查意见.*采购文件/, /法审.*询价/, /法审.*采购文件/, /合同草案/, /修订模式/],
  },
  {
    code: '04_挂网公告',
    required: true,
    patterns: [/询价公告/, /采购公告/, /公告扫描件/, /补遗/, /变更公告/, /流标公告/],
  },
  {
    code: '05_响应及保证金',
    required: true,
    patterns: [/响应文件/, /投标/, /保证金/, /银行回单/, /报价函/, /报价表/],
  },
  {
    code: '06_开标评审',
    required: true,
    patterns: [/开标/, /评审过程/, /评审报告/, /评标/, /开标视频/, /复评/],
  },
  {
    code: '07_候选人与结果公示',
    required: true,
    patterns: [/候选人公示/, /成交结果公示/, /结果公示/, /质疑函/, /异议函/, /回复/, /公示.*变更/],
  },
  {
    code: '08_通知书及保证金处理',
    required: true,
    patterns: [/成交通知书/, /成交结果通知书/, /保证金.*退/, /退.*保证金/, /履约保证金/],
  },
  {
    code: '09_合同审批与签订',
    required: true,
    patterns: [/合同审批/, /合同审查/, /审查意见.*合同/, /采购合同/, /原材料采购合同/, /盖章合同/, /用章/],
  },
  {
    code: '10_订单履约结算',
    required: false,
    patterns: [/采购订单/, /订单/, /验收/, /培训/, /到货/, /付款/, /预付款/, /报销/, /结算/, /发票/, /尾款/],
  },
];

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function normalizeName(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[（(]file_\d+[）)]/ig, '')
    .replace(/\(\d+\)/g, '')
    .replace(/（\d+）/g, '')
    .replace(/[-_]+/g, '');
}

function csvEscape(value) {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
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
  return cnDate(ms || Date.now());
}

function locationOf(item) {
  const r = item.roaming || {};
  if (r.file_src_type === 'private') return '我的云文档';
  if (r.file_src_type === 'roaming' || r.group_type === 'tmp') return '我的设备';
  return r.file_src || r.original_device_type || '未知位置';
}

function detectProject(name) {
  const hit = projects.find(project => project.patterns.some(re => re.test(name)));
  if (hit) return hit.name;
  if (/零星采购|零星/.test(name)) return '零星采购';
  return '99_待确认';
}

function detectStage(name) {
  if (/审查意见|法审/.test(name) && /合同/.test(name)) return '09_合同审批与签订';
  if (/审查意见|法审/.test(name) && /(询价|采购文件|招标文件|补遗)/.test(name)) return '03_询价文件及法审';
  if (/合同审批表/.test(name)) return '09_合同审批与签订';
  if (/采购审批表|采购申请表|审批表/.test(name)) return '02_采购准备';
  const hit = stages.find(stage => stage.patterns.some(re => re.test(name)));
  return hit ? hit.code : '99_待确认';
}

function isProcurementRelated(name) {
  return procurementNeedles.some(re => re.test(name));
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

async function fetchWpsInventory() {
  const context = await chromium.launchPersistentContext(userDataDir, {
    executablePath: chromePath,
    headless: true,
    viewport: { width: 1440, height: 1000 },
  });
  try {
    const page = await context.newPage();
    await page.goto('https://www.kdocs.cn/latest', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await delay(4000);

    const rows = [];
    let maxMtime = '';
    for (let pageNo = 0; pageNo < 120; pageNo++) {
      const url = `https://drive.kdocs.cn/api/v5/roaming?include=group_type&count=100${maxMtime ? `&max_mtime=${encodeURIComponent(maxMtime)}` : ''}`;
      const res = await fetchJson(page, url);
      if (res.status !== 200 || !Array.isArray(res.json.list)) {
        throw new Error(`WPS roaming fetch failed: ${res.status} ${JSON.stringify(res.json).slice(0, 300)}`);
      }
      rows.push(...res.json.list);
      const dates = res.json.list.map(dateFromItem);
      if (!res.json.next || !res.json.next_mtime) break;
      if (dates.length && dates.every(d => d < startDate)) break;
      maxMtime = res.json.next_mtime;
    }
    return rows;
  } finally {
    await context.close();
  }
}

async function walkFiles(root) {
  const out = [];
  async function walk(dir) {
    let entries = [];
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(full);
      else out.push(full);
    }
  }
  await walk(root);
  return out;
}

async function readLocalSamples() {
  const files = await walkFiles(localSampleRoot);
  const samples = [];
  for (const file of files) {
    const stat = await fs.stat(file);
    const name = path.basename(file);
    if (!isProcurementRelated(name) && !isProcurementRelated(file)) continue;
    samples.push({
      name,
      path: file,
      date: cnDate(stat.mtimeMs),
      normalized: normalizeName(name),
      project: detectProject(name),
      stage: detectStage(name),
    });
  }
  return samples;
}

function buildCloudRows(items, localSamples) {
  const localByName = new Map();
  for (const sample of localSamples) {
    if (!localByName.has(sample.normalized)) localByName.set(sample.normalized, []);
    localByName.get(sample.normalized).push(sample.path);
  }

  const seen = new Set();
  const rows = [];
  for (const item of items) {
    const r = item.roaming || {};
    const f = item.file || {};
    const fileId = Number(f.fileid || r.fileid);
    const name = r.name || f.fname || '';
    const ftype = f.ftype || '';
    const date = dateFromItem(item);
    if (!fileId || !name || ftype === 'folder') continue;
    if (date < startDate || date > endDate) continue;
    if (!isProcurementRelated(name)) continue;
    if (seen.has(fileId)) continue;
    seen.add(fileId);

    const normalized = normalizeName(name);
    const project = detectProject(name);
    const stage = detectStage(name);
    const localMatches = localByName.get(normalized) || [];
    rows.push({
      date,
      project,
      stage,
      name,
      location: locationOf(item),
      wpsKey: `file_${fileId}`,
      sourceGroupId: Number(f.groupid || r.groupid || 0),
      sourceParentId: Number(f.parent_id ?? f.parentid ?? 0),
      cloudStatus: '云端已检出',
      localStatus: localMatches.length ? '本地样本已匹配' : '仅云端检出',
      localPaths: localMatches.join(' | '),
      confirmReason: project === '99_待确认' || stage === '99_待确认' ? '项目或阶段需人工确认' : '',
    });
  }
  rows.sort((a, b) => a.project.localeCompare(b.project, 'zh-CN') || a.stage.localeCompare(b.stage, 'zh-CN') || a.date.localeCompare(b.date));
  return rows;
}

function buildLocalOnlyRows(localSamples, cloudRows) {
  const cloudNames = new Set(cloudRows.map(row => normalizeName(row.name)));
  return localSamples
    .filter(sample => !cloudNames.has(sample.normalized))
    .sort((a, b) => a.project.localeCompare(b.project, 'zh-CN') || a.stage.localeCompare(b.stage, 'zh-CN') || a.date.localeCompare(b.date))
    .map(sample => ({
      date: sample.date,
      project: sample.project,
      stage: sample.stage,
      name: sample.name,
      localPath: sample.path,
      checkStatus: '本地样本有但云端清单未同名检出',
    }));
}

function counts(rows, key) {
  const map = new Map();
  for (const row of rows) map.set(row[key], (map.get(row[key]) || 0) + 1);
  return [...map.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-CN'));
}

function missingByProject(cloudRows, localOnlyRows) {
  const allProjects = [...new Set([
    ...cloudRows.map(row => row.project),
    ...localOnlyRows.map(row => row.project),
  ])].filter(project => project !== '99_待确认').sort((a, b) => a.localeCompare(b, 'zh-CN'));

  return allProjects.map(project => {
    const present = new Set([
      ...cloudRows.filter(row => row.project === project).map(row => row.stage),
      ...localOnlyRows.filter(row => row.project === project).map(row => row.stage),
    ]);
    const missingRequired = stages.filter(stage => stage.required && !present.has(stage.code)).map(stage => stage.code);
    const missingOptional = stages.filter(stage => !stage.required && !present.has(stage.code)).map(stage => stage.code);
    return {
      project,
      present: [...present].filter(x => x !== '99_待确认').sort().join('、') || '无',
      missingRequired,
      missingOptional,
    };
  });
}

async function writeCsv(file, headers, rows) {
  const lines = [headers.map(h => h.title).join(',')];
  for (const row of rows) lines.push(headers.map(h => csvEscape(row[h.key])).join(','));
  await fs.writeFile(file, '\uFEFF' + lines.join('\r\n'), 'utf8');
}

async function writeOutputs(cloudRows, localOnlyRows) {
  await fs.mkdir(outDir, { recursive: true });

  const cloudCsv = path.join(outDir, '云端归档清单.csv');
  const localCsv = path.join(outDir, '本地样本核对清单.csv');
  const reportMd = path.join(outDir, '缺件检查报告.md');
  const rulesMd = path.join(outDir, '工作流封装规则.md');
  const templateMd = path.join(outDir, '询价采购全过程归档模板.md');

  await writeCsv(cloudCsv, [
    { title: '日期', key: 'date' },
    { title: '匹配项目', key: 'project' },
    { title: '流程阶段', key: 'stage' },
    { title: '文件名', key: 'name' },
    { title: '来源位置', key: 'location' },
    { title: 'WPS key', key: 'wpsKey' },
    { title: '源groupid', key: 'sourceGroupId' },
    { title: '源parentid', key: 'sourceParentId' },
    { title: '云端状态', key: 'cloudStatus' },
    { title: '本地核对状态', key: 'localStatus' },
    { title: '本地样本路径', key: 'localPaths' },
    { title: '待确认原因', key: 'confirmReason' },
  ], cloudRows);

  await writeCsv(localCsv, [
    { title: '日期', key: 'date' },
    { title: '匹配项目', key: 'project' },
    { title: '流程阶段', key: 'stage' },
    { title: '文件名', key: 'name' },
    { title: '本地路径', key: 'localPath' },
    { title: '核对状态', key: 'checkStatus' },
  ], localOnlyRows);

  const missing = missingByProject(cloudRows, localOnlyRows);
  const needsConfirm = cloudRows.filter(row => row.project === '99_待确认' || row.stage === '99_待确认');
  const byProject = counts(cloudRows, 'project');
  const byStage = counts(cloudRows, 'stage');

  const report = [
    '# 询价采购全过程缺件检查报告',
    '',
    `- 数据源: WPS 云端 dry-run 为主，本地样本目录为 ${localSampleRoot}`,
    `- 日期范围: ${startDate} 至 ${endDate}`,
    `- 云端采购相关文件: ${cloudRows.length}`,
    `- 本地样本补充线索: ${localOnlyRows.length}`,
    `- 云端清单: ${cloudCsv}`,
    `- 本地核对清单: ${localCsv}`,
    '',
    '## 云端项目统计',
    ...byProject.map(([name, count]) => `- ${name}: ${count}`),
    '',
    '## 云端流程阶段统计',
    ...byStage.map(([name, count]) => `- ${name}: ${count}`),
    '',
    '## 项目缺件检查',
    ...missing.map(row => [
      `### ${row.project}`,
      `- 已见阶段: ${row.present}`,
      `- 必备缺件: ${row.missingRequired.length ? row.missingRequired.join('、') : '无'}`,
      `- 条件/后续缺件: ${row.missingOptional.length ? row.missingOptional.join('、') : '无'}`,
    ].join('\n')),
    '',
    '## 待人工确认',
    needsConfirm.length
      ? needsConfirm.slice(0, 80).map(row => `- ${row.date} | ${row.project} | ${row.stage} | ${row.wpsKey} | ${row.name}`).join('\n')
      : '- 无',
    needsConfirm.length > 80 ? `- 另有 ${needsConfirm.length - 80} 条详见云端归档清单。` : '',
    '',
    '## 本地样本有但云端清单未同名检出',
    localOnlyRows.length
      ? localOnlyRows.slice(0, 80).map(row => `- ${row.date} | ${row.project} | ${row.stage} | ${row.name}`).join('\n')
      : '- 无',
    localOnlyRows.length > 80 ? `- 另有 ${localOnlyRows.length - 80} 条详见本地样本核对清单。` : '',
    '',
  ].filter(Boolean).join('\n');
  await fs.writeFile(reportMd, '\uFEFF' + report, 'utf8');

  const rules = [
    '# 询价采购全过程归档工作流封装规则',
    '',
    '## 输入',
    `- WPS 云端扫描日期范围默认 ${startDate} 至 ${endDate}。`,
    `- 本地样本目录默认 ${localSampleRoot}，只用于核对，不作为主数据源。`,
    '',
    '## 项目识别',
    ...projects.map(project => `- ${project.name}: ${project.patterns.map(String).join('、')}`),
    '- 未命中项目关键词但命中采购关键词的文件进入 `99_待确认`。',
    '',
    '## 阶段识别',
    ...stages.map(stage => `- ${stage.code}: ${stage.patterns.map(String).join('、')}`),
    '- 合同法审优先归入 `09_合同审批与签订`，询价文件/采购文件法审优先归入 `03_询价文件及法审`。',
    '',
    '## 缺件判断',
    '- `01` 至 `09` 默认作为询价采购证据链必备阶段。',
    '- `10_订单履约结算` 作为框架协议、付款、验收、结算等后续阶段，按项目状态判断。',
    '- `99_待确认` 不计入阶段完备性，需人工复核后再并入正式阶段。',
    '',
    '## 安全规则',
    '- dry-run 只生成 CSV/Markdown。',
    '- 需要真正整理 WPS 云端时，只复制到新建归档目录，不删除、不移动、不覆盖原文件。',
  ].join('\n');
  await fs.writeFile(rulesMd, '\uFEFF' + rules, 'utf8');

  const template = [
    '# 询价采购全过程归档模板',
    '',
    '## 使用方式',
    '- 每个采购项目单独建一个项目目录，目录名建议为 `项目名称_采购年度或批次`。',
    '- 项目目录下按下列流程阶段排序归档，保持从决策到结算的证据链完整。',
    '- WPS 云端扫描结果为主，本地样本只作为核对和补充线索。',
    '',
    '## 01_决策立项',
    '- 归档材料：办公会议题、专题会议题、情况汇报、会议纪要、项目备案、预算测算、设备或材料清单。',
    '- 归档要点：先有集体决策依据；会议纪要如果晚出，可先归议题和情况汇报，后续补纪要。',
    '',
    '## 02_采购准备',
    '- 归档材料：采购审批表、采购申请表、至少三家初步询价或报价、最高限价、采购需求说明。',
    '- 归档要点：采购审批表与询价文件版本要能互相对应。',
    '',
    '## 03_询价文件及法审',
    '- 归档材料：询价采购文件、合同草案、修订稿、采购文件法审意见、补遗法审意见。',
    '- 归档要点：询价文件通常包含合同主要条款，挂网前应完成必要审查。',
    '',
    '## 04_挂网公告',
    '- 归档材料：询价公告、公告扫描件或网页截图、补遗/变更公告、流标公告。',
    '- 归档要点：公开询价公告期按制度不少于 3 个工作日；简易询价按适用制度另行标注。',
    '',
    '## 05_响应及保证金',
    '- 归档材料：响应文件、报价函/报价表、供应商资质、保证金银行回单或到账确认。',
    '- 归档要点：开标前确认全部应收响应保证金到账。',
    '',
    '## 06_开标评审',
    '- 归档材料：开标记录、开标视频、评审过程表、评审报告、评审小组材料、复评材料。',
    '- 归档要点：评审过程表和评审报告可提前套模板，开标后及时补实质内容。',
    '',
    '## 07_候选人与结果公示',
    '- 归档材料：成交候选人公示、成交结果公示、质疑函/异议函及回复、公示变更材料。',
    '- 归档要点：候选人公示与结果公示分别留存；结果公示按制度不少于 3 个工作日。',
    '',
    '## 08_通知书及保证金处理',
    '- 归档材料：成交通知书、成交结果通知书、未成交供应商保证金退还记录、成交方履约保证金处理记录。',
    '- 归档要点：先退未成交响应保证金，再进入合同审批和签署闭环。',
    '',
    '## 09_合同审批与签订',
    '- 归档材料：合同法审意见、修订模式合同、合同审批表、内网审批附件包、盖章合同、用章记录。',
    '- 归档要点：内网合同审批附件应上传前序关键材料，确保审批人能看到完整采购过程。',
    '',
    '## 10_订单履约结算',
    '- 归档材料：框架协议采购订单、到货/安装/调试/培训/验收资料、付款审批、发票、报销、结算、质保尾款。',
    '- 归档要点：框架协议类项目以下采购订单作为履约主线；付款结算需绑定验收和发票材料。',
    '',
    '## 99_待确认',
    '- 放置材料：文件名无法判断项目或阶段、扫描件未识别、重复版本冲突、非本次采购主线但可能相关的材料。',
    '- 处理规则：人工确认后并入正式阶段；确认为无关文件则从归档范围剔除。',
    '',
  ].join('\n');
  await fs.writeFile(templateMd, '\uFEFF' + template, 'utf8');

  return { cloudCsv, localCsv, reportMd, rulesMd, templateMd };
}

(async () => {
  const [wpsItems, localSamples] = await Promise.all([fetchWpsInventory(), readLocalSamples()]);
  const cloudRows = buildCloudRows(wpsItems, localSamples);
  const localOnlyRows = buildLocalOnlyRows(localSamples, cloudRows);
  const outputs = await writeOutputs(cloudRows, localOnlyRows);
  console.log(JSON.stringify({
    dateRange: `${startDate}..${endDate}`,
    cloudRows: cloudRows.length,
    localOnlyRows: localOnlyRows.length,
    outputs,
    byProject: Object.fromEntries(counts(cloudRows, 'project')),
    byStage: Object.fromEntries(counts(cloudRows, 'stage')),
  }, null, 2));
})().catch(err => {
  console.error(err.stack || err.message || err);
  process.exit(1);
});
