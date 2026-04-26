#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import requests


API_BASE = "https://api.zsxq.com/v2"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download PDF files from a Knowledge Planet group file listing."
    )
    parser.add_argument("--group-url", help="Knowledge Planet group URL, e.g. https://wx.zsxq.com/group/123.")
    parser.add_argument("--group-id", help="Knowledge Planet group id. Overrides --group-url parsing.")
    parser.add_argument("--files-api-json", help="Existing files API JSON to reuse instead of fetching.")
    parser.add_argument("--target-dir", required=True, help="Intermediate task directory.")
    parser.add_argument("--cookie-header", help="Cookie header copied from the logged-in browser session.")
    parser.add_argument("--authorization", help="Optional Authorization header if required by the session.")
    parser.add_argument("--count", type=int, default=100, help="Files per API page when fetching.")
    parser.add_argument("--max-pages", type=int, default=10, help="Maximum file API pages to fetch.")
    parser.add_argument("--limit", type=int, default=0, help="Optional max PDF downloads. 0 means all.")
    parser.add_argument("--dry-run", action="store_true", help="Write logs without downloading PDFs.")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def safe_name(value: str) -> str:
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "_", value).strip()
    return value or "unnamed.pdf"


def group_id_from_args(args: argparse.Namespace) -> str:
    if args.group_id:
        return args.group_id
    if args.group_url:
        match = re.search(r"/group/(\d+)", args.group_url)
        if match:
            return match.group(1)
    raise SystemExit("Provide --group-id or a --group-url containing /group/<id>.")


def build_session(args: argparse.Namespace) -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json, text/plain, */*",
            "Referer": args.group_url or "https://wx.zsxq.com/",
        }
    )
    if args.cookie_header:
        session.headers["Cookie"] = args.cookie_header
    if args.authorization:
        session.headers["Authorization"] = args.authorization
    return session


def extract_files(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return []
    resp_data = payload.get("resp_data") or payload.get("data") or {}
    files = resp_data.get("files") or resp_data.get("items") or payload.get("files") or []
    return files if isinstance(files, list) else []


def fetch_file_pages(args: argparse.Namespace, group_id: str, session: requests.Session, target_dir: Path) -> list[dict[str, Any]]:
    pages_dir = ensure_dir(target_dir / "api_pages")
    all_files: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    end_time = None

    for page_index in range(1, args.max_pages + 1):
        params = {"count": args.count, "sort": "download_count"}
        if end_time:
            params["end_time"] = end_time
        url = f"{API_BASE}/groups/{group_id}/files"
        response = session.get(url, params=params, timeout=30)
        response.raise_for_status()
        payload = response.json()
        (pages_dir / f"files-page-{page_index:02d}.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        files = extract_files(payload)
        if not files:
            break

        new_count = 0
        for item in files:
            file_info = item.get("file") or item
            file_id = str(file_info.get("file_id") or file_info.get("id") or file_info.get("fileId") or "")
            if file_id and file_id not in seen_ids:
                seen_ids.add(file_id)
                all_files.append(item)
                new_count += 1
        if new_count == 0:
            break

        last_info = (files[-1].get("file") or files[-1]) if files else {}
        next_end_time = last_info.get("create_time") or last_info.get("created_at") or last_info.get("update_time")
        if not next_end_time or next_end_time == end_time:
            break
        end_time = next_end_time

    aggregate = {"resp_data": {"files": all_files}, "fetched_at": datetime.now().isoformat(timespec="seconds")}
    (target_dir / "file_api_aggregate.json").write_text(
        json.dumps(aggregate, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return all_files


def load_files(args: argparse.Namespace, group_id: str, session: requests.Session, target_dir: Path) -> list[dict[str, Any]]:
    if args.files_api_json:
        source = Path(args.files_api_json)
        payload = json.loads(source.read_text(encoding="utf-8"))
        (target_dir / "file_api_aggregate.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return extract_files(payload)
    return fetch_file_pages(args, group_id, session, target_dir)


def file_id_of(item: dict[str, Any]) -> str:
    file_info = item.get("file") or item
    return str(file_info.get("file_id") or file_info.get("id") or file_info.get("fileId") or "")


def file_name_of(item: dict[str, Any]) -> str:
    file_info = item.get("file") or item
    return str(file_info.get("name") or file_info.get("title") or f"{file_id_of(item)}.pdf")


def is_pdf_item(item: dict[str, Any]) -> bool:
    name = file_name_of(item).lower()
    file_info = item.get("file") or item
    mime = str(file_info.get("mime_type") or file_info.get("content_type") or "").lower()
    return name.endswith(".pdf") or "pdf" in mime


def extract_download_url(payload: Any) -> str:
    if isinstance(payload, str):
        return payload
    if not isinstance(payload, dict):
        return ""
    resp_data = payload.get("resp_data") or payload.get("data") or payload
    for key in ("download_url", "url", "file_url", "signed_url"):
        value = resp_data.get(key)
        if isinstance(value, str) and value.startswith("http"):
            return value
    nested = resp_data.get("file") if isinstance(resp_data, dict) else None
    if isinstance(nested, dict):
        for key in ("download_url", "url", "file_url"):
            value = nested.get(key)
            if isinstance(value, str) and value.startswith("http"):
                return value
    return ""


def get_download_url(session: requests.Session, file_id: str) -> tuple[str, Any]:
    candidates = [
        f"{API_BASE}/files/{file_id}/download_url",
        f"{API_BASE}/files/{file_id}/download_url?download=1",
    ]
    last_payload: Any = None
    for url in candidates:
        response = session.get(url, timeout=30)
        response.raise_for_status()
        payload = response.json()
        last_payload = payload
        download_url = extract_download_url(payload)
        if download_url:
            return download_url, payload
    return "", last_payload


def download_pdfs(args: argparse.Namespace, files: list[dict[str, Any]], session: requests.Session, target_dir: Path) -> list[dict[str, Any]]:
    pdf_dir = ensure_dir(target_dir / "pdfs")
    log: list[dict[str, Any]] = []
    pdf_items = [item for item in files if is_pdf_item(item)]
    if args.limit:
        pdf_items = pdf_items[: args.limit]

    for index, item in enumerate(pdf_items, start=1):
        file_id = file_id_of(item)
        name = safe_name(file_name_of(item))
        if not name.lower().endswith(".pdf"):
            name += ".pdf"
        output_path = pdf_dir / name
        entry = {
            "index": index,
            "name": name,
            "file_id": file_id,
            "path": str(output_path),
            "ok": False,
            "stage": "download_url",
            "error": "",
        }
        try:
            if args.dry_run:
                entry.update({"ok": True, "stage": "dry_run"})
                log.append(entry)
                continue
            if not file_id:
                raise RuntimeError("missing file id")
            download_url, url_payload = get_download_url(session, file_id)
            entry["download_url_payload"] = url_payload
            if not download_url:
                raise RuntimeError("download_url not found in API response")
            entry["stage"] = "download"
            response = session.get(download_url, timeout=120)
            response.raise_for_status()
            output_path.write_bytes(response.content)
            entry.update({"ok": True, "bytes": output_path.stat().st_size, "stage": "done"})
        except Exception as exc:
            entry["error"] = str(exc)
        log.append(entry)

    (target_dir / "pdf_download_log.json").write_text(
        json.dumps(log, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return log


def main() -> int:
    args = parse_args()
    target_dir = ensure_dir(Path(args.target_dir))
    group_id = group_id_from_args(args)
    session = build_session(args)
    try:
        files = load_files(args, group_id, session, target_dir)
        log = download_pdfs(args, files, session, target_dir)
    except Exception as exc:
        print(f"capture_zsxq_pdfs failed: {exc}", file=sys.stderr)
        return 1

    summary = {
        "group_id": group_id,
        "files_total": len(files),
        "pdf_total": sum(1 for item in files if is_pdf_item(item)),
        "download_ok": sum(1 for item in log if item.get("ok")),
        "target_dir": str(target_dir),
    }
    (target_dir / "pdf_capture_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
