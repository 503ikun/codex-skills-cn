#!/usr/bin/env python
from __future__ import annotations

import argparse
import html
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any


NOISE_EXACT = {
    "笔记",
    "星球管理后台",
    "榜单",
    "最新",
    "精华",
    "微信群",
    "问答",
    "只看星主",
    "查看详情",
    "展开全部",
    "查看更多评论",
    "写文章",
    "本文为公众号付费文章。",
    "欢迎各位老板品鉴。",
}
NOISE_SUBSTR = (
    "可搜索当前星球",
    "所有星球",
    "创建/管理的星球",
    "加入的星球",
    "更多优质星球",
    "更多优质内容",
    "点击发表主题",
    "迅雷下载助手",
    "主题加载中",
)
DEFAULT_CATEGORIES = [
    ("一、入口与认识渠道", ("相亲", "搭讪", "网恋", "挖掘", "认识", "渠道")),
    ("二、约会设计与关系推进", ("约会", "表白", "推进", "关系")),
    ("三、礼物与关系维护", ("礼物", "维护")),
    ("四、观念补充与旧文存档", ()),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build one classified Markdown note from Knowledge Planet PDF downloads and OCR output."
    )
    parser.add_argument("--task-dir", required=True, help="Intermediate task directory.")
    parser.add_argument("--output-dir", required=True, help="Final Markdown destination directory.")
    parser.add_argument("--file-stem", required=True, help="Output Markdown file stem.")
    parser.add_argument("--title", required=True, help="Markdown title.")
    parser.add_argument("--source-url", default="", help="Knowledge Planet source URL.")
    parser.add_argument("--capture-log", help="Optional browser capture log for page-visible appendix.")
    parser.add_argument("--category-map-json", help="Optional JSON object: category title -> list of title keywords.")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def rel(path_value: str | Path, base_dir: Path) -> str:
    if not path_value:
        return ""
    try:
        return Path(path_value).resolve().relative_to(base_dir.resolve()).as_posix()
    except Exception:
        return str(path_value)


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def extract_files(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return []
    resp_data = payload.get("resp_data") or payload.get("data") or {}
    files = resp_data.get("files") or resp_data.get("items") or payload.get("files") or []
    return files if isinstance(files, list) else []


def clean_markup(text: str) -> str:
    if not text:
        return ""
    text = html.unescape(text)
    text = re.sub(r'<e[^>]*title="([^"]+)"[^>]*/>', r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def safe_stem(file_name: str) -> str:
    title = Path(file_name).stem
    if title.endswith("“") and title.count("“") > title.count("”"):
        title = title[:-1] + "”"
    return title


def item_name(item: dict[str, Any]) -> str:
    file_info = item.get("file") or item
    return str(file_info.get("name") or file_info.get("title") or "未命名 PDF")


def item_key(item: dict[str, Any]) -> str:
    return safe_stem(item_name(item))


def is_page_marker(line: str) -> bool:
    value = line.strip()
    return bool(
        re.match(r"^#{1,6}\s+(Page|\?)\s*\d+\s*\??$", value, flags=re.IGNORECASE)
        or re.fullmatch(r"\?\s*\d+\s*\?", value)
    )


def is_metadata_line(line: str, index: int) -> bool:
    if index <= 5 and (line.startswith("# ") or line.startswith("- ")):
        return True
    return line.startswith("Source PDF:") or line.startswith("Conversion:")


def is_section_heading(line: str) -> bool:
    value = line.strip()
    if re.match(r"^（[一二三四五六七八九十]+）\S+", value):
        return True
    if re.match(r"^\d+[.．、]\s*\S{1,24}$", value):
        return True
    if value in {"主要内容:", "主要内容：", "最后总结", "总结"}:
        return True
    return False


def flush_paragraph(buffer: list[str], output: list[str]) -> None:
    if not buffer:
        return
    paragraph = "".join(buffer).strip()
    paragraph = re.sub(r"\s+", " ", paragraph)
    if paragraph:
        output.extend([paragraph, ""])
    buffer.clear()


def clean_pdf_markdown(md_text: str) -> str:
    raw_lines = md_text.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    filtered: list[str] = []
    previous = None
    for index, raw in enumerate(raw_lines):
        line = raw.strip()
        if not line or is_page_marker(line) or is_metadata_line(line, index):
            continue
        if line in NOISE_EXACT or any(token in line for token in NOISE_SUBSTR):
            continue
        if line == previous:
            continue
        filtered.append(line)
        previous = line

    output: list[str] = []
    buffer: list[str] = []
    for line in filtered:
        if is_section_heading(line) or (line.startswith("《") and line.endswith("》")):
            flush_paragraph(buffer, output)
            output.extend([f"##### {line.replace(':', '：')}", ""])
            continue
        buffer.append(line)
        if re.search(r"[。！？；]$", line) or len("".join(buffer)) >= 180:
            flush_paragraph(buffer, output)
    flush_paragraph(buffer, output)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(output).strip())


def clean_page_text(text: str) -> str:
    lines: list[str] = []
    previous = None
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").splitlines():
        line = raw.strip()
        if not line or line in NOISE_EXACT or any(token in line for token in NOISE_SUBSTR):
            continue
        if line == previous:
            continue
        lines.append(line)
        previous = line
    return "\n".join(lines).strip()


def load_capture_text(path: Path | None) -> tuple[str, str]:
    if not path or not path.exists():
        return "", ""
    payload = load_json(path, {})
    rounds = payload.get("rounds") or []
    text = max((round_info.get("text", "") for round_info in rounds), key=len, default="")
    return clean_page_text(text), payload.get("base_url", "")


def load_categories(path: Path | None) -> list[tuple[str, tuple[str, ...]]]:
    if path and path.exists():
        payload = load_json(path, {})
        return [(str(title), tuple(values)) for title, values in payload.items()]
    return DEFAULT_CATEGORIES


def category_for(title: str, categories: list[tuple[str, tuple[str, ...]]]) -> str:
    fallback = categories[-1][0]
    for category, keywords in categories:
        if keywords and any(keyword in title for keyword in keywords):
            return category
    return fallback


def build_article(
    item: dict[str, Any],
    index: int,
    ocr_by_name: dict[str, dict[str, Any]],
    download_by_name: dict[str, dict[str, Any]],
    output_dir: Path,
) -> str:
    file_info = item.get("file") or item
    topic = item.get("topic") or {}
    name = item_name(item)
    title = safe_stem(name)
    ocr = ocr_by_name.get(name) or {}
    download = download_by_name.get(name) or {}
    talk_text = clean_markup((topic.get("talk") or {}).get("text") or "")

    lines = [
        f"### 文章 {index}｜{title}",
        "",
        f"- 发布时间：{topic.get('create_time', file_info.get('create_time', ''))}",
        f"- 原始 PDF：{rel(download.get('path', ''), output_dir) if download.get('path') else '未下载'}",
        f"- Markdown：{rel(ocr.get('md_path', ''), output_dir) if ocr.get('md_path') else '未生成'}",
        f"- 转换方式：{ocr.get('method') or ('OCR' if ocr.get('pages') else '')}",
        "",
    ]
    if talk_text:
        lines.extend(["#### 原帖", "", talk_text, ""])

    comments = []
    for comment in topic.get("show_comments") or []:
        owner = (comment.get("owner") or {}).get("name") or ""
        comment_text = clean_markup(comment.get("text") or "")
        created_at = comment.get("create_time") or ""
        if comment_text:
            comments.append(f"- {owner}（{created_at}）：{comment_text}")
    if comments:
        lines.extend(["#### 可见评论", "", "\n".join(comments), ""])

    lines.extend(["#### 正文", ""])
    md_path = Path(ocr.get("md_path", ""))
    if ocr.get("ok") and md_path.exists():
        body = clean_pdf_markdown(md_path.read_text(encoding="utf-8", errors="ignore"))
        lines.append(body or "> [Markdown 正文为空]")
    else:
        error = ocr.get("error") or download.get("error") or "未生成 Markdown"
        lines.append(f"> [PDF 转换失败] {error}")
    return "\n".join(lines).strip()


def main() -> int:
    args = parse_args()
    task_dir = Path(args.task_dir)
    output_dir = ensure_dir(Path(args.output_dir))
    output_path = output_dir / f"{args.file_stem}.md"

    files_payload = load_json(task_dir / "file_api_aggregate.json", {})
    files = extract_files(files_payload)
    ocr_log = load_json(task_dir / "pdf_ocr_log.json", [])
    download_log = load_json(task_dir / "pdf_download_log.json", [])
    capture_text, capture_url = load_capture_text(Path(args.capture_log) if args.capture_log else None)
    source_url = args.source_url or capture_url
    categories = load_categories(Path(args.category_map_json) if args.category_map_json else None)

    ocr_by_name = {item.get("name"): item for item in ocr_log}
    download_by_name = {item.get("name"): item for item in download_log}

    grouped: dict[str, list[dict[str, Any]]] = {category: [] for category, _ in categories}
    for item in files:
        title = item_key(item)
        grouped.setdefault(category_for(title, categories), []).append(item)

    lines = [
        f"# {args.title}",
        "",
        "## 目录",
        "",
    ]
    for category, _ in categories:
        if grouped.get(category):
            lines.append(f"- {category}")
            for item in grouped[category]:
                lines.append(f"  - {item_key(item)}")

    lines.extend(
        [
            "",
            "## 采集概况",
            "",
            f"- 整理时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"- 来源页面：{source_url}",
            "- 整理方式：知识星球文件区 PDF 下载、Markdown 转换、扫描 PDF OCR fallback、按主题分类汇总。",
            "- 内容保留策略：保留原帖、可见评论、PDF 正文；只清理转换头、页码、重复来源行和 UI 噪声。",
            f"- 文章总数：{len(files)}",
            f"- PDF 下载成功数量：{sum(1 for item in download_log if item.get('ok'))}",
            f"- PDF 转 Markdown 成功数量：{sum(1 for item in ocr_log if item.get('ok'))}",
            f"- 中间产物目录：{task_dir}",
            "",
        ]
    )

    for category, _ in categories:
        items = grouped.get(category) or []
        if not items:
            continue
        lines.extend([f"## {category}", ""])
        for index, item in enumerate(items, start=1):
            lines.append(build_article(item, index, ocr_by_name, download_by_name, output_dir))
            lines.extend(["", "---", ""])

    lines.extend(["## 附录：页面可复制内容与采集日志", ""])
    if capture_text:
        lines.extend(["### 页面可复制内容", "", capture_text, ""])

    failures = [
        item
        for item in [*download_log, *ocr_log]
        if not item.get("ok") and (item.get("name") or item.get("pdf_path"))
    ]
    lines.extend(["### 采集日志与缺失项", ""])
    lines.extend(
        [
            f"- 文件 API 聚合结果：{rel(task_dir / 'file_api_aggregate.json', output_dir)}",
            f"- PDF 下载日志：{rel(task_dir / 'pdf_download_log.json', output_dir)}",
            f"- PDF 转换/OCR 日志：{rel(task_dir / 'pdf_ocr_log.json', output_dir)}",
            "",
        ]
    )
    if failures:
        for item in failures:
            lines.append(f"- {item.get('name') or item.get('pdf_path')}：{item.get('stage') or item.get('method') or 'convert'} failed; {item.get('error', '')}")
    else:
        lines.append("无下载或 OCR 失败项。")

    text = "\n".join(lines).strip() + "\n"
    for noise in ("主题加载中", "查看详情", "展开全部", "迅雷下载助手", "? 1 ?", "?? PDF?"):
        text = text.replace(noise, "")
    output_path.write_text(text, encoding="utf-8")

    summary = {
        "output": str(output_path),
        "bytes": output_path.stat().st_size,
        "articles": len(files),
        "categories": sum(1 for items in grouped.values() if items),
    }
    (task_dir / "final_pdf_summary_build_log.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
