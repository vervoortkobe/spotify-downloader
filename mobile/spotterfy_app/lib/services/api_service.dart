import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';
import '../models/playlist_model.dart';
import 'network_stats_service.dart';

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
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final progRes = await http.get(
          Uri.parse('$_baseUrl/scrape-progress/$jobId'),
          headers: _headers(json: false),
        );
        _trackDown(progRes.bodyBytes.length);
        if (progRes.statusCode != 200) continue;
        final prog = jsonDecode(progRes.body) as Map<String, dynamic>;
        if (prog['status'] == 'complete') {
          debugPrint('scrapePlaylist job complete');
          break;
        }
        if (prog['status'] == 'error') {
          debugPrint('scrapePlaylist job error: $prog');
          return null;
        }
        if (i % 4 == 0) debugPrint('scrapePlaylist progress $i: $prog');
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

  static Future<List<int>?> downloadTrack(
    TrackModel track, {
    String? sourceUrlOverride,
  }) async {
    try {
      final sourceUrl = sourceUrlOverride ?? track.sourceUrl;
      final reqBody = jsonEncode({...track.toJson(), 'sourceUrl': sourceUrl});
      _trackUp(reqBody);
      final response = await http.post(
        Uri.parse('$_baseUrl/download-track'),
        headers: _headers(),
        body: reqBody,
      );
      _trackDown(response.bodyBytes.length);
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    }
  }
}
