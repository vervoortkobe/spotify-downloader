import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';
import '../models/playlist_model.dart';
import 'network_stats_service.dart';

/// One poll of a backend scrape job.
///
/// Mirrors the JSON from `GET /api/scrape-progress/<jobId>`.
class ScrapeProgress {
  /// Tracks resolved so far.
  final int completed;

  /// Total tracks, or 0 while the backend is still enumerating them.
  final int total;

  /// `starting`, `scraping`, `complete` or `error`.
  final String status;

  const ScrapeProgress({
    required this.completed,
    required this.total,
    required this.status,
  });

  bool get isComplete => status == 'complete';
  bool get isError => status == 'error';

  /// 0..1, or null while [total] is still unknown. A null here means the bar has
  /// to stay indeterminate - guessing a percentage would jump around as the
  /// backend discovers the playlist size.
  double? get fraction =>
      total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
}

class ApiService {
  static const String _baseUrl = 'https://spotdl.vervoortkobe.be.eu.org/api';
  // Set via --dart-define=SPOTTERFY_API_KEY=xxx (must match backend SPOTTERFY_API_KEY)
  static const String _apiKey = String.fromEnvironment(
    'SPOTTERFY_API_KEY',
    defaultValue: '',
  );
  static Map<String, String> _headers({bool json = true}) => {
    if (json) 'Content-Type': 'application/json',
    if (_apiKey.isNotEmpty) 'X-Spotterfy-Key': _apiKey,
  };

  static void _trackUp(String body) =>
      NetworkStatsService.instance?.addUp(body.length);
  static void _trackDown(int bytes) =>
      NetworkStatsService.instance?.addDown(bytes);

  /// Strip an owner suffix for STORAGE only (Firebase save path).
  /// The UI keeps the raw title so the author stays visible; only the
  /// persisted copy is cleaned. Handles both "Title - Owner" and
  /// "Title by Owner" (case-insensitive), using the known owner when available.
  static String cleanPlaylistName(String raw, [String owner = '']) {
    var name = raw.trim();
    if (owner.isNotEmpty) {
      final dash = ' - $owner';
      if (name.endsWith(dash)) {
        return name.substring(0, name.length - dash.length).trim();
      }
      final by = ' by $owner';
      if (name.toLowerCase().endsWith(by.toLowerCase())) {
        return name.substring(0, name.length - by.length).trim();
      }
    }
    return name;
  }

  static final Random _jobIdRandom = Random();

  /// Job id generated on the client, mirroring the web frontend.
  ///
  /// The backend echoes this id back, but sending it means we always know which
  /// job to poll even if the POST response body is lost or the gateway returns a
  /// 5xx after the server already accepted the request. Without it, a dropped
  /// response made the app say "could not read that playlist" while the backend
  /// happily kept scraping.
  static String _newJobId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final r1 = _jobIdRandom.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final r2 = _jobIdRandom.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'm-$ts-$r1$r2';
  }

  /// Best-effort human-readable message from a backend error body, covering both
  /// `{"error": "..."}` and the `{"event":"error","data":{"message":...}}` shape.
  static String? _backendMessage(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final err = data['error'];
        if (err is String && err.trim().isNotEmpty) return err.trim();
        final inner = data['data'];
        if (inner is Map) {
          final msg = inner['message'];
          if (msg is String && msg.trim().isNotEmpty) return msg.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Backoff for a retried start POST: honour the server's `Retry-After` when it
  /// sends one (rate limiting), otherwise grow linearly.
  static Duration _startRetryDelay(http.Response res, int attempt) {
    final header = res.headers['retry-after'];
    final seconds = header == null ? null : int.tryParse(header.trim());
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds.clamp(1, 30));
    }
    return Duration(milliseconds: 400 * attempt);
  }

  static Future<PlaylistModel?> scrapePlaylist(
    String url, {
    String service = 'auto',
    void Function(ScrapeProgress progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    final cleanUrl = url.split('?').first;
    final jobId = _newJobId();
    debugPrint('scrapePlaylist request url=$cleanUrl service=$service job=$jobId');

    void fail(String message) {
      debugPrint('scrapePlaylist failed: $message');
      onError?.call(message);
    }

    try {
      // --- 1) Start the job -------------------------------------------------
      // Retry transient failures (rate limit / gateway / network) so a blip on
      // the way out does not abort an import the backend could still run.
      http.Response? startRes;
      for (var attempt = 1; attempt <= 4; attempt++) {
        try {
          final reqBody = jsonEncode({
            'playlistUrl': cleanUrl,
            'service': service,
            'progressJobId': jobId,
          });
          _trackUp(reqBody);
          startRes = await http.post(
            Uri.parse('$_baseUrl/scrape-playlist'),
            headers: _headers(),
            body: reqBody,
          );
          _trackDown(startRes.bodyBytes.length);
          debugPrint(
            'scrapePlaylist start attempt $attempt status=${startRes.statusCode}',
          );
          if (startRes.statusCode == 200) break;
          final retryable =
              startRes.statusCode == 429 || startRes.statusCode >= 500;
          if (!retryable || attempt == 4) break;
          await Future.delayed(_startRetryDelay(startRes, attempt));
        } catch (e) {
          // The request may still have reached the server, so keep the job id
          // and try to pick the job up below rather than giving up outright.
          debugPrint('scrapePlaylist start attempt $attempt error: $e');
          startRes = null;
          if (attempt == 4) break;
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      final startData = <String, dynamic>{};
      if (startRes != null && startRes.statusCode == 200) {
        final decoded = jsonDecode(startRes.body);
        if (decoded is Map<String, dynamic>) startData.addAll(decoded);
      }

      // Legacy synchronous response (older backend versions).
      if (startData['event'] == 'complete' && startData['data'] != null) {
        final playlistData = startData['data'] as Map<String, dynamic>;
        final tracks = (playlistData['tracks'] as List<dynamic>)
            .map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
            .toList();
        // Synchronous path, so report a single finished snapshot rather than
        // leaving the caller's progress UI stuck at zero.
        onProgress?.call(
          ScrapeProgress(
            completed: tracks.length,
            total: tracks.length,
            status: 'complete',
          ),
        );
        return PlaylistModel(
          id: cleanUrl.hashCode.toString(),
          // Raw title for display — stripping happens only on save (toFirestore).
          name: (playlistData['playlistName'] as String? ?? 'Playlist').trim(),
          owner: playlistData['playlistOwner'] as String? ?? '',
          tracks: tracks,
          creatorUid: '',
          source: service == 'auto' ? 'spotify' : service,
          spotifyUrl: cleanUrl,
        );
      }

      // A hard 4xx (including a 429 we already retried) means the job never
      // started, so say why instead of showing a generic failure. A 5xx is
      // different: the gateway may have failed *after* the server began
      // scraping, so we fall through and try to poll the job by the id we sent.
      if (startRes != null &&
          startRes.statusCode != 200 &&
          startRes.statusCode < 500) {
        fail(
          startRes.statusCode == 429
              ? 'The server is busy - please try importing again in a moment.'
              : _backendMessage(startRes.body) ??
                    'Server rejected the import (HTTP ${startRes.statusCode}).',
        );
        return null;
      }

      // Poll the id we generated unless the backend handed one back.
      final returnedId = (startData['jobId'] as String?)?.trim();
      final activeJobId = (returnedId == null || returnedId.isEmpty)
          ? jobId
          : returnedId;

      // --- 2) Poll progress -------------------------------------------------
      // No overall timeout: large playlists (2000+ tracks) can take many
      // minutes. We only give up when the backend reports it never knew this
      // job, which is what happens if the start request never landed.
      var i = 0;
      var missingPolls = 0;
      final startConfirmed = startRes != null && startRes.statusCode == 200;
      final missingLimit = startConfirmed ? 3 : 12;
      while (true) {
        await Future.delayed(const Duration(milliseconds: 500));
        late http.Response progRes;
        try {
          progRes = await http.get(
            Uri.parse('$_baseUrl/scrape-progress/$activeJobId'),
            headers: _headers(json: false),
          );
          _trackDown(progRes.bodyBytes.length);
        } catch (e) {
          debugPrint('scrapePlaylist progress poll error: $e');
          continue;
        }
        i++;
        if (progRes.statusCode == 404) {
          missingPolls++;
          if (missingPolls >= missingLimit) {
            fail('The server is not tracking this import. Please try again.');
            return null;
          }
          continue;
        }
        if (progRes.statusCode != 200) {
          if (i % 20 == 0) {
            debugPrint(
              'scrapePlaylist progress poll error: ${progRes.statusCode}',
            );
          }
          continue;
        }
        missingPolls = 0;
        late Map<String, dynamic> prog;
        try {
          prog = jsonDecode(progRes.body) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('scrapePlaylist progress decode error: $e');
          continue;
        }
        final snapshot = ScrapeProgress(
          completed: (prog['completed'] as num?)?.toInt() ?? 0,
          total: (prog['total'] as num?)?.toInt() ?? 0,
          status: prog['status'] as String? ?? 'scraping',
        );
        onProgress?.call(snapshot);
        if (snapshot.isComplete) {
          debugPrint('scrapePlaylist job complete');
          break;
        }
        if (snapshot.isError) {
          // The progress snapshot carries no message; read the stored result so
          // the user sees the real reason instead of a generic failure.
          final message = await _scrapeResultError(activeJobId);
          fail(message ?? 'The playlist could not be read.');
          return null;
        }
        if (i % 4 == 0) debugPrint('scrapePlaylist progress $i: $prog');
      }

      // --- 3) Read the result ----------------------------------------------
      final result = await _fetchScrapeResult(activeJobId);
      if (result == null) {
        fail('The server finished the import but its result was unavailable.');
        return null;
      }
      final err = result['error'];
      if (err != null) {
        fail(err.toString());
        return null;
      }
      final tracks = (result['tracks'] as List<dynamic>)
          .map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
          .toList();
      // Prefer the canonical entity URL the backend resolved (matters for
      // Spotify short share links like open.spotify.com/s/<code>), so the same
      // playlist always gets the same id regardless of how it was shared.
      final canonical = (result['canonicalUrl'] as String? ?? '')
          .split('?')
          .first;
      final identityUrl = canonical.isNotEmpty ? canonical : cleanUrl;
      debugPrint(
        'scrapePlaylist success tracks=${tracks.length} playlistName=${result['playlistName']}',
      );
      return PlaylistModel(
        id: identityUrl.hashCode.toString(),
        // Raw title for display — stripping happens only on save (toFirestore).
        name: (result['playlistName'] as String? ?? 'Playlist').trim(),
        owner: result['playlistOwner'] as String? ?? '',
        tracks: tracks,
        creatorUid: '',
        source: service == 'auto' ? 'spotify' : service,
        spotifyUrl: identityUrl,
      );
    } catch (e) {
      debugPrint('Scrape failed: $e');
      fail('Import failed: $e');
      return null;
    }
  }

  /// Fetches `/api/scrape-result/<id>`, retrying briefly while the backend
  /// publishes it (it can land a moment after progress flips to complete).
  static Future<Map<String, dynamic>?> _fetchScrapeResult(String jobId) async {
    for (var attempt = 1; attempt <= 6; attempt++) {
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/scrape-result/$jobId'),
          headers: _headers(json: false),
        );
        _trackDown(res.bodyBytes.length);
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) return decoded;
        }
        debugPrint(
          'scrapePlaylist result attempt $attempt status=${res.statusCode}',
        );
        final retryable =
            res.statusCode == 404 || res.statusCode == 429 || res.statusCode >= 500;
        if (!retryable) return null;
      } catch (e) {
        debugPrint('scrapePlaylist result attempt $attempt error: $e');
      }
      if (attempt < 6) {
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    return null;
  }

  /// The backend's stored message for a job that finished with an error.
  static Future<String?> _scrapeResultError(String jobId) async {
    final result = await _fetchScrapeResult(jobId);
    final err = result?['error'];
    return err?.toString();
  }

  static String streamTrackUrl(String sourceUrl) {
    return '$_baseUrl/stream?source_url=${Uri.encodeComponent(sourceUrl)}';
  }

  /// This build's version, shown in Settings.
  static const String appVersion = '1.0.0';
  static const String appVersionLabel = 'Beta';

  /// Download URL, fetched from /api/app-version at check time.
  static String? appDownloadUrl;

  /// Latest published version, for the "Check for updates" action.
  ///
  /// Returns null when the check could not be made (offline, server error), so
  /// the caller can tell "up to date" apart from "couldn't check".
  static Future<Map<String, String>?> checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/app-version'),
        headers: _headers(),
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      appDownloadUrl = (body['url'] as String? ?? '');
      return {
        'version': (body['version'] as String?) ?? '',
        'label': (body['label'] as String?) ?? '',
        'notes': (body['notes'] as String?) ?? '',
        'url': (body['url'] as String? ?? ''),
      };
    } catch (e) {
      debugPrint('checkForUpdates failed: $e');
      return null;
    }
  }

  /// Dotted-version comparison, so 1.0.10 correctly beats 1.0.9.
  static bool isNewerVersion(String remote, String local) {
    List<int> parse(String v) => v
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parse(remote);
    final b = parse(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Song lookup. Returns real results (title, artist, artwork, length) so the
  /// search bar can find individual songs, not just playlists.
  static Future<List<TrackModel>?> searchTracks(
    String query, {
    int limit = 20,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/search-tracks',
        ).replace(queryParameters: {'q': query, 'limit': '$limit'}),
        headers: _headers(),
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final raw = (body is Map ? body['tracks'] : null);
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => TrackModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('Track search failed: $e');
      return null;
    }
  }

  /// Resolves a pasted YouTube video URL into the same track shape used by
  /// song search, so it can be played and saved from the search results.
  static Future<TrackModel?> resolveYoutubeTrack(String url) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/resolve-youtube-url'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode({'youtubeUrl': url}),
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final videoId = body['videoId'] as String? ?? '';
      if (videoId.isEmpty) return null;
      return TrackModel(
        id: 'yt_$videoId',
        title: (body['title'] as String?)?.trim().isNotEmpty == true
            ? (body['title'] as String).trim()
            : 'YouTube video $videoId',
        artists: body['channel'] as String? ?? '',
        cover: (body['thumbnail'] as String?)?.trim().isNotEmpty == true
            ? (body['thumbnail'] as String).trim()
            : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        durationMs: ((body['duration'] as num?) ?? 0).toInt() * 1000,
        sourceUrl: 'https://www.youtube.com/watch?v=$videoId',
      );
    } catch (e) {
      debugPrint('YouTube URL resolve failed: $e');
      return null;
    }
  }

  /// Streams a track to the caller and reports progress as bytes arrive.
  ///
  /// [onProgress] receives `(received, total)`. [total] is `-1` when the server
  /// sends no Content-Length, in which case progress can only be indeterminate.
  ///
  /// This deliberately does *not* use `http.post`: that buffers the whole body
  /// before returning, so the caller had no way to show a progress bar and the
  /// notification sat at zero until the file had fully arrived.
  static Future<List<int>?> downloadTrack(
    TrackModel track, {
    String? sourceUrlOverride,
    void Function(int received, int total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final sourceUrl = sourceUrlOverride ?? track.sourceUrl;
      final reqBody = jsonEncode({...track.toJson(), 'sourceUrl': sourceUrl});
      _trackUp(reqBody);
      final request =
          http.Request('POST', Uri.parse('$_baseUrl/download-track'))
            ..headers.addAll(_headers())
            ..bodyBytes = utf8.encode(reqBody);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        client.close();
        return null;
      }
      final total = response.contentLength ?? -1;
      final bytes = BytesBuilder(copy: false);
      var received = 0;
      var lastReported = 0;
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        received += chunk.length;
        // Throttle hard. A 5 MB track arrives as hundreds of chunks and each
        // one would otherwise cost a platform-channel round trip plus a full
        // notification rebuild, which is slower than the download itself.
        final done = total > 0 && received >= total;
        if (onProgress != null &&
            (done || received - lastReported >= 64 * 1024)) {
          lastReported = received;
          onProgress(received, total);
        }
      }
      client.close();
      final out = bytes.takeBytes();
      _trackDown(out.length);
      onProgress?.call(received, total);
      return out;
    } catch (e) {
      debugPrint('Download failed: $e');
      client.close();
      return null;
    }
  }
}
