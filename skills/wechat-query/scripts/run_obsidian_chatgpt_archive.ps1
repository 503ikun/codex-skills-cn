[CmdletBinding()]
param(
    [int]$HoursBack = 24,
    [string]$ApiBase = 'http://localhost:5000',
    [string]$OutputRoot = 'C:\Users\Administrator\iCloudDrive\iCloud~md~obsidian\obsidian\仓库\微信公众号跟踪',
    [string[]]$Accounts = @(
        '赛博禅心',
        '酷玩实验室',
        '数据GO',
        '滇南王',
        '记忆承载3',
        '记忆承载',
        '大树乡谈',
        '木禾黑猫',
        'L先生说',
        '今天你看多了吗',
        '饭爷的江湖',
        '炒股拌饭',
        '数字生命卡兹克',
        '401K-景交所',
        '在公关',
        '谈资',
        'Sir电影',
        '逛逛GitHub'
    ),
    [ValidateSet('single-long-dialogue','none')]
    [string]$ChatMode = 'single-long-dialogue',
    [ValidateSet('skip','stop')]
    [string]$OnChatGPTFailure = 'skip',
    [switch]$DryRun,
    [int]$MaxArticles = 0,
    [string]$TitleLike = '*Google Chrome*',
    [int]$ReplyTimeoutSec = 900,
    [string]$NowIso = '',
    [string[]]$SingleMainArticleAccounts = @('酷玩实验室')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ContinuousDialogueHelper = Join-Path (Split-Path -Parent $SkillRoot) 'continuous-dialogue\scripts\chrome-chatgpt-uia.ps1'

function Invoke-JsonGet {
    param([string]$Path, [hashtable]$Query = @{})
    $builder = [System.UriBuilder]::new(($ApiBase.TrimEnd('/') + $Path))
    if ($Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$Query[$key])
        }
        $builder.Query = ($pairs -join '&')
    }
    $client = [System.Net.WebClient]::new()
    $client.Encoding = [System.Text.Encoding]::UTF8
    try {
        $client.DownloadString($builder.Uri.AbsoluteUri) | ConvertFrom-Json
    } finally {
        $client.Dispose()
    }
}

function Invoke-JsonPost {
    param([string]$Path, [object]$Body = $null)
    $uri = $ApiBase.TrimEnd('/') + $Path
    $client = [System.Net.WebClient]::new()
    $client.Encoding = [System.Text.Encoding]::UTF8
    $client.Headers[[System.Net.HttpRequestHeader]::ContentType] = 'application/json; charset=utf-8'
    try {
        if ($null -eq $Body) {
            $client.UploadString($uri, 'POST', '') | ConvertFrom-Json
        } else {
            $json = $Body | ConvertTo-Json -Depth 20
            $client.UploadString($uri, 'POST', $json) | ConvertFrom-Json
        }
    } finally {
        $client.Dispose()
    }
}

function Invoke-ArticleFetchWithRetry {
    param(
        [string]$Url,
        [int]$MaxAttempts = 4
    )

    $last = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $last = Invoke-JsonPost -Path '/api/article/fetch' -Body @{ url = $Url }
        if ($last.success) { return $last }

        $message = [string]$last.error
        $waitSeconds = 4
        if ($message -match '(\d+)\s*秒') {
            $waitSeconds = [Math]::Max(4, [int]$Matches[1] + 1)
        }
        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $waitSeconds
        }
    }
    $last
}

function Write-Utf8BomText {
    param([string]$Path, [string]$Text)
    $encoding = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-Utf8Text {
    param([string]$Path, [string]$Text)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function ConvertTo-BeijingTime {
    param([long]$UnixSeconds)
    if ($UnixSeconds -le 0) { return $null }
    [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds).ToOffset([TimeSpan]::FromHours(8))
}

function Get-FirstAccountCandidate {
    param([object]$SearchResponse)
    if (-not $SearchResponse.success) { return $null }
    if ($SearchResponse.data -and $SearchResponse.data.list -and $SearchResponse.data.list.Count -gt 0) {
        return $SearchResponse.data.list[0]
    }
    $null
}

function Get-ArticleItems {
    param([object]$ArticlesResponse)
    if (-not $ArticlesResponse.success) { return @() }
    if ($ArticlesResponse.data -and $ArticlesResponse.data.articles) {
        return @($ArticlesResponse.data.articles)
    }
    @()
}

function Test-SingleMainArticleAccount {
    param(
        [string]$Query,
        [string]$Nickname
    )

    foreach ($account in $SingleMainArticleAccounts) {
        if ($Query -eq $account -or $Nickname -eq $account) { return $true }
    }
    $false
}

function New-MasterPrompt {
    param([object[]]$Articles)
    $lines = @(
        '我们接下来在同一个非临时对话里连续精读一批微信公众号文章。',
        '',
        '目标：',
        '1. 每篇都输出尽量长、结构化、可直接放进 Obsidian 的中文分析。',
        '2. 每篇都要根据文章具体主题提出针对性问题，不要使用模板化空问题。',
        '3. 每篇都要连接到我的个人知识库、正式组织/采购/风控工作、投资判断、AI workflow 和 Obsidian 知识系统。',
        '4. 从第二篇开始主动寻找与前文的呼应、冲突、互证和可建立的双链。',
        '5. 不要只摘要，要拆论点、证据链、隐含前提、弱点、反方观点、可迁移框架。',
        '',
        '统一输出结构：',
        '- Suggested theme classification',
        '- Long-form core summary',
        '- Author key claims and evidence chain',
        '- Hidden assumptions / weak points',
        '- Targeted questions',
        '- Personal connections',
        '- Cross-article echoes',
        '- Obsidian-ready final note block',
        '',
        '本批文章：'
    )
    foreach ($article in $Articles) {
        $lines += ('- 第 {0} 篇：{1}｜{2}' -f $article.article_index, $article.account_nickname, $article.title)
    }
    $lines -join "`n"
}

function New-ArticlePrompt {
    param([object]$Article)
    @"
请处理第 $($Article.article_index) 篇文章。必须只围绕本篇文章，但要主动与前面已经处理过的文章建立呼应。

文章元信息：
- 公众号：$($Article.account_nickname)
- 标题：$($Article.title)
- 发布时间：$($Article.publish_dt)
- 原文链接：$($Article.link)

请输出尽量长，且按以下结构：
1. Suggested theme classification：根据本篇内容判断主题，不要套固定分类。
2. Long-form core summary：长摘要，保留关键细节、转折、作者态度。
3. Author's key claims and evidence chain：逐条拆主要论点与证据链。
4. Hidden assumptions / weak points：指出隐含前提、可能夸张、证据不足和反方观点。
5. Targeted questions：提出至少 10 个针对本篇主题的追问。
6. Personal connections：连接我的 Obsidian、AI workflow、正式组织/采购/风控工作、投资/商业判断和个人决策。
7. Cross-article echoes：如果能和此前文章互相照应，要明确写出连接点。
8. Obsidian-ready final note block：给出可直接复制到 Obsidian 的 Markdown 块，包含 tags、aliases、links、action checklist。

文章全文：

$($Article.plain_content)
"@
}

function Invoke-ChatGptRound {
    param(
        [string]$Prompt,
        [string]$ExpectedMarker,
        [string]$OutFile
    )
    if (-not (Test-Path -LiteralPath $ContinuousDialogueHelper)) {
        throw "continuous-dialogue helper not found: $ContinuousDialogueHelper"
    }

    $promptFile = $OutFile -replace '\.json$', '.prompt.txt'
    Write-Utf8BomText -Path $promptFile -Text $Prompt
    $send = & powershell -NoProfile -ExecutionPolicy Bypass -File $ContinuousDialogueHelper -Action send-round -TitleLike $TitleLike -TextFile $promptFile -TimeoutSec $ReplyTimeoutSec
    $send | Out-File -LiteralPath ($OutFile -replace '\.json$', '.send.json') -Encoding utf8
    $sendData = $send | ConvertFrom-Json
    if (-not ($sendData.PSObject.Properties.Name -contains 'message_sent') -or -not $sendData.message_sent) {
        throw "ChatGPT prompt was not sent"
    }
    if (($sendData.PSObject.Properties.Name -contains 'wait_result') -and $sendData.wait_result -and -not $sendData.wait_result.completed) {
        throw "ChatGPT reply did not complete before timeout"
    }

    $copy = & powershell -NoProfile -ExecutionPolicy Bypass -File $ContinuousDialogueHelper -Action copy-latest-reply -TitleLike $TitleLike -TimeoutSec 120
    $copy | Out-File -LiteralPath $OutFile -Encoding utf8
    $data = $copy | ConvertFrom-Json
    if (-not ($data.PSObject.Properties.Name -contains 'clipboard_text')) {
        throw "copy-latest-reply did not return clipboard_text"
    }
    $answer = [string]$data.clipboard_text
    if ([string]::IsNullOrWhiteSpace($answer)) {
        throw "empty ChatGPT reply"
    }
    $markerMatched = $true
    if ($ExpectedMarker) {
        $markerMatched = $answer -like "*$ExpectedMarker*"
        if (-not $markerMatched -and $ExpectedMarker -match '^(.{4,24})') {
            $markerMatched = $answer -like "*$($Matches[1])*"
        }
        if (-not $markerMatched -and $Prompt -match '请处理第\s*(\d+)\s*篇文章') {
            $markerMatched = ($answer -like "*第 $($Matches[1]) 篇*") -or ($answer -like "*第$($Matches[1])篇*")
        }
    }
    if (-not $markerMatched) {
        throw "copied reply does not contain expected marker: $ExpectedMarker"
    }
    $answer
}

function Get-ThemeFile {
    param([object]$Article)
    $text = (($Article.title + ' ' + $Article.account_nickname + ' ' + $Article.plain_content) -join ' ')
    if ($text -match 'AI|软件|GitHub|Claude|Agent|代码|开发|Skill') {
        return @('01-AI-software-tools.md', 'AI软件与工具系统')
    }
    if ($text -match '五粮液|白酒|滇南王|股|投资|市场|年报|估值|财报') {
        return @('05-investment-company-analysis.md', '投资市场与公司分析')
    }
    if ($text -match '电池|锂|能源|海水|产业周期|技术') {
        return @('02-energy-tech-cycle.md', '能源技术与产业周期')
    }
    if ($text -match '雪糕|运动鞋|猫|香奈儿|顶奢|消费|品牌|营销|广告') {
        return @('03-consumption-brand-local-economy.md', '消费地方经济与品牌营销')
    }
    if ($text -match '越南|铁路|人口|经济体|城市|宏观|基建|地缘') {
        return @('04-macro-geopolitics-population.md', '地缘基建人口与宏观观察')
    }
    if ($text -match '老板|老公|职场|生活|工作|加班|讨生活') {
        return @('06-workplace-society-personal-decision.md', '职场社会与个人决策')
    }
    if ($text -match '电影|看片|影帝|寒战|票房|Sir') {
        return @('07-film-culture-experience-economy.md', '影视文化与体验经济')
    }
    @('08-miscellaneous.md', '综合观察')
}

if ([string]::IsNullOrWhiteSpace($NowIso)) {
    $now = [DateTimeOffset]::Now.ToOffset([TimeSpan]::FromHours(8))
} else {
    $now = [DateTimeOffset]::Parse($NowIso).ToOffset([TimeSpan]::FromHours(8))
}
$cutoff = $now.AddHours(-1 * $HoursBack)

$health = Invoke-JsonGet -Path '/api/health'
$status = Invoke-JsonGet -Path '/api/admin/status'
if (-not $status.authenticated -or $status.loginState -ne 'valid') {
    Write-Output ("Wechat login is not valid. authenticated={0}, loginState={1}. Please scan login before archive run." -f $status.authenticated, $status.loginState)
    exit 2
}

$matches = @()
$candidates = @()
foreach ($name in $Accounts) {
    $search = Invoke-JsonGet -Path '/api/public/searchbiz' -Query @{ query = $name }
    $candidate = Get-FirstAccountCandidate -SearchResponse $search
    if (-not $candidate) {
        $matches += [pscustomobject]@{ query = $name; found = $false; nickname = ''; alias = ''; fakeid = ''; error = $search.error }
        continue
    }
    $matches += [pscustomobject]@{ query = $name; found = $true; nickname = $candidate.nickname; alias = $candidate.alias; fakeid = $candidate.fakeid; error = '' }
    $listResponse = Invoke-JsonGet -Path '/api/public/articles' -Query @{ fakeid = $candidate.fakeid; begin = 0; count = 10 }
    $accountItems = @()
    foreach ($item in (Get-ArticleItems -ArticlesResponse $listResponse)) {
        $publish = ConvertTo-BeijingTime -UnixSeconds ([long]($item.create_time))
        if ($null -eq $publish) {
            $publish = ConvertTo-BeijingTime -UnixSeconds ([long]($item.update_time))
        }
        if ($publish -and $publish -ge $cutoff -and $publish -le $now) {
            $accountItems += [pscustomobject]@{
                aid = $item.aid
                title = $item.title
                link = $item.link
                update_time = $item.update_time
                create_time = $item.create_time
                digest = $item.digest
                cover = $item.cover
                author = $item.author
                query = $name
                account_nickname = $candidate.nickname
                account_alias = $candidate.alias
                fakeid = $candidate.fakeid
                publish_dt = $publish.ToString('o')
            }
        }
    }
    if (Test-SingleMainArticleAccount -Query $name -Nickname ([string]$candidate.nickname)) {
        $accountItems = @($accountItems | Select-Object -First 1)
    }
    $candidates += $accountItems
}

$candidates = @($candidates | Sort-Object publish_dt -Descending)
if ($MaxArticles -gt 0) {
    $candidates = @($candidates | Select-Object -First $MaxArticles)
}

if ($DryRun) {
    [pscustomobject]@{
        mode = 'dry-run'
        checked_at = $now.ToString('o')
        hours_back = $HoursBack
        account_count = $Accounts.Count
        single_main_article_accounts = $SingleMainArticleAccounts
        matched_count = @($matches | Where-Object { $_.found }).Count
        candidate_article_count = $candidates.Count
        candidates = $candidates | Select-Object account_nickname,title,publish_dt,link
    } | ConvertTo-Json -Depth 8
    exit 0
}

if ($candidates.Count -eq 0) {
    Write-Output ("No new WeChat articles in the last {0} hours. Checked {1} accounts at {2}." -f $HoursBack, $Accounts.Count, $now.ToString('o'))
    exit 0
}

$dateFolder = Join-Path $OutputRoot $now.ToString('yyyy-MM-dd')
$dialogueFolder = Join-Path $dateFolder 'v2-one-dialogue'
New-Item -ItemType Directory -Force -Path $dialogueFolder | Out-Null

$enriched = @()
$fetchFailures = @()
$idx = 0
foreach ($article in $candidates) {
    $idx += 1
    $fetch = Invoke-ArticleFetchWithRetry -Url $article.link
    Start-Sleep -Seconds 1
    $plain = ''
    $html = ''
    $fullTitle = $article.title
    if ($fetch.success -and $fetch.data) {
        $plain = [string]$fetch.data.plain_content
        $html = [string]$fetch.data.content
        if ($fetch.data.title) { $fullTitle = [string]$fetch.data.title }
    } else {
        $fetchFailures += [pscustomobject]@{ article_index = $idx; title = $article.title; link = $article.link; error = $fetch.error }
    }
    $enriched += [pscustomobject]@{
        article_index = $idx
        aid = $article.aid
        title = $fullTitle
        link = $article.link
        update_time = $article.update_time
        create_time = $article.create_time
        digest = $article.digest
        cover = $article.cover
        author = $article.author
        query = $article.query
        account_nickname = $article.account_nickname
        account_alias = $article.account_alias
        fakeid = $article.fakeid
        publish_dt = $article.publish_dt
        fetch_success = [bool]($fetch.success)
        fetch_error = if ($fetch.success) { '' } else { [string]$fetch.error }
        plain_content = $plain
        html_content = $html
    }
}

Write-Utf8Text -Path (Join-Path $dateFolder 'raw-metadata.json') -Text ($matches | ConvertTo-Json -Depth 12)
Write-Utf8Text -Path (Join-Path $dateFolder 'articles-enriched.json') -Text ($enriched | ConvertTo-Json -Depth 20)

$masterPrompt = New-MasterPrompt -Articles $enriched
Write-Utf8BomText -Path (Join-Path $dialogueFolder '000-master.txt') -Text $masterPrompt
foreach ($article in $enriched) {
    Write-Utf8BomText -Path (Join-Path $dialogueFolder ('{0:000}-article.txt' -f $article.article_index)) -Text (New-ArticlePrompt -Article $article)
}

$rows = @()
$chatFailures = @()
if ($ChatMode -eq 'single-long-dialogue') {
    try {
        Invoke-ChatGptRound -Prompt $masterPrompt -ExpectedMarker '' -OutFile (Join-Path $dialogueFolder 'v2-copy-000-master.json') | Out-Null
    } catch {
        if ($OnChatGPTFailure -eq 'stop') { throw }
        $chatFailures += [pscustomobject]@{ article_index = 0; title = 'master'; error = $_.Exception.Message }
    }
}

foreach ($article in $enriched) {
    $answer = ''
    $source = 'not_sent'
    $roundError = ''
    if ($ChatMode -eq 'single-long-dialogue') {
        $promptPath = Join-Path $dialogueFolder ('{0:000}-article.txt' -f $article.article_index)
        $prompt = [System.IO.File]::ReadAllText($promptPath, [System.Text.Encoding]::UTF8)
        $copyPath = Join-Path $dialogueFolder ('v2-copy-{0:000}.json' -f $article.article_index)
        try {
            $answer = Invoke-ChatGptRound -Prompt $prompt -ExpectedMarker ([string]$article.title) -OutFile $copyPath
            $source = 'chatgpt_long_dialogue'
        } catch {
            $roundError = $_.Exception.Message
            $chatFailures += [pscustomobject]@{ article_index = $article.article_index; title = $article.title; error = $roundError }
            if ($OnChatGPTFailure -eq 'stop') { throw }
            $source = 'chatgpt_skipped_after_failure'
        }
    }
    $rows += [pscustomobject]@{
        article_index = $article.article_index
        source = $source
        account = $article.account_nickname
        title = $article.title
        publish_dt = $article.publish_dt
        url = $article.link
        answer_len = $answer.Length
        error = $roundError
        answer = $answer
    }
}

$jsonl = ($rows | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }) -join "`n"
Write-Utf8Text -Path (Join-Path $dateFolder 'conversation-checkpoints-v2.jsonl') -Text ($jsonl + "`n")

$themeGroups = @{}
foreach ($row in $rows) {
    if ($row.source -eq 'chatgpt_skipped_after_failure') { continue }
    $article = $enriched | Where-Object { $_.article_index -eq $row.article_index } | Select-Object -First 1
    $theme = Get-ThemeFile -Article $article
    $key = $theme[0]
    if (-not $themeGroups.ContainsKey($key)) {
        $themeGroups[$key] = [pscustomobject]@{ File = $theme[0]; Title = $theme[1]; Items = @() }
    }
    $themeGroups[$key].Items += [pscustomobject]@{ Row = $row; Article = $article }
}

foreach ($group in $themeGroups.Values) {
    $parts = @(
        "# $($group.Title)",
        "> 日期：$($now.ToString('yyyy-MM-dd'))  ",
        "> 范围：最近 $HoursBack 小时公众号文章  ",
        "> 归档版本：v2，同一个非临时 ChatGPT 长对话；失败篇默认跳过并写入运行摘要。",
        ''
    )
    foreach ($item in $group.Items) {
        $row = $item.Row
        $parts += ''
        $parts += '---'
        $parts += ''
        $parts += "## {0:00}. {1}" -f $row.article_index, $row.title
        $parts += ''
        $parts += "- 公众号：$($row.account)"
        $parts += "- 发布时间：$($row.publish_dt)"
        $parts += "- 原文链接：$($row.url)"
        $parts += "- 来源：$($row.source)"
        $parts += ''
        $parts += $row.answer
    }
    Write-Utf8BomText -Path (Join-Path $dateFolder $group.File) -Text ($parts -join "`n")
}

$summary = @(
    '# 运行摘要 v2',
    '',
    "- 执行时间：$($now.ToString('o'))",
    "- 输出目录：``$dateFolder``",
    "- 跟踪公众号数量：$($Accounts.Count)",
    "- 单主文公众号：$($SingleMainArticleAccounts -join '、')",
    "- 匹配成功公众号数量：$(@($matches | Where-Object { $_.found }).Count)",
    "- 最近 $HoursBack 小时命中文章：$($enriched.Count)",
    "- 全文抓取成功：$(@($enriched | Where-Object { $_.fetch_success }).Count)/$($enriched.Count)",
    "- ChatGPT 模式：$ChatMode",
    "- ChatGPT 失败策略：$OnChatGPTFailure",
    '',
    '## 文章清单',
    ''
)
foreach ($row in $rows) {
    $summary += ('{0}. {1}｜{2}｜{3}｜{4}' -f $row.article_index, $row.account, $row.title, $row.publish_dt, $row.source)
}
if ($fetchFailures.Count -gt 0) {
    $summary += ''
    $summary += '## 全文抓取失败'
    foreach ($failure in $fetchFailures) {
        $summary += ('- 第 {0} 篇：{1}｜{2}' -f $failure.article_index, $failure.title, $failure.error)
    }
}
if ($chatFailures.Count -gt 0) {
    $summary += ''
    $summary += '## ChatGPT 失败或跳过'
    foreach ($failure in $chatFailures) {
        $summary += ('- 第 {0} 篇：{1}｜{2}' -f $failure.article_index, $failure.title, $failure.error)
    }
}
$summary += ''
$summary += '## 主题文件'
foreach ($group in ($themeGroups.Values | Sort-Object File)) {
    $summary += ('- `{0}`：{1}（{2} 篇）' -f $group.File, $group.Title, $group.Items.Count)
}
Write-Utf8BomText -Path (Join-Path $dateFolder '运行摘要-v2.md') -Text ($summary -join "`n")

[pscustomobject]@{
    output_dir = $dateFolder
    article_count = $enriched.Count
    checkpoint_rows = $rows.Count
    chat_failures = $chatFailures.Count
    theme_files = @($themeGroups.Values | ForEach-Object { $_.File })
} | ConvertTo-Json -Depth 8
