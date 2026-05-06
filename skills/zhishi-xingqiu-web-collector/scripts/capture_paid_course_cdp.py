"""Capture logged-in paid-course/article platforms through Chrome CDP.

This script is intentionally conservative: it uses the currently logged-in
Chrome session exposed on a local debugging port and only calls endpoints the
page itself can access with credentials included.
"""

from __future__ import annotations

import argparse
import html
import itertools
import json
import re
import time
import urllib.parse
import urllib.request
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path


DEFAULT_CDP_HTTP = "http://127.0.0.1:9222"
ARTICLE_DATE_RE = re.compile(r"^\d{4}[-./]\d{1,2}[-./]\d{1,2}(?:\s+\d{1,2}:\d{2})?$")
XIAOETONG_DETAIL_API = "/xe.course.business_go.get.detail/2.0.0"
XIAOETONG_CORE_API = "/xe.course.business_go.core.info.get/2.0.0"
XIAOETONG_LOOP_API = "/xe.course.business_go.resource.loop_resource.get/2.0.0"
XIAOETONG_DETAIL_API_PLAIN = "/xe.course.business.get.detail/2.0.0"
XIAOETONG_CORE_API_PLAIN = "/xe.course.business.core.info.get/2.0.0"
XIAOETONG_MEMBER_COLUMN_API = "/xe.course.business.member.column_items.get/2.0.0"
XIAOETONG_MEMBER_SINGLE_API = "/xe.course.business.member.single_items.get/2.0.0"
XIAOETONG_MEMBER_COURSE_API = "/xe.course.business.member.course.get/2.0.0"
XIAOETONG_COLUMN_ITEMS_API = "/xe.course.business.column.items.get/2.0.0"


class CDP:
    def __init__(self, ws_url: str):
        try:
            import websocket
        except ImportError as exc:
            raise SystemExit("Missing dependency: install websocket-client for CDP capture.") from exc
        self.ws = websocket.create_connection(ws_url, timeout=8)
        self.seq = itertools.count(1)

    def close(self) -> None:
        self.ws.close()

    def cmd(self, method: str, params: dict | None = None, timeout: float = 20) -> dict:
        msg_id = next(self.seq)
        self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        deadline = time.time() + timeout
        while time.time() < deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == msg_id:
                if "error" in msg:
                    raise RuntimeError(f"{method} failed: {msg['error']}")
                return msg
        raise TimeoutError(method)

    def eval(self, expression: str, timeout: float = 20):
        response = self.cmd(
            "Runtime.evaluate",
            {"expression": expression, "returnByValue": True, "awaitPromise": True},
            timeout=timeout,
        )
        result = response.get("result", {}).get("result", {})
        return result.get("value")

    def drain(self, seconds: float, response_filter=None) -> list[dict]:
        events: list[dict] = []
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                self.ws.settimeout(max(0.1, deadline - time.time()))
                msg = json.loads(self.ws.recv())
            except Exception:
                break
            if response_filter and msg.get("method") == "Network.responseReceived":
                if response_filter(msg.get("params", {})):
                    events.append(msg)
            else:
                events.append(msg)
        return events


class TextHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style"}:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        attr = dict(attrs)
        if tag == "img":
            src = attr.get("data-src") or attr.get("src") or ""
            alt = attr.get("alt") or "image"
            self.parts.append(f"\n![{alt}]({src})\n" if src else f"\n![{alt}]\n")
        elif tag in {"p", "div", "section", "article", "br", "li", "tr", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style"} and self.skip_depth:
            self.skip_depth -= 1
        elif not self.skip_depth and tag in {"p", "div", "section", "article", "li", "tr", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.skip_depth:
            self.parts.append(data)


def html_to_text(raw_html: str) -> str:
    parser = TextHTMLParser()
    parser.feed(raw_html or "")
    text = html.unescape("".join(parser.parts))
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def load_json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def append_jsonl(path: Path | None, event: str, **fields) -> None:
    if not path:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"time": now(), "event": event, **fields}, ensure_ascii=False) + "\n")


def http_json(url: str):
    with urllib.request.urlopen(url, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def host_from_url(url: str) -> str:
    return urllib.parse.urlparse(url).netloc


def product_id_from_url(url: str) -> str:
    match = re.search(r"/(p_[A-Za-z0-9]+)", url or "")
    return match.group(1) if match else ""


def resource_id_from_url(url: str) -> str:
    match = re.search(r"/(?:text|audio|video)/(i_[A-Za-z0-9]+)", url or "")
    return match.group(1) if match else ""


def task_path(args, name: str) -> Path:
    return Path(args.task_dir) / name


def cdp_pages(cdp_http: str) -> list[dict]:
    return http_json(f"{cdp_http.rstrip('/')}/json")


def select_page(args) -> dict:
    marker = args.host_marker or host_from_url(args.source_url)
    pages = cdp_pages(args.cdp_http)
    for page in pages:
        if page.get("type") == "page" and marker and marker in page.get("url", ""):
            return page
    for page in pages:
        if page.get("type") == "page":
            return page
    raise RuntimeError("No Chrome page is exposed on the CDP port.")


def connect(args) -> CDP:
    page = select_page(args)
    cdp = CDP(page["webSocketDebuggerUrl"])
    cdp.cmd("Runtime.enable")
    cdp.cmd("Network.enable")
    cdp.cmd("Page.enable")
    return cdp


def page_state(cdp: CDP) -> dict:
    return cdp.eval(
        """(() => ({
          url: location.href,
          title: document.title,
          textLen: document.body ? document.body.innerText.length : 0,
          textHead: document.body ? document.body.innerText.slice(0, 1200) : ""
        }))()"""
    )


def interesting_response(args):
    marker = args.host_marker or host_from_url(args.source_url)

    def inner(params: dict) -> bool:
        response = params.get("response", {})
        url = response.get("url", "")
        mime = response.get("mimeType", "")
        if marker and marker not in url:
            return False
        if any(noise in url for noise in ("aegis", "logreport", "sentry", "analytics")):
            return False
        return "json" in mime or "/xe." in url or "course" in url or "goods" in url or "resource" in url

    return inner


def get_response_body(cdp: CDP, request_id: str) -> dict:
    try:
        return cdp.cmd("Network.getResponseBody", {"requestId": request_id}, timeout=5).get("result", {})
    except Exception as exc:
        return {"error": repr(exc)}


def recursive_records(obj) -> list[dict]:
    records: list[dict] = []
    if isinstance(obj, dict):
        title = obj.get("title") or obj.get("name") or obj.get("resource_name") or obj.get("resource_title")
        ident = obj.get("resource_id") or obj.get("id") or obj.get("biz_id") or obj.get("course_id")
        date = obj.get("created_at") or obj.get("create_time") or obj.get("sale_at") or obj.get("update_time")
        if title and ident:
            records.append({
                "title": title,
                "id": ident,
                "date_like": date,
                "url_like": obj.get("url") or obj.get("link") or obj.get("jump_url"),
                "keys": sorted(obj.keys())[:40],
            })
        for value in obj.values():
            records.extend(recursive_records(value))
    elif isinstance(obj, list):
        for item in obj:
            records.extend(recursive_records(item))
    return records


def scroll_page(cdp: CDP, rounds: int) -> None:
    for _ in range(rounds):
        cdp.eval(
            """(() => {
              window.scrollBy(0, 900);
              [...document.querySelectorAll('*')]
                .filter(e => e.scrollHeight > e.clientHeight + 200)
                .sort((a,b) => (b.scrollHeight-b.clientHeight) - (a.scrollHeight-a.clientHeight))
                .slice(0, 8)
                .forEach(e => e.scrollTop += 900);
              return true;
            })()"""
        )
        time.sleep(0.8)


def probe(args) -> None:
    cdp = connect(args)
    captures = []
    try:
        if args.navigate:
            cdp.cmd("Page.navigate", {"url": args.source_url})
            time.sleep(args.wait)
        before = page_state(cdp)
        events = cdp.drain(args.listen_seconds, interesting_response(args))
        scroll_page(cdp, args.scroll_rounds)
        events.extend(cdp.drain(args.listen_seconds, interesting_response(args)))
        for event in events:
            params = event.get("params", {})
            response = params.get("response", {})
            body = get_response_body(cdp, params.get("requestId", ""))
            text = body.get("body") if not body.get("base64Encoded") else ""
            records = []
            if text:
                try:
                    records = recursive_records(json.loads(text))
                except Exception:
                    records = []
            captures.append({
                "type": params.get("type"),
                "url": response.get("url"),
                "status": response.get("status"),
                "mimeType": response.get("mimeType"),
                "body_preview": (text or "")[:1200],
                "record_count": len(records),
                "records": records[:20],
            })
        out = task_path(args, args.probe_out)
        save_json(out, {"captured_at": now(), "state": before, "captures": captures})
        print(json.dumps({"out": str(out), "captures": len(captures), "record_candidates": sum(c["record_count"] for c in captures)}, ensure_ascii=False))
    finally:
        cdp.close()


def api_post(cdp: CDP, path: str, data: dict, timeout: float = 30) -> dict:
    expression = f"""
    (async () => {{
      const data = {json.dumps(data, ensure_ascii=False)};
      const body = Object.entries(data)
        .map(([k, v]) => `bizData[${{encodeURIComponent(k)}}]=${{encodeURIComponent(v ?? '')}}`)
        .join('&');
      const response = await fetch({json.dumps(path)}, {{
        method: 'POST',
        headers: {{'Content-Type': 'application/x-www-form-urlencoded'}},
        body,
        credentials: 'include'
      }});
      return {{status: response.status, text: await response.text()}};
    }})()
    """
    result = cdp.eval(expression, timeout=timeout)
    if not result:
        raise RuntimeError(f"No result from {path}")
    return json.loads(result.get("text") or "{}")


def api_post_plain(cdp: CDP, path: str, data: dict | None = None, timeout: float = 30) -> dict:
    """POST a normal x-www-form-urlencoded body from the current page context.

    Xiaoetong has two common API wrappers. Some article pages use `bizData[...]`
    keys, while paid member/course pages often call plain form fields such as
    `column_id`, `resource_id`, `page_index`, and `page_size`.
    """
    expression = f"""
    (async () => {{
      const data = {json.dumps(data or {}, ensure_ascii=False)};
      const response = await fetch({json.dumps(path)}, {{
        method: 'POST',
        headers: {{'Content-Type': 'application/x-www-form-urlencoded'}},
        body: new URLSearchParams(data).toString(),
        credentials: 'include'
      }});
      return {{status: response.status, text: await response.text()}};
    }})()
    """
    result = cdp.eval(expression, timeout=timeout)
    if not result:
        raise RuntimeError(f"No result from {path}")
    return json.loads(result.get("text") or "{}")


def fetch_xiaoetong_detail_flexible(cdp: CDP, args, resource_id: str) -> dict:
    """Fetch detail using both known Xiaoetong API families.

    The `business_go` endpoints work for many article columns. Member bundles
    and purchased-course pages may only expose the plain `business` endpoints.
    """
    product_id = args.product_id or product_id_from_url(args.source_url)
    errors = []
    for core_api, detail_api, poster in [
        (XIAOETONG_CORE_API, XIAOETONG_DETAIL_API, api_post),
        (XIAOETONG_CORE_API_PLAIN, XIAOETONG_DETAIL_API_PLAIN, api_post_plain),
    ]:
        try:
            core = poster(cdp, core_api, {"resource_id": resource_id}, timeout=45)
            detail = poster(cdp, detail_api, {"resource_id": resource_id, "product_id": product_id}, timeout=60)
            core_data = core.get("data") or {}
            detail_data = detail.get("data") or {}
            title = core_data.get("resource_name") or detail_data.get("title") or ""
            date = (core_data.get("sale_at_complete") or core_data.get("sale_at") or core_data.get("created_at") or "")[:10].replace(".", "-")
            text = html_to_text(detail_data.get("org_content") or detail_data.get("content") or "")
            if title and date and text and not text.startswith(title):
                text = f"{title}\n{date} 00:00\n{text}"
            return {
                "resource_id": resource_id,
                "article_title": title,
                "article_date": date,
                "url": f"https://{host_from_url(args.source_url)}/p/course/text/{resource_id}?product_id={product_id}",
                "text": text,
                "detail_code": detail.get("code"),
                "core": core,
                "detail": detail,
                "api_family": "plain" if poster is api_post_plain else "business_go",
            }
        except Exception as exc:
            errors.append(f"{core_api}/{detail_api}: {exc!r}")
    raise RuntimeError("; ".join(errors))


def fetch_xiaoetong_detail(cdp: CDP, args, resource_id: str) -> dict:
    product_id = args.product_id or product_id_from_url(args.source_url)
    core = api_post(cdp, XIAOETONG_CORE_API, {"resource_id": resource_id})
    detail = api_post(cdp, XIAOETONG_DETAIL_API, {"resource_id": resource_id, "product_id": product_id}, timeout=45)
    core_data = core.get("data") or {}
    detail_data = detail.get("data") or {}
    title = core_data.get("resource_name") or detail_data.get("title") or ""
    date = (core_data.get("sale_at_complete") or core_data.get("sale_at") or core_data.get("created_at") or "")[:10].replace(".", "-")
    text = html_to_text(detail_data.get("org_content") or detail_data.get("content") or "")
    if title and date and not text.startswith(title):
        text = f"{title}\n{date} 00:00\n{text}"
    return {
        "resource_id": resource_id,
        "article_title": title,
        "article_date": date,
        "url": f"https://{host_from_url(args.source_url)}/p/course/text/{resource_id}?product_id={product_id}",
        "text": text,
        "detail_code": detail.get("code"),
    }


def fetch_xiaoetong_loop(cdp: CDP, args, resource_id: str) -> dict:
    product_id = args.product_id or product_id_from_url(args.source_url)
    data = api_post(
        cdp,
        XIAOETONG_LOOP_API,
        {"resource_id": resource_id, "product_id": product_id, "resource_type": 1},
    )
    if data.get("code") not in (0, "0", None):
        raise RuntimeError(f"loop_resource failed for {resource_id}: {data}")
    return data.get("data") or {}


def raw_file(args) -> Path:
    return task_path(args, args.raw)


def seen_keys(data: dict) -> set[str]:
    return {f"{a.get('article_date') or a.get('date')}|{a.get('article_title') or a.get('title')}" for a in data.get("articles", [])}


def normalize_record(record: dict, method: str) -> dict:
    title = record.get("article_title") or record.get("title") or ""
    date = record.get("article_date") or record.get("date") or ""
    return {
        "title": title,
        "date": date,
        "article_title": title,
        "article_date": date,
        "url": record.get("url") or "",
        "text": record.get("text") or "",
        "capture_method": method,
        "resource_id": record.get("resource_id") or resource_id_from_url(record.get("url") or ""),
        "captured_at": now(),
    }


def sample_details(args) -> None:
    data = load_json(raw_file(args), {"articles": [], "errors": []})
    ids = [args.start_id] if args.start_id else []
    ids.extend(resource_id_from_url(a.get("url") or "") or a.get("resource_id") or "" for a in data.get("articles", []))
    ids = [rid for rid in dict.fromkeys(ids) if rid]
    cdp = connect(args)
    samples = []
    try:
        for rid in ids[: args.max_articles]:
            try:
                record = fetch_xiaoetong_detail(cdp, args, rid)
                samples.append({"resource_id": rid, "title": record["article_title"], "date": record["article_date"], "text_len": len(record["text"]), "head": record["text"][:240]})
            except Exception as exc:
                samples.append({"resource_id": rid, "error": repr(exc)})
            print(json.dumps(samples[-1], ensure_ascii=False), flush=True)
    finally:
        cdp.close()
    out = task_path(args, args.out)
    save_json(out, {"captured_at": now(), "samples": samples})
    print(json.dumps({"out": str(out), "count": len(samples)}, ensure_ascii=False))


def traverse(args) -> None:
    path = raw_file(args)
    data = load_json(path, {"articles": [], "errors": []})
    seen = seen_keys(data)
    progress = task_path(args, args.progress_log) if args.progress_log else None
    current = args.start_id
    if not current:
        for article in reversed(data.get("articles", [])):
            current = article.get("resource_id") or resource_id_from_url(article.get("url") or "")
            if current:
                break
    if not current:
        raise SystemExit("Need --start-id or existing raw records with resource ids/URLs.")
    cdp = connect(args)
    saved = 0
    visited: set[str] = set()
    append_jsonl(progress, "start", start_id=current, existing=len(data.get("articles", [])))
    try:
        while current and saved < args.max_new and len(visited) < args.max_steps:
            if current in visited:
                raise RuntimeError(f"Loop detected at {current}")
            visited.add(current)
            try:
                detail = fetch_xiaoetong_detail(cdp, args, current)
                key = f"{detail.get('article_date')}|{detail.get('article_title')}"
                if key not in seen:
                    if len(detail.get("text") or "") < args.min_text_len:
                        raise RuntimeError(f"Text too short: {len(detail.get('text') or '')} for {key}")
                    data.setdefault("articles", []).append(normalize_record(detail, "cdp-api-loop"))
                    seen.add(key)
                    saved += 1
                    save_json(path, data)
                    append_jsonl(progress, "article_saved", saved=saved, total=len(data["articles"]), resource_id=current, title=detail.get("article_title"), date=detail.get("article_date"), text_len=len(detail.get("text") or ""))
                    print(json.dumps({"saved": saved, "total": len(data["articles"]), "date": detail.get("article_date"), "title": detail.get("article_title"), "text_len": len(detail.get("text") or "")}, ensure_ascii=False), flush=True)
                loop = fetch_xiaoetong_loop(cdp, args, current)
                current = (loop.get(args.direction) or {}).get("id") or ""
                time.sleep(args.delay)
            except Exception as exc:
                data.setdefault("errors", []).append({"resource_id": current, "error": repr(exc), "time": now()})
                save_json(path, data)
                append_jsonl(progress, "article_error", resource_id=current, error=repr(exc))
                if args.stop_on_error:
                    raise
                loop = fetch_xiaoetong_loop(cdp, args, current)
                current = (loop.get(args.direction) or {}).get("id") or ""
    finally:
        save_json(path, data)
        cdp.close()
    summary = {"saved": saved, "total_articles": len(data.get("articles", [])), "visited": len(visited), "last_resource_id": current}
    append_jsonl(progress, "finish", **summary)
    print(json.dumps(summary, ensure_ascii=False))


def capture_known_urls(args) -> None:
    path = raw_file(args)
    data = load_json(path, {"articles": [], "errors": []})
    seen = seen_keys(data)
    urls = list(dict.fromkeys(a.get("url") for a in data.get("articles", []) if a.get("url")))
    cdp = connect(args)
    saved = 0
    try:
        for url in urls[: args.max_articles]:
            cdp.cmd("Page.navigate", {"url": url})
            time.sleep(args.wait)
            state = page_state(cdp)
            text = cdp.eval("document.body ? document.body.innerText : ''") or ""
            lines = [line.strip() for line in text.splitlines() if line.strip()]
            date_idx = next((i for i, line in enumerate(lines) if ARTICLE_DATE_RE.match(line)), -1)
            title = lines[date_idx - 1] if date_idx > 0 else (lines[0] if lines else "")
            date = lines[date_idx][:10].replace(".", "-").replace("/", "-") if date_idx >= 0 else ""
            key = f"{date}|{title}"
            if title and date and key not in seen and len(text) >= args.min_text_len:
                data.setdefault("articles", []).append(normalize_record({"article_title": title, "article_date": date, "url": state.get("url") or url, "text": text}, "cdp-known-url"))
                seen.add(key)
                saved += 1
                save_json(path, data)
            print(json.dumps({"saved": saved, "current": key, "text_len": len(text)}, ensure_ascii=False), flush=True)
    finally:
        save_json(path, data)
        cdp.close()


def normalize_existing(args) -> None:
    path = raw_file(args)
    data = load_json(path, {"articles": [], "errors": []})
    cdp = connect(args)
    updated = 0
    try:
        for idx, article in enumerate(data.get("articles", [])[: args.max_articles]):
            rid = article.get("resource_id") or resource_id_from_url(article.get("url") or "")
            if not rid:
                continue
            try:
                detail = fetch_xiaoetong_detail(cdp, args, rid)
                if len(detail.get("text") or "") >= args.min_text_len:
                    data["articles"][idx].update(normalize_record(detail, "cdp-api-normalized"))
                    updated += 1
                    if updated % args.save_every == 0:
                        save_json(path, data)
                print(json.dumps({"updated": updated, "idx": idx, "title": detail.get("article_title"), "text_len": len(detail.get("text") or "")}, ensure_ascii=False), flush=True)
                time.sleep(args.delay)
            except Exception as exc:
                data.setdefault("errors", []).append({"resource_id": rid, "error": repr(exc), "time": now()})
                if args.stop_on_error:
                    raise
    finally:
        save_json(path, data)
        cdp.close()
    print(json.dumps({"updated": updated, "total_articles": len(data.get("articles", []))}, ensure_ascii=False))


def fetch_paged_plain(cdp: CDP, path: str, params: dict, page_size: int, max_pages: int, delay: float = 0.0) -> dict:
    all_items = []
    total = None
    pages = []
    for page_index in range(1, max_pages + 1):
        page_params = {**params, "page_index": page_index, "page_size": page_size}
        response = api_post_plain(cdp, path, page_params, timeout=60)
        data = response.get("data") or {}
        items = data.get("list") or []
        if isinstance(data.get("total"), int):
            total = data.get("total")
        pages.append({"page_index": page_index, "count": len(items), "code": response.get("code"), "msg": response.get("msg")})
        all_items.extend(items)
        if delay:
            time.sleep(delay)
        if len(items) < page_size:
            break
    return {"total": total, "list": all_items, "pages": pages}


def capture_member_tree(args) -> None:
    """Capture Xiaoetong member-product resource trees.

    Use this when the product catalog tab is empty but the user owns a member
    product via "我的已购", and the member page exposes `member.column_items` /
    `member.single_items` rather than a linear article loop.
    """
    product_id = args.product_id or product_id_from_url(args.source_url)
    if not product_id:
        raise SystemExit("Need --product-id or a source URL containing p_xxx.")
    path = raw_file(args)
    progress = task_path(args, args.progress_log) if args.progress_log else None
    cdp = connect(args)
    try:
        append_jsonl(progress, "start-member-tree", product_id=product_id)
        top_columns = fetch_paged_plain(
            cdp,
            XIAOETONG_MEMBER_COLUMN_API,
            {"column_id": product_id, "isDesc": args.is_desc},
            args.page_size,
            args.max_pages,
            args.delay,
        )
        singles = fetch_paged_plain(
            cdp,
            XIAOETONG_MEMBER_SINGLE_API,
            {"column_id": product_id, "isDesc": args.is_desc},
            args.page_size,
            args.max_pages,
            args.delay,
        )
        member_courses = fetch_paged_plain(
            cdp,
            XIAOETONG_MEMBER_COURSE_API,
            {"column_id": product_id, "isDesc": args.is_desc},
            args.page_size,
            args.max_pages,
            args.delay,
        )
        columns = []
        lessons = []
        for idx, column in enumerate(top_columns["list"], 1):
            if args.max_columns and idx > args.max_columns:
                break
            column_id = column.get("resource_id")
            if not column_id:
                continue
            items = fetch_paged_plain(
                cdp,
                XIAOETONG_COLUMN_ITEMS_API,
                {"column_id": column_id, "isDesc": args.is_desc},
                args.item_page_size,
                args.max_item_pages,
                args.delay,
            )
            columns.append({"column": column, "item_total": items.get("total"), "items": items["list"]})
            for item_index, item in enumerate(items["list"], 1):
                lessons.append({
                    "parent_id": column_id,
                    "parent_title": column.get("resource_title"),
                    "parent_summary": column.get("summary"),
                    "item_index": item_index,
                    **item,
                })
            save_json(path, {
                "captured_at": now(),
                "source_url": args.source_url,
                "product_id": product_id,
                "top_columns": top_columns["list"],
                "singles": singles["list"],
                "member_courses": member_courses["list"],
                "columns": columns,
                "lessons": lessons,
            })
            append_jsonl(progress, "column", index=idx, title=column.get("resource_title"), lessons=len(lessons))

        for item_index, item in enumerate(singles["list"], 1):
            lessons.append({
                "parent_id": "__single__",
                "parent_title": "导读与单课",
                "parent_summary": "会员单课与导读内容",
                "item_index": item_index,
                **item,
            })

        if args.fetch_details:
            for idx, lesson in enumerate(lessons, 1):
                rid = lesson.get("resource_id")
                if not rid:
                    continue
                try:
                    detail = fetch_xiaoetong_detail_flexible(cdp, args, rid)
                    lesson.update({"detail_record": detail, "detail_error": ""})
                except Exception as exc:
                    lesson.update({"detail_error": repr(exc)})
                if idx % args.save_every == 0:
                    save_json(path, {
                        "captured_at": now(),
                        "source_url": args.source_url,
                        "product_id": product_id,
                        "top_columns": top_columns["list"],
                        "singles": singles["list"],
                        "member_courses": member_courses["list"],
                        "columns": columns,
                        "lessons": lessons,
                    })
                append_jsonl(progress, "detail", index=idx, total=len(lessons), title=lesson.get("resource_title"), error=lesson.get("detail_error", ""))
                if args.delay:
                    time.sleep(args.delay)

        output = {
            "captured_at": now(),
            "source_url": args.source_url,
            "product_id": product_id,
            "top_columns_total": top_columns.get("total"),
            "top_columns": top_columns["list"],
            "singles_total": singles.get("total"),
            "singles": singles["list"],
            "member_courses_total": member_courses.get("total"),
            "member_courses": member_courses["list"],
            "columns": columns,
            "lessons": lessons,
        }
        save_json(path, output)
        append_jsonl(progress, "done-member-tree", columns=len(columns), singles=len(singles["list"]), lessons=len(lessons))
        print(json.dumps({"out": str(path), "columns": len(columns), "singles": len(singles["list"]), "lessons": len(lessons)}, ensure_ascii=False))
    finally:
        cdp.close()


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--host-marker", default="")
    parser.add_argument("--product-id", default="")
    parser.add_argument("--task-dir", required=True)
    parser.add_argument("--raw", default="raw.json")
    parser.add_argument("--cdp-http", default=DEFAULT_CDP_HTTP)


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture paid-course/article content through an already logged-in Chrome CDP session.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("probe")
    add_common(p)
    p.add_argument("--probe-out", default="cdp-network-probe.json")
    p.add_argument("--navigate", action="store_true")
    p.add_argument("--wait", type=float, default=3.0)
    p.add_argument("--listen-seconds", type=float, default=8.0)
    p.add_argument("--scroll-rounds", type=int, default=8)

    s = sub.add_parser("sample-details")
    add_common(s)
    s.add_argument("--start-id", default="")
    s.add_argument("--max-articles", type=int, default=5)
    s.add_argument("--out", default="cdp-api-detail-sample.json")

    t = sub.add_parser("traverse")
    add_common(t)
    t.add_argument("--start-id", default="")
    t.add_argument("--direction", choices=["previous", "next"], default="previous")
    t.add_argument("--max-new", type=int, default=5)
    t.add_argument("--max-steps", type=int, default=800)
    t.add_argument("--delay", type=float, default=0.2)
    t.add_argument("--min-text-len", type=int, default=80)
    t.add_argument("--progress-log", default="cdp-api-capture-progress.jsonl")
    t.add_argument("--stop-on-error", action="store_true")

    k = sub.add_parser("capture-known-urls")
    add_common(k)
    k.add_argument("--max-articles", type=int, default=5)
    k.add_argument("--wait", type=float, default=2.0)
    k.add_argument("--min-text-len", type=int, default=500)

    n = sub.add_parser("normalize-existing")
    add_common(n)
    n.add_argument("--max-articles", type=int, default=999999)
    n.add_argument("--delay", type=float, default=0.2)
    n.add_argument("--min-text-len", type=int, default=80)
    n.add_argument("--save-every", type=int, default=20)
    n.add_argument("--stop-on-error", action="store_true")

    m = sub.add_parser("capture-member-tree")
    add_common(m)
    m.add_argument("--page-size", type=int, default=50)
    m.add_argument("--item-page-size", type=int, default=100)
    m.add_argument("--max-pages", type=int, default=20)
    m.add_argument("--max-item-pages", type=int, default=20)
    m.add_argument("--max-columns", type=int, default=0)
    m.add_argument("--is-desc", default="1")
    m.add_argument("--delay", type=float, default=0.1)
    m.add_argument("--fetch-details", action="store_true")
    m.add_argument("--save-every", type=int, default=25)
    m.add_argument("--progress-log", default="member-tree-progress.jsonl")

    args = parser.parse_args()
    Path(args.task_dir).mkdir(parents=True, exist_ok=True)
    if args.cmd == "probe":
        probe(args)
    elif args.cmd == "sample-details":
        sample_details(args)
    elif args.cmd == "traverse":
        traverse(args)
    elif args.cmd == "capture-known-urls":
        capture_known_urls(args)
    elif args.cmd == "normalize-existing":
        normalize_existing(args)
    elif args.cmd == "capture-member-tree":
        capture_member_tree(args)


if __name__ == "__main__":
    main()
