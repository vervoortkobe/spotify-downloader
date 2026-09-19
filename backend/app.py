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


def _warp_status_message() -> str:
    import socket as _s
    proxy = os.environ.get("ALL_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY") or ""
    sock_ok = False
    try:
        s = _s.socket(); s.settimeout(2); s.connect(("127.0.0.1", 4000)); s.close(); sock_ok = True
    except Exception:
        pass
    cli_ok = _warp_cli_connected()
    if cli_ok and sock_ok and proxy:
        return f"Connected (proxy mode via {proxy} on 127.0.0.1:4000 - WARP tunnel active)"
    elif cli_ok and not sock_ok and proxy:
        return f"Connected (tunnel mode - WARP daemon Connected, proxy env {proxy} but socket not listening - egress still via WARP)"
    elif cli_ok and not sock_ok and not proxy:
        return "Connected (tunnel mode - WARP daemon Connected, no proxy needed - host egress is via WARP)"
    elif cli_ok and sock_ok and not proxy:
        return "Connected (tunnel+proxy socket ok, traffic via WARP)"
    elif proxy and sock_ok:
        return f"Connected (proxy socket ok via {proxy}, cli not confirming)"
    elif proxy and not sock_ok:
        return f"Degraded - env {proxy} but socket down and cli not connected"
    else:
        return "Disconnected - no WARP cli, no proxy env/socket (direct egress)"


def _log_warp_startup():
    print(f"[WARP Proxy] {_warp_status_message()}", flush=True)


def create_app():
    app = Flask(__name__)

    frontend_urls = os.environ.get(
        "FRONTEND_URL",
        "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001,http://192.168.1.5:3000,http://192.168.1.5:3001",
    )
    allowed_origins = [url.strip() for url in frontend_urls.split(",") if url.strip()]
    CORS(app, origins=allowed_origins, allow_headers=["Content-Type", "Authorization", "X-Spotterfy-Key", "X-App-Token", "X-Admin-Token"])

    # --- Rate limiting + App-key header (only your apps) ---
    import time as _time
    import threading as _rl_th
    from flask import request as _req, jsonify as _jsonify, g as _g
    # In-memory sliding window: { (ip, endpoint_key): [timestamps] }
    _rl_store: dict[tuple[str, str], list[float]] = {}
    _rl_lock = _rl_th.Lock()
    # Limits per endpoint (requests / 60s) tuned for WARP/Spotify
    # NOTE: order matters - _endpoint_key uses first substring match, so keep
    # "scrape-progress" before "progress" (the latter is a substring of the former).
    # Progress endpoints are cheap in-memory reads polled every 500ms by the
    # frontend/mobile during fetches, so they get generous buckets.
    _RL_LIMITS: dict[str, int] = {
        "scrape-playlist": 6,          # heavy Spotify+YT
        "scrape-user-playlists": 8,
        "scrape-progress": 300,        # cheap poll (500ms) during playlist fetch
        "scrape-result": 120,          # cheap, fetched once per completed job
        "progress": 300,               # cheap polls: /api/progress/<id> + /api/progress/all
        "download-track": 20,
        "download-playlist-zip": 6,
        "stream": 30,
        "stream-track": 30,
        "default": 60,
    }
    # Exempt from key/rate
    _EXEMPT_PATHS = {"/api/health", "/api/warp-status", "/", "/api/refresh-discover"}

    def _client_ip() -> str:
        xf = _req.headers.get("X-Forwarded-For", "")
        if xf:
            return xf.split(",")[0].strip()
        return _req.remote_addr or "unknown"

    def _endpoint_key(path: str) -> str:
        p = path.lower()
        for k in _RL_LIMITS:
            if k in p:
                return k
        return "default"

    @app.before_request
    def _check_app_key_and_rate_limit():
        path = _req.path or ""
        # Only protect /api/* and not exempt
        if not path.startswith("/api/"):
            return None
        if any(path == e or path.startswith(e + "/") or path.startswith(e + "?") for e in _EXEMPT_PATHS):
            # /api/refresh-discover has its own REFRESH_TOKEN check, skip app-key
            if path.startswith("/api/refresh-discover"):
                return None
            # health/warp still exempt from key but still rate-limited lightly
            if path in ("/api/health", "/api/warp-status"):
                pass
            else:
                # exempt paths bypass
                if path in _EXEMPT_PATHS:
                    return None
        # 1) Mandatory app header if SPOTTERFY_API_KEY is set
        # Stream endpoints are exempt from header (audioplayers UrlSource can't set custom header) but still rate-limited
        _HEADER_EXEMPT = {"/api/health", "/api/warp-status", "/", "/api/stream", "/api/stream-track"}
        required_key = os.environ.get("SPOTTERFY_API_KEY") or os.environ.get("APP_API_KEY") or os.environ.get("API_KEY")
        if required_key:
            got = _req.headers.get("X-Spotterfy-Key") or _req.headers.get("X-App-Token") or ""
            is_header_exempt = any(path == e or path.startswith(e + "?") or path.startswith(e + "/") for e in _HEADER_EXEMPT)
            if not is_header_exempt:
                if got != required_key:
                    return _jsonify({"error": "missing or invalid X-Spotterfy-Key"}), 401
        # 2) Rate limiting (sliding window 60s)
        # Allow disabling via RATE_LIMIT_DISABLE=1
        if os.environ.get("RATE_LIMIT_DISABLE") == "1":
            return None
        ip = _client_ip()
        key = _endpoint_key(path)
        limit = _RL_LIMITS.get(key, _RL_LIMITS["default"])
        now = _time.time()
        window = 60.0
        bucket = (ip, key)
        with _rl_lock:
            lst = _rl_store.get(bucket, [])
            # prune
            lst = [t for t in lst if now - t < window]
            if len(lst) >= limit:
                retry = int(window - (now - lst[0])) + 1
                return _jsonify({"error": "rate_limited", "retry_after": retry, "limit": limit, "window": "60s"}), 429, {"Retry-After": str(retry)}
            lst.append(now)
            _rl_store[bucket] = lst
        # add rate headers
        _g._rl_remaining = limit - len(lst)
        return None

    @app.after_request
    def _add_rate_headers(resp):
        try:
            if hasattr(_g, "_rl_remaining"):
                resp.headers["X-RateLimit-Remaining"] = str(_g._rl_remaining)
        except Exception:
            pass
        return resp

    from routes import routes
    app.register_blueprint(routes)

    _log_warp_startup()
    import threading as _th
    def _warp_heartbeat():
        import time as _t
        last = None
        while True:
            _t.sleep(60)
            # Only log on state change instead of every minute
            msg = _warp_status_message()
            if msg != last:
                print(f"[WARP Proxy] {msg}", flush=True)
                last = msg
    _th.Thread(target=_warp_heartbeat, daemon=True).start()

    # Daily discover refresh directly in backend (no GitHub workflow needed)
    if os.environ.get("DISCOVER_REFRESH_DISABLE") != "1":
        def _discover_scheduler():
            import time as _t
            import datetime as _dt
            # wait a bit for Flask to be ready, then do initial warm if needed
            _t.sleep(10)
            while True:
                try:
                    from discover_refresh import refresh_all_discover
                    # Run once on startup if discoverCache empty/stale (best-effort)
                    print("[DiscoverScheduler] Running daily refresh...", flush=True)
                    refresh_all_discover()
                except Exception as e:
                    print(f"[DiscoverScheduler] refresh failed: {e}", flush=True)
                # sleep until next 04:00 UTC
                try:
                    now = _dt.datetime.utcnow()
                    nxt = now.replace(hour=0, minute=0, second=0, microsecond=0)
                    if nxt <= now:
                        nxt += _dt.timedelta(days=1)
                    secs = (nxt - now).total_seconds()
                    print(f"[DiscoverScheduler] next run at {nxt.isoformat()}Z in {int(secs)}s", flush=True)
                    _t.sleep(secs)
                except Exception:
                    _t.sleep(24 * 3600)
        _th.Thread(target=_discover_scheduler, daemon=True).start()
        print("[DiscoverScheduler] enabled (daily 00:00 UTC, disable with DISCOVER_REFRESH_DISABLE=1)", flush=True)

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
