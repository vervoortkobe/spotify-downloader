from __future__ import annotations

import os
import tempfile

_playlist_client = None

JOB_STORE = {}
COMPLETED_JOBS_DIR = os.path.join(tempfile.gettempdir(), "spotify_downloader_jobs")
os.makedirs(COMPLETED_JOBS_DIR, exist_ok=True)

progress_store = {}
CANCELLED_TRACKS = set()
CANCELLED_PLAYLIST_JOBS = set()
