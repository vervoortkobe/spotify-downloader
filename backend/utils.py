from __future__ import annotations

import os
import re

import requests
from yt_dlp import YoutubeDL
from mutagen.easyid3 import EasyID3
from mutagen.id3 import APIC, ID3
from mutagen.mp3 import MP3
from flask import Response, stream_with_context

from spotifydown_api import PlaylistClient
from config import progress_store, CANCELLED_TRACKS, CANCELLED_PLAYLIST_JOBS, _playlist_client


def get_yt_info(track_title, artists):
    try:
        search_query = f"ytsearch1:{track_title} {artists} audio"
        ydl_opts = {
            "quiet": True,
            "noplaylist": True,
            "skip_download": True,
            "extract_flat": True
        }
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=False)
            if 'entries' in info and info['entries']:
                info = info['entries'][0]

            video_id = info.get('id', '')
            video_url = f"https://www.youtube.com/watch?v={video_id}" if video_id else ""

            thumbnail = ""
            thumbnails = info.get('thumbnails', [])
            if thumbnails:
                jpegs = [t for t in thumbnails if '.jpg' in t.get('url', '') or '.jpeg' in t.get('url', '')]
                if jpegs:
                    thumbnail = jpegs[-1].get('url')
            if not thumbnail:
                thumbnail = info.get('thumbnail') or ""

            return thumbnail, video_url
    except Exception as e:
        print(f"YT info fetch failed for {track_title}: {e}")
        return "", ""


def detect_url_service(url):
    """Detect service, type, and ID from a URL.
    Returns (service, type, id) or (None, None, None).
    """
    url = url.strip()

    # Spotify
    m = re.search(r'open\.spotify\.com/(track|playlist)/([a-zA-Z0-9]+)', url)
    if m:
        return 'spotify', m.group(1), m.group(2)

    # YouTube (watch / youtu.be / shorts / music.youtube.com)
    m = re.search(r'(?:youtube\.com/watch\?.*v=|youtu\.be/|music\.youtube\.com/watch\?.*v=|youtube\.com/shorts/)([a-zA-Z0-9_-]{11})', url)
    if m:
        return 'youtube', 'track', m.group(1)

    # YouTube (playlist)
    m = re.search(r'(?:youtube\.com|music\.youtube\.com)/playlist\?.*list=([a-zA-Z0-9_-]+)', url)
    if m:
        return 'youtube', 'playlist', m.group(1)

    # SoundCloud (set/playlist)
    m = re.search(r'soundcloud\.com/([a-zA-Z0-9_-]+)/sets/', url)
    if m:
        return 'soundcloud', 'playlist', url

    # SoundCloud (track)
    m = re.search(r'soundcloud\.com/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)', url)
    if m:
        return 'soundcloud', 'track', url

    return None, None, None


def scrape_external_data(url, service, url_type):
    """Scrape track/playlist data from YouTube or SoundCloud using yt-dlp.
    Returns (playlist_name, tracks_list).
    """
    is_flat = url_type == "playlist"
    ydl_opts = {
        "quiet": True,
        "skip_download": True,
        "extract_flat": is_flat,
    }
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)

    if not info:
        raise ValueError(f"Could not fetch data from {url}")

    if url_type == "playlist":
        entries = info.get("entries", [])
        tracks = []
        for entry in entries:
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

            thumbnail = entry.get("thumbnail", "")
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
        playlist_name = info.get("title", f"{service.title()} Playlist")
    else:
        vid = info.get("id", "")
        thumbnail = info.get("thumbnail", "")
        thumbnails = info.get("thumbnails", [])
        if thumbnails:
            jpegs = [t for t in thumbnails if ".jpg" in t.get("url", "") or ".jpeg" in t.get("url", "")]
            thumbnail = (jpegs[-1].get("url") if jpegs else thumbnails[-1].get("url")) or thumbnail
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
        response = requests.get(url, stream=True, timeout=10)
        if response.status_code == 200:
            content_type = response.headers.get("Content-Type", "image/jpeg")
            return response.content, content_type
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

    ydl_opts = {
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
    }
    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(source, download=True)

            if not info or ('entries' in info and not info['entries']):
                print(f"Track not found on YouTube: {track_title}")
                progress_store[track_id] = -1.0
                return None

            if 'entries' in info and info['entries']:
                info = info['entries'][0]

            filepath = ydl.prepare_filename(info)
            base, _ = os.path.splitext(filepath)
            final_path = base + ".mp3"
    except Exception as e:
        print(f"YT Download failed for {track_title}: {e}")
        progress_store[track_id] = -1.0
        return None

    if os.path.exists(final_path):
        progress_store[track_id] = 95.0

        thumbnails = info.get('thumbnails', [])
        dl_cover = None
        if thumbnails:
            jpegs = [t for t in thumbnails if '.jpg' in t.get('url', '') or '.jpeg' in t.get('url', '') or '.png' in t.get('url', '')]
            if jpegs:
                dl_cover = jpegs[-1].get('url')

        if not dl_cover:
            dl_cover = info.get('thumbnail')

        cover_url = cover_url or dl_cover if source_url else dl_cover or cover_url

        print(f"Applying metadata to {final_path} with cover: {cover_url}")
        apply_metadata(final_path, track_title, artists, album, release_date, cover_url)
        progress_store[track_id] = 100.0

    if not os.path.exists(final_path):
        progress_store[track_id] = -1.0
        return None

    return final_path


def _resolve_audio_stream(source):
    ydl_opts = {
        "format": "bestaudio/best",
        "noplaylist": True,
        "quiet": True,
        "skip_download": True,
        "socket_timeout": 30,
    }
    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(source, download=False)
    except Exception as e:
        return None, None, f"Failed to resolve source: {e}"

    if not info:
        return None, None, "Could not resolve source"

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
        return None, None, "No streamable audio URL found"

    return audio_url, content_type, None


def _proxy_audio_stream(audio_url, content_type, range_header=None):
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Accept": "*/*",
    }
    if range_header:
        headers["Range"] = range_header

    upstream = requests.get(audio_url, headers=headers, stream=True, timeout=30)

    status = upstream.status_code
    resp_headers = {
        "Content-Type": upstream.headers.get("Content-Type", content_type),
        "Accept-Ranges": "bytes",
    }
    for h in ("Content-Length", "Content-Range"):
        if h in upstream.headers:
            resp_headers[h] = upstream.headers[h]

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
