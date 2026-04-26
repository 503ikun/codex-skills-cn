#!/usr/bin/env python3
"""Summarize an AI-Scientist-v2 experiment directory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def newest_files(root: Path, pattern: str, limit: int = 5) -> list[Path]:
    files = [path for path in root.rglob(pattern) if path.is_file()]
    return sorted(files, key=lambda item: item.stat().st_mtime, reverse=True)[:limit]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", help="Experiment run directory or parent experiments directory.")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = Path(args.output_dir).expanduser().resolve()
    if not root.exists():
        raise SystemExit(f"Output path not found: {root}")

    pdfs = newest_files(root, "*.pdf")
    htmls = newest_files(root, "unified_tree_viz.html")
    logs = newest_files(root, "*.log")
    txt_logs = newest_files(root, "*.txt")
    json_files = newest_files(root, "*.json")

    blockers = []
    if not pdfs:
        blockers.append("No PDF was found under the provided directory.")
    if not htmls:
        blockers.append("No unified_tree_viz.html file was found.")
    if not logs and not txt_logs:
        blockers.append("No .log or .txt logs were found.")

    result = {
        "root": str(root),
        "pdfs": [str(path) for path in pdfs],
        "treeVisualizations": [str(path) for path in htmls],
        "logFiles": [str(path) for path in logs + txt_logs],
        "jsonFiles": [str(path) for path in json_files],
        "blockers": blockers,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print(f"Run root: {result['root']}")
    print(f"PDF count: {len(result['pdfs'])}")
    for path in result["pdfs"]:
        print(f"  - {path}")
    print(f"Tree visualization count: {len(result['treeVisualizations'])}")
    for path in result["treeVisualizations"]:
        print(f"  - {path}")
    print(f"Log count: {len(result['logFiles'])}")
    for path in result["logFiles"][:10]:
        print(f"  - {path}")
    print(f"JSON count: {len(result['jsonFiles'])}")
    for path in result["jsonFiles"][:10]:
        print(f"  - {path}")
    if blockers:
        print("Blockers:")
        for item in blockers:
            print(f"  - {item}")
    else:
        print("Blockers: none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
