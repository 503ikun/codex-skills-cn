#!/usr/bin/env python3
"""Convert a single local file to Markdown with markitdown."""

from __future__ import annotations

import argparse
import importlib
import subprocess
import sys
from pathlib import Path


INSTALL_SPEC = "markitdown[all]"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a single local file into Markdown."
    )
    parser.add_argument("input_path", help="Path to the source file.")
    parser.add_argument(
        "--output",
        help="Optional output path. Defaults to <input_basename>.md next to the source.",
    )
    return parser.parse_args()


def resolve_input(path_text: str) -> Path:
    input_path = Path(path_text).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    if not input_path.is_file():
        raise IsADirectoryError(f"Expected a file, got: {input_path}")
    return input_path


def resolve_output(input_path: Path, output_text: str | None) -> Path:
    if output_text:
        return Path(output_text).expanduser().resolve()
    return input_path.with_suffix(".md")


def ensure_markitdown() -> tuple[type, bool]:
    try:
        module = importlib.import_module("markitdown")
        return module.MarkItDown, False
    except ImportError:
        print(
            f"[INFO] markitdown is not installed. Installing {INSTALL_SPEC}...",
            file=sys.stderr,
        )
        subprocess.run(
            [sys.executable, "-m", "pip", "install", INSTALL_SPEC],
            check=True,
        )
        module = importlib.import_module("markitdown")
        return module.MarkItDown, True


def convert_file(markitdown_cls: type, input_path: Path) -> str:
    converter = markitdown_cls()
    result = converter.convert(str(input_path))
    text_content = getattr(result, "text_content", None)
    if not text_content:
        raise RuntimeError(
            "markitdown conversion succeeded but returned no Markdown text."
        )
    return text_content


def main() -> int:
    args = parse_args()

    try:
        input_path = resolve_input(args.input_path)
        output_path = resolve_output(input_path, args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        markitdown_cls, installed_now = ensure_markitdown()
        markdown_text = convert_file(markitdown_cls, input_path)
        output_path.write_text(markdown_text, encoding="utf-8")

        print(f"[OK] Converted: {input_path}")
        print(f"[OK] Output: {output_path}")
        print(f"[OK] Auto-installed markitdown: {'yes' if installed_now else 'no'}")

        if input_path.stat().st_size > 25 * 1024 * 1024:
            print(
                "[WARN] Large input file detected. Extraction quality and runtime may vary.",
                file=sys.stderr,
            )

        return 0
    except FileNotFoundError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2
    except IsADirectoryError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as exc:
        print(
            f"[ERROR] Failed to install {INSTALL_SPEC}. pip exit code: {exc.returncode}",
            file=sys.stderr,
        )
        return 3
    except Exception as exc:
        print(f"[ERROR] Conversion failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
