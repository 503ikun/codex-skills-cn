"""Build themed Markdown folders from a paid-course/member resource tree.

Input is the JSON produced by `capture_paid_course_cdp.py capture-member-tree`.
The builder keeps source text intact, strips obvious HTML/UI noise, and writes
one Markdown file per parent course/column plus a master index.
"""

from __future__ import annotations

import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path


TYPE_MAP = {
    1: "图文",
    2: "音频",
    3: "视频",
    4: "直播",
    5: "会员",
    6: "专栏",
    8: "大专栏",
    20: "电子书",
    25: "训练营",
    50: "课程",
}


class TextHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {"p", "div", "section", "br", "li", "h1", "h2", "h3"}:
            self.parts.append("\n")
        if tag == "img" and attrs.get("src"):
            self.parts.append(f"\n![]({attrs['src']})\n")
        if tag == "a" and attrs.get("href"):
            self.parts.append("")

    def handle_data(self, data):
        if data and data.strip():
            self.parts.append(data.strip())

    def handle_endtag(self, tag):
        if tag in {"p", "div", "section", "li", "h1", "h2", "h3"}:
            self.parts.append("\n")


def html_to_text(raw_html: str) -> str:
    parser = TextHTMLParser()
    parser.feed(raw_html or "")
    text = "".join(parser.parts)
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def sanitize(text: str, max_len: int = 80) -> str:
    text = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", text or "未命名")
    text = re.sub(r"\s+", " ", text).strip().strip(".")
    return text[:max_len].rstrip() or "未命名"


def parse_date(text: str | None) -> str:
    if not text:
        return ""
    text = str(text).strip().replace("/", "-").replace(".", "-")
    match = re.search(r"(20\d{2}|19\d{2})-(\d{1,2})-(\d{1,2})", text)
    if match:
        return f"{int(match.group(1)):04d}-{int(match.group(2)):02d}-{int(match.group(3)):02d}"
    return text


def load_category_map(path: str | None) -> list[dict]:
    if not path:
        return []
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        return [{"category": key, "keywords": value} for key, value in data.items()]
    return data


def category_for(title: str, summary: str, category_map: list[dict]) -> str:
    text = f"{title or ''} {summary or ''}"
    for item in category_map:
        keywords = item.get("keywords") or []
        if isinstance(keywords, str):
            keywords = [keywords]
        if any(keyword and keyword in text for keyword in keywords):
            return item.get("category") or "未分类"
    if "导读" in text or "单课" in text:
        return "00-导读与单课"
    if any(k in text for k in ["宏观", "投资", "货币政策", "社融", "美联储", "金融市场", "房地产", "通胀", "利率"]):
        return "01-宏观投资与金融市场"
    if any(k in text for k in ["历史", "简史", "日本", "美国", "德国", "俄罗斯", "全球化", "大萧条"]):
        return "02-经济历史与国家比较"
    if any(k in text for k in ["经济学讲义", "需求理论", "价格理论", "市场机制", "制度经济学", "福利经济学", "企业机制", "货币经济学"]):
        return "03-经济理论与制度机制"
    if any(k in text for k in ["国运", "危机", "债务", "通缩", "减税", "财政政策", "公共政策", "人口", "税"]):
        return "04-现实问题与政策解释"
    if any(k in text for k in ["经典", "书籍", "哈耶克", "凯恩斯", "亚当", "李嘉图", "弗里德曼", "米塞斯", "诺斯", "科斯"]):
        return "05-大师经典与书籍解读"
    return "06-专题补充"


def body_for(lesson: dict) -> str:
    record = lesson.get("detail_record") or {}
    if record.get("text"):
        return record["text"].strip()
    detail = ((record.get("detail") or {}).get("data") or {})
    body = html_to_text(detail.get("org_content") or detail.get("content") or "")
    if body:
        return body
    core = ((record.get("core") or {}).get("data") or {})
    descrb = core.get("descrb")
    if descrb:
        try:
            blocks = json.loads(descrb) if isinstance(descrb, str) else descrb
            if isinstance(blocks, list):
                return "\n\n".join(str(block.get("value") or "").strip() for block in blocks if block.get("value"))
        except Exception:
            return str(descrb)
    return ""


def build(args) -> None:
    raw = json.loads(Path(args.raw).read_text(encoding="utf-8"))
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    category_map = load_category_map(args.category_map_json)

    parents: dict[str, dict] = {}
    for lesson in raw.get("lessons", []):
        parent_id = lesson.get("parent_id") or "__single__"
        parent_title = "导读与单课" if parent_id == "__single__" else (lesson.get("parent_title") or "未命名")
        parent_summary = "会员单课与导读内容" if parent_id == "__single__" else (lesson.get("parent_summary") or "")
        parents.setdefault(parent_id, {"title": parent_title, "summary": parent_summary, "lessons": []})["lessons"].append(lesson)

    index_rows = []
    empty = []
    for idx, (parent_id, group) in enumerate(parents.items(), 1):
        title = group["title"]
        summary = group["summary"]
        category = category_for(title, summary, category_map)
        category_dir = output_dir / category
        category_dir.mkdir(exist_ok=True)
        lessons = group["lessons"]
        lessons.sort(key=lambda item: (parse_date(item.get("start_at")) or "9999-99-99", item.get("item_index") or 999999))
        path = category_dir / f"{idx:02d}-{sanitize(title)}-最终版.md"
        lines = [
            f"# {title}",
            "",
            "## 采集说明",
            "",
            f"- 来源：{args.title}",
            f"- 顶层资源ID：`{parent_id}`",
            f"- 主题分类：{category}",
            f"- 课时数量：{len(lessons)}",
            f"- 来源页面：{raw.get('source_url') or args.source_url}",
        ]
        if summary:
            lines.append(f"- 课程说明：{summary}")
        lines.extend(["", "## 目录", ""])
        for lesson in lessons:
            lines.append(f"- {parse_date(lesson.get('start_at')) or '日期未标注'}｜{lesson.get('resource_title') or lesson.get('title') or lesson.get('resource_id')}")
        lines.extend(["", "## 正文"])
        for lesson in lessons:
            title_line = lesson.get("resource_title") or lesson.get("title") or lesson.get("resource_id")
            lines.extend([
                "",
                f"### {parse_date(lesson.get('start_at')) or '日期未标注'}｜{title_line}",
                "",
                f"- 资源类型：{TYPE_MAP.get(lesson.get('resource_type'), lesson.get('resource_type'))}",
                f"- 资源ID：`{lesson.get('resource_id')}`",
                "",
            ])
            body = body_for(lesson)
            if body:
                lines.append(body)
            else:
                empty.append({"resource_id": lesson.get("resource_id"), "title": title_line, "parent": title})
                lines.append("> 未从详情接口取得可转换正文；已保留资源元信息。")
        path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")
        index_rows.append({"category": category, "title": title, "count": len(lessons), "path": path})

    index_path = output_dir / f"{sanitize(args.title, 100)}-总目录-最终版.md"
    index_lines = [
        f"# {args.title}整理最终版",
        "",
        "## 采集概况",
        "",
        f"- 顶层资源：{len(parents)}",
        f"- 课时/内容条目：{sum(row['count'] for row in index_rows)}",
        f"- 空正文标记：{len(empty)}",
        "",
        "## 分类目录",
        "",
    ]
    for category in sorted({row["category"] for row in index_rows}):
        index_lines.extend([f"### {category}", ""])
        for row in [item for item in index_rows if item["category"] == category]:
            index_lines.append(f"- [{row['title']}]({row['path'].relative_to(output_dir).as_posix()})（{row['count']} 条）")
        index_lines.append("")
    index_path.write_text("\n".join(index_lines).strip() + "\n", encoding="utf-8")

    report = {
        "output_dir": str(output_dir),
        "index": str(index_path),
        "files": len(index_rows),
        "lessons": sum(row["count"] for row in index_rows),
        "empty_body_count": len(empty),
        "empty": empty,
    }
    if args.report:
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build themed Markdown folders from paid-course/member capture JSON.")
    parser.add_argument("--raw", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--title", default="付费课程")
    parser.add_argument("--source-url", default="")
    parser.add_argument("--category-map-json", default="")
    parser.add_argument("--report", default="")
    args = parser.parse_args()
    build(args)


if __name__ == "__main__":
    main()
