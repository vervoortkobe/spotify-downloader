import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';
import '../models/playlist_model.dart';

class ApiService {
  static const String _baseUrl = 'https://spotdl.vervoortkobe.be.eu.org/api';

  static Future<PlaylistModel?> scrapePlaylist(
    String url, {
    String service = 'auto',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/scrape-playlist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playlistUrl': url, 'service': service}),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['event'] != 'complete') return null;

      final playlistData = data['data'] as Map<String, dynamic>;
      final tracks = (playlistData['tracks'] as List<dynamic>)
          .map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
          .toList();

      return PlaylistModel(
        id: url.hashCode.toString(),
        name: playlistData['playlistName'] as String? ?? 'Playlist',
        tracks: tracks,
        creatorUid: '',
        source: service == 'auto' ? 'spotify' : service,
        spotifyUrl: url,
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
      final response = await http.post(
        Uri.parse('$_baseUrl/scrape-user-playlists'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'profileUrl': profileUrl}),
      );
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
      final response = await http.post(
        Uri.parse('$_baseUrl/download-track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({...track.toJson(), 'sourceUrl': sourceUrl}),
      );
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    }
  }
}
