from __future__ import annotations

import os
import re
import threading
import time
import urllib.request

import requests
from yt_dlp import YoutubeDL
from mutagen.easyid3 import EasyID3
from mutagen.id3 import APIC, ID3
from mutagen.mp3 import MP3
from flask import Response, stream_with_context

from audio_client import PlaylistClient
from config import progress_store, scrape_job_progress, CANCELLED_TRACKS, CANCELLED_PLAYLIST_JOBS, _playlist_client


def _get_proxy_url() -> str | None:
    return os.environ.get("ALL_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY") or os.environ.get("all_proxy") or os.environ.get("https_proxy") or os.environ.get("http_proxy")


def _get_proxy_for_requests() -> dict[str, str] | None:
    proxy_url = _get_proxy_url()
    if not proxy_url:
        return None
    if proxy_url.startswith("http://127.0.0.1:4000") or proxy_url.startswith("http://localhost:4000"):
        socks_url = proxy_url.replace("http://", "socks5://")
        return {"http": socks_url, "https": socks_url}
    return {"http": proxy_url, "https": proxy_url}


def _get_proxy_for_ytdlp() -> str | None:
    url = _get_proxy_url()
    if url and (url.startswith("http://127.0.0.1:4000") or url.startswith("http://localhost:4000")):
        return url.replace("http://", "socks5://")
    return url


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


def _log_warp_context(action: str):
    proxy = _get_proxy_url()
    import socket as _s
    sock_ok = False
    try:
        s = _s.socket(); s.settimeout(1); s.connect(("127.0.0.1", 4000)); s.close(); sock_ok = True
    except Exception:
        pass
    cli_ok = _warp_cli_connected()
    if cli_ok and sock_ok and proxy:
        print(f"[WARP Proxy] {action} - Connected (proxy mode via {proxy})", flush=True)
    elif cli_ok and sock_ok and not proxy:
        print(f"[WARP Proxy] {action} - Connected (tunnel mode, proxy socket ok but no env - traffic via WARP)", flush=True)
    elif cli_ok and not sock_ok:
        print(f"[WARP Proxy] {action} - Connected (tunnel mode via WARP daemon - direct egress is already through WARP)", flush=True)
    elif proxy and sock_ok:
        print(f"[WARP Proxy] {action} - Connected via {proxy} (proxy socket ok, cli not confirming)", flush=True)
    elif proxy and not sock_ok:
        print(f"[WARP Proxy] {action} - Degraded (env {proxy} but socket down)", flush=True)
    else:
        print(f"[WARP Proxy] {action} - Disconnected (direct mode, no WARP cli/daemon)", flush=True)

# YouTube search result cache: avoids re-searching the same track
_YT_CACHE: dict[str, tuple[str, str, float]] = {}
_YT_CACHE_LOCK = threading.Lock()
_YT_CACHE_TTL = 3600 * 6

_AUDIO_URL_CACHE: dict[str, tuple[str, str, dict, float]] = {}
_AUDIO_CACHE_LOCK = threading.Lock()
_AUDIO_CACHE_TTL = 600

def _audio_cache_get(source: str) -> tuple[str, str, dict] | None:
    with _AUDIO_CACHE_LOCK:
        e = _AUDIO_URL_CACHE.get(source)
        if e and (time.time() - e[3]) < _AUDIO_CACHE_TTL:
            return e[0], e[1], e[2]
    return None

def _audio_cache_set(source: str, audio_url: str, content_type: str, headers: dict):
    with _AUDIO_CACHE_LOCK:
        _AUDIO_URL_CACHE[source] = (audio_url, content_type, headers, time.time())
        if len(_AUDIO_URL_CACHE) > 500:
            cutoff = time.time() - _AUDIO_CACHE_TTL
            stale = [k for k, v in list(_AUDIO_URL_CACHE.items()) if v[3] < cutoff]
            for k in stale:
                del _AUDIO_URL_CACHE[k]


def _yt_cache_key(title: str, artists: str) -> str:
    return f"{title.strip().lower()}|{artists.strip().lower()}"


def _yt_cache_get(title: str, artists: str) -> tuple[str, str] | None:
    key = _yt_cache_key(title, artists)
    with _YT_CACHE_LOCK:
        entry = _YT_CACHE.get(key)
        if entry and (time.time() - entry[2]) < _YT_CACHE_TTL:
            return entry[0], entry[1]
    return None


def _yt_cache_set(title: str, artists: str, thumbnail: str, video_url: str) -> None:
    key = _yt_cache_key(title, artists)
    with _YT_CACHE_LOCK:
        _YT_CACHE[key] = (thumbnail, video_url, time.time())
        if len(_YT_CACHE) > 2000:
            cutoff = time.time() - _YT_CACHE_TTL
            stale = [k for k, v in _YT_CACHE.items() if v[2] < cutoff]
            for k in stale:
                del _YT_CACHE[k]


def _youtube_extractor_args():
    return {
        "youtube": {
            "player_client": ["web", "web_embedded"],
            "formats": ["missing_pot"],
        }
    }


class _QuietYTDLPLogger:
    def debug(self, *args, **kwargs):
        pass

    def info(self, *args, **kwargs):
        pass

    def warning(self, *args, **kwargs):
        pass

    def error(self, *args, **kwargs):
        pass


def _clean_ytdlp_error(exc: Exception) -> str:
    message = str(exc)
    lowered = message.lower()
    if "sign in to confirm you're not a bot" in lowered or "sign in to confirm you\u2019re not a bot" in lowered:
        return "YouTube blocked anonymous access for this video."
    if "http error 429" in lowered or "too many requests" in lowered:
        return "YouTube rate-limited the request."
    if "requested format is not available" in lowered:
        return "No streamable audio format is available for this video."
    if "only images are available for download" in lowered:
        return "YouTube only exposed image data for this video."
    return message


def _best_thumbnail_url(thumbnails, fallback=""):
    if not isinstance(thumbnails, list):
        return fallback or ""

    best_url = ""
    best_score = -1

    for thumb in thumbnails:
        if not isinstance(thumb, dict):
            continue
        url = thumb.get("url", "")
        if not url:
            continue
        width = thumb.get("width") or 0
        height = thumb.get("height") or 0
        try:
            score = int(width) * int(height)
        except (TypeError, ValueError):
            score = 0
        if score >= best_score:
            best_score = score
            best_url = url

    return best_url or fallback or ""


def _run_ytdl_once(source, base_opts, download=False):
    ydl_opts = dict(base_opts)
    ydl_opts["quiet"] = True
    ydl_opts["no_warnings"] = True
    ydl_opts["logger"] = _QuietYTDLPLogger()
    with YoutubeDL(ydl_opts) as ydl:
        return ydl.extract_info(source, download=download)


def extract_info(source, base_opts, download=False):
    try:
        return _run_ytdl_once(source, base_opts, download=download)
    except Exception as exc:
        raise RuntimeError(_clean_ytdlp_error(exc))


def extract_info_with_tracking(source, base_opts, download=False):
    """Extract info and return (info, None) for interface compatibility."""
    return _run_ytdl_once(source, base_opts, download=download), None


def http_get(url, **kwargs):
    kwargs.setdefault("proxies", _get_proxy_for_requests())
    return requests.get(url, **kwargs)


def get_yt_info(track_title, artists):
    cached = _yt_cache_get(track_title, artists)
    if cached:
        return cached
    try:
        _log_warp_context("get_yt_info")
        search_query = f"ytsearch1:{track_title} {artists} audio"
        proxy_url = _get_proxy_for_ytdlp()
        base_opts = {
            "quiet": True,
            "noplaylist": True,
            "skip_download": True,
            "extractor_args": _youtube_extractor_args(),
            "remote_components": ["ejs:github"],
        }
        if proxy_url:
            base_opts["proxy"] = proxy_url
        info = extract_info(search_query, base_opts, download=False)
        if 'entries' in info and info['entries']:
            info = info['entries'][0]

        video_id = info.get('id', '')
        video_url = f"https://www.youtube.com/watch?v={video_id}" if video_id else ""

        thumbnail = _best_thumbnail_url(info.get("thumbnails", []), info.get("thumbnail") or "")

        _yt_cache_set(track_title, artists, thumbnail, video_url)
        return thumbnail, video_url
    except Exception as e:
        print(f"YT info fetch failed for {track_title}: {e}")
        return "", ""


def detect_url_service(url):
    url = url.strip()

    m = re.search(r'open\.spotify\.com/(track|playlist)/([a-zA-Z0-9]+)', url)
    if m:
        return 'spotify', m.group(1), m.group(2)

    m = re.search(r'(?:youtube\.com/watch\?.*v=|youtu\.be/|music\.youtube\.com/watch\?.*v=|youtube\.com/shorts/)([a-zA-Z0-9_-]{11})', url)
    if m:
        return 'youtube', 'track', m.group(1)

    m = re.search(r'(?:youtube\.com|music\.youtube\.com)/playlist\?.*list=([a-zA-Z0-9_-]+)', url)
    if m:
        return 'youtube', 'playlist', m.group(1)

    m = re.search(r'soundcloud\.com/([a-zA-Z0-9_-]+)/sets/', url)
    if m:
        return 'soundcloud', 'playlist', url

    m = re.search(r'soundcloud\.com/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)', url)
    if m:
        return 'soundcloud', 'track', url

    return None, None, None


def scrape_external_data(url, service, url_type, progress_job_id=None):
    is_flat = url_type == "playlist"
    proxy_url = _get_proxy_for_ytdlp()
    base_opts = {
        "quiet": True,
        "skip_download": True,
        "extract_flat": is_flat,
        "extractor_args": _youtube_extractor_args(),
        "remote_components": ["ejs:github"],
        "cachedir": False,
    }
    if proxy_url:
        base_opts["proxy"] = proxy_url
    info = extract_info(url, base_opts, download=False)

    if not info:
        raise ValueError(f"Could not fetch data from {url}")

    if url_type == "playlist":
        entries = info.get("entries", [])
        if progress_job_id:
            scrape_job_progress[progress_job_id] = {'total': len(entries), 'completed': 0, 'status': 'scraping'}
        tracks = []
        for i, entry in enumerate(entries):
            if not entry:
                continue
            vid = entry.get("id", "")
            entry_url = entry.get("url") or entry.get("webpage_url") or ""
            if not entry_url and vid:
                if service == "youtube":
                    entry_url = f"https://www.youtube.com/watch?v={vid}"
                elif service == "soundcloud":
                    uploader = entry.get("uploader_id") or entry.get("channel_id") or ""
                    slug = entry.get("title", "").lower().replace(" ", "-") if entry.get("title") else ""
                    if uploader and slug:
                        entry_url = f"https://soundcloud.com/{uploader}/{slug}"

            thumbnail = _best_thumbnail_url(entry.get("thumbnails", []), entry.get("thumbnail", ""))
            if not thumbnail and service == "youtube" and vid:
                thumbnail = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
            if not thumbnail and service == "soundcloud":
                thumbnails = entry.get("thumbnails", [])
                if thumbnails:
                    thumbnail = thumbnails[-1].get("url", "")

            tracks.append({
                "id": vid or entry_url,
                "title": entry.get("title", "Unknown Track"),
                "artists": entry.get("channel") or entry.get("uploader") or "",
                "album": "",
                "cover": thumbnail,
                "releaseDate": "",
                "downloadLink": "",
                "sourceUrl": entry_url,
            })
            if progress_job_id and (i % 5 == 0 or i == len(entries) - 1):
                p = scrape_job_progress.get(progress_job_id)
                if p:
                    p['completed'] = len(tracks)
                    print(
                        f"[Scrape] Job {progress_job_id} progress: {p['completed']}/{p.get('total', len(entries))} tracks scraped",
                        flush=True,
                    )
        playlist_name = info.get("title", f"{service.title()} Playlist")
    else:
        vid = info.get("id", "")
        thumbnail = _best_thumbnail_url(info.get("thumbnails", []), info.get("thumbnail", ""))
        if not thumbnail and service == "youtube" and vid:
            thumbnail = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"

        entry_url = info.get("webpage_url") or url
        artists = info.get("channel") or info.get("uploader") or ""
        tracks = [{
            "id": vid or url,
            "title": info.get("title", "Unknown Track"),
            "artists": artists,
            "album": "",
            "cover": thumbnail,
            "releaseDate": "",
            "downloadLink": "",
            "sourceUrl": entry_url,
        }]
        playlist_name = f"{info.get('title', 'Track')} - {artists}" if artists else info.get('title', 'Track')

    return playlist_name, tracks


def get_playlist_client():
    global _playlist_client
    if _playlist_client is None:
        _playlist_client = PlaylistClient()
    return _playlist_client


def download_cover(url):
    try:
        if not url: return None, None
        resp = requests.get(url, timeout=10, stream=True, proxies=_get_proxy_for_requests())
        try:
            if resp.status_code == 200:
                content_type = resp.headers.get("Content-Type", "image/jpeg")
                return resp.content, content_type
        finally:
            resp.close()
    except Exception:
        pass
    return None, None


def apply_metadata(filepath, track_title, artists, album, release_date, cover_url):
    try:
        audio = MP3(filepath)
        if audio.tags is None:
            audio.add_tags()
            audio.tags.save(filepath, v2_version=3)

        audio_easy = EasyID3(filepath)
        audio_easy["title"] = track_title or ""
        audio_easy["artist"] = artists or ""
        audio_easy["album"] = album or ""
        audio_easy["date"] = release_date or ""
        audio_easy.save(v2_version=3)

        cover_data, mime_type = download_cover(cover_url)
        if cover_data:
            audio_id3 = ID3(filepath)
            audio_id3["APIC"] = APIC(
                encoding=3,
                mime=mime_type or "image/jpeg",
                type=3,
                desc="Cover",
                data=cover_data
            )
            audio_id3.save(v2_version=3)

    except Exception as e:
        print(f"Failed to write metadata: {e}")


def download_track_logic(track_id, track_title, artists, album, release_date, cover_url, output_dir, job_id=None, source_url=None):
    _log_warp_context("download")
    source = source_url if source_url else f"ytsearch1:{track_title} {artists} audio"
    output_template = os.path.join(output_dir, f"%(title)s.%(ext)s")

    if track_id in CANCELLED_TRACKS:
        CANCELLED_TRACKS.discard(track_id)

    def yt_progress_hook(d):
        if track_id in CANCELLED_TRACKS or (job_id and job_id in CANCELLED_PLAYLIST_JOBS):
            raise Exception("Download cancelled by user")

        if d['status'] == 'downloading':
            try:
                raw_pct = d.get('_percent_str', '0.0%').strip()
                clean_pct = re.sub(r'\x1b\[[0-9;]*m', '', raw_pct).replace('%', '')
                progress_store[track_id] = float(clean_pct) * 0.90
            except Exception:
                pass
        elif d['status'] == 'finished':
            progress_store[track_id] = 90.0

    download_strategies = [
        _youtube_extractor_args(),
        {"youtube": {"player_client": ["android"], "formats": ["missing_pot"]}},
    ]

    info = None
    final_path = None
    last_error = None
    try:
        proxy_url = _get_proxy_for_ytdlp()
        for strat_idx, extractor_args in enumerate(download_strategies, 1):
            if final_path:
                break
            print(f"[Download] {track_title} - trying strategy {strat_idx}/{len(download_strategies)}", flush=True)
            base_opts = {
                "format": "bestaudio/best",
                "noplaylist": True,
                "quiet": True,
                "outtmpl": output_template,
                "progress_hooks": [yt_progress_hook],
                "postprocessors": [
                    {
                        "key": "FFmpegExtractAudio",
                        "preferredcodec": "mp3",
                        "preferredquality": "192",
                    }
                ],
                "extractor_args": extractor_args,
                "remote_components": ["ejs:github"],
            }
            if proxy_url:
                base_opts["proxy"] = proxy_url
            try:
                info = _run_ytdl_once(source, base_opts, download=True)
                if not info or ('entries' in info and not info['entries']):
                    print(f"Track not found on YouTube: {track_title}")
                    progress_store[track_id] = -1.0
                    return None

                if 'entries' in info and info['entries']:
                    info = info['entries'][0]

                filepath = _QuietYTDLPLogger  # placeholder, use ydl
                ydl_opts = dict(base_opts)
                ydl_opts["quiet"] = True
                ydl_opts["no_warnings"] = True
                ydl_opts["logger"] = _QuietYTDLPLogger()
                with YoutubeDL(ydl_opts) as ydl:
                    filepath = ydl.prepare_filename(info)
                base, _ = os.path.splitext(filepath)
                final_path = base + ".mp3"
                break
            except Exception as exc:
                last_error = exc
        if final_path is None:
            raise RuntimeError(_clean_ytdlp_error(last_error or RuntimeError("yt-dlp download failed")))
    except Exception as e:
        print(f"YT Download failed for {track_title}: {e}")
        progress_store[track_id] = -1.0
        return None

    if os.path.exists(final_path):
        progress_store[track_id] = 95.0

        dl_cover = _best_thumbnail_url(info.get("thumbnails", []), info.get("thumbnail", ""))

        if not dl_cover:
            vid = info.get('id')
            if vid:
                dl_cover = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"

        cover_url = (cover_url or dl_cover) if source_url else (dl_cover or cover_url)

        print(f"Applying metadata to {final_path} with cover: {cover_url}")
        apply_metadata(final_path, track_title, artists, album, release_date, cover_url)
        progress_store[track_id] = 100.0
        print(f"[Download] Completed: {track_title} - {artists}", flush=True)

    if not os.path.exists(final_path):
        progress_store[track_id] = -1.0
        return None

    return final_path


def _pick_audio_format(formats):
    if not formats:
        return None, "audio/webm"
    def _valid(f):
        if not f.get("url"):
            return False
        ext = f.get("ext", "")
        fid = str(f.get("format_id", ""))
        if ext in ("mhtml", "json") or fid.startswith("sb"):
            return False
        if f.get("protocol") in ("m3u8", "m3u8_native"):
            return False
        return True
    valid = [f for f in formats if _valid(f)]
    if not valid:
        return None, "audio/webm"
    audio_only = [f for f in valid if f.get("vcodec") == "none"]
    pool = audio_only if audio_only else valid
    for fmt in reversed(pool):
        ext = fmt.get("ext", "webm")
        if ext == "opus":
            return fmt, "audio/ogg"
        if ext in ("webm", "m4a", "mp4", "ogg"):
            return fmt, f"audio/{ext}"
    fmt = pool[-1]
    ext = fmt.get("ext", "webm")
    ct = "audio/ogg" if ext == "opus" else f"audio/{ext}" if ext in ("webm","m4a","mp4","ogg") else "audio/webm"
    return fmt, ct

def _proxy_googlevideo(audio_url, content_type, base_headers, range_header, proxy_dict):
    req_headers = dict(base_headers) if base_headers else {}
    if "User-Agent" not in req_headers:
        req_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    if range_header:
        req_headers["Range"] = range_header
    upstream = requests.get(audio_url, headers=req_headers, stream=True, proxies=proxy_dict, timeout=15, allow_redirects=True)
    if upstream.status_code in (403, 401):
        body = upstream.content[:200] if upstream.content else b""
        upstream.close()
        return None, f"googlevideo HTTP {upstream.status_code} {body!r}"
    if upstream.status_code not in (200, 206):
        upstream.close()
        return None, f"googlevideo HTTP {upstream.status_code}"
    status_code = upstream.status_code
    resp_headers = {
        "Content-Type": content_type,
        "Accept-Ranges": "bytes",
        "Cache-Control": "no-cache",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges, Content-Type",
    }
    cl = upstream.headers.get("Content-Length")
    if cl:
        resp_headers["Content-Length"] = cl
    cr = upstream.headers.get("Content-Range")
    if cr:
        resp_headers["Content-Range"] = cr
    elif status_code == 206 and range_header:
        resp_headers["Content-Range"] = range_header.replace("bytes=", "bytes ") + "/*"
    def generate(_up=upstream):
        try:
            for chunk in _up.iter_content(chunk_size=65536):
                if chunk:
                    yield chunk
        finally:
            _up.close()
    return Response(stream_with_context(generate()), status=status_code, headers=resp_headers, direct_passthrough=True), None

def open_audio_stream(source, range_header=None):
    _log_warp_context("stream")
    proxy_url = _get_proxy_for_ytdlp()
    proxy_dict = _get_proxy_for_requests()
    print(f"[Stream] Requested source: {source[:200]} range={range_header or 'none'}", flush=True)
    cached = _audio_cache_get(source)
    if cached:
        audio_url, content_type, base_headers = cached
        print(f"[Stream] Cache HIT for {source[:80]} -> {audio_url[:60]}...", flush=True)
        resp, err = _proxy_googlevideo(audio_url, content_type, base_headers, range_header, proxy_dict)
        if resp:
            print(f"[Stream] Cache SUCCESS status={resp.status_code}", flush=True)
            return resp, None
        print(f"[Stream] Cache stale ({err}), re-extracting...", flush=True)
        with _AUDIO_CACHE_LOCK:
            _AUDIO_URL_CACHE.pop(source, None)
    strategies = [
        _youtube_extractor_args(),
        {"youtube": {"player_client": ["android"], "formats": ["missing_pot"]}},
        {"youtube": {"player_client": ["ios"], "formats": ["missing_pot"]}},
    ]
    last_err = None
    for use_proxy in ([True] if proxy_url else [False]) + ([False] if proxy_url else []):
        cur_proxy_url = proxy_url if use_proxy else None
        cur_proxy_dict = proxy_dict if use_proxy else None
        if not use_proxy and proxy_url:
            print("[Stream] Retrying all strategies WITHOUT proxy (direct egress)...", flush=True)
            with _AUDIO_CACHE_LOCK:
                _AUDIO_URL_CACHE.pop(source, None)
        for strat_idx, extractor_args in enumerate(strategies, 1):
            player_clients = extractor_args.get("youtube", {}).get("player_client", [])
            base_opts = {
                "format": "bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio/best",
                "noplaylist": True,
                "quiet": True,
                "no_warnings": True,
                "socket_timeout": 15,
                "extractor_args": extractor_args,
                "remote_components": ["ejs:github"],
            }
            if cur_proxy_url:
                base_opts["proxy"] = cur_proxy_url
            try:
                print(f"[Stream] Strategy {strat_idx} ({player_clients}) {'via proxy' if use_proxy else 'direct'}: extracting info...", flush=True)
                with YoutubeDL(base_opts) as ydl:
                    info = ydl.extract_info(source, download=False)
                    if not info or ('entries' in info and not info.get('entries')):
                        last_err = f"Strategy {strat_idx} ({player_clients}): no results"
                        print(f"[Stream] {last_err}", flush=True)
                        continue
                    if 'entries' in info and info['entries']:
                        info = info['entries'][0]
                    video_title = info.get("title", "Unknown")
                    video_id = info.get("id", "")
                    print(f"[Stream] Found: [{video_id}] {video_title}", flush=True)
                    formats = info.get("formats", []) or []
                    selected_fmt, content_type = _pick_audio_format(formats)
                    if not selected_fmt:
                        audio_url = info.get("url", "")
                        if not audio_url:
                            last_err = f"Strategy {strat_idx} ({player_clients}): no streamable URL"
                            print(f"[Stream] {last_err}", flush=True)
                            continue
                        base_headers = info.get("http_headers", {}) or {}
                        content_type = "audio/webm"
                    else:
                        audio_url = selected_fmt["url"]
                        base_headers = selected_fmt.get("http_headers") or info.get("http_headers", {}) or {}
                        print(f"[Stream] Selected audio format: {selected_fmt.get('format_id')} ext={selected_fmt.get('ext')} abr={selected_fmt.get('abr','?')}", flush=True)
                    _audio_cache_set(source, audio_url, content_type, base_headers)
                    resp, err = _proxy_googlevideo(audio_url, content_type, base_headers, range_header, cur_proxy_dict)
                    if resp:
                        print(f"[Stream] Strategy {strat_idx} SUCCESS status={resp.status_code} ct={content_type} {'via proxy' if use_proxy else 'direct'}", flush=True)
                        return resp, None
                    last_err = f"Strategy {strat_idx} ({player_clients}): {err}"
                    print(f"[Stream] {last_err}", flush=True)
                    continue
            except Exception as exc:
                last_err = f"Strategy {strat_idx} ({player_clients}): {_clean_ytdlp_error(exc)}"
                print(f"[Stream] Strategy {strat_idx} FAILED: {exc}", flush=True)
                continue
        if not use_proxy:
            break
    print(f"[Stream] All strategies exhausted for: {source[:150]} - last error: {last_err}", flush=True)
    return None, last_err or "All extraction strategies failed"
