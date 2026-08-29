from __future__ import annotations

import os
import sys
from pathlib import Path

from flask import Flask
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).resolve().parent.parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _warp_cli_connected() -> bool:
    import subprocess as _sp
    for cmd in (["warp-cli", "--accept-tos", "status"], ["warp-cli", "status"]):
        try:
            r = _sp.run(cmd, capture_output=True, text=True, timeout=2)
            txt = (r.stdout or "") + (r.stderr or "")
            if "connected" in txt.lower():
                return True
        except Exception:
            continue
    return False


def _log_warp_startup():
    import socket as _s
    proxy = os.environ.get("ALL_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY") or ""
    sock_ok = False
    try:
        s = _s.socket(); s.settimeout(2); s.connect(("127.0.0.1", 4000)); s.close(); sock_ok = True
    except Exception:
        pass
    cli_ok = _warp_cli_connected()
    if cli_ok and sock_ok and proxy:
        print(f"[WARP Proxy] Connected (proxy mode via {proxy} on 127.0.0.1:4000 - WARP tunnel active)", flush=True)
    elif cli_ok and not sock_ok and proxy:
        print(f"[WARP Proxy] Connected (tunnel mode - WARP daemon Connected, proxy env {proxy} but socket not listening - egress still via WARP)", flush=True)
    elif cli_ok and not sock_ok and not proxy:
        print("[WARP Proxy] Connected (tunnel mode - WARP daemon Connected, no proxy needed - host egress is via WARP)", flush=True)
    elif cli_ok and sock_ok and not proxy:
        print("[WARP Proxy] Connected (tunnel+proxy socket ok, traffic via WARP)", flush=True)
    elif proxy and sock_ok:
        print(f"[WARP Proxy] Connected (proxy socket ok via {proxy}, cli not confirming)", flush=True)
    elif proxy and not sock_ok:
        print(f"[WARP Proxy] Degraded - env {proxy} but socket down and cli not connected", flush=True)
    else:
        print("[WARP Proxy] Disconnected - no WARP cli, no proxy env/socket (direct egress)", flush=True)


def create_app():
    app = Flask(__name__)

    frontend_urls = os.environ.get(
        "FRONTEND_URL",
        "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001,http://192.168.1.5:3000,http://192.168.1.5:3001",
    )
    allowed_origins = [url.strip() for url in frontend_urls.split(",") if url.strip()]
    CORS(app, origins=allowed_origins)

    from routes import routes
    app.register_blueprint(routes)

    _log_warp_startup()
    import threading as _th
    def _warp_heartbeat():
        import time as _t
        while True:
            _t.sleep(60)
            _log_warp_startup()
    _th.Thread(target=_warp_heartbeat, daemon=True).start()

    return app


app = create_app()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    try:
        from waitress import serve
        threads = int(os.environ.get("WAITRESS_THREADS", "8"))
        print(f"[Server] Starting production server (waitress) on 0.0.0.0:{port} with {threads} threads", flush=True)
        serve(app, host="0.0.0.0", port=port, threads=threads)
    except ImportError:
        print("[Server] waitress not installed, falling back to Flask dev server", flush=True)
        app.run(host="0.0.0.0", port=port, debug=False)
