import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';
import '../models/playlist_model.dart';
import 'network_stats_service.dart';

class ApiService {
  static const String _baseUrl = 'https://spotdl.vervoortkobe.be.eu.org/api';

  static void _trackUp(String body) => NetworkStatsService.instance?.addUp(body.length);
  static void _trackDown(int bytes) => NetworkStatsService.instance?.addDown(bytes);

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
        headers: {'Content-Type': 'application/json'},
        body: reqBody,
      );
      _trackDown(startRes.bodyBytes.length);
      debugPrint('scrapePlaylist start status=${startRes.statusCode} body=${startRes.body.substring(0, startRes.body.length > 1000 ? 1000 : startRes.body.length)}');
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
          name: playlistData['playlistName'] as String? ?? 'Playlist',
          tracks: tracks,
          creatorUid: '',
          source: service == 'auto' ? 'spotify' : service,
          spotifyUrl: cleanUrl,
        );
      }
      final jobId = startData['jobId'] as String?;
      if (jobId == null) {
        debugPrint('scrapePlaylist no jobId and not legacy complete: keys=${startData.keys.toList()}');
        return null;
      }
      debugPrint('scrapePlaylist jobId=$jobId polling...');
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final progRes = await http.get(Uri.parse('$_baseUrl/scrape-progress/$jobId'));
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
      final resultRes = await http.get(Uri.parse('$_baseUrl/scrape-result/$jobId'));
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
      debugPrint('scrapePlaylist success tracks=${tracks.length} playlistName=${result['playlistName']}');
      return PlaylistModel(
        id: cleanUrl.hashCode.toString(),
        name: result['playlistName'] as String? ?? 'Playlist',
        tracks: tracks,
        creatorUid: '',
        source: service == 'auto' ? 'spotify' : service,
        spotifyUrl: cleanUrl,
      );
    } catch (e) {
      debugPrint('Scrape failed: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> scrapeUserPlaylists(
    String profileUrl,
  ) async {
    try {
      final reqBody = jsonEncode({'profileUrl': profileUrl});
      _trackUp(reqBody);
      final response = await http.post(
        Uri.parse('$_baseUrl/scrape-user-playlists'),
        headers: {'Content-Type': 'application/json'},
        body: reqBody,
      );
      _trackDown(response.bodyBytes.length);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['error'] != null) return null;
      final playlists = data['playlists'] as List<dynamic>;
      return playlists.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Scrape user playlists failed: $e');
      return null;
    }
  }

  static String streamTrackUrl(String sourceUrl) {
    return '$_baseUrl/stream?source_url=${Uri.encodeComponent(sourceUrl)}';
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
        headers: {'Content-Type': 'application/json'},
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
