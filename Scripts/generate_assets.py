#!/usr/bin/env python3
"""Temporary Dear Us image harness.

gpt-image-2 via https://api.shu.cool/v1
Rate limit: 5 calls/minute, 3 concurrent.
Auth: SHU_API_KEY from the environment. Never print it.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from asset_catalog import (  # noqa: E402
    MANIFEST_PATH,
    MODEL,
    compose_prompt,
    manifest_document,
)

BASE_URL = os.environ.get("SHU_BASE_URL", "https://api.shu.cool/v1").rstrip("/")
OUT_DIR = ROOT / "DesignAssets" / "generated"
WORK_DIR = ROOT / "DesignAssets" / "work"
STATE_PATH = WORK_DIR / "state.json"
DEFAULT_PER_MINUTE = 5
DEFAULT_CONCURRENCY = 3
HTTP_TIMEOUT = 300
MAX_RETRIES = 3


class RateLimiter:
    def __init__(self, per_minute: int, concurrency: int) -> None:
        self.per_minute = per_minute
        self.sema = threading.Semaphore(concurrency)
        self.lock = threading.Lock()
        self.times: deque[float] = deque()

    def acquire(self) -> None:
        self.sema.acquire()
        while True:
            with self.lock:
                now = time.monotonic()
                while self.times and now - self.times[0] >= 60:
                    self.times.popleft()
                if len(self.times) < self.per_minute:
                    self.times.append(now)
                    return
                wait = 60 - (now - self.times[0]) + 0.08
            time.sleep(max(wait, 0.05))

    def release(self) -> None:
        self.sema.release()


def die(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def api_key() -> str:
    key = (os.environ.get("SHU_API_KEY") or "").strip()
    if not key:
        die("缺少 SHU_API_KEY")
    return key


def load_catalog() -> dict:
    doc = manifest_document()
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    return doc


def by_id(doc: dict) -> dict[str, dict]:
    return {e["id"]: e for e in doc["entries"]}


def png_path(entry: dict) -> Path:
    return OUT_DIR / entry["group"] / f"{entry['id']}.png"


def meta_path(entry: dict) -> Path:
    return OUT_DIR / entry["group"] / f"{entry['id']}.json"


def load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {"runs": [], "assets": {}}


def save_state(state: dict) -> None:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n")


def topo_sort(entries: list[dict], index: dict[str, dict]) -> list[dict]:
    seen: set[str] = set()
    ordered: list[dict] = []

    def visit(item: dict) -> None:
        if item["id"] in seen:
            return
        seen.add(item["id"])
        for dep in item.get("depends_on") or []:
            if dep in index:
                visit(index[dep])
        ordered.append(item)

    for item in entries:
        visit(item)
    return ordered


def read_png(path: Path) -> bytes:
    data = path.read_bytes()
    if not data:
        die(f"空文件: {path}")
    return data


def post_json(url: str, payload: dict, key: str) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {exc.code} {exc.reason}: {detail[:2000]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"请求失败: {exc.reason}") from exc
    if status != 200:
        raise RuntimeError(f"HTTP {status}: {raw[:500]!r}")
    return json.loads(raw)


def encode_multipart(fields: dict[str, str], files: list[tuple[str, str, bytes]]) -> tuple[bytes, str]:
    boundary = f"----dearUs{int(time.time() * 1000)}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        chunks.append(value.encode() + b"\r\n")
    for field, filename, blob in files:
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(
            f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'.encode()
        )
        chunks.append(b"Content-Type: image/png\r\n\r\n")
        chunks.append(blob + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def post_multipart(url: str, fields: dict[str, str], files: list[tuple[str, str, bytes]], key: str) -> dict:
    body, content_type = encode_multipart(fields, files)
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": content_type,
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {exc.code} {exc.reason}: {detail[:2000]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"请求失败: {exc.reason}") from exc
    if status != 200:
        raise RuntimeError(f"HTTP {status}: {raw[:500]!r}")
    return json.loads(raw)


def decode_image(data: dict) -> bytes:
    items = data.get("data") or []
    if not items:
        raise RuntimeError(f"响应没有图片: {list(data.keys())}")
    item = items[0]
    if item.get("b64_json"):
        return base64.b64decode(item["b64_json"])
    if item.get("url"):
        with urllib.request.urlopen(item["url"], timeout=120) as resp:
            return resp.read()
    raise RuntimeError(f"图片缺少 b64_json/url: {list(item.keys())}")


def generate_payload(entry: dict, prompt: str, quality: str) -> dict:
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "size": entry["canvas"],
        "quality": quality,
        "output_format": "png",
        "background": "transparent" if entry["alpha"] else "opaque",
        "moderation": "low",
        "n": 1,
    }
    return payload


def call_generate(entry: dict, prompt: str, quality: str, key: str) -> dict:
    return post_json(f"{BASE_URL}/images/generations", generate_payload(entry, prompt, quality), key)


def call_edit(entry: dict, prompt: str, quality: str, key: str, index: dict[str, dict]) -> dict:
    images_b64 = []
    files = []
    for ref_id in entry["reference"]:
        ref = index[ref_id]
        path = png_path(ref)
        if not path.exists():
            raise RuntimeError(f"{entry['id']} 需要参考图 {ref_id}，但 {path} 不存在")
        blob = read_png(path)
        images_b64.append({"image_url": f"data:image/png;base64,{base64.b64encode(blob).decode('ascii')}"})
        files.append(("image[]", f"{ref_id}.png", blob))

    json_payload = generate_payload(entry, prompt, quality)
    json_payload["images"] = images_b64
    json_payload["input_fidelity"] = "high"
    try:
        return post_json(f"{BASE_URL}/images/edits", json_payload, key)
    except RuntimeError as exc:
        message = str(exc)
        if "HTTP 4" not in message and "HTTP 5" not in message:
            raise
        fields = {
            "model": MODEL,
            "prompt": prompt,
            "size": entry["canvas"],
            "quality": quality,
            "output_format": "png",
            "background": "transparent" if entry["alpha"] else "opaque",
            "moderation": "low",
            "input_fidelity": "high",
            "n": "1",
        }
        return post_multipart(f"{BASE_URL}/images/edits", fields, files, key)


def copy_reuse(entry: dict, index: dict[str, dict]) -> Path:
    src_id = entry["reuse"]
    src = index[src_id]
    src_path = png_path(src)
    if not src_path.exists():
        raise RuntimeError(f"{entry['id']} reuse {src_id}，但 {src_path} 不存在")
    dest = png_path(entry)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(src_path.read_bytes())
    meta_path(entry).write_text(
        json.dumps(
            {
                "id": entry["id"],
                "reuse": src_id,
                "copied_from": str(src_path.relative_to(ROOT)),
                "copied_at": datetime.now(timezone.utc).isoformat(),
            },
            indent=2,
        )
        + "\n"
    )
    return dest


def should_skip(entry: dict, force: bool) -> bool:
    return png_path(entry).exists() and not force


def record(state: dict, entry: dict, status: str, **extra: object) -> None:
    row = {
        "id": entry["id"],
        "status": status,
        "path": str(png_path(entry).relative_to(ROOT)),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    row.update(extra)
    state.setdefault("assets", {})[entry["id"]] = row


def run_one(
    entry: dict,
    index: dict[str, dict],
    quality: str,
    key: str,
    limiter: RateLimiter,
    force: bool,
    dry_run: bool,
    state: dict,
    state_lock: threading.Lock,
) -> str:
    dest = png_path(entry)
    if should_skip(entry, force):
        return f"skip {entry['id']}"
    if entry["mode"] == "copy":
        if dry_run:
            return f"dry-run copy {entry['id']} <- {entry['reuse']}"
        copy_reuse(entry, index)
        with state_lock:
            record(state, entry, "copied", reuse=entry["reuse"])
            save_state(state)
        return f"copy {entry['id']}"

    prompt = compose_prompt(entry)
    if dry_run:
        refs = ",".join(entry["reference"]) or "-"
        return f"dry-run {entry['mode']} {entry['id']} refs={refs} size={entry['canvas']} alpha={entry['alpha']}"

    last_error = None
    for attempt in range(1, MAX_RETRIES + 1):
        limiter.acquire()
        started = time.monotonic()
        try:
            if entry["mode"] == "edit":
                data = call_edit(entry, prompt, quality, key, index)
            else:
                data = call_generate(entry, prompt, quality, key)
            blob = decode_image(data)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(blob)
            sidecar = {
                "id": entry["id"],
                "model": data.get("model") or MODEL,
                "size": data.get("size") or entry["canvas"],
                "quality": data.get("quality") or quality,
                "background": data.get("background"),
                "usage": data.get("usage"),
                "seconds": round(time.monotonic() - started, 2),
                "attempt": attempt,
                "prompt": prompt,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            meta_path(entry).write_text(json.dumps(sidecar, indent=2, ensure_ascii=False) + "\n")
            with state_lock:
                record(state, entry, "ok", usage=data.get("usage"), seconds=sidecar["seconds"])
                save_state(state)
            return f"ok {entry['id']} {dest.relative_to(ROOT)} {sidecar['seconds']}s"
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            wait = min(8 * attempt, 24)
            print(f"fail {entry['id']} attempt {attempt}: {exc}", file=sys.stderr)
            if attempt < MAX_RETRIES:
                time.sleep(wait)
        finally:
            limiter.release()

    with state_lock:
        record(state, entry, "error", error=str(last_error)[:1000])
        save_state(state)
    return f"error {entry['id']}: {last_error}"


def select_entries(doc: dict, args: argparse.Namespace) -> list[dict]:
    index = by_id(doc)
    entries = list(doc["entries"])
    if args.id:
        missing = [i for i in args.id if i not in index]
        if missing:
            die("未知 id: " + ", ".join(missing))
        entries = [index[i] for i in args.id]
    elif args.group:
        entries = [e for e in entries if e["group"] in args.group]
    elif args.stage:
        entries = [e for e in entries if e["stage"] == args.stage]
    elif args.pending:
        entries = [e for e in entries if not png_path(e).exists()]
    else:
        entries = [e for e in entries if e["stage"] == "lock"]

    if args.runtime_only:
        entries = [e for e in entries if e["runtime"]]
    if args.limit is not None:
        entries = entries[: args.limit]
    return topo_sort(entries, index)


def cmd_status(doc: dict) -> int:
    runtime = [e for e in doc["entries"] if e["runtime"]]
    print(f"runtime {len(runtime)} / lock {len(doc['entries']) - len(runtime)}")
    for group, expected in doc["groups"].items():
        have = sum(1 for e in runtime if e["group"] == group)
        done = sum(1 for e in runtime if e["group"] == group and png_path(e).exists())
        print(f"  {group:12} {have:3}/{expected:<3} generated {done}")
    lock_done = sum(1 for e in doc["entries"] if e["stage"] == "lock" and png_path(e).exists())
    lock_total = sum(1 for e in doc["entries"] if e["stage"] == "lock")
    print(f"lock stage {lock_done}/{lock_total}")
    return 0


def cmd_prompt(doc: dict, asset_id: str) -> int:
    index = by_id(doc)
    if asset_id not in index:
        die(f"未知 id: {asset_id}")
    print(compose_prompt(index[asset_id]))
    return 0


def cmd_generate(doc: dict, args: argparse.Namespace) -> int:
    if args.stage == "production" and not args.yes:
        die("production 需要 --yes，且应先锁定母版")

    index = by_id(doc)
    selected = select_entries(doc, args)
    if not selected:
        print("没有匹配的条目")
        return 0

    if args.stage == "production" or args.yes:
        master = png_path(index["env_room_master"])
        if not master.exists() and not args.dry_run:
            die("还没有 env_room_master，先跑 --stage lock")

    limiter = RateLimiter(args.per_minute, args.concurrency)
    key = "" if args.dry_run else api_key()
    state = load_state()
    state_lock = threading.Lock()
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(
        f"{len(selected)} entries · model {MODEL} · quality {args.quality} · "
        f"{args.per_minute}/min · conc {args.concurrency}"
        + (" · dry-run" if args.dry_run else "")
    )

    # Keep dependency order: run in waves so a worker never starts before deps exist.
    remaining = list(selected)
    failures = 0
    while remaining:
        ready: list[dict] = []
        blocked: list[dict] = []
        done_ids = {e["id"] for e in selected if png_path(e).exists()} | {
            e["id"] for e in remaining if False
        }
        generated_now = set()
        for entry in remaining:
            deps = entry.get("depends_on") or []
            ok = True
            for dep in deps:
                if args.dry_run:
                    continue
                if dep not in index:
                    continue
                if not png_path(index[dep]).exists() and dep not in generated_now:
                    ok = False
                    break
            if ok:
                ready.append(entry)
            else:
                blocked.append(entry)

        if not ready:
            missing = []
            for entry in blocked:
                for dep in entry.get("depends_on") or []:
                    if dep in index and not png_path(index[dep]).exists():
                        missing.append(f"{entry['id']} <- {dep}")
            die("依赖未生成:\n  " + "\n  ".join(missing[:20]))

        wave = ready
        remaining = blocked
        with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futs = [
                pool.submit(
                    run_one,
                    entry,
                    index,
                    args.quality,
                    key,
                    limiter,
                    args.force,
                    args.dry_run,
                    state,
                    state_lock,
                )
                for entry in wave
            ]
            for fut in as_completed(futs):
                line = fut.result()
                print(line)
                if line.startswith("error"):
                    failures += 1
                elif line.startswith("ok ") or line.startswith("copy "):
                    generated_now.add(line.split()[1])

    return 1 if failures else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Dear Us gpt-image-2 harness")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("dump-manifest", help="写出 asset_manifest.json")
    sub.add_parser("status", help="条目与生成进度")

    p_prompt = sub.add_parser("prompt", help="打印合成提示词")
    p_prompt.add_argument("id")

    p_gen = sub.add_parser("generate", help="按限流生成")
    p_gen.add_argument("--stage", choices=["lock", "production"])
    p_gen.add_argument("--group", action="append")
    p_gen.add_argument("--id", action="append")
    p_gen.add_argument("--pending", action="store_true")
    p_gen.add_argument("--runtime-only", action="store_true")
    p_gen.add_argument("--limit", type=int)
    p_gen.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    p_gen.add_argument("--per-minute", dest="per_minute", type=int, default=DEFAULT_PER_MINUTE)
    p_gen.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY)
    p_gen.add_argument("--force", action="store_true")
    p_gen.add_argument("--dry-run", action="store_true")
    p_gen.add_argument("--yes", action="store_true", help="确认生产阶段")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.concurrency < 1 or args.concurrency > 3:
        die("并发必须是 1–3")
    if args.command == "generate" and (args.per_minute < 1 or args.per_minute > 5):
        die("每分钟调用必须是 1–5")

    doc = load_catalog()
    if args.command == "dump-manifest":
        print(f"wrote {MANIFEST_PATH}")
        return 0
    if args.command == "status":
        return cmd_status(doc)
    if args.command == "prompt":
        return cmd_prompt(doc, args.id)
    if args.command == "generate":
        return cmd_generate(doc, args)
    die(f"未知命令 {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
