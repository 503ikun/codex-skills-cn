#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from pathlib import Path


NOISE_EXACT = {
    "查看详情",
    "展开全部",
    "写评论",
    "主题加载中",
    "没有更多了",
    "最新",
    "上一页",
    "下一页",
}
NOISE_SUBSTR = ("迅雷下载助手", "zsxq", "reconnecting")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a Markdown note from a browser capture log.")
    parser.add_argument("--capture-log", required=True, help="Path to *.capture.json.")
    parser.add_argument("--target-dir", required=True, help="Directory for Markdown output.")
    parser.add_argument("--file-stem", default=None, help="Optional Markdown file stem.")
    parser.add_argument("--title", default="复制粘贴任何内容采集", help="Markdown title.")
    return parser.parse_args()


def slugify(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    value = value.strip("-._")
    return value or "capture"


def normalize_line(line: str) -> str:
    line = line.strip().replace("\r", "")
    line = re.sub(r"[ \t]+", " ", line)
    return line.strip()


def is_noise(line: str) -> bool:
    lower = line.lower()
    if not line:
        return True
    if line in NOISE_EXACT:
        return True
    return any(token in lower for token in NOISE_SUBSTR)


def extract_blocks(round_text: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for raw_line in round_text.split("\n"):
        line = normalize_line(raw_line)
        if is_noise(line):
            if current:
                block = "\n".join(current).strip()
                if block:
                    blocks.append(block)
                current = []
            continue
        current.append(line)
    if current:
        block = "\n".join(current).strip()
        if block:
            blocks.append(block)
    return blocks


def dedupe_blocks(rounds: list[dict]) -> list[dict]:
    merged: dict[str, dict] = {}
    for round_info in rounds:
        for block in extract_blocks(round_info.get("text", "")):
            if len(block) < 20:
                continue
            key = re.sub(r"\s+", " ", block[:120]).strip()
            item = {
                "text": block,
                "url": round_info.get("url"),
                "page_index": round_info.get("page_index"),
                "round": round_info.get("round"),
            }
            previous = merged.get(key)
            if not previous or len(block) > len(previous["text"]):
                merged[key] = item
    return list(merged.values())


def relative_paths(paths: list[str], base_dir: Path) -> list[str]:
    rels: list[str] = []
    for value in paths:
        try:
            rels.append(Path(value).resolve().relative_to(base_dir.resolve()).as_posix())
        except Exception:
            try:
                rels.append(Path(value).relative_to(base_dir).as_posix())
            except Exception:
                rels.append(Path(value).name)
    return rels


def main() -> int:
    args = parse_args()
    capture_path = Path(args.capture_log)
    target_dir = Path(args.target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)

    payload = json.loads(capture_path.read_text(encoding="utf-8"))
    rounds = payload.get("rounds", [])
    blocks = dedupe_blocks(rounds)

    all_downloaded = []
    all_screenshots = []
    for round_info in rounds:
        all_downloaded.extend(round_info.get("downloaded_images", []))
        all_screenshots.append(round_info.get("screenshot"))

    downloaded = sorted(set(relative_paths([p for p in all_downloaded if p], target_dir)))
    screenshots = sorted(set(relative_paths([p for p in all_screenshots if p], target_dir)))

    stem = slugify(args.file_stem or capture_path.stem.replace(".capture", ""))
    md_path = target_dir / f"{stem}.md"

    lines = [
        f"# {args.title}",
        "",
        f"- 采集时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"- 来源页面：{payload.get('base_url', '')}",
        f"- 目标目录：{target_dir}",
        f"- 总内容块数：{len(blocks)}",
        f"- 采集轮次：{len(rounds)}",
        f"- 下载图片数：{len(downloaded)}",
        "",
    ]

    for idx, block in enumerate(blocks, start=1):
        lines.extend(
            [
                f"## 内容块 {idx}",
                "",
                f"- 来源页面：{block.get('url', '')}",
                f"- 页码序号：{block.get('page_index', '')}",
                f"- 采集轮次：{block.get('round', '')}",
                "",
                block["text"],
                "",
            ]
        )
        if idx != len(blocks):
            lines.extend(["---", ""])

    if downloaded:
        lines.extend(["## 图片资源", ""])
        for rel in downloaded:
            lines.extend([f"![image]({rel})", ""])

    if screenshots:
        lines.extend(["## 页面截图", ""])
        for rel in screenshots:
            lines.extend([f"![screenshot]({rel})", ""])

    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(md_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
