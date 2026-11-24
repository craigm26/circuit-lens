#!/usr/bin/env python3
"""Family Electronics Studio Teardown Gallery for pi-nas.local:8088.

Receives POST /api/teardowns from the CircuitLens iOS app and renders a
browsable family gallery at http://pi-nas.local:8088/.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def make_handler(data_dir: Path):
    data_dir.mkdir(parents=True, exist_ok=True)

    class _Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: bytes, content_type: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self) -> None:
            if self.path != "/api/teardowns":
                self._send(404, b"Not found", "text/plain")
                return
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw.decode("utf-8"))
            ts_id = time.strftime("%Y%m%d-%H%M%S")
            img_b64 = payload.pop("imageBase64JPEG", None)
            if img_b64:
                (data_dir / f"{ts_id}.jpg").write_bytes(base64.b64decode(img_b64))
                payload["image"] = f"/img/{ts_id}.jpg"
            payload["id"] = ts_id
            payload["saved_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
            (data_dir / f"{ts_id}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
            resp = json.dumps({"ok": True, "id": ts_id, "url": f"http://pi-nas.local:8088/#{ts_id}"}).encode()
            self._send(201, resp, "application/json")

        def do_GET(self) -> None:
            if self.path.startswith("/img/"):
                fname = Path(self.path.removeprefix("/img/")).name
                p = data_dir / fname
                if p.exists() and p.suffix == ".jpg":
                    self._send(200, p.read_bytes(), "image/jpeg")
                    return
                self._send(404, b"Not found", "text/plain")
                return

            items = []
            for jf in sorted(data_dir.glob("*.json"), reverse=True):
                try:
                    items.append(json.loads(jf.read_text(encoding="utf-8")))
                except Exception:
                    continue

            cards = []
            for it in items:
                title = html.escape(str(it.get("title", "Scanned Board")))
                saved = html.escape(str(it.get("saved_at", "")))
                level = html.escape(str(it.get("level", "")))
                summ = it.get("summary") or {}
                story = html.escape(str(summ.get("wholeBoardStory", "")))
                flow = html.escape(str(summ.get("signalFlow", "")))
                comps = "".join(
                    f"<li><code>{html.escape(c.get('designator',''))}</code> — {html.escape(c.get('category',''))}</li>"
                    for c in it.get("components", [])
                )
                img_html = f'<img src="{html.escape(it["image"])}" alt="{title}" />' if it.get("image") else ""
                cards.append(
                    f'<article class="card" id="{html.escape(it.get("id",""))}">'
                    f'{img_html}<div class="meta">{saved} · {level}</div>'
                    f'<h2>{title}</h2><p>{story}</p>'
                    f'<div class="flow">{flow}</div><ul>{comps}</ul></article>'
                )

            page = f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Family Electronics Studio · pi-nas.local</title>
<style>
body {{ margin:0; background:#0b0e11; color:#e8edf2; font-family:system-ui,sans-serif; padding:24px; }}
.wrap {{ max-width:980px; margin:0 auto; }}
h1 {{ margin:0 0 6px; }} .sub {{ color:#94a3b8; margin:0 0 24px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:18px; }}
.card {{ background:#12161c; border:1px solid #26303d; border-radius:12px; padding:16px; }}
.card img {{ width:100%; border-radius:8px; margin-bottom:10px; }}
.meta {{ font-size:12px; color:#38bdf8; font-family:monospace; }}
.flow {{ font-family:monospace; font-size:12px; color:#fbbf24; margin:8px 0; }}
ul {{ padding-left:18px; color:#cbd5e1; font-size:13px; }}
</style></head>
<body><div class="wrap">
<h1>Family Electronics Studio</h1>
<p class="sub">Boards scanned with CircuitLens AR on iOS ({len(items)} saved teardowns)</p>
<div class="grid">{''.join(cards) or '<p class="sub">No teardowns saved yet — tap Save Teardown in CircuitLens!</p>'}</div>
</div></body></html>"""
            self._send(200, page.encode("utf-8"), "text/html; charset=utf-8")

    return _Handler


def main() -> int:
    ap = argparse.ArgumentParser(description="CircuitLens Family Electronics Studio gallery server.")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8088)
    ap.add_argument("--data-dir", default=str(Path.home() / "circuit-lens-teardowns"))
    args = ap.parse_args()
    srv = HTTPServer((args.host, args.port), make_handler(Path(args.data_dir)))
    print(f"Family Electronics Studio listening on http://{args.host}:{args.port}")
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
