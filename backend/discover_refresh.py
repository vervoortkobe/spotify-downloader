from __future__ import annotations
import os
import time
import threading

DISCOVER_URLS = [
    "https://open.spotify.com/playlist/37i9dQZF1DX1kfybUJZB6S",
    "https://open.spotify.com/playlist/37i9dQZF1DWWSuZL7uNdVA",
    "https://open.spotify.com/playlist/37i9dQZF1EIdZFdTlGR1gX",
    "https://open.spotify.com/playlist/37i9dQZF1EIdDyy28MYSyS",
    "https://open.spotify.com/playlist/37i9dQZF1EQfqRaYoWBGEg",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO37wTNS",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0PRpBu",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0lhGr6",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO2O09Hg",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3tjkZi",
]

def _init_firestore():
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
        if not firebase_admin._apps:
            # Prefer service account JSON path or inline JSON
            sa_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH")
            sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
            if sa_path and os.path.exists(sa_path):
                cred = credentials.Certificate(sa_path)
                firebase_admin.initialize_app(cred)
            elif sa_json:
                import json, tempfile
                data = json.loads(sa_json)
                cred = credentials.Certificate(data)
                firebase_admin.initialize_app(cred)
            else:
                # Application default credentials (Cloud Run, etc.)
                cred = credentials.ApplicationDefault()
                firebase_admin.initialize_app(cred)
        return firestore.client()
    except Exception as e:
        print(f"[DiscoverRefresh] Firestore init failed: {e}", flush=True)
        return None

def _doc_id_for_url(url: str) -> str:
    clean = url.split("?")[0]
    return str(hash(clean) & 0x7fffffff) if False else str(abs(hash(clean)))  # placeholder, replaced below

def _hash_id(url: str) -> str:
    clean = url.split("?")[0]
    # must match Flutter: clean.hashCode.toString() -> Dart hashCode not stable across platforms
    # Use Python hash of clean -> but to match Dart, Flutter uses `clean.hashCode.toString()` in ApiService.
    # Dart hashCode is not cross-language stable, so use same as Flutter discover fallback: `url.hashCode.toString()` where hashCode is Dart's String.hashCode (different).
    # To make both sides agree, use simple `abs(hash(clean))` in Python and also Flutter side should use same? Instead use firestore doc id = clean split first's Python hash via same method as Flutter uses for ApiService: Flutter does `cleanUrl.hashCode.toString()` - that's Dart's hash.
    # So we normalize to `clean` as doc id via python's hash of URL string using stable hashing: use hashlib
    import hashlib
    return hashlib.md5(clean.encode()).hexdigest()[:20]

# override to use stable md5 for cross-platform
def _stable_doc_id(url: str) -> str:
    import hashlib
    clean = url.split("?")[0]
    return hashlib.md5(clean.encode()).hexdigest()[:16]

# But Flutter cache uses `hashCode.toString()` - we need both to match.
# So Flutter's discoverCache helper now uses md5 as well? Patch: keep both ids via field spotifyUrl query.
# We store doc id as md5, and query via where spotifyUrl == clean, so id mismatch doesn't matter.

def scrape_and_store_one(url: str, db) -> bool:
    from audio_client import get_playlist_client, SpotifyDownAPIError
    from utils import get_yt_info
    from concurrent.futures import ThreadPoolExecutor, as_completed

    clean = url.split("?")[0]
    try:
        # reuse same parsing as routes._run_scrape_job
        from utils import detect_url_service
        service, url_type, item_id = detect_url_service(clean)
        if service != "spotify" or url_type not in ("playlist", "album"):
            print(f"[DiscoverRefresh] skip non-spotify {clean}", flush=True)
            return False
        client = get_playlist_client()
        metadata = client.get_playlist_metadata(item_id)
        raw_tracks = list(client.iter_playlist_tracks(item_id))
        print(f"[DiscoverRefresh] {clean} -> {metadata.name} {len(raw_tracks)} tracks", flush=True)

        tracks = []
        # sequential to avoid WARP overload (max 4 workers, not 12)
        def process(track):
            yt_cover, yt_url = get_yt_info(track.title, track.artists)
            return {
                "id": track.spotify_id,
                "title": track.title,
                "artists": track.artists,
                "album": track.album or "",
                "cover": track.cover_url or yt_cover or "",
                "releaseDate": track.release_date or "",
                "downloadLink": "",
                "sourceUrl": yt_url,
            }

        # staggered with small delay to keep WARP happy
        with ThreadPoolExecutor(max_workers=4) as ex:
            futures = {ex.submit(process, t): i for i, t in enumerate(raw_tracks)}
            by_idx = {}
            for f in as_completed(futures):
                by_idx[futures[f]] = f.result()
                time.sleep(0.05)
            tracks = [by_idx[i] for i in range(len(raw_tracks))]

        # Firestore doc - use where spotifyUrl query so id stable, but use md5 for doc id
        doc_id = _stable_doc_id(clean)
        payload = {
            "name": metadata.name,
            "owner": metadata.owner or "",
            "coverUrl": getattr(metadata, "cover_url", "") or (tracks[0].get("cover") if tracks else ""),
            "tracks": tracks,
            "source": "spotify",
            "spotifyUrl": clean,
            "creatorUid": "system_discover",
            "sharedWith": [],
            "isCustom": False,
            "isUsersOwn": False,
            "trackCount": len(tracks),
            "lastScrapedAt": __import__("firebase_admin").firestore.SERVER_TIMESTAMP if db else None,
        }
        # remove None SERVER_TIMESTAMP if db is None
        if db is None:
            print(f"[DiscoverRefresh] DRY RUN {clean} would store {len(tracks)} tracks", flush=True)
            return True
        db.collection("discoverCache").document(doc_id).set(payload, merge=True)
        # also store by hashCode doc for legacy Flutter clients that use hashCode id
        legacy_id = str(abs(hash(clean)) % 1000000000)
        # don't duplicate, just ensure query via spotifyUrl works anyway
        print(f"[DiscoverRefresh] stored {clean} as {doc_id} ({len(tracks)} tracks)", flush=True)
        return True
    except Exception as e:
        print(f"[DiscoverRefresh] failed {clean}: {e}", flush=True)
        import traceback; traceback.print_exc()
        return False

def refresh_all_discover():
    db = _init_firestore()
    if db is None:
        print("[DiscoverRefresh] No Firestore - aborting (set GOOGLE_APPLICATION_CREDENTIALS)", flush=True)
        return
    for idx, url in enumerate(DISCOVER_URLS):
        ok = scrape_and_store_one(url, db)
        if idx < len(DISCOVER_URLS) - 1:
            time.sleep(2.0 if ok else 1.0)
    print("[DiscoverRefresh] done", flush=True)

def refresh_all_discover_async():
    th = threading.Thread(target=refresh_all_discover, daemon=True)
    th.start()
    return th

if __name__ == "__main__":
    refresh_all_discover()
