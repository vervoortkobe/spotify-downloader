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


def download_track_logic(track_id, track_title, artists, album, release_date, cover_url, output_dir, job_id=None, youtube_url=None):
    source = youtube_url if youtube_url else f"ytsearch1:{track_title} {artists} audio"
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
        "javascript_runtime": "deno",
        "remote_components": ["ejs:github"],
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
        cover_url = None
        if thumbnails:
            jpegs = [t for t in thumbnails if '.jpg' in t.get('url', '') or '.jpeg' in t.get('url', '')]
            if jpegs:
                cover_url = jpegs[-1].get('url')

        if not cover_url:
            cover_url = info.get('thumbnail')

        print(f"Applying metadata to {final_path} with cover: {cover_url}")
        apply_metadata(final_path, track_title, artists, album, release_date, cover_url)
        progress_store[track_id] = 100.0

    if not os.path.exists(final_path):
        progress_store[track_id] = -1.0
        return None

    return final_path


def _resolve_audio_stream(source):
    ydl_opts = {
        "format": "bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio/best",
        "noplaylist": True,
        "quiet": True,
        "skip_download": True,
        "socket_timeout": 15,
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
