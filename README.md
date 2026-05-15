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
| `auto-video-editing` | 从 SRT 字幕生成完整白板动画视频。 | 适合把字幕拆成分镜，依次完成图片生成、白板动画视频生成和端到端剪辑工作流；对应本机中文 skill“自动剪辑”。 |
| `chrome` | 通过 Codex Chrome 扩展控制外部 Google Chrome。 | 适合用户明确说 `@chrome`、要查看当前 Chrome 标签页、操作已有网页，或使用已安装的 Codex Chrome 扩展进行浏览器自动化。 |
| `continuous-dialogue` | 多轮连续对话推进和结构化记录。 | 适合在 Chrome、ChatGPT 网页或项目页面中一轮一轮推进访谈、研究、长对话，并把过程整理成 Markdown 或 Obsidian 笔记。 |
| `convert-anything-to-markdown` | 把常见文件转换成 Markdown。 | 适合把 PDF、DOCX、PPTX、XLSX、图片、HTML、音频、JSON、XML、CSV、ZIP 等转换为适合 Obsidian、LLM 输入或知识库整理的 Markdown。 |
| `oh-my-codex` | oh-my-codex / OMX 工作流助手。 | 适合了解、安装、评估、使用和排查 OMX 工作流，包括深度访谈、规划审批、持续执行和并行团队执行等模式。 |
| `paper-auto-writing` | 论文自动写作和 AI-Scientist-v2 风格流程。 | 适合研究选题、论文大纲、文献综合、草稿写作、评审式修改、运行计划生成和实验日志/PDF 总结。 |
| `playwright` | 通过命令行 Playwright 自动化真实浏览器。 | 适合网页导航、表单填写、截图、页面数据提取和 UI 流程调试，偏 CLI 自动化场景。 |
| `playwright-interactive` | 持久化 Playwright 浏览器与 Electron 调试。 | 适合本地 Web 应用、Electron 应用的交互式调试、视觉检查、功能 QA 和截图验证。 |
| `search-last-30-days-discussions` | 跨平台搜索最近 30 天真实讨论。 | 适合研究人物、公司、产品、事件、竞品对比、舆情、社区反馈和趋势判断，综合 Reddit、X、YouTube、Hacker News、GitHub、Polymarket 和网页信号。 |
| `token-pacing` | 计算 token/额度使用节奏。 | 适合根据当前用量和重置时间，估算每天可用额度、是否会提前耗尽，以及如何把额度刚好用到重置前。 |
| `wechat-query` | 微信公众号文章订阅、查询与推送。 | 适合部署微信公众号文章缓存服务、扫码登录、订阅公众号、查询缓存文章、抓取单篇文章全文，以及配置每日巡检和文章汇总推送。 |
| `whiteboard-animation` | 从图片生成白板手绘动画视频。 | 适合把单张或批量图片转换成带线稿绘制、上色和手部覆盖效果的 H.264 MP4 白板动画。 |
| `wps-doc-organizer` | WPS / 金山文档云端整理。 | 适合按日期范围扫描 WPS 云文档，按业务目录分类，生成 dry-run 清单，并在确认后复制归档，不删除原文件。 |
| `wx-cli` | 查询本地微信数据库中的聊天记录和联系人。 | 适合安装并调用 `wx-cli` 查询微信聊天记录、消息历史、联系人、群成员、会话和收藏内容。 |
| `zhishi-xingqiu-web-collector` | 知识星球和网页内容采集到 Markdown。 | 适合采集知识星球帖子、文件区、网页文章、列表页和长滚动页面，保留正文、图片、截图、翻页和去重后的 Markdown。 |

## 仓库结构

```text
codex-skills-cn/
  README.md
  LICENSE
  skills/
    auto-video-editing/
    chrome/
    continuous-dialogue/
    convert-anything-to-markdown/
    oh-my-codex/
    paper-auto-writing/
    playwright/
    playwright-interactive/
    search-last-30-days-discussions/
    token-pacing/
    wechat-query/
    whiteboard-animation/
    wps-doc-organizer/
    wx-cli/
    zhishi-xingqiu-web-collector/
```

## 安全提醒

发布和复用 skills 时，不要提交真实的 API Key、cookie、Authorization header、访问令牌、账号密码、私人文档或其他敏感信息。

本仓库中的脚本和说明可能会提到环境变量名或占位符，例如 `OPENAI_API_KEY`、`S2_API_KEY`、`WECHAT_COOKIE`、`<Cookie header>`。这些只是使用说明，不应替换成真实密钥后提交。

`wechat-query`、`wx-cli`、`自动剪辑` 等涉及本地环境或账号状态的 skills 只发布源码、说明和模板，不包含本地 `.env`、登录 cookie、SQLite 数据库、日志、虚拟环境、构建产物或动态二维码。
