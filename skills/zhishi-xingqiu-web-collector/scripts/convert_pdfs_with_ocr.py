#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_CONVERT_SCRIPT = (
    Path.home()
    / ".codex"
    / "skills"
    / "convert-anything-to-markdown"
    / "scripts"
    / "convert_to_markdown.py"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert downloaded PDFs to Markdown, falling back to local OCR for scanned PDFs."
    )
    parser.add_argument("--pdf-dir", required=True, help="Directory containing PDF files.")
    parser.add_argument("--output-dir", required=True, help="Directory for per-PDF Markdown files.")
    parser.add_argument("--convert-script", default=str(DEFAULT_CONVERT_SCRIPT), help="convert-anything-to-markdown script.")
    parser.add_argument("--min-text-chars", type=int, default=80, help="Minimum converted text length before OCR fallback.")
    parser.add_argument("--ocr-scale", type=float, default=2.0, help="PDF render scale for OCR fallback.")
    parser.add_argument("--limit", type=int, default=0, help="Optional max PDFs to process. 0 means all.")
    parser.add_argument("--force-ocr", action="store_true", help="Skip markitdown and use OCR directly.")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def meaningful_text_length(text: str) -> int:
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").splitlines():
        line = raw.strip()
        if not line or line.startswith("# ") or line.startswith("- "):
            continue
        lines.append(line)
    return len("\n".join(lines).strip())


def run_markitdown(convert_script: Path, pdf_path: Path, output_path: Path) -> tuple[bool, str]:
    if not convert_script.exists():
        return False, f"convert script not found: {convert_script}"
    command = [sys.executable, str(convert_script), str(pdf_path), "--output", str(output_path)]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=600)
    if completed.returncode != 0:
        return False, (completed.stderr or completed.stdout).strip()
    return True, (completed.stdout or "").strip()


def load_ocr_engine() -> Any:
    try:
        from rapidocr_onnxruntime import RapidOCR
    except ImportError as exc:
        raise RuntimeError(
            "rapidocr_onnxruntime is required for scanned PDF OCR. "
            "Install local OCR dependencies or rerun without OCR fallback."
        ) from exc
    return RapidOCR()


def ocr_image(engine: Any, image: Any) -> list[str]:
    try:
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("numpy is required for OCR fallback") from exc

    result = engine(np.array(image))
    if isinstance(result, tuple):
        result = result[0]
    if not result:
        return []

    lines: list[str] = []
    for item in result:
        text = ""
        if isinstance(item, (list, tuple)):
            if len(item) >= 2 and isinstance(item[1], str):
                text = item[1]
            elif len(item) >= 1 and isinstance(item[0], str):
                text = item[0]
        elif isinstance(item, str):
            text = item
        if text.strip():
            lines.append(text.strip())
    return lines


def ocr_pdf(pdf_path: Path, output_path: Path, scale: float) -> dict[str, Any]:
    try:
        import pypdfium2 as pdfium
    except ImportError as exc:
        raise RuntimeError("pypdfium2 is required for scanned PDF OCR") from exc

    engine = load_ocr_engine()
    pdf = pdfium.PdfDocument(str(pdf_path))
    markdown_lines = [
        f"# {pdf_path.stem}",
        "",
        f"- Source PDF: {pdf_path.name}",
        f"- Pages: {len(pdf)}",
        "- Conversion: local OCR fallback (rapidocr_onnxruntime + pypdfium2)",
        "",
    ]
    page_char_counts: list[int] = []
    for page_index in range(len(pdf)):
        page = pdf[page_index]
        bitmap = page.render(scale=scale)
        image = bitmap.to_pil()
        page_lines = ocr_image(engine, image)
        page_text = "\n".join(page_lines).strip()
        page_char_counts.append(len(page_text))
        markdown_lines.extend([f"## Page {page_index + 1}", "", page_text or "> [No OCR text detected]", ""])

    output_path.write_text("\n".join(markdown_lines).strip() + "\n", encoding="utf-8")
    return {
        "pages": len(pdf),
        "page_char_counts": page_char_counts,
        "text_chars": sum(page_char_counts),
    }


def convert_one(args: argparse.Namespace, pdf_path: Path, output_dir: Path) -> dict[str, Any]:
    output_path = output_dir / f"{pdf_path.stem}.md"
    entry: dict[str, Any] = {
        "name": pdf_path.name,
        "pdf_path": str(pdf_path),
        "md_path": str(output_path),
        "ok": False,
        "method": "",
        "error": "",
    }

    try:
        if not args.force_ocr:
            ok, message = run_markitdown(Path(args.convert_script), pdf_path, output_path)
            entry["markitdown_message"] = message
            if ok and output_path.exists():
                text = output_path.read_text(encoding="utf-8", errors="ignore")
                entry["markitdown_text_chars"] = meaningful_text_length(text)
                if entry["markitdown_text_chars"] >= args.min_text_chars:
                    entry.update({"ok": True, "method": "markitdown"})
                    return entry

        ocr_info = ocr_pdf(pdf_path, output_path, args.ocr_scale)
        entry.update({"ok": True, "method": "ocr", **ocr_info})
    except Exception as exc:
        entry["error"] = str(exc)
    return entry


def main() -> int:
    args = parse_args()
    pdf_dir = Path(args.pdf_dir)
    output_dir = ensure_dir(Path(args.output_dir))
    if not pdf_dir.exists() or not pdf_dir.is_dir():
        print(f"pdf directory not found: {pdf_dir}", file=sys.stderr)
        return 1

    pdfs = sorted(pdf_dir.glob("*.pdf"))
    if args.limit:
        pdfs = pdfs[: args.limit]

    log = [convert_one(args, pdf_path, output_dir) for pdf_path in pdfs]
    log_path = output_dir.parent / "pdf_ocr_log.json"
    log_path.write_text(json.dumps(log, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = {
        "processed": len(log),
        "ok": sum(1 for item in log if item.get("ok")),
        "markitdown": sum(1 for item in log if item.get("method") == "markitdown"),
        "ocr": sum(1 for item in log if item.get("method") == "ocr"),
        "written_at": datetime.now().isoformat(timespec="seconds"),
        "log_path": str(log_path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary["ok"] == len(log) else 1


if __name__ == "__main__":
    raise SystemExit(main())
