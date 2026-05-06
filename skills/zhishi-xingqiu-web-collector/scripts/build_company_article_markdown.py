"""Build an industry -> company -> article Markdown file from captured raw JSON."""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path


NOISE_LINES = {
    "展开全部",
    "收起",
    "复制链接",
    "写留言",
    "发表评论",
    "暂无评论",
    "加载中",
    "返回前一页",
    "店铺主页",
}

GENERIC_COMPANY_NAMES = {
    "A股",
    "AH股",
    "A+H股",
    "会员必看",
    "补充",
    "现金流量表",
    "利润表",
    "资产负债表",
    "年报",
    "半年报",
    "财报",
    "估值",
    "核心资产",
}

DEFAULT_HEURISTICS = [
    ("新能源、电力设备与产业链", ["新能源", "锂", "钠电", "电池", "储能", "光伏", "风电", "电力设备"]),
    ("医药、医疗器械与耗材复购", ["医疗", "医药", "生物", "药", "眼科", "耗材"]),
    ("消费品牌、渠道与服务运营", ["白酒", "啤酒", "食品", "消费", "家电", "乳品", "调味品"]),
    ("半导体、算力与科技硬件", ["半导体", "芯片", "算力", "AI", "电子", "通信", "机器人"]),
    ("设备平台、自动化与工程交付", ["设备", "工程机械", "自动化", "船舶", "工业机械"]),
    ("资源开采、能源供给与强周期品", ["煤", "石油", "能源", "矿", "有色", "化工", "水电", "核电"]),
    ("金融地产与类金融资产", ["银行", "保险", "地产", "金融", "证券"]),
    ("互联网平台与软件服务", ["互联网", "平台", "软件", "腾讯", "阿里", "美团", "小米"]),
    ("综合市场与投资方法", ["市场", "估值", "财报", "现金流", "投资", "风险", "机会", "股东"]),
]


def read_text_maybe(path: Path) -> str:
    for enc in ("utf-8-sig", "utf-8", "gb18030"):
        try:
            return path.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return path.read_text(encoding="utf-8", errors="replace")


def clean_company_name(name: str) -> str:
    name = name.split("|")[-1]
    name = re.sub(r"\s+", "", name)
    name = re.sub(r"(?:\d{2,4}年?报|半年报|年报|财报|财务数据?|财务|估值|解读|逐字稿|纵向分析|产品|历史|指标|范本|数据|24|25|23|22|21|20)+$", "", name)
    return re.sub(r"[《》“”\"'：:，,。；;（）()【】\[\]]", "", name).strip()


def load_industry_map(path: Path | None) -> dict[str, str]:
    if not path:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    mapping: dict[str, str] = {}
    if all(isinstance(v, str) for v in payload.values()):
        for company, industry in payload.items():
            mapping[clean_company_name(company)] = industry
    else:
        for industry, companies in payload.items():
            if isinstance(companies, list):
                for company in companies:
                    mapping[clean_company_name(str(company))] = industry
    return {k: v for k, v in mapping.items() if k}


def load_company_research(path: Path | None) -> dict[str, str]:
    if not path or not path.exists():
        return {}
    text = read_text_maybe(path)
    current = ""
    mapping: dict[str, str] = {}
    for line in text.splitlines():
        heading = re.match(r"^##\s+(.+?)\s*$", line)
        if heading and not heading.group(1).startswith("分类方法"):
            current = heading.group(1).strip()
        if not current:
            continue
        for raw in re.findall(r"\[\[([^\]]+)\]\]", line):
            name = clean_company_name(raw)
            if len(name) >= 2 and name not in GENERIC_COMPANY_NAMES:
                mapping.setdefault(name, current)
    return mapping


def article_key(article: dict) -> tuple[str, str]:
    return (article.get("article_date") or article.get("date") or "", (article.get("article_title") or article.get("title") or "").strip())


def strip_body(text: str, title: str, date: str) -> str:
    lines = [line.rstrip() for line in (text or "").replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    if lines and lines[0].strip() == title.strip():
        lines.pop(0)
    if lines and re.match(rf"^{re.escape(date)}(?:\s+\d{{1,2}}:\d{{2}})?$", lines[0].strip()):
        lines.pop(0)
    cleaned = []
    previous = None
    blank = False
    for line in lines:
        s = line.strip()
        if s in NOISE_LINES:
            continue
        if s == previous and len(s) > 8:
            continue
        previous = s
        if not s:
            if not blank:
                cleaned.append("")
            blank = True
        else:
            cleaned.append(line)
            blank = False
    return "\n".join(cleaned).strip()


def known_names(*maps: dict[str, str]) -> list[str]:
    names = set()
    for mapping in maps:
        names.update(mapping)
    return sorted((name for name in names if len(name) >= 2), key=lambda x: (-len(x), x))


def title_candidates(title: str) -> list[str]:
    found = []
    for raw in re.findall(r"[“【《]([^”】》]{2,32})[”】》]", title):
        found.extend(re.split(r"[、/和与vsVS对决]+", raw))
    return [clean_company_name(x) for x in found if clean_company_name(x) and clean_company_name(x) not in GENERIC_COMPANY_NAMES]


def infer_company(article: dict, names: list[str]) -> tuple[str, list[str]]:
    title = article.get("article_title") or article.get("title") or ""
    text = article.get("text") or ""
    hay = title + "\n" + text[:1600]
    found: list[str] = []
    for candidate in title_candidates(title):
        if candidate not in found:
            found.append(candidate)
    for name in names:
        if name in hay and name not in found:
            found.append(name)
    if found:
        return found[0], found[1:8]
    for industry, keywords in DEFAULT_HEURISTICS:
        if any(keyword in hay for keyword in keywords):
            if industry == "综合市场与投资方法":
                return "市场与投资方法", []
            return industry.replace("与产业链", "行业").replace("、", "/"), []
    return "综合观察", []


def infer_industry(company: str, article: dict, industry_map: dict[str, str], company_map: dict[str, str]) -> tuple[str, str, bool]:
    if company in industry_map:
        return industry_map[company], "行业映射表", False
    if company in company_map:
        return company_map[company], "公司研究分类", False
    hay = f"{company}\n{article.get('article_title') or article.get('title') or ''}\n{(article.get('text') or '')[:1600]}"
    for industry, keywords in DEFAULT_HEURISTICS:
        if any(keyword in hay for keyword in keywords):
            return industry, "内容关键词暂归类", True
    return "综合市场与投资方法", "内容关键词暂归类", True


def article_url(article: dict) -> str:
    return article.get("url") or article.get("source_url") or ""


def render_article(article: dict, company: str, related: list[str], source: str) -> list[str]:
    date, title = article_key(article)
    body = strip_body(article.get("text") or "", title, date)
    lines = [f"#### {date}｜{title}", ""]
    if article_url(article):
        lines.append(f"> 来源链接：{article_url(article)}")
    lines.append(f"> 主讲公司：{company}")
    if related:
        lines.append(f"> 相关公司：{'、'.join(related)}")
    lines.append(f"> 行业依据：{source}")
    lines.append("")
    lines.append(body or "（正文为空或仅包含图片，详见来源链接。）")
    lines.append("")
    return lines


def download_markdown_images(markdown: str, assets_dir: Path, limit: int) -> list[dict]:
    assets_dir.mkdir(parents=True, exist_ok=True)
    log = []
    urls = list(dict.fromkeys(re.findall(r"!\[[^\]]*\]\((https?://[^)]+)\)", markdown)))
    for idx, url in enumerate(urls[:limit], 1):
        suffix = Path(urllib.parse.urlparse(url).path).suffix or ".png"
        target = assets_dir / f"image-{idx:04d}{suffix}"
        try:
            urllib.request.urlretrieve(url, target)
            log.append({"url": url, "path": str(target), "bytes": target.stat().st_size})
        except Exception as exc:
            log.append({"url": url, "error": repr(exc)})
    return log


def build(args) -> dict:
    raw = json.loads(Path(args.raw).read_text(encoding="utf-8"))
    articles = sorted(raw.get("articles", []), key=article_key)
    industry_map = load_industry_map(Path(args.industry_map_json) if args.industry_map_json else None)
    company_map = load_company_research(Path(args.company_research_md) if args.company_research_md else None)
    names = known_names(industry_map, company_map)
    grouped: dict[str, dict[str, list[tuple[dict, list[str], str, bool]]]] = defaultdict(lambda: defaultdict(list))
    source_counts: Counter = Counter()
    note_flags: dict[tuple[str, str], bool] = defaultdict(bool)

    for article in articles:
        company, related = infer_company(article, names)
        industry, source, note = infer_industry(company, article, industry_map, company_map)
        grouped[industry][company].append((article, related, source, note))
        note_flags[(industry, company)] = note_flags[(industry, company)] or note
        source_counts[source] += 1

    dates = [article_key(a)[0] for a in articles if article_key(a)[0]]
    lines = [
        f"# {args.title}",
        "",
        "## 采集说明",
        "",
        f"- 文章数量：{len(articles)}",
        f"- 日期范围：{min(dates) if dates else ''} 至 {max(dates) if dates else ''}",
        "- 整理方式：按行业、公司、文章三级结构排列；同一公司下按旧到新排序；正文保留原意，仅清理明显 UI 噪音和滚动重复文本。",
        "- 分类依据：优先使用行业映射 JSON；其次使用公司研究 Markdown；仍未覆盖时按标题和正文关键词暂归类。",
        "",
    ]
    if args.source_url:
        lines.insert(4, f"- 来源页面：{args.source_url}")

    for industry in sorted(grouped):
        lines.append(f"## {industry}")
        lines.append("")
        for company in sorted(grouped[industry]):
            label = company + ("（未在映射表中，按内容暂归类）" if note_flags[(industry, company)] else "")
            lines.append(f"### {label}")
            lines.append("")
            items = sorted(grouped[industry][company], key=lambda item: article_key(item[0]))
            for article, related, source, _note in items:
                lines.extend(render_article(article, company, related, source))

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"{args.file_stem}.md"
    markdown = "\n".join(lines).rstrip() + "\n"
    output.write_text(markdown, encoding="utf-8")
    image_log = []
    if args.download_images:
        image_log = download_markdown_images(markdown, output_dir / f"{args.file_stem}.assets", args.image_limit)
    report = {
        "output": str(output),
        "total_articles": len(articles),
        "industry_count": len(grouped),
        "company_count": sum(len(companies) for companies in grouped.values()),
        "classification_sources": dict(source_counts),
        "image_downloads": image_log,
    }
    if args.report:
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a company/industry sorted Markdown note from captured article raw JSON.")
    parser.add_argument("--raw", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--file-stem", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--source-url", default="")
    parser.add_argument("--industry-map-json", default="")
    parser.add_argument("--company-research-md", default="")
    parser.add_argument("--report", default="")
    parser.add_argument("--download-images", action="store_true")
    parser.add_argument("--image-limit", type=int, default=200)
    args = parser.parse_args()
    print(json.dumps(build(args), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
