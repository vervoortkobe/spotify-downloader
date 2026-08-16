from __future__ import annotations

import os
import re
import threading
import time

import requests
from yt_dlp import YoutubeDL
from mutagen.easyid3 import EasyID3
from mutagen.id3 import APIC, ID3
from mutagen.mp3 import MP3
from flask import Response, jsonify, stream_with_context

from spotify_client import PlaylistClient
from config import progress_store, scrape_job_progress, CANCELLED_TRACKS, CANCELLED_PLAYLIST_JOBS, _playlist_client

# YouTube search result cache: avoids re-searching the same track
_YT_CACHE: dict[str, tuple[str, str, float]] = {}
_YT_CACHE_LOCK = threading.Lock()
_YT_CACHE_TTL = 3600 * 6


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
            "player_client": ["android", "mweb", "web_embedded", "tv", "web_safari"],
            "player_skip": ["configs"],
            "webpage_client": "web_safari",
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
        search_query = f"ytsearch1:{track_title} {artists} audio"
        base_opts = {
            "quiet": True,
            "noplaylist": True,
            "skip_download": True,
            "extractor_args": _youtube_extractor_args(),
            "remote_components": ["ejs:github"],
        }
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
    base_opts = {
        "quiet": True,
        "skip_download": True,
        "extract_flat": is_flat,
        "extractor_args": _youtube_extractor_args(),
        "remote_components": ["ejs:github"],
    }
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
        {"youtube": {"player_client": ["mweb"], "formats": ["missing_pot"]}},
        {"youtube": {"player_client": ["web"], "formats": ["missing_pot"]}},
        {"youtube": {"player_client": ["android"], "formats": ["missing_pot"]}},
    ]

    info = None
    final_path = None
    last_error = None
    try:
        for strat_idx, extractor_args in enumerate(download_strategies, 1):
            if final_path:
                break
            print(f"[Download] {track_title} — trying strategy {strat_idx}/{len(download_strategies)}", flush=True)
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


def resolve_audio_stream(source, extra_opts=None):
    base_opts = {
        "format": "bestaudio/best",
        "noplaylist": True,
        "quiet": True,
        "skip_download": True,
        "socket_timeout": 30,
        "extractor_args": _youtube_extractor_args(),
        "remote_components": ["ejs:github"],
    }
    if extra_opts:
        base_opts.update(extra_opts)
    try:
        info = _run_ytdl_once(source, base_opts, download=False)
    except Exception as e:
        return None, None, None, f"Failed to resolve source: {e}"

    if not info:
        return None, None, None, "Could not resolve source"

    if "entries" in info and info["entries"]:
        info = info["entries"][0]

    audio_url = None
    content_type = "audio/webm"
    formats = info.get("formats", [])
    for fmt in reversed(formats):
        if fmt.get("vcodec") == "none" and fmt.get("url"):
            ext = fmt.get("ext", "webm")
            content_type = f"audio/{ext}" if ext in ("webm", "m4a", "mp4", "ogg") else "audio/webm"
            audio_url = fmt["url"]
            break
    if not audio_url:
        for fmt in reversed(formats):
            if fmt.get("url"):
                ext = fmt.get("ext", "webm")
                content_type = f"audio/{ext}" if ext in ("webm", "m4a", "mp4", "ogg") else "audio/webm"
                audio_url = fmt["url"]
                break
    if not audio_url:
        audio_url = info.get("url", "")

    if not audio_url:
        return None, None, None, "No streamable audio URL found"

    request_headers = {}
    if isinstance(info, dict):
        top_headers = info.get("http_headers", {})
        if isinstance(top_headers, dict):
            request_headers.update(top_headers)

    selected_format = None
    for fmt in reversed(formats):
        if fmt.get("url") == audio_url:
            selected_format = fmt
            break
    if isinstance(selected_format, dict):
        fmt_headers = selected_format.get("http_headers", {})
        if isinstance(fmt_headers, dict):
            request_headers.update(fmt_headers)

    return audio_url, content_type, request_headers or None, None


def _get_proxy_for_requests():
    """Return a proxies dict for requests from the WARP proxy environment variables."""
    proxy_url = os.environ.get("ALL_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY")
    if proxy_url:
        return {"http": proxy_url, "https": proxy_url}
    return None


def proxy_audio_stream(audio_url, content_type, range_header=None, upstream_headers=None):
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "*/*",
        "Referer": "https://www.youtube.com/",
        "Origin": "https://www.youtube.com",
    }
    if upstream_headers:
        headers.update(upstream_headers)
    if range_header:
        headers["Range"] = range_header

    proxies = _get_proxy_for_requests()

    try:
        upstream = requests.get(audio_url, headers=headers, stream=True, timeout=30, proxies=proxies)
    except Exception as exc:
        print(f"[Stream] Audio fetch failed for {audio_url}: {exc}", flush=True)
        return jsonify({"error": "Audio stream temporarily unavailable"}), 502

    if upstream.status_code not in (200, 206):
        print(f"[Stream] Upstream returned HTTP {upstream.status_code} for {audio_url}", flush=True)
        upstream.close()
        return jsonify({"error": f"Upstream returned HTTP {upstream.status_code}"}), 502

    status = upstream.status_code
    resp_headers = {
        "Content-Type": upstream.headers.get("Content-Type", content_type),
        "Accept-Ranges": "bytes",
    }
    for h in ("Content-Length", "Content-Range"):
        if h in upstream.headers:
            resp_headers[h] = upstream.headers[h]

    print(f"[Stream] Streaming audio {audio_url[:80]}... status={status} content-type={resp_headers['Content-Type']}", flush=True)

    def generate():
        for chunk in upstream.iter_content(chunk_size=65536):
            if chunk:
                yield chunk

    return Response(
        stream_with_context(generate()),
        status=status,
        headers=resp_headers,
        direct_passthrough=True,
    )
