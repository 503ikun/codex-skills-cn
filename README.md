# Codex Skills 中文集合

这是 503ikun 的个人 Codex skills 集合，用于跨设备备份、开源发布和复用。

固定仓库链接：

```text
https://github.com/503ikun/codex-skills-cn
```

下次在新的 Codex 环境里，可以直接复制这句话给 Codex：

```text
请从 https://github.com/503ikun/codex-skills-cn 安装里面的全部 Codex skills。
```

如果只想安装某一个 skill，可以这样说：

```text
请从 https://github.com/503ikun/codex-skills-cn 安装 skills/wps-doc-organizer。
```

安装后请重启 Codex，让新 skills 被加载。

## Skills 列表

| Skill | 简介 | 适用场景 |
| --- | --- | --- |
| `continuous-dialogue` | 多轮连续对话推进和结构化记录。 | 适合在 Chrome、ChatGPT 网页或项目页面中一轮一轮推进访谈、研究、长对话，并把过程整理成 Markdown 或 Obsidian 笔记。 |
| `convert-anything-to-markdown` | 把常见文件转换成 Markdown。 | 适合把 PDF、DOCX、PPTX、XLSX、图片、HTML、音频、JSON、XML、CSV、ZIP 等转换为适合 Obsidian、LLM 输入或知识库整理的 Markdown。 |
| `oh-my-codex` | oh-my-codex / OMX 工作流助手。 | 适合了解、安装、评估、使用和排查 OMX 工作流，包括深度访谈、规划审批、持续执行和并行团队执行等模式。 |
| `paper-auto-writing` | 论文自动写作和 AI-Scientist-v2 风格流程。 | 适合研究选题、论文大纲、文献综合、草稿写作、评审式修改、运行计划生成和实验日志/PDF 总结。 |
| `playwright-interactive` | 持久化 Playwright 浏览器与 Electron 调试。 | 适合本地 Web 应用、Electron 应用的交互式调试、视觉检查、功能 QA 和截图验证。 |
| `search-last-30-days-discussions` | 跨平台搜索最近 30 天真实讨论。 | 适合研究人物、公司、产品、事件、竞品对比、舆情、社区反馈和趋势判断，综合 Reddit、X、YouTube、Hacker News、GitHub、Polymarket 和网页信号。 |
| `wps-doc-organizer` | WPS / 金山文档云端整理。 | 适合按日期范围扫描 WPS 云文档，按业务目录分类，生成 dry-run 清单，并在确认后复制归档，不删除原文件。 |
| `zhishi-xingqiu-web-collector` | 知识星球和网页内容采集到 Markdown。 | 适合采集知识星球帖子、文件区、网页文章、列表页和长滚动页面，保留正文、图片、截图、翻页和去重后的 Markdown。 |

## 仓库结构

```text
codex-skills-cn/
  README.md
  LICENSE
  skills/
    continuous-dialogue/
    convert-anything-to-markdown/
    oh-my-codex/
    paper-auto-writing/
    playwright-interactive/
    search-last-30-days-discussions/
    wps-doc-organizer/
    zhishi-xingqiu-web-collector/
```

## 安全提醒

发布和复用 skills 时，不要提交真实的 API Key、cookie、Authorization header、访问令牌、账号密码、私人文档或其他敏感信息。

本仓库中的脚本和说明可能会提到环境变量名或占位符，例如 `OPENAI_API_KEY`、`S2_API_KEY`、`<Cookie header>`。这些只是使用说明，不应替换成真实密钥后提交。
