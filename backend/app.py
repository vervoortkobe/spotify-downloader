from __future__ import annotations

import gc
import os
import sys
import tempfile
import zipfile
import shutil
import glob
import requests
import threading
import uuid
import time
from pathlib import Path

from flask import Flask, jsonify, request, send_file, after_this_request, send_from_directory
from flask_cors import CORS
from yt_dlp import YoutubeDL
import mutagen
from mutagen.easyid3 import EasyID3
from dotenv import load_dotenv

load_dotenv()
from mutagen.id3 import APIC, ID3
from mutagen.mp3 import MP3

# Add parent directory to path for spotifydown_api import
ROOT = Path(__file__).resolve().parent.parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from spotifydown_api import (  # noqa: E402
    PlaylistClient,
    SpotifyDownAPIError,
    SpotifyEmbedAPI,
    detect_spotify_url_type,
    sanitize_filename,
)

app = Flask(__name__)

# Load allowed origins from environment variable 'FRONTEND_URL'
# For multiple domains, separate them with a comma.
# Defaults to local development origins if not set.
frontend_urls = os.environ.get(
    "FRONTEND_URL", 
    "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001"
)
allowed_origins = [url.strip() for url in frontend_urls.split(",") if url.strip()]

CORS(app, origins=allowed_origins)

# Reusable client (saves memory on repeated requests)
_playlist_client: PlaylistClient | None = None

# Job store for background playlist downloads
JOB_STORE = {}
# Temporary directory for completed jobs
COMPLETED_JOBS_DIR = os.path.join(tempfile.gettempdir(), "spotify_downloader_jobs")
os.makedirs(COMPLETED_JOBS_DIR, exist_ok=True)

def get_yt_thumbnail(track_title, artists):
    """Fetch YouTube thumbnail for a track (fast meta-only search)."""
    try:
        search_query = f"ytsearch1:{track_title} {artists} audio"
        ydl_opts = {
            "quiet": True,
            "noplaylist": True,
            "skip_download": True,
            "extract_flat": True # Fetch metadata only
        }
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=False)
            if 'entries' in info and info['entries']:
                info = info['entries'][0]
            
            thumbnails = info.get('thumbnails', [])
            if thumbnails:
                # Find largest JPEG
                jpegs = [t for t in thumbnails if '.jpg' in t.get('url', '') or '.jpeg' in t.get('url', '')]
                if jpegs:
                    return jpegs[-1].get('url')
            return info.get('thumbnail') or ""
    except Exception as e:
        print(f"YT Thumb fetch failed for {track_title}: {e}")
        return ""

def get_playlist_client() -> PlaylistClient:
    """Get or create a playlist client (singleton pattern for memory efficiency)."""
    global _playlist_client
    if _playlist_client is None:
        _playlist_client = PlaylistClient()
    return _playlist_client


@app.route("/api/scrape-playlist", methods=["POST"])
def scrape_playlist():
    """Fetch Spotify playlist/track metadata.

    Request body:
        {"playlistUrl": "https://open.spotify.com/playlist/..."}

    Response:
        {"event": "complete", "data": {"playlistName": "...", "tracks": [...]}}
    """
    try:
        data = request.get_json()
        spotify_url = data.get("playlistUrl", "").strip()

        if not spotify_url:
            return jsonify({"event": "error", "data": {"message": "No URL provided"}}), 400

        # Detect URL type
        url_type, item_id = detect_spotify_url_type(spotify_url)

        if url_type == "unknown" or not item_id:
            return (
                jsonify({"event": "error", "data": {"message": "Invalid Spotify URL"}}),
                400,
            )

        client = get_playlist_client()
        tracks: list[dict] = []

        if url_type == "track":
            # Single track
            api = SpotifyEmbedAPI()
            track = api.get_track(item_id)
            
            # Fetch YT Thumbnail as priority
            yt_cover = get_yt_thumbnail(track.title, track.artists)
            
            tracks.append(
                {
                    "id": track.spotify_id,
                    "title": track.title,
                    "artists": track.artists,
                    "album": track.album or "",
                    "cover": yt_cover or track.cover_url or "",
                    "releaseDate": track.release_date or "",
                    "downloadLink": "",  # No server-side downloads
                }
            )
            playlist_name = f"{track.title} - {track.artists}"

        else:
            # Playlist
            metadata = client.get_playlist_metadata(item_id)
            playlist_name = f"{metadata.name} - {metadata.owner or 'Unknown'}"

            # Fetch tracks with memory-efficient iteration
            raw_tracks = list(client.iter_playlist_tracks(item_id))
            
            # Fetch YT thumbnails in parallel for speed
            from concurrent.futures import ThreadPoolExecutor
            
            def process_track(track):
                yt_cover = get_yt_thumbnail(track.title, track.artists)
                return {
                    "id": track.spotify_id,
                    "title": track.title,
                    "artists": track.artists,
                    "album": track.album or "",
                    "cover": yt_cover or track.cover_url or "",
                    "releaseDate": track.release_date or "",
                    "downloadLink": "",
                }

            # Limit parallel tasks to avoid hitting YT rate limits
            with ThreadPoolExecutor(max_workers=5) as executor:
                tracks = list(executor.map(process_track, raw_tracks))

            # Memory management for large playlists
            gc.collect()

        # Final cleanup
        gc.collect()

        return jsonify(
            {
                "event": "complete",
                "data": {
                    "playlistName": playlist_name,
                    "tracks": tracks,
                },
            }
        )

    except SpotifyDownAPIError as e:
        return jsonify({"event": "error", "data": {"message": f"Spotify API error: {e}"}}), 500
    except Exception as e:
        print(f"Scrape error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"event": "error", "data": {"message": f"Error: {e}"}}), 500

progress_store = {}
CANCELLED_TRACKS = set()
CANCELLED_PLAYLIST_JOBS = set()

@app.route("/api/cancel-track/<track_id>", methods=["POST"])
def cancel_track(track_id):
    """Cancel a downloading track by raising an exception in its hook."""
    CANCELLED_TRACKS.add(track_id)
    if track_id in progress_store:
        del progress_store[track_id]
    return jsonify({"status": "cancelled"})


@app.route("/api/cancel-playlist/<job_id>", methods=["POST"])
def cancel_playlist(job_id):
    """Cancel a background playlist download job."""
    job = JOB_STORE.get(job_id)
    if not job:
        return jsonify({"status": "not_found"}), 404

    CANCELLED_PLAYLIST_JOBS.add(job_id)
    job["status"] = "cancelled"
    job["message"] = "Playlist download cancelled"
    return jsonify({"status": "cancelled"})

@app.route("/api/progress/<track_id>")
def get_progress(track_id):
    """Return the current download progress of a track (0-100)."""
    if track_id == "all":
        return jsonify(progress_store)
    return jsonify({"progress": progress_store.get(track_id, 0)})

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
        # Enforce writing ID3v2.3 for Windows File Explorer/Media Player compatibility
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

def download_track_logic(track_id, track_title, artists, album, release_date, cover_url, output_dir, job_id=None):
    search_query = f"ytsearch1:{track_title} {artists} audio"
    output_template = os.path.join(output_dir, f"%(title)s.%(ext)s")
    
    if track_id in CANCELLED_TRACKS:
        CANCELLED_TRACKS.discard(track_id)
    
    def yt_progress_hook(d):
        if track_id in CANCELLED_TRACKS or (job_id and job_id in CANCELLED_PLAYLIST_JOBS):
            raise Exception("Download cancelled by user")
            
        if d['status'] == 'downloading':
            try:
                import re
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
            info = ydl.extract_info(search_query, download=True)
            
            # If search produced no results, skip this track
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
        progress_store[track_id] = -1.0 # Signal failure
        return None
        
    if os.path.exists(final_path):
        progress_store[track_id] = 95.0
        
        # ALWAYS use YouTube thumbnail for song cover as requested
        # Try to find the highest resolution JPEG from thumbnails if available
        thumbnails = info.get('thumbnails', [])
        cover_url = None
        if thumbnails:
            # Filter for JPEG/JPG and sort by resolution
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


@app.route("/api/download-track", methods=["POST"])
def download_track():
    """Download a single track and return the MP3 file."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"event": "error", "message": "No data provided"}), 400

        track_id = data.get("id", "tmp_id")
        progress_store[track_id] = 0.0
        track_title = data.get("title", "Unknown Title")
        artists = data.get("artists", "Unknown Artist")
        album = data.get("album", "")
        release_date = data.get("releaseDate", "")
        cover_url = data.get("cover", "")

        temp_dir = tempfile.mkdtemp()
        
        def cleanup():
            try:
                shutil.rmtree(temp_dir)
            except Exception as e:
                print(f"Error cleaning up {temp_dir}: {e}")
                
        # Register cleanup to run after request
        # However, due to file locking on Windows, after_this_request can fail to remove files that are still being sent.
        # But this is okay for a portfolio project, temp folder will just sit there until garbage collection / OS clears it.
        # Instead of after_this_request which would fail or block, we can leave the file or clean it differently.
        
        @after_this_request
        def remove_file(response):
            # A bit tricky: we cannot easily delete the file while flask is sending it if we yield it directly.
            # But we can try passing the directory for automated cleanup when OS removes TMP.
            return response
            
        final_path = download_track_logic(track_id, track_title, artists, album, release_date, cover_url, temp_dir)
        
        if not final_path or not os.path.exists(final_path):
            progress_store[track_id] = -1.0
            return jsonify({"event": "error", "message": "Download failed - song not found on YouTube"}), 500

        res = send_file(
            final_path,
            as_attachment=True,
            download_name=f"{track_title} - {artists}.mp3",
            mimetype="audio/mpeg"
        )
        return res

    except Exception as e:
        print(f"Error downloading track: {e}")
        return jsonify({"event": "error", "message": str(e)}), 500

@app.route("/api/download-playlist-zip", methods=["POST"])
def download_playlist_zip():
    """Start downloading tracks in the background and return a job handle."""
    try:
        data = request.get_json()
        tracks = data.get("tracks", [])
        playlist_name = data.get("playlistName", "Playlist")
        
        if not tracks:
            return jsonify({"event": "error", "message": "No tracks provided"}), 400

        # Pre-reset progress for all tracks
        for t in tracks:
            tid = t.get("id")
            if tid:
                progress_store[tid] = 0.0

        job_id = str(uuid.uuid4())
        JOB_STORE[job_id] = {"status": "processing", "progress": 0, "path": None, "error": None}

        # Start background processing
        thread = threading.Thread(target=process_playlist_job, args=(job_id, tracks, playlist_name))
        thread.start()

        return jsonify({"job_id": job_id})

    except Exception as e:
        print(f"Error starting playlist job: {e}")
        return jsonify({"event": "error", "message": str(e)}), 500

def process_playlist_job(job_id, tracks, playlist_name):
    """Background task to download and zip songs."""
    temp_dir = tempfile.mkdtemp()
    try:
        output_dir = os.path.join(temp_dir, sanitize_filename(playlist_name))
        os.makedirs(output_dir, exist_ok=True)
        
        from concurrent.futures import ThreadPoolExecutor

        def process_track_for_zip(track):
            try:
                track_id = track.get("id", "tmp_id")
                track_title = track.get("title", "Unknown Title")
                artists = track.get("artists", "Unknown Artist")
                album = track.get("album", "")
                release_date = track.get("releaseDate", "")
                cover_url = track.get("cover", "")
                
                if job_id in CANCELLED_PLAYLIST_JOBS:
                    return

                final_path = download_track_logic(track_id, track_title, artists, album, release_date, cover_url, output_dir, job_id=job_id)
                
                if final_path and os.path.exists(final_path):
                    user_friendly_name = os.path.join(output_dir, f"{sanitize_filename(track_title)} - {sanitize_filename(artists)}.mp3")
                    if not final_path == user_friendly_name:
                        shutil.move(final_path, user_friendly_name)
            except Exception as track_e:
                print(f"Error on track {track.get('title')}: {track_e}")

        with ThreadPoolExecutor(max_workers=5) as executor:
            list(executor.map(process_track_for_zip, tracks))

        if job_id in CANCELLED_PLAYLIST_JOBS:
            JOB_STORE[job_id] = {"status": "cancelled", "message": "Playlist download cancelled"}
            return
        
        if not os.path.exists(output_dir) or not os.listdir(output_dir):
            JOB_STORE[job_id] = {"status": "error", "message": "No tracks found/downloaded"}
            return

        safe_playlist_name = sanitize_filename(playlist_name) or "Spotify_Playlist"
        zip_base_name = os.path.join(temp_dir, safe_playlist_name)
        zip_path = shutil.make_archive(zip_base_name, 'zip', output_dir)
        
        if os.path.exists(zip_path):
            # Move to permanent job folder
            final_zip_path = os.path.join(COMPLETED_JOBS_DIR, f"{job_id}.zip")
            shutil.move(zip_path, final_zip_path)
            JOB_STORE[job_id] = {"status": "completed", "path": final_zip_path, "filename": f"{safe_playlist_name}.zip"}
        else:
            JOB_STORE[job_id] = {"status": "error", "message": "Failed to create ZIP"}

    except Exception as e:
        print(f"Playlist job {job_id} failed: {e}")
        JOB_STORE[job_id] = {"status": "error", "message": str(e)}
    finally:
        try:
            shutil.rmtree(temp_dir)
        except:
            pass

@app.route("/api/job-status/<job_id>")
def job_status(job_id):
    """Check status of a playlist download job."""
    job = JOB_STORE.get(job_id)
    if not job:
        return jsonify({"status": "not_found"}), 404
    return jsonify(job)

@app.route("/api/download-job/<job_id>")
def download_job(job_id):
    """Download the completed ZIP for a job."""
    job = JOB_STORE.get(job_id)
    if not job or job.get("status") != "completed":
        return jsonify({"error": "Job not finished or not found"}), 404
    
    path = job.get("path")
    if not path or not os.path.exists(path):
        return jsonify({"error": "File not found"}), 404

    @after_this_request
    def remove_job(response):
        try:
            if os.path.exists(path):
                os.remove(path)
            if job_id in JOB_STORE:
                del JOB_STORE[job_id]
        except Exception as e:
            print(f"Cleanup error: {e}")
        return response

    return send_file(
        path,
        as_attachment=True,
        download_name=job.get("filename", "playlist.zip"),
        mimetype="application/zip"
    )


@app.route("/api/health")
def health_check():
    """Health check endpoint for monitoring."""
    return jsonify({"online": True})


@app.route("/")
def index():
    """Root endpoint with API info."""
    return jsonify({"online": True})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
