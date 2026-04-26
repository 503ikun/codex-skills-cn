#!/usr/bin/env python3
"""Create an AI-Scientist-v2 topic Markdown file."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def slugify(value: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9]+", "_", value.strip().lower()).strip("_")
    return normalized or "research_topic"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True, help="Workshop-style topic title.")
    parser.add_argument(
        "--keywords",
        default="ai research, automation, experimentation",
        help="Comma-separated keywords.",
    )
    parser.add_argument(
        "--tldr",
        default="Investigate a focused research direction with a concrete experimental angle.",
        help="One or two sentence summary.",
    )
    parser.add_argument(
        "--abstract",
        default=(
            "Describe the problem setting, why it matters, the intended experiment direction, "
            "and what kind of contribution or negative result would still be valuable."
        ),
        help="Abstract paragraph.",
    )
    parser.add_argument(
        "--output",
        help="Output Markdown path. Defaults to ./<slug>.md in the current directory.",
    )
    args = parser.parse_args()

    output = Path(args.output) if args.output else Path.cwd() / f"{slugify(args.title)}.md"
    output.parent.mkdir(parents=True, exist_ok=True)
    content = (
        f"# Title: {args.title}\n\n"
        "## Keywords\n"
        f"{args.keywords}\n\n"
        "## TL;DR\n"
        f"{args.tldr}\n\n"
        "## Abstract\n"
        f"{args.abstract}\n"
    )
    output.write_text(content, encoding="utf-8")
    print(str(output.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
