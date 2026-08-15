from __future__ import annotations

import os
import random
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable

import requests


_DEFAULT_HEALTHCHECK_URL = os.environ.get(
    "PROXY_HEALTHCHECK_URL",
    "https://www.youtube.com/robots.txt",
)

_SOURCE_CANDIDATES = (
    Path(__file__).resolve().parent / "proxies",
    Path(__file__).resolve().parent / "proxies.txt",
    Path(__file__).resolve().parent / "proxies.list",
)


def _resolve_source_path() -> Path | None:
    for candidate in _SOURCE_CANDIDATES:
        if candidate.exists():
            return candidate
    return None


def _iter_proxy_lines(text: str) -> Iterable[str]:
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        yield line


def _normalize_proxy(proxy: str) -> str:
    proxy = proxy.strip()
    if not proxy:
        return ""
    if "://" not in proxy:
        return f"http://{proxy}"
    return proxy


def _proxy_to_requests_config(proxy: str) -> dict[str, str]:
    return {"http": proxy, "https": proxy}


class ProxyManager:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._source_path = _resolve_source_path()
        self._proxies: list[str] = []
        self._cursor = 0

    @property
    def source_path(self) -> Path | None:
        return self._source_path

    def load(self) -> tuple[int, int]:
        source_path = _resolve_source_path()
        self._source_path = source_path

        if not source_path:
            with self._lock:
                self._proxies = []
                self._cursor = 0
            return 0, 0

        try:
            raw_text = source_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            raw_text = ""

        proxies = []
        for line in _iter_proxy_lines(raw_text):
            proxy = _normalize_proxy(line)
            if proxy:
                proxies.append(proxy)

        healthy = self._health_check_all(proxies)
        with self._lock:
            self._proxies = healthy
            self._cursor = 0 if not healthy else random.randrange(len(healthy))

        if healthy != proxies:
            self._persist(healthy)

        return len(healthy), len(proxies)

    def _persist(self, proxies: list[str]) -> None:
        source_path = self._source_path
        if not source_path:
            return

        try:
            source_path.write_text("\n".join(proxies) + ("\n" if proxies else ""), encoding="utf-8")
        except Exception as exc:
            print(f"[Proxy] Failed to persist proxy list: {exc}", flush=True)

    def _health_check_one(self, proxy: str) -> bool:
        try:
            response = requests.get(
                _DEFAULT_HEALTHCHECK_URL,
                proxies=_proxy_to_requests_config(proxy),
                timeout=10,
                stream=True,
                headers={"User-Agent": "Mozilla/5.0"},
            )
            try:
                return 200 <= response.status_code < 400
            finally:
                response.close()
        except Exception:
            return False

    def _health_check_all(self, proxies: list[str]) -> list[str]:
        if not proxies:
            return []

        healthy_set: set[str] = set()
        with ThreadPoolExecutor(max_workers=min(12, max(1, len(proxies)))) as executor:
            future_map = {executor.submit(self._health_check_one, proxy): proxy for proxy in proxies}
            for future in as_completed(future_map):
                proxy = future_map[future]
                try:
                    if future.result():
                        healthy_set.add(proxy)
                except Exception:
                    continue

        healthy = [proxy for proxy in proxies if proxy in healthy_set]
        random.shuffle(healthy)
        return healthy

    def get_proxy(self) -> str | None:
        with self._lock:
            if not self._proxies:
                return None
            proxy = self._proxies[self._cursor % len(self._proxies)]
            self._cursor = (self._cursor + 1) % len(self._proxies)
            return proxy

    def get_proxy_for_requests(self) -> dict[str, str] | None:
        proxy = self.get_proxy()
        return _proxy_to_requests_config(proxy) if proxy else None

    def get_proxy_for_yt_dlp(self) -> str | None:
        return self.get_proxy()

    def report_failure(self, proxy: str | None) -> None:
        if not proxy:
            return

        changed = False
        with self._lock:
            if proxy in self._proxies:
                self._proxies = [candidate for candidate in self._proxies if candidate != proxy]
                self._cursor = 0 if not self._proxies else self._cursor % len(self._proxies)
                changed = True

        if changed:
            print(f"[Proxy] Removed dead proxy: {proxy}", flush=True)
            self._persist(self.snapshot())

    def snapshot(self) -> list[str]:
        with self._lock:
            return list(self._proxies)

    def count(self) -> int:
        with self._lock:
            return len(self._proxies)


proxy_manager = ProxyManager()


def initialize_proxies() -> tuple[int, int]:
    alive, total = proxy_manager.load()
    print(f"[Proxy] Startup health check complete: {alive}/{total} proxies alive", flush=True)
    return alive, total


def next_proxy() -> str | None:
    return proxy_manager.get_proxy_for_yt_dlp()


def next_requests_proxies() -> dict[str, str] | None:
    return proxy_manager.get_proxy_for_requests()


def proxy_candidates(allow_direct_fallback: bool = False) -> list[str | None]:
    candidates = proxy_manager.snapshot()
    random.shuffle(candidates)
    if candidates:
        return candidates + ([None] if allow_direct_fallback else [])
    return [None]


def report_dead_proxy(proxy: str | None) -> None:
    proxy_manager.report_failure(proxy)


def build_ytdl_opts(base_opts: dict | None = None, proxy: str | None = None) -> dict:
    opts = dict(base_opts or {})
    selected_proxy = proxy if proxy is not None else next_proxy()
    if selected_proxy:
        opts["proxy"] = selected_proxy
    opts.setdefault("quiet", True)
    opts.setdefault("no_warnings", True)
    return opts
