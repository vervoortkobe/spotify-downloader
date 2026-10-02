import 'dart:convert';
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

  static Future<PlaylistModel?> scrapePlaylist(
    String url, {
    String service = 'auto',
    void Function(ScrapeProgress progress)? onProgress,
  }) async {
    try {
      final cleanUrl = url.split('?').first;
      debugPrint('scrapePlaylist request url=$cleanUrl service=$service');
      final reqBody = jsonEncode({'playlistUrl': cleanUrl, 'service': service});
      _trackUp(reqBody);
      final startRes = await http.post(
        Uri.parse('$_baseUrl/scrape-playlist'),
        headers: _headers(),
        body: reqBody,
      );
      _trackDown(startRes.bodyBytes.length);
      debugPrint(
        'scrapePlaylist start status=${startRes.statusCode} body=${startRes.body.substring(0, startRes.body.length > 1000 ? 1000 : startRes.body.length)}',
      );
      if (startRes.statusCode != 200) {
        debugPrint('scrapePlaylist non-200');
        return null;
      }
      final startData = jsonDecode(startRes.body) as Map<String, dynamic>;
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
      final jobId = startData['jobId'] as String?;
      if (jobId == null) {
        debugPrint(
          'scrapePlaylist no jobId and not legacy complete: keys=${startData.keys.toList()}',
        );
        return null;
      }
      debugPrint('scrapePlaylist jobId=$jobId polling...');
      // The backend resolves the job on a worker thread, so this polls
      // /api/scrape-progress. Each response carries the real completed/total,
      // which is what makes "song 7 of 24" possible instead of a spinner that
      // knows nothing.
      var sawCompletion = false;
      for (int i = 0; i < 240; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final progRes = await http.get(
          Uri.parse('$_baseUrl/scrape-progress/$jobId'),
          headers: _headers(json: false),
        );
        _trackDown(progRes.bodyBytes.length);
        if (progRes.statusCode != 200) continue;
        final prog = jsonDecode(progRes.body) as Map<String, dynamic>;
        final snapshot = ScrapeProgress(
          completed: (prog['completed'] as num?)?.toInt() ?? 0,
          total: (prog['total'] as num?)?.toInt() ?? 0,
          status: prog['status'] as String? ?? 'scraping',
        );
        onProgress?.call(snapshot);
        if (snapshot.isComplete) {
          debugPrint('scrapePlaylist job complete');
          sawCompletion = true;
          break;
        }
        if (snapshot.isError) {
          debugPrint('scrapePlaylist job error: $prog');
          return null;
        }
        if (i % 4 == 0) debugPrint('scrapePlaylist progress $i: $prog');
      }
      if (!sawCompletion) {
        // Two minutes without a terminal state. Fetching the result anyway would
        // either 404 or, worse, return a half-built playlist.
        debugPrint('scrapePlaylist timed out waiting for $jobId');
        return null;
      }
      final resultRes = await http.get(
        Uri.parse('$_baseUrl/scrape-result/$jobId'),
        headers: _headers(json: false),
      );
      _trackDown(resultRes.bodyBytes.length);
      debugPrint('scrapePlaylist result status=${resultRes.statusCode}');
      if (resultRes.statusCode != 200) {
        debugPrint('scrapePlaylist result non-200 body=${resultRes.body}');
        return null;
      }
      final result = jsonDecode(resultRes.body) as Map<String, dynamic>;
      if (result['error'] != null) {
        debugPrint('scrapePlaylist result error: ${result['error']}');
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
      return null;
    }
  }

  static String streamTrackUrl(String sourceUrl) {
    return '$_baseUrl/stream?source_url=${Uri.encodeComponent(sourceUrl)}';
  }

  /// This build's version, shown in Settings.
  static const String appVersion = '1.0.0';
  static const String appVersionLabel = 'Beta';

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
      return {
        'version': (body['version'] as String?) ?? '',
        'label': (body['label'] as String?) ?? '',
        'notes': (body['notes'] as String?) ?? '',
      };
    } catch (e) {
      debugPrint('checkForUpdates failed: $e');
      return null;
    }
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
