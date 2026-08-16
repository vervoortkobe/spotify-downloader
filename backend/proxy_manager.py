from __future__ import annotations


def initialize_proxies() -> tuple[int, int]:
    print("[Proxy] Proxies disabled — using direct connections", flush=True)
    return 0, 0


def next_proxy() -> str | None:
    return None


def next_requests_proxies() -> dict[str, str] | None:
    return None


def get_role_proxy(role: str) -> str | None:
    return None


def proxy_candidates(allow_direct_fallback: bool = True) -> list[str | None]:
    return [None]


def report_dead_proxy(proxy: str | None) -> None:
    pass


def build_ytdl_opts(base_opts: dict | None = None, proxy: str | None = None) -> dict:
    opts = dict(base_opts or {})
    opts.setdefault("quiet", True)
    opts.setdefault("no_warnings", True)
    return opts
