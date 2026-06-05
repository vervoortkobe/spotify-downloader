from __future__ import annotations

import gc
import os
import tempfile
import shutil
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor

from flask import Blueprint, jsonify, request, send_file, after_this_request

from spotifydown_api import (
    SpotifyDownAPIError,
    SpotifyEmbedAPI,
    detect_spotify_url_type,
    sanitize_filename,
)

from config import progress_store, CANCELLED_TRACKS, CANCELLED_PLAYLIST_JOBS, JOB_STORE, COMPLETED_JOBS_DIR
from utils import get_yt_info, get_playlist_client, download_track_logic, _resolve_audio_stream, _proxy_audio_stream, detect_url_service, scrape_external_data

routes = Blueprint("routes", __name__)


@routes.route("/api/scrape-playlist", methods=["POST"])
def scrape_playlist():
    try:
        data = request.get_json()
        input_url = data.get("playlistUrl", "").strip()
        service = data.get("service", "auto")

        if not input_url:
            return jsonify({"event": "error", "data": {"message": "No URL provided"}}), 400

        if service == "auto":
            detected_service, url_type, item_id = detect_url_service(input_url)
            service = detected_service
        else:
            _, url_type, item_id = detect_url_service(input_url)

        if not service:
            return jsonify({"event": "error", "data": {"message": "Unsupported URL — please use Spotify, YouTube, or SoundCloud."}}), 400

        if not url_type or not item_id:
            return jsonify({"event": "error", "data": {"message": "Could not parse URL"}}), 400

        tracks: list[dict] = []

        if service == "spotify":
            client = get_playlist_client()

            if url_type == "track":
                api = SpotifyEmbedAPI()
                track = api.get_track(item_id)
                yt_cover, yt_url = get_yt_info(track.title, track.artists)
                tracks.append({
                    "id": track.spotify_id,
                    "title": track.title,
                    "artists": track.artists,
                    "album": track.album or "",
                    "cover": yt_cover or track.cover_url or "",
                    "releaseDate": track.release_date or "",
                    "downloadLink": "",
                    "sourceUrl": yt_url,
                })
                playlist_name = f"{track.title} - {track.artists}"
            else:
                metadata = client.get_playlist_metadata(item_id)
                playlist_name = f"{metadata.name} - {metadata.owner or 'Unknown'}"
                raw_tracks = list(client.iter_playlist_tracks(item_id))

                def process_track(track):
                    yt_cover, yt_url = get_yt_info(track.title, track.artists)
                    return {
                        "id": track.spotify_id,
                        "title": track.title,
                        "artists": track.artists,
                        "album": track.album or "",
                        "cover": yt_cover or track.cover_url or "",
                        "releaseDate": track.release_date or "",
                        "downloadLink": "",
                        "sourceUrl": yt_url,
                    }

                with ThreadPoolExecutor(max_workers=5) as executor:
                    tracks = list(executor.map(process_track, raw_tracks))

                gc.collect()
        elif service in ("youtube", "soundcloud"):
            playlist_name, tracks = scrape_external_data(input_url, service, url_type)
        else:
            return jsonify({"event": "error", "data": {"message": f"Unsupported service: {service}"}}), 400

        gc.collect()

        return jsonify({
            "event": "complete",
            "data": {
                "playlistName": playlist_name,
                "tracks": tracks,
            },
        })

    except SpotifyDownAPIError as e:
        return jsonify({"event": "error", "data": {"message": f"Spotify API error: {e}"}}), 500
    except Exception as e:
        print(f"Scrape error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"event": "error", "data": {"message": f"Error: {e}"}}), 500


@routes.route("/api/cancel-track/<track_id>", methods=["POST"])
def cancel_track(track_id):
    CANCELLED_TRACKS.add(track_id)
    if track_id in progress_store:
        del progress_store[track_id]
    return jsonify({"status": "cancelled"})


@routes.route("/api/cancel-playlist/<job_id>", methods=["POST"])
def cancel_playlist(job_id):
    job = JOB_STORE.get(job_id)
    if not job:
        return jsonify({"status": "not_found"}), 404

    CANCELLED_PLAYLIST_JOBS.add(job_id)
    job["status"] = "cancelled"
    job["message"] = "Playlist download cancelled"
    return jsonify({"status": "cancelled"})


@routes.route("/api/progress/<track_id>")
def get_progress(track_id):
    if track_id == "all":
        return jsonify(progress_store)
    return jsonify({"progress": progress_store.get(track_id, 0)})


@routes.route("/api/resolve-youtube-url", methods=["POST"])
def resolve_youtube_url():
    try:
        data = request.get_json()
        youtube_url = (data or {}).get("youtubeUrl", "").strip()

        if not youtube_url:
            return jsonify({"error": "No URL provided"}), 400

        if not ("youtube.com" in youtube_url or "youtu.be" in youtube_url):
            return jsonify({"error": "Not a valid YouTube URL"}), 400

        from yt_dlp import YoutubeDL
        ydl_opts = {
            "quiet": True,
            "noplaylist": True,
            "skip_download": True,
        }
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(youtube_url, download=False)

        if not info:
            return jsonify({"error": "Could not resolve URL"}), 400

        thumbnails = info.get("thumbnails", [])
        thumbnail = ""
        if thumbnails:
            jpegs = [t for t in thumbnails if ".jpg" in t.get("url", "") or ".jpeg" in t.get("url", "")]
            thumbnail = (jpegs[-1].get("url") if jpegs else thumbnails[-1].get("url")) or ""
        if not thumbnail:
            thumbnail = info.get("thumbnail", "")

        return jsonify({
            "title": info.get("title", ""),
            "thumbnail": thumbnail,
            "duration": info.get("duration", 0),
            "videoId": info.get("id", ""),
            "channel": info.get("channel", info.get("uploader", "")),
        })

    except Exception as e:
        print(f"resolve-youtube-url error: {e}")
        return jsonify({"error": str(e)}), 500


@routes.route("/api/stream", methods=["GET"])
def stream_track_get():
    source_url = request.args.get("source_url", "").strip()
    title = request.args.get("title", "").strip()
    artists = request.args.get("artists", "").strip()

    if not source_url and not (title or artists):
        return jsonify({"error": "Provide source_url or title+artists"}), 400

    source = source_url if source_url else f"ytsearch1:{title} {artists} audio"

    audio_url, content_type, err = _resolve_audio_stream(source)
    if err:
        return jsonify({"error": err}), 404

    range_header = request.headers.get("Range", None)
    return _proxy_audio_stream(audio_url, content_type, range_header)


@routes.route("/api/stream-track", methods=["POST"])
def stream_track():
    data = request.get_json()
    source_url = (data or {}).get("sourceUrl", "").strip()
    title = (data or {}).get("title", "").strip()
    artists = (data or {}).get("artists", "").strip()

    if not source_url and not (title or artists):
        return jsonify({"error": "Provide sourceUrl or title+artists"}), 400

    source = source_url if source_url else f"ytsearch1:{title} {artists} audio"

    audio_url, content_type, err = _resolve_audio_stream(source)
    if err:
        return jsonify({"error": err}), 404

    range_header = request.headers.get("Range", None)
    return _proxy_audio_stream(audio_url, content_type, range_header)


@routes.route("/api/download-track", methods=["POST"])
def download_track():
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
        source_url = data.get("sourceUrl", "").strip() or None

        temp_dir = tempfile.mkdtemp()

        @after_this_request
        def remove_file(response):
            return response

        final_path = download_track_logic(track_id, track_title, artists, album, release_date, cover_url, temp_dir, source_url=source_url)

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


@routes.route("/api/download-playlist-zip", methods=["POST"])
def download_playlist_zip():
    try:
        data = request.get_json()
        tracks = data.get("tracks", [])
        playlist_name = data.get("playlistName", "Playlist")

        if not tracks:
            return jsonify({"event": "error", "message": "No tracks provided"}), 400

        for t in tracks:
            tid = t.get("id")
            if tid:
                progress_store[tid] = 0.0

        job_id = str(uuid.uuid4())
        JOB_STORE[job_id] = {"status": "processing", "progress": 0, "path": None, "error": None}

        thread = threading.Thread(target=process_playlist_job, args=(job_id, tracks, playlist_name))
        thread.start()

        return jsonify({"job_id": job_id})

    except Exception as e:
        print(f"Error starting playlist job: {e}")
        return jsonify({"event": "error", "message": str(e)}), 500


def process_playlist_job(job_id, tracks, playlist_name):
    temp_dir = tempfile.mkdtemp()
    try:
        output_dir = os.path.join(temp_dir, sanitize_filename(playlist_name))
        os.makedirs(output_dir, exist_ok=True)

        def process_track_for_zip(track):
            try:
                track_id = track.get("id", "tmp_id")
                track_title = track.get("title", "Unknown Title")
                artists = track.get("artists", "Unknown Artist")
                album = track.get("album", "")
                release_date = track.get("releaseDate", "")
                cover_url = track.get("cover", "")
                source_url = track.get("sourceUrl", "").strip() or None

                if job_id in CANCELLED_PLAYLIST_JOBS:
                    return

                final_path = download_track_logic(track_id, track_title, artists, album, release_date, cover_url, output_dir, job_id=job_id, source_url=source_url)

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


@routes.route("/api/job-status/<job_id>")
def job_status(job_id):
    job = JOB_STORE.get(job_id)
    if not job:
        return jsonify({"status": "not_found"}), 404
    return jsonify(job)


@routes.route("/api/download-job/<job_id>")
def download_job(job_id):
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


@routes.route("/api/health")
def health_check():
    print("[Health Check] Received check request from frontend", flush=True)
    response = jsonify({"online": True})
    print("[Health Check] Responding to health check: online=True", flush=True)
    return response


@routes.route("/")
def index():
    return jsonify({"online": True})
