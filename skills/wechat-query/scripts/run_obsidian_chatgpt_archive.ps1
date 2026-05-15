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
    [int]$ApiTimeoutSec = 90,
    [string]$NowIso = '',
    [string[]]$SingleMainArticleAccounts = @('酷玩实验室', 'Sir电影', '数据GO')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ContinuousDialogueHelper = Join-Path (Split-Path -Parent $SkillRoot) 'continuous-dialogue\scripts\chrome-chatgpt-uia.ps1'
$PreflightScript = Join-Path $SkillRoot 'scripts\check_service_and_login.ps1'
$CodexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE '.codex' } else { $env:CODEX_HOME }
$AutomationMemoryPath = Join-Path $CodexHome 'automations\24\memory.md'

if (-not ('CodexTimeoutWebClient' -as [type])) {
    Add-Type @'
using System;
using System.Net;

public class CodexTimeoutWebClient : WebClient {
    public int TimeoutMilliseconds { get; set; }

    public CodexTimeoutWebClient(int timeoutMilliseconds) {
        TimeoutMilliseconds = timeoutMilliseconds;
    }

    protected override WebRequest GetWebRequest(Uri address) {
        WebRequest request = base.GetWebRequest(address);
        request.Timeout = TimeoutMilliseconds;
        HttpWebRequest httpRequest = request as HttpWebRequest;
        if (httpRequest != null) {
            httpRequest.ReadWriteTimeout = TimeoutMilliseconds;
        }
        return request;
    }
}
'@
}

function Get-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    $property.Value
}

function Test-LoginStatusValid {
    param([object]$Status)
    if ($null -eq $Status) { return $false }
    $authenticated = [bool](Get-ObjectProperty -Object $Status -Name 'authenticated' -Default $false)
    $loginState = [string](Get-ObjectProperty -Object $Status -Name 'loginState' -Default 'unknown')
    $isExpired = [bool](Get-ObjectProperty -Object $Status -Name 'isExpired' -Default $false)
    $authenticated -and $loginState -eq 'valid' -and -not $isExpired
}

function Test-EstimatedExpiredLoginStillWorks {
    param([object]$Status)
    if ($null -eq $Status) { return $false }
    $authenticated = [bool](Get-ObjectProperty -Object $Status -Name 'authenticated' -Default $false)
    $loginState = [string](Get-ObjectProperty -Object $Status -Name 'loginState' -Default 'unknown')
    $isExpired = [bool](Get-ObjectProperty -Object $Status -Name 'isExpired' -Default $false)
    if (-not ($authenticated -and $loginState -eq 'valid' -and $isExpired)) {
        return $false
    }

    try {
        $probe = Invoke-JsonGet -Path '/api/public/searchbiz' -Query @{ query = '赛博禅心' }
        if (Test-WeChatSessionInvalidResponse -Response $probe) { return $false }
        return [bool](Get-ObjectProperty -Object $probe -Name 'success' -Default $false)
    } catch {
        return $false
    }
}

function New-LoginRequiredResult {
    param(
        [string]$Reason,
        [object]$Status = $null
    )
    [pscustomobject]@{
        status = 'login_required'
        action = 'notify_login_invalid'
        reason = $Reason
        message = 'WeChat login is invalid or expired. Please use the official-account administrator WeChat to scan login, then rerun the archive workflow.'
        authenticated = [bool](Get-ObjectProperty -Object $Status -Name 'authenticated' -Default $false)
        loginState = [string](Get-ObjectProperty -Object $Status -Name 'loginState' -Default 'unknown')
        isExpired = [bool](Get-ObjectProperty -Object $Status -Name 'isExpired' -Default $false)
        lastInvalidReason = [string](Get-ObjectProperty -Object $Status -Name 'lastInvalidReason' -Default '')
        automation_memory_path = $AutomationMemoryPath
    }
}

function Stop-ArchiveForLoginRequired {
    param(
        [string]$Reason,
        [object]$Status = $null
    )
    New-LoginRequiredResult -Reason $Reason -Status $Status | ConvertTo-Json -Depth 6
    exit 0
}

function Stop-ArchiveForServiceDown {
    param([string]$Reason)
    [pscustomobject]@{
        status = 'service_unavailable'
        action = 'notify_service_down'
        reason = $Reason
        message = 'wechat-query service is unavailable and automatic recovery did not restore it.'
        automation_memory_path = $AutomationMemoryPath
    } | ConvertTo-Json -Depth 6
    exit 1
}

function Test-WeChatSessionInvalidResponse {
    param([object]$Response)
    if ($null -eq $Response) { return $false }
    $success = Get-ObjectProperty -Object $Response -Name 'success' -Default $null
    if ($null -ne $success -and [bool]$success) { return $false }
    $text = try { $Response | ConvertTo-Json -Depth 12 -Compress } catch { [string]$Response }
    $text -match '(?i)invalid session|session expired|session invalid|not logged in|login required|200003'
}

function Get-FreshLoginStatus {
    try {
        Invoke-JsonGet -Path '/api/admin/status'
    } catch {
        $null
    }
}

function Assert-ApiResponseNotLoginInvalid {
    param(
        [object]$Response,
        [string]$Endpoint
    )
    if (Test-WeChatSessionInvalidResponse -Response $Response) {
        $status = Get-FreshLoginStatus
        Stop-ArchiveForLoginRequired -Reason "$Endpoint returned an invalid WeChat session response" -Status $status
    }
}

function Invoke-ArchivePreflight {
    $health = $null
    try {
        $health = Invoke-JsonGet -Path '/api/health'
    } catch {
        if (Test-Path -LiteralPath $PreflightScript) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $PreflightScript | Out-Null
        }
        try {
            $health = Invoke-JsonGet -Path '/api/health'
        } catch {
            Stop-ArchiveForServiceDown -Reason $_.Exception.Message
        }
    }

    $status = $null
    try {
        $status = Invoke-JsonGet -Path '/api/admin/status'
    } catch {
        Stop-ArchiveForServiceDown -Reason ("admin status endpoint unavailable: {0}" -f $_.Exception.Message)
    }

    if (-not (Test-LoginStatusValid -Status $status) -and -not (Test-EstimatedExpiredLoginStillWorks -Status $status)) {
        Stop-ArchiveForLoginRequired -Reason 'preflight admin status is not a usable login' -Status $status
    }

    [pscustomobject]@{
        health = $health
        status = $status
    }
}

function Invoke-JsonGet {
    param([string]$Path, [hashtable]$Query = @{})
    $builder = [System.UriBuilder]::new(($ApiBase.TrimEnd('/') + $Path))
    if ($Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            '{0}={1}' -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$Query[$key])
        }
        $builder.Query = ($pairs -join '&')
    }
    $client = [CodexTimeoutWebClient]::new([Math]::Max(1, $ApiTimeoutSec) * 1000)
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
    $client = [CodexTimeoutWebClient]::new([Math]::Max(1, $ApiTimeoutSec) * 1000)
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
        Assert-ApiResponseNotLoginInvalid -Response $last -Endpoint '/api/article/fetch'
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

function Convert-MarkdownHeadingsDown {
    param([string]$Markdown)
    if ([string]::IsNullOrEmpty($Markdown)) { return $Markdown }

    $lines = $Markdown -split "`r?`n"
    $converted = foreach ($line in $lines) {
        if ($line -match '^(#{1,6})(\s+.*)$') {
            $level = [Math]::Min(6, $Matches[1].Length + 1)
            ('#' * $level) + $Matches[2]
        } else {
            $line
        }
    }
    $converted -join "`n"
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
        '2. 每篇都要参考 2026-05-06 归档样例的提问方式：Targeted questions 必须是围绕本篇具体人物、公司、行业、数据、争议、资产、工具、组织问题写出的具体问题，不要使用模板化空问题。',
        '3. 每篇都要连接到我的个人知识库、正式组织/采购/风控工作、投资判断、AI workflow 和 Obsidian 知识系统。',
        '4. 从第二篇开始主动寻找与前文的呼应、冲突、互证和可建立的双链。',
        '5. 不要只摘要，要拆论点、证据链、隐含前提、弱点、反方观点、可迁移框架。',
        '',
        '统一输出结构：',
        '- 不要使用一级标题。每篇内部小节从二级标题（##）开始；三级、四级标题可按需使用。',
        '- Suggested theme classification',
        '- Long-form core summary',
        '- Author key claims and evidence chain',
        '- Hidden assumptions / weak points',
        '- Targeted questions：每篇 20 个左右；问题必须点名本篇的具体对象、变量、案例、数据、风险、反方条件和可验证指标。',
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

请输出尽量长，且按以下结构。风格必须参考 2026-05-06 已合格归档中的写法：不是本地模板化摘要，而是深度精读；尤其 Targeted questions 要像那篇一样围绕文章具体内容连续追问。
重要排版要求：不要在你的回复中使用一级标题（#）。本篇文章标题会由归档脚本统一生成一级标题；你内部的小节必须从二级标题（##）开始。

1. Suggested theme classification：根据本篇内容判断主题，不要套固定分类。
2. Long-form core summary：长摘要，保留关键细节、转折、作者态度。
3. Author's key claims and evidence chain：逐条拆主要论点与证据链。
4. Hidden assumptions / weak points：指出隐含前提、可能夸张、证据不足和反方观点。
5. Targeted questions：提出 20 个左右针对本篇主题的追问。禁止使用“这篇文章最核心的判断是什么”“作者使用了哪些证据”这类泛泛问题。每个问题都必须点名本篇的具体对象、公司、政策、数据、人物、产品、业务环节、投资变量、组织风险或个人决策场景；问题要能直接进入 Obsidian 作为后续研究问题。
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
    if (-not [bool](Get-ObjectProperty -Object $sendData -Name 'message_sent' -Default $false)) {
        throw "ChatGPT prompt was not sent"
    }
    $waitResult = Get-ObjectProperty -Object $sendData -Name 'wait_result' -Default $null
    if ($waitResult -and -not [bool](Get-ObjectProperty -Object $waitResult -Name 'completed' -Default $false)) {
        throw "ChatGPT reply did not complete before timeout"
    }

    $copy = & powershell -NoProfile -ExecutionPolicy Bypass -File $ContinuousDialogueHelper -Action copy-latest-reply -TitleLike $TitleLike -TimeoutSec 120
    $copy | Out-File -LiteralPath $OutFile -Encoding utf8
    $data = $copy | ConvertFrom-Json
    $clipboardText = Get-ObjectProperty -Object $data -Name 'clipboard_text' -Default $null
    if ($null -eq $clipboardText) {
        throw "copy-latest-reply did not return clipboard_text"
    }
    $answer = [string]$clipboardText
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

$preflight = Invoke-ArchivePreflight

$matches = @()
$candidates = @()
foreach ($name in $Accounts) {
    $search = Invoke-JsonGet -Path '/api/public/searchbiz' -Query @{ query = $name }
    Assert-ApiResponseNotLoginInvalid -Response $search -Endpoint '/api/public/searchbiz'
    $candidate = Get-FirstAccountCandidate -SearchResponse $search
    if (-not $candidate) {
        $matches += [pscustomobject]@{ query = $name; found = $false; nickname = ''; alias = ''; fakeid = ''; error = $search.error }
        continue
    }
    $matches += [pscustomobject]@{ query = $name; found = $true; nickname = $candidate.nickname; alias = $candidate.alias; fakeid = $candidate.fakeid; error = '' }
    $listResponse = Invoke-JsonGet -Path '/api/public/articles' -Query @{ fakeid = $candidate.fakeid; begin = 0; count = 10 }
    Assert-ApiResponseNotLoginInvalid -Response $listResponse -Endpoint '/api/public/articles'
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
        "> 主题：$($group.Title)",
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
        $parts += "# 第 {0:00} 篇精读｜{1}" -f $row.article_index, $row.title
        $parts += ''
        $parts += "- 公众号：$($row.account)"
        $parts += "- 发布时间：$($row.publish_dt)"
        $parts += "- 原文链接：$($row.url)"
        $parts += "- 来源：$($row.source)"
        $parts += ''
        $parts += (Convert-MarkdownHeadingsDown -Markdown ([string]$row.answer))
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
