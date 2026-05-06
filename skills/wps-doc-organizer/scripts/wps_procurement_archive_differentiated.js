const fs = require('fs/promises');
const path = require('path');

const startDate = '2025-09-01';
const endDate = '2026-04-28';
const baseDir = path.join(process.cwd(), 'output', `询价采购全过程归档_${startDate}至${endDate}`);
const cloudCsv = path.join(baseDir, '云端归档清单.csv');
const localCsv = path.join(baseDir, '本地样本核对清单.csv');
const outDir = path.join(process.cwd(), 'output', `询价采购全过程归档_差异化规则版_${startDate}至${endDate}`);

const projectConfigs = {
  'LED芯片': {
    type: '完整公开询价',
    status: '已完成',
    aliases: [/LED芯片/i, /LED灯珠芯片/i, /芯片/, /灯珠/],
    note: '完整公开询价样例；重点复核合同、合同法审、履约函、订单。',
    requirements: fullInquiryRequirements({ allowMissingResponse: true, allowMissingReason: '业务提示为已有；当前未按文件名直接检出，可能在通用响应文件、保证金回单或扫描件包中，列为待人工复核。' }),
  },
  'SMT整线生产设备': {
    type: '完整公开询价',
    status: '已完成',
    aliases: [/SMT/i, /整线生产设备/, /贴片机/, /锡膏/, /钢网/],
    note: '完整公开询价样例；保留流标、二次询价、开标视频、扫描件包、合同 zip 为补充证据。',
    requirements: fullInquiryRequirements({ allowMissingResponse: true, allowMissingReason: '响应文件/保证金材料可能已随扫描件包或招标代理资料归档，需人工复核。' }),
  },
  '压铸件': {
    type: '完整公开询价',
    status: '已完成',
    aliases: [/压铸件/, /散热器/],
    note: '响应保证金已退还；保证金处理状态按业务事实标注为已完成。',
    requirements: fullInquiryRequirements({ guaranteeCompleted: true, allowMissingResponse: true, allowMissingReason: '业务确认：响应保证金已退还；若响应文件/回单未按文件名检出，不作为硬缺件。' }),
  },
  '钢板': {
    type: '低值零星采购',
    status: '已完成',
    aliases: [/钢板/],
    note: '低于 20000 元零星采购；不要求公告、公示、评审、保证金。',
    requirements: pettyPurchaseRequirements(),
  },
  '消防设备': {
    type: '低值零星采购',
    status: '已完成',
    aliases: [/消防设备/, /零星采购-消防/, /消防/],
    exclude: [/废旧灭火器/, /灭火器处置/, /买受人/, /拍卖须知/, /灭火器保证金/, /废旧物资/],
    note: '零星消防设备只检查审批、合同/采购确认、验收/交接、结算付款；历史灭火器处置单列备查。',
    requirements: pettyPurchaseRequirements({ contractOptional: false }),
  },
  '驱动电源': {
    type: '招标代理配合归档',
    status: '未签合同',
    aliases: [/驱动电源/, /公母防水接头/, /防水接头/],
    note: '响应保证金由招标代理公司处理，本方不按缺件处理；当前合同阶段为待签/待补。',
    requirements: agencySupportRequirements(),
  },
  '装修及厂房改造': {
    type: '系统内委托',
    status: '执行中',
    aliases: [/装修/, /厂房/, /古田/, /改造工程/, /智造中心/],
    note: '直接委托系统内公司，不要求公开询价完整链条。',
    requirements: internalEntrustRequirements(),
  },
  '劳务外包服务': {
    type: '未执行或暂缓',
    status: '未执行',
    aliases: [/劳务外包/],
    note: '未执行；只归档已形成的议题、情况汇报、办公会材料，不生成执行缺件。',
    requirements: suspendedRequirements(),
  },
  '透镜硅胶圈': {
    type: '未执行或暂缓',
    status: '未开始执行',
    aliases: [/透镜硅胶圈/, /硅胶圈/, /密封圈/],
    note: '预计走专题会，尚未开始执行；只归档准备材料。',
    requirements: suspendedRequirements({ includeContractDraft: true }),
  },
};

function fullInquiryRequirements(options = {}) {
  return [
    req('01_决策立项', '办公会议题/专题会/情况汇报/会议纪要/预算或清单', true),
    req('02_采购准备', '采购审批表、三家询价/报价、最高限价或采购需求', true),
    req('03_询价文件及法审', '询价采购文件、合同草案、采购文件法审意见、修订稿', true),
    req('04_挂网公告', '询价公告、公告截图/扫描件、补遗/变更/流标公告', true),
    req('05_响应及保证金', options.guaranteeCompleted ? '响应文件、报价文件、保证金到账及退还记录' : '响应文件、报价文件、保证金到账记录', !options.allowMissingResponse, options.allowMissingReason || ''),
    req('06_开标评审', '开标记录/开标视频、评审过程表、评审报告', true),
    req('07_候选人与结果公示', '成交候选人公示、成交结果公示、异议/质疑回复', true),
    req('08_通知书及保证金处理', options.guaranteeCompleted ? '成交通知书、未成交保证金退还记录（已退还）' : '成交通知书、保证金退还/转履约记录', true, options.guaranteeCompleted ? '业务确认：响应保证金已退还。' : ''),
    req('09_合同审批与签订', '合同法审、合同审批表、盖章合同、用章/内网审批附件', true),
    req('10_订单履约结算', '采购订单、验收/交付/培训、付款、发票、报销、结算', false),
    req('补充证据', '开标视频、扫描件包、合同 zip、履约函、往来函件', false),
  ];
}

function pettyPurchaseRequirements(options = {}) {
  return [
    req('02_采购准备', '采购审批表/采购申请/采购审批表+付款', true),
    req('09_合同审批与签订', options.contractOptional ? '合同或采购确认文件（可选）' : '合同或采购确认文件', !options.contractOptional),
    req('验收交接', '验收单、发货单、交接单、签收单', true),
    req('10_订单履约结算', '付款、报销、结算、发票', false),
    req('不适用', '公告、公示、评审报告、成交通知书、响应保证金', false, '低值零星采购不要求完整公开询价链条。'),
  ];
}

function agencySupportRequirements() {
  return [
    req('01_决策立项', '办公会/专题会/情况汇报/采购事宜汇报', true),
    req('02_采购准备', '采购审批表、初步报价或采购需求', true),
    req('03_询价文件及法审', '询价文件、补遗书、法审意见', true),
    req('04_挂网公告', '公告、补遗、变更公告、代理发布材料', true),
    req('07_候选人与结果公示', '成交候选人公示、成交结果公示、公示变更', true),
    req('代理保证金', '响应保证金由招标代理公司办理，本方配合归档，不作为缺件', false, '业务确认：保证金委托招标代理处理。'),
    req('用章配合', '成交通知书、成交结果通知书、用章留存件、配合代理盖章材料', false),
    req('09_合同审批与签订', '合同法审、合同审批、签约合同', false, '当前未签合同，标记为待签/待补。'),
  ];
}

function internalEntrustRequirements() {
  return [
    req('01_决策立项', '决策材料、专题会/办公会、情况汇报', true),
    req('委托依据', '委托函、系统内公司承接依据、合同或协议', true),
    req('实施过程', '施工图、预算审核、协调函、整改通知、过程记录', false),
    req('验收交接', '验收单、整改闭环、交接/确认材料', false),
    req('10_订单履约结算', '付款、报销、结算、发票', false),
    req('不适用', '公开询价公告、公示、评审报告、保证金', false, '系统内委托流程不按完整公开询价链条检查。'),
  ];
}

function suspendedRequirements(options = {}) {
  const requirements = [
    req('01_决策立项', '专题会/办公会议题/情况汇报/准备材料', false, '项目未执行或未开始执行，仅归档已形成材料。'),
    req('02_采购准备', '需求、报价、初步方案、审批草稿', false),
  ];
  if (options.includeContractDraft) requirements.push(req('合同草稿', '合同草稿或订单草稿，如已形成则归档', false));
  requirements.push(req('不适用', '公告、公示、评审、保证金、正式合同、验收付款', false, '未执行或未开始执行，不生成后续缺件。'));
  return requirements;
}

function req(stage, material, required, note = '') {
  return { stage, material, required, note };
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
  return rows
    .filter(r => r.some(Boolean))
    .map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] || ''])));
}

function csvEscape(value) {
  const s = String(value ?? '');
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function normalize(value) {
  return String(value || '').toLowerCase().replace(/\s+/g, '');
}

function rowText(row) {
  return `${row['文件名'] || ''} ${row['本地样本路径'] || ''} ${row['本地路径'] || ''} ${row['匹配项目'] || ''}`;
}

function detectProject(row) {
  const current = row['匹配项目'];
  const text = rowText(row);
  if (current && current !== '99_待确认' && projectConfigs[current]) return current;

  // Avoid mixing historical old-extinguisher disposal into current low-value fire equipment purchase.
  if (/灭火器|废旧物资|买受人|拍卖须知/.test(text)) return '灭火器处置备查';

  for (const [project, config] of Object.entries(projectConfigs)) {
    if (config.exclude && config.exclude.some(re => re.test(text))) continue;
    if (config.aliases.some(re => re.test(text))) return project;
  }
  return current || '99_待确认';
}

function detectStage(row, project) {
  const name = row['文件名'] || '';
  const text = rowText(row);
  const current = row['流程阶段'] || '99_待确认';

  if (/开标视频|\.mp4$/i.test(text)) return '补充证据';
  if (/扫描件|wpssc|\.zip$/i.test(text)) return '补充证据';
  if (/履约事项|电压等级|商请明确|供货事项|往来函|回函/.test(text)) return '补充证据';
  if (/验收单|发货单|交接清单|签收单|整改通知|整改|施工整改/.test(text)) return '验收交接';
  if (/委托|系统内|造价咨询|预算审核|施工图|工程量|协调处理/.test(text) && project === '装修及厂房改造') return /验收|整改|协调/.test(text) ? '实施过程' : '委托依据';
  if (/合同审批|合同审查|审查意见.*合同|采购合同|补充协议|合同\.|合同（|合同\(|盖章合同|用章/.test(name)) return '09_合同审批与签订';
  if (/审查意见|法审/.test(name) && /(询价|采购文件|补遗|招标文件)/.test(name)) return '03_询价文件及法审';
  if (/询价.*文件|采购文件|招标文件|集中预采购项目|公开询价采购/.test(name)) return '03_询价文件及法审';
  if (/采购审批|审批表|采购申请|申请表/.test(name)) return '02_采购准备';
  if (/报价|询价记录|控制价|最高限价/.test(name)) return '02_采购准备';
  if (/公告|补遗|变更公告|流标公告/.test(name)) return '04_挂网公告';
  if (/响应文件|投标|保证金|银行回单|报价函|报价表/.test(name)) return '05_响应及保证金';
  if (/开标|评审|评标|复评/.test(name)) return '06_开标评审';
  if (/候选人公示|结果公示|质疑|异议|公示变更/.test(name)) return '07_候选人与结果公示';
  if (/成交通知书|成交结果通知书/.test(name)) return '08_通知书及保证金处理';
  if (/订单|付款|预付款|报销|结算|发票|尾款/.test(name)) return '10_订单履约结算';
  if (/办公会|专题会|会议纪要|议题|情况汇报|预算|清单|备案/.test(name)) return '01_决策立项';
  return current;
}

function shouldInclude(row, project) {
  if (project === '99_待确认') return false;
  const text = rowText(row);
  if (project === '消防设备' && /废旧灭火器|灭火器处置|买受人|拍卖须知|废旧物资/.test(text)) return false;
  return true;
}

function enrichRows(cloudRows, localRows) {
  const rows = [];
  for (const row of cloudRows) {
    const project = detectProject(row);
    if (!shouldInclude(row, project)) continue;
    rows.push({
      source: 'WPS云端',
      date: row['日期'],
      project,
      originalProject: row['匹配项目'],
      stage: detectStage(row, project),
      originalStage: row['流程阶段'],
      name: row['文件名'],
      wpsKey: row['WPS key'],
      sourceParentId: row['源parentid'],
      localPath: row['本地样本路径'],
      location: row['来源位置'],
    });
  }
  for (const row of localRows) {
    const project = detectProject(row);
    if (!shouldInclude(row, project)) continue;
    rows.push({
      source: '本地样本',
      date: row['日期'],
      project,
      originalProject: row['匹配项目'],
      stage: detectStage(row, project),
      originalStage: row['流程阶段'],
      name: row['文件名'],
      wpsKey: '',
      sourceParentId: '',
      localPath: row['本地路径'],
      location: '本地样本',
    });
  }
  return dedupeRows(rows).sort((a, b) =>
    a.project.localeCompare(b.project, 'zh-CN') ||
    a.stage.localeCompare(b.stage, 'zh-CN') ||
    a.date.localeCompare(b.date) ||
    a.name.localeCompare(b.name, 'zh-CN')
  );
}

function dedupeRows(rows) {
  const seen = new Set();
  const out = [];
  for (const row of rows) {
    const key = row.wpsKey || `${row.project}|${row.stage}|${normalize(row.name)}|${normalize(row.localPath)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(row);
  }
  return out;
}

function matchRequirement(rows, project, requirement) {
  const projectRows = rows.filter(r => r.project === project);
  if (requirement.stage === '不适用') return [];
  if (requirement.stage === '代理保证金') {
    return projectRows.filter(r => /保证金/.test(r.name));
  }
  if (requirement.stage === '用章配合') {
    return projectRows.filter(r => /用章|成交通知|成交结果通知|后续盖章/.test(`${r.name} ${r.localPath}`));
  }
  if (requirement.stage === '合同草稿') {
    return projectRows.filter(r => /合同|订单/.test(r.name));
  }
  return projectRows.filter(r => r.stage === requirement.stage);
}

function summarizeFiles(files) {
  if (!files.length) return '';
  return files.slice(0, 8).map(file => {
    const key = file.wpsKey ? ` [${file.wpsKey}]` : '';
    return `${file.date} ${file.name}${key}`;
  }).join('；');
}

function summarizePaths(files) {
  return files
    .map(file => file.localPath)
    .filter(Boolean)
    .slice(0, 5)
    .join(' | ');
}

function buildChecklist(rows) {
  const checklist = [];
  for (const [project, config] of Object.entries(projectConfigs)) {
    for (const requirement of config.requirements) {
      const matched = matchRequirement(rows, project, requirement);
      const missing = requirement.required && matched.length === 0;
      let status = missing ? '缺件' : matched.length ? '已检出' : '合理缺省/不适用';
      let note = requirement.note || config.note || '';
      if (project === '驱动电源' && requirement.stage === '09_合同审批与签订') status = matched.length ? '待签/已有前置材料' : '待签/待补';
      if (project === '压铸件' && requirement.stage === '08_通知书及保证金处理') note = [note, '业务确认：响应保证金已退还。'].filter(Boolean).join(' ');
      if (!requirement.required && matched.length === 0 && requirement.stage === '05_响应及保证金') status = '待人工复核';
      checklist.push({
        project,
        type: config.type,
        status: config.status,
        stage: requirement.stage,
        material: requirement.material,
        foundFiles: summarizeFiles(matched),
        wpsKeys: matched.map(x => x.wpsKey).filter(Boolean).slice(0, 12).join(' | '),
        localPaths: summarizePaths(matched),
        isMissing: missing ? '是' : '否',
        checkStatus: status,
        note,
      });
    }
  }
  return checklist;
}

function counts(rows, key) {
  const map = new Map();
  for (const row of rows) map.set(row[key], (map.get(row[key]) || 0) + 1);
  return [...map.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-CN'));
}

async function writeCsv(file, headers, rows) {
  const lines = [headers.map(h => h.title).join(',')];
  for (const row of rows) lines.push(headers.map(h => csvEscape(row[h.key])).join(','));
  await fs.writeFile(file, '\uFEFF' + lines.join('\r\n'), 'utf8');
}

function buildReport(checklist, rows) {
  const lines = [
    '# 按项目归档检查报告',
    '',
    `- 数据源: ${cloudCsv}`,
    `- 本地样本: ${localCsv}`,
    `- 日期范围: ${startDate} 至 ${endDate}`,
    `- 差异化规则后纳入文件: ${rows.length}`,
    '',
    '## 项目统计',
    ...counts(rows, 'project').map(([k, v]) => `- ${k}: ${v}`),
    '',
  ];

  for (const [project, config] of Object.entries(projectConfigs)) {
    const projectItems = checklist.filter(x => x.project === project);
    lines.push(`## ${project}`);
    lines.push(`- 采购类型: ${config.type}`);
    lines.push(`- 项目状态: ${config.status}`);
    lines.push(`- 说明: ${config.note}`);
    lines.push('');
    lines.push('| 流程阶段 | 材料要求 | 检查状态 | 已找到材料 | 备注 |');
    lines.push('| --- | --- | --- | --- | --- |');
    for (const item of projectItems) {
      lines.push(`| ${item.stage} | ${item.material} | ${item.checkStatus} | ${item.foundFiles || '-'} | ${item.note || '-'} |`);
    }
    const missing = projectItems.filter(x => x.isMissing === '是');
    lines.push('');
    lines.push(`- 必备缺件: ${missing.length ? missing.map(x => x.stage).join('、') : '无'}`);
    lines.push('');
  }
  return lines.join('\n');
}

function buildRules() {
  return [
    '# 工作流封装规则（差异化规则版）',
    '',
    '## 数据源',
    '- 以 WPS 云端 dry-run 清单为主。',
    '- 本地样本只用于补充识别通用文件名、开标视频、扫描件包、合同 zip 等证据。',
    '- 本工作流只生成本地 CSV/Markdown，不执行云端复制、删除或覆盖。',
    '',
    '## 采购类型',
    '- 完整公开询价：检查决策、审批、询价文件法审、公告、响应/保证金、开标评审、公示、通知书、合同审批、订单结算。',
    '- 低值零星采购：只检查采购审批表、合同或采购确认文件、验收单、发货单/交接单、付款/报销；不要求公告、公示、评审、成交通知书、保证金。',
    '- 招标代理配合归档：保证金由代理处理，不作为本方缺件；重点归档公告/补遗/公示、配合用章、后续合同材料。',
    '- 系统内委托：检查决策、委托依据、合同/协议、实施过程、验收整改、结算；不按公开询价链条检查。',
    '- 未执行或暂缓：只归档已形成的专题会、议题、情况汇报、准备材料，不生成后续缺件。',
    '',
    '## 项目事实',
    '- 钢板、消防设备：低值零星采购。',
    '- 劳务外包服务：未执行。',
    '- 驱动电源：招标代理配合归档，当前未签合同。',
    '- 透镜硅胶圈：预计走专题会，当前未开始执行。',
    '- 压铸件：完整公开询价，响应保证金已退还。',
    '- 装修及厂房改造：系统内委托。',
    '- LED芯片、SMT整线生产设备：完整公开询价样例。',
    '',
    '## 通用文件识别',
    '- `成交通知书.doc`、`响应文件---光通.docx`、`保证金处置说明函.pdf` 等通用名称需结合项目关键词、parentid、本地路径和同批材料判断。',
    '- LED 芯片合同、合同法审、履约函归入合同审批或补充证据。',
    '- SMT 开标视频、扫描件包、合同 zip 归入补充证据，不作为必备阶段缺件。',
    '',
  ].join('\n');
}

async function main() {
  const cloudRows = parseCsv(await fs.readFile(cloudCsv, 'utf8'));
  const localRows = parseCsv(await fs.readFile(localCsv, 'utf8'));
  const rows = enrichRows(cloudRows, localRows);
  const checklist = buildChecklist(rows);

  await fs.mkdir(outDir, { recursive: true });
  const detailedCsv = path.join(outDir, '项目详细归档清单.csv');
  const reportMd = path.join(outDir, '按项目归档检查报告.md');
  const rulesMd = path.join(outDir, '工作流封装规则.md');
  const evidenceCsv = path.join(outDir, '差异化归档证据明细.csv');

  await writeCsv(detailedCsv, [
    { title: '项目', key: 'project' },
    { title: '采购类型', key: 'type' },
    { title: '项目状态', key: 'status' },
    { title: '流程阶段', key: 'stage' },
    { title: '材料要求', key: 'material' },
    { title: '已检出文件', key: 'foundFiles' },
    { title: 'WPS key', key: 'wpsKeys' },
    { title: '本地样本路径', key: 'localPaths' },
    { title: '是否缺件', key: 'isMissing' },
    { title: '检查状态', key: 'checkStatus' },
    { title: '备注', key: 'note' },
  ], checklist);

  await writeCsv(evidenceCsv, [
    { title: '来源', key: 'source' },
    { title: '日期', key: 'date' },
    { title: '项目', key: 'project' },
    { title: '原匹配项目', key: 'originalProject' },
    { title: '流程阶段', key: 'stage' },
    { title: '原流程阶段', key: 'originalStage' },
    { title: '文件名', key: 'name' },
    { title: 'WPS key', key: 'wpsKey' },
    { title: '源parentid', key: 'sourceParentId' },
    { title: '本地路径', key: 'localPath' },
    { title: '来源位置', key: 'location' },
  ], rows);

  await fs.writeFile(reportMd, '\uFEFF' + buildReport(checklist, rows), 'utf8');
  await fs.writeFile(rulesMd, '\uFEFF' + buildRules(), 'utf8');

  const missing = checklist.filter(x => x.isMissing === '是');
  console.log(JSON.stringify({
    inputCloudRows: cloudRows.length,
    inputLocalRows: localRows.length,
    evidenceRows: rows.length,
    checklistRows: checklist.length,
    missingRows: missing.length,
    outputs: { detailedCsv, evidenceCsv, reportMd, rulesMd },
    missingByProject: Object.fromEntries(counts(missing, 'project')),
  }, null, 2));
}

main().catch(err => {
  console.error(err.stack || err.message || err);
  process.exit(1);
});
