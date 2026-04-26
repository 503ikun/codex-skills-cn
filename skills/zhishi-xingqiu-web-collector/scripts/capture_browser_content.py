#!/usr/bin/env python
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import pyautogui
    import pygetwindow as gw
    import pyperclip
    import requests
except ImportError as exc:  # pragma: no cover
    raise SystemExit(f"Missing dependency: {exc}")


IMAGE_URL_RE = re.compile(
    r"""https?://[^\s"'<>]+?\.(?:png|jpg|jpeg|gif|webp|bmp|svg)(?:\?[^\s"'<>]*)?""",
    re.IGNORECASE,
)
NEXT_LABELS = ("下一页", "next", ">", "›", "后页", "后一页")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture browser-visible content into a structured JSON log."
    )
    parser.add_argument("--target-dir", required=True, help="Directory for logs and assets.")
    parser.add_argument("--file-stem", default=None, help="Optional output stem.")
    parser.add_argument(
        "--title-substring",
        default="Google Chrome",
        help="Window title substring used to find the browser window.",
    )
    parser.add_argument("--max-rounds", type=int, default=40)
    parser.add_argument("--stale-rounds", type=int, default=3)
    parser.add_argument("--scroll-steps", type=int, default=10)
    parser.add_argument("--scroll-pause", type=float, default=0.35)
    parser.add_argument("--page-pause", type=float, default=1.2)
    parser.add_argument("--max-pages", type=int, default=10)
    return parser.parse_args()


def now_stamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def slugify(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    value = value.strip("-._")
    return value or "capture"


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def list_windows(substring: str) -> list[Any]:
    return [w for w in gw.getAllWindows() if getattr(w, "title", "") and substring in w.title]


def activate_window(substring: str) -> Any:
    windows = list_windows(substring)
    if not windows:
        raise RuntimeError(f"No window title contains: {substring}")
    win = windows[0]
    if getattr(win, "isMinimized", False):
        win.restore()
        time.sleep(0.5)
    win.activate()
    time.sleep(0.8)
    return win


def safe_click(x: int, y: int) -> None:
    pyautogui.click(x, y)
    time.sleep(0.2)


def copy_current_url() -> str:
    pyautogui.hotkey("ctrl", "l")
    time.sleep(0.2)
    pyautogui.hotkey("ctrl", "c")
    time.sleep(0.3)
    url = pyperclip.paste().strip()
    pyautogui.press("esc")
    time.sleep(0.15)
    return url


def focus_page_body(win: Any) -> None:
    center_x = int(win.left + max(200, win.width * 0.45))
    center_y = int(win.top + max(220, win.height * 0.35))
    safe_click(center_x, center_y)


def copy_page_text(win: Any) -> str:
    focus_page_body(win)
    pyautogui.hotkey("ctrl", "a")
    time.sleep(0.25)
    pyautogui.hotkey("ctrl", "c")
    time.sleep(0.8)
    return pyperclip.paste()


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="ignore")).hexdigest()


def download_images(image_urls: list[str], output_dir: Path, seen: set[str]) -> list[str]:
    downloaded: list[str] = []
    ensure_dir(output_dir)
    session = requests.Session()
    session.headers.update({"User-Agent": "Mozilla/5.0"})
    for index, url in enumerate(image_urls, start=1):
        if url in seen:
            continue
        try:
            response = session.get(url, timeout=15)
            response.raise_for_status()
            suffix = Path(re.sub(r"\?.*$", "", url)).suffix.lower() or ".bin"
            if len(suffix) > 8:
                suffix = ".bin"
            name = f"image-{len(seen)+1:04d}{suffix}"
            path = output_dir / name
            path.write_bytes(response.content)
            downloaded.append(str(path))
            seen.add(url)
        except Exception:
            continue
    return downloaded


def save_round_screenshot(path: Path) -> None:
    ensure_dir(path.parent)
    pyautogui.screenshot().save(path)


def scroll_page(steps: int, pause: float) -> None:
    for _ in range(steps):
        pyautogui.press("pagedown")
        time.sleep(pause)


def probe_next_page() -> bool:
    original = pyperclip.paste()
    try:
        for _ in range(25):
            pyautogui.press("tab")
            time.sleep(0.15)
            pyautogui.hotkey("ctrl", "c")
            time.sleep(0.15)
            focused = pyperclip.paste().strip().lower()
            if any(label.lower() in focused for label in NEXT_LABELS):
                pyautogui.press("enter")
                time.sleep(2.0)
                return True
    finally:
        pyperclip.copy(original)
    return False


def build_capture_log(args: argparse.Namespace) -> Path:
    target_dir = ensure_dir(Path(args.target_dir))
    stem = slugify(args.file_stem or f"browser-capture-{now_stamp()}")
    work_dir = ensure_dir(target_dir / f"{stem}-assets")
    screenshot_dir = ensure_dir(work_dir / "screenshots")
    image_dir = ensure_dir(work_dir / "images")
    log_path = target_dir / f"{stem}.capture.json"

    win = activate_window(args.title_substring)
    base_url = copy_current_url()
    rounds: list[dict[str, Any]] = []
    seen_hashes: set[str] = set()
    seen_image_urls: set[str] = set()
    stale = 0
    page_index = 1
    pagination_attempts = 0

    while len(rounds) < args.max_rounds:
        url = copy_current_url()
        text = normalize_text(copy_page_text(win))
        image_urls = sorted(set(IMAGE_URL_RE.findall(text)))
        screenshot_path = screenshot_dir / f"page-{page_index:02d}-round-{len(rounds)+1:02d}.png"
        save_round_screenshot(screenshot_path)
        downloaded = download_images(image_urls, image_dir, seen_image_urls)

        digest = text_hash(text)
        if digest in seen_hashes:
            stale += 1
        else:
            stale = 0
            seen_hashes.add(digest)

        rounds.append(
            {
                "round": len(rounds) + 1,
                "page_index": page_index,
                "url": url or base_url,
                "text_length": len(text),
                "text_hash": digest,
                "text": text,
                "image_urls": image_urls,
                "downloaded_images": downloaded,
                "screenshot": str(screenshot_path),
                "captured_at": datetime.now().isoformat(timespec="seconds"),
            }
        )

        if stale >= args.stale_rounds:
            if pagination_attempts < args.max_pages and probe_next_page():
                pagination_attempts += 1
                page_index += 1
                stale = 0
                time.sleep(args.page_pause)
                continue
            break

        scroll_page(args.scroll_steps, args.scroll_pause)
        time.sleep(args.page_pause)

    payload = {
        "title_substring": args.title_substring,
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "base_url": base_url,
        "target_dir": str(target_dir),
        "asset_dir": str(work_dir),
        "rounds": rounds,
        "summary": {
            "round_count": len(rounds),
            "page_count": page_index,
            "downloaded_image_count": sum(len(r["downloaded_images"]) for r in rounds),
        },
    }
    log_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return log_path


def main() -> int:
    args = parse_args()
    try:
        log_path = build_capture_log(args)
    except Exception as exc:
        print(f"capture failed: {exc}", file=sys.stderr)
        return 1
    print(log_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
